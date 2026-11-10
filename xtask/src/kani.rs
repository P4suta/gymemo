//! Verifies the Kani harnesses of xtask in the Rust image.
//! The harnesses that the sources declare, the ones that Kani lists, and the ones that Kani verifies must be the same.
//!
//! The check catches the mistakes and unsound shortcuts of a cooperating contributor, such as a harness that doesn't compile or a harness that never runs.
//! It doesn't withstand a committer who writes code to detect or deceive the check.
//!
//! A harness counts only under the attribute `#[kani::proof]` alone at the start of its line, and the code of the sources may name `proof` nowhere else, the body of a macro included.
//! The sources may neither name `include`, whose macro brings in code, nor write the attribute `path`, which moves a module away from the file that its module path names.
//! A harness goes by its full path, which is the path that Kani reports.
//! That path joins the module path of the file, the inline modules around the harness, and the name of its function.
//! Kani lists each harness with the file that declares it, so a harness from a file that the scan skips stops the run before any verification.
//! A `path` that a macro fills in passes the scan.
//! Kani's listing then stops the run, since it names a harness of the moved file under a module path that the file doesn't declare.

use crate::{
    bounded::{self, Image, Mount, Reading, Step, Toolset, WORK},
    failure::{Context, Failure, Result, ensure},
    host::Host,
    json::{self, Value},
    swift_source::identifier,
};
use std::{iter, ops::RangeInclusive, path::Path};

/// The sources whose harnesses Kani verifies.
const SOURCES: &str = "xtask/src";
/// The package whose harnesses Kani verifies, which is also its directory in the repository.
const PACKAGE: &str = "xtask";
/// The attribute that marks a harness, alone at the start of its line.
const HARNESS: &str = "#[kani::proof]";
/// The file that `cargo kani list --format json` writes into the directory where it runs.
const LISTING: &str = "kani-list.json";
/// The version of the listing's format that the check reads, which Kani 0.68.0 writes.
const LISTING_VERSION: &str = "0.1";

/// One harness that a source declares.
#[derive(Debug, PartialEq, Eq)]
pub struct Harness {
    /// The module path and the name of the function, as Kani names the harness.
    path: String,
    /// The file, relative to the repository.
    file: String,
    /// The line of the attribute.
    line: usize,
}

impl Harness {
    /// The file and the line of the attribute.
    fn place(&self) -> String {
        format!("{}:{}", self.file, self.line)
    }
}

/// Where the scan of Rust text stands.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Lexing {
    Code,
    /// In a comment from `//` to the end of its line.
    LineComment,
    /// In a comment between `/*` and `*/`, which nests to this depth.
    BlockComment(usize),
    /// In a string literal between double quotes.
    Text,
    /// In a raw string literal that this many `#` close after its closing quote.
    RawText(usize),
}

/// The number of `#` before the opening quote of a raw string literal that starts after its `r`, or nothing when no raw string starts there.
fn raw_hashes(rest: &str) -> Option<usize> {
    let hashes = rest.len() - rest.trim_start_matches('#').len();
    rest[hashes..].starts_with('"').then_some(hashes)
}

/// The characters after an opening `'` up to the end of a character literal, or none for the `'` of a lifetime or a label.
fn literal_length(rest: &str) -> usize {
    let mut characters = rest.chars();
    match (characters.next(), characters.next()) {
        (Some('\\'), Some(_)) => {
            2 + characters
                .position(|character| character == '\'')
                .map_or(0, |at| at + 1)
        }
        (Some(_), Some('\'')) => 2,
        _ => 0,
    }
}

/// The text with every character of its comments, its string literals, and its character literals turned into a space and every line break kept, so each line keeps its number.
/// A block comment nests, and a comment or a literal that doesn't end turns the rest of the text into spaces, which the compiler refuses anyway.
fn code(text: &str) -> String {
    let mut code = String::with_capacity(text.len());
    let mut characters = text.chars();
    let mut lexing = Lexing::Code;
    while let Some(character) = characters.next() {
        let rest = characters.as_str();
        let raw = (character == 'r').then(|| raw_hashes(rest)).flatten();
        // The characters after this one that the step reads too, whether the code keeps them, and where the scan stands after them.
        let (further, kept, after) = match (lexing, character, rest.chars().next()) {
            (Lexing::Code, '/', Some('/')) => (1, false, Lexing::LineComment),
            (Lexing::Code, '/', Some('*')) => (1, false, Lexing::BlockComment(1)),
            (Lexing::Code, '"', _) => (0, false, Lexing::Text),
            (Lexing::Code, '\'', _) => match literal_length(rest) {
                0 => (0, true, Lexing::Code),
                length => (length, false, Lexing::Code),
            },
            (Lexing::Code, _, _) => match raw {
                Some(hashes) => (hashes + 1, false, Lexing::RawText(hashes)),
                None => (0, true, Lexing::Code),
            },
            (Lexing::LineComment, '\n', _) => (0, false, Lexing::Code),
            (Lexing::BlockComment(depth), '/', Some('*')) => {
                (1, false, Lexing::BlockComment(depth + 1))
            }
            (Lexing::BlockComment(depth), '*', Some('/')) => match depth - 1 {
                0 => (1, false, Lexing::Code),
                outer => (1, false, Lexing::BlockComment(outer)),
            },
            (Lexing::Text, '\\', _) => (1, false, Lexing::Text),
            (Lexing::Text, '"', _) => (0, false, Lexing::Code),
            (Lexing::RawText(hashes), '"', _)
                if rest.bytes().take_while(|byte| *byte == b'#').count() >= hashes =>
            {
                (hashes, false, Lexing::Code)
            }
            (state, _, _) => (0, false, state),
        };
        code.extend(
            iter::once(character)
                .chain(characters.by_ref().take(further))
                .map(|read| if kept || read == '\n' { read } else { ' ' }),
        );
        lexing = after;
    }
    code
}

/// Whether Rust reads `character` as whitespace, which its Pattern_White_Space property defines.
/// The property holds the two direction marks, which Unicode's White_Space doesn't hold.
/// The other characters of White_Space don't compile outside literals and comments, so reading them as whitespace hides nothing.
fn whitespace(character: char) -> bool {
    character.is_whitespace() || matches!(character, '\u{200E}' | '\u{200F}')
}

/// The tokens of Rust code with their byte offsets: each identifier or number whole, and each other character that isn't whitespace alone.
fn tokens(code: &str) -> Vec<(usize, &str)> {
    let mut tokens = Vec::new();
    let mut word = None;
    for (at, character) in code.char_indices() {
        if identifier(character) {
            word.get_or_insert(at);
            continue;
        }
        if let Some(start) = word.take() {
            tokens.push((start, &code[start..at]));
        }
        if !whitespace(character) {
            tokens.push((at, &code[at..at + character.len_utf8()]));
        }
    }
    tokens.extend(word.map(|start| (start, &code[start..])));
    tokens
}

/// The index of the token that closes the group that the token at `open` opens, counting parentheses, brackets, and braces alike.
/// A group that never closes reaches `usize::MAX`, so the rest of the text counts as inside it.
fn closing(tokens: &[(usize, &str)], open: usize) -> usize {
    let mut depth = 0_usize;
    for (index, &(_, token)) in tokens.iter().enumerate().skip(open) {
        match token {
            "(" | "[" | "{" => depth += 1,
            ")" | "]" | "}" => {
                depth -= 1;
                if depth == 0 {
                    return index;
                }
            }
            _ => {}
        }
    }
    usize::MAX
}

/// The tokens of each `macro_rules!` and each `macro` item, from its keyword to the token that closes its body.
/// A `macro` item with parameters keeps its body in the braces after them.
fn macro_bodies(tokens: &[(usize, &str)]) -> Vec<RangeInclusive<usize>> {
    let token = |index: usize| tokens.get(index).map_or("", |&(_, token)| token);
    let mut bodies = Vec::new();
    for index in 0..tokens.len() {
        let item = match token(index) {
            "macro_rules" => token(index + 1) == "!",
            "macro" => token(index + 1).starts_with(identifier),
            _ => false,
        };
        if !item {
            continue;
        }
        let Some(open) = (index..tokens.len()).find(|&at| matches!(token(at), "(" | "[" | "{"))
        else {
            continue;
        };
        let mut end = closing(tokens, open);
        if token(index) == "macro" && token(end.saturating_add(1)) == "{" {
            end = closing(tokens, end + 1);
        }
        bodies.push(index..=end);
    }
    bodies
}

/// The module path of the source `file` under `SOURCES`, where `main.rs` is the root of the crate and a `mod.rs` stands for its directory.
fn module(file: &str) -> Vec<&str> {
    let relative = file
        .strip_prefix(SOURCES)
        .and_then(|rest| rest.strip_prefix('/'))
        .unwrap_or(file);
    let mut parts = relative
        .strip_suffix(".rs")
        .unwrap_or(relative)
        .split('/')
        .collect::<Vec<_>>();
    if parts.last() == Some(&"mod") {
        parts.pop();
    }
    if parts == ["main"] {
        parts.clear();
    }
    parts
}

/// The harnesses that `source` declares as `file`, or a refusal of each place that the check can't follow.
/// The identifier `proof` stays reserved for a line-start `#[kani::proof]`, since a glob import of `kani` or a tool attribute makes `#[proof]` or `#[kanitool::proof]` mark a harness too.
/// The body of a macro may not name `proof` at all, since its harnesses take the module path of each place that invokes the macro.
/// The identifier `include` stays refused, since its macro makes Kani compile code from a file that the scan skips, even under a name that `use` gives it.
/// The attribute `path` stays refused, since it makes Kani compile a file under a module path that the file doesn't name.
fn harnesses(file: &str, source: &str) -> Result<Vec<Harness>> {
    let code = code(source);
    let tokens = tokens(&code);
    let bodies = macro_bodies(&tokens);
    let token = |index: Option<usize>| {
        index
            .and_then(|index| tokens.get(index))
            .map(|&(_, token)| token)
    };
    let mut found = Vec::new();
    let mut refused = Vec::new();
    // The inline modules around the token, each with the depth of the braces inside it.
    let mut modules = Vec::new();
    let mut depth = 0_usize;
    // The depth of the brackets inside the attribute around the token, which is 0 outside every attribute.
    let mut attribute = 0_usize;
    for (index, &(at, current)) in tokens.iter().enumerate() {
        let before = |back: usize| token(index.checked_sub(back));
        let after = |ahead: usize| token(Some(index + ahead));
        let line = || code[..at].matches('\n').count() + 1;
        let place = || format!("{file}:{}", line());
        match current {
            "{" => depth += 1,
            "}" => {
                if modules.last().is_some_and(|&(_, inside)| inside == depth) {
                    modules.pop();
                }
                depth = depth.saturating_sub(1);
            }
            "mod" => {
                if let (Some(name), Some("{")) = (after(1), after(2)) {
                    modules.push((name, depth + 1));
                }
            }
            "[" if attribute > 0 => attribute += 1,
            "[" if before(1) == Some("#") || (before(1) == Some("!") && before(2) == Some("#")) => {
                attribute = 1;
            }
            "]" if attribute > 0 => attribute -= 1,
            "path" if attribute > 0 => refused.push(format!(
                "{}: names path in an attribute, which moves a module away from the file that its module path names",
                place()
            )),
            "include" => refused.push(format!(
                "{}: names include, whose macro brings in code from a file that the check doesn't scan",
                place()
            )),
            "proof" if bodies.iter().any(|body| body.contains(&index)) => refused.push(format!(
                "{}: names proof in the body of a macro, so a harness that the macro makes takes the module path of each place that invokes the macro, which the check can't name",
                place()
            )),
            "proof" => {
                // The attribute alone at the start of its line puts only the indentation and its `#[kani::` before `proof`.
                let indented = code[..at].rsplit('\n').next().unwrap_or_default();
                let marks = indented.trim_start() == "#[kani::" && code[at..].starts_with("proof]");
                let function = tokens[index..]
                    .iter()
                    .map(|&(_, token)| token)
                    .skip_while(|token| *token != "fn")
                    .nth(1);
                match (marks, function) {
                    (true, Some(name)) if name.starts_with(identifier) => found.push(Harness {
                        path: module(file)
                            .into_iter()
                            .chain(modules.iter().map(|&(module, _)| module))
                            .chain([name])
                            .collect::<Vec<_>>()
                            .join("::"),
                        file: file.to_owned(),
                        line: line(),
                    }),
                    (true, Some(_)) => refused.push(format!(
                        "{}: {HARNESS} marks a function whose name a macro fills in, so the check can't name the harness",
                        place()
                    )),
                    (true, None) => {
                        refused.push(format!("{}: {HARNESS} marks no function", place()));
                    }
                    (false, _) => refused.push(format!(
                        "{}: names proof outside an attribute {HARNESS} alone at the start of its line, so Kani may verify a harness that the check can't match",
                        place()
                    )),
                }
            }
            _ => {}
        }
    }
    ensure(refused.is_empty(), || refused.join("\n"))?;
    Ok(found)
}

/// The verified, the failed, and the total harnesses of Kani's last line `Complete - N successfully verified harnesses, M failures, T total.`.
fn summary(output: &str) -> Option<[usize; 3]> {
    let line = output
        .lines()
        .rev()
        .find_map(|line| line.trim().strip_prefix("Complete - "))?;
    let (verified, rest) = line.split_once(" successfully verified harnesses, ")?;
    let (failures, rest) = rest.split_once(" failures, ")?;
    let total = rest.strip_suffix(" total.")?;
    Some([
        verified.parse().ok()?,
        failures.parse().ok()?,
        total.parse().ok()?,
    ])
}

/// The path of each harness whose line `Checking harness PATH...` the line `VERIFICATION:- SUCCESSFUL` follows.
fn verified(output: &str) -> Vec<&str> {
    let mut checking = None;
    let mut verified = Vec::new();
    for line in output.lines().map(str::trim) {
        if let Some(path) = line
            .strip_prefix("Checking harness ")
            .and_then(|rest| rest.strip_suffix("..."))
        {
            checking = Some(path);
        } else if let Some(outcome) = line.strip_prefix("VERIFICATION:- ") {
            verified.extend(checking.take().filter(|_| outcome == "SUCCESSFUL"));
        }
    }
    verified
}

/// The `declared` harnesses that no item of `found` matches, and the items of `found` that match no declared harness, where each declared harness matches one item at most.
fn unmatched<T>(
    declared: &[Harness],
    found: impl IntoIterator<Item = T>,
    matches: impl Fn(&Harness, &T) -> bool,
) -> (Vec<&Harness>, Vec<T>) {
    let mut missing = declared.iter().collect::<Vec<_>>();
    let mut unexpected = Vec::new();
    for item in found {
        match missing.iter().position(|harness| matches(harness, &item)) {
            Some(index) => {
                missing.remove(index);
            }
            None => unexpected.push(item),
        }
    }
    (missing, unexpected)
}

/// Refuses the `unexpected` harnesses under the line that `found` starts and the `missing` declared harnesses under the line that `absent` starts, or passes when both are empty.
fn mismatch(found: &str, unexpected: &[String], absent: &str, missing: &[&Harness]) -> Result<()> {
    let mut refusals = Vec::new();
    if !unexpected.is_empty() {
        refusals.push(format!("{found}: {}", unexpected.join(", ")));
    }
    if !missing.is_empty() {
        let places = missing
            .iter()
            .map(|harness| format!("{} at {}", harness.path, harness.place()))
            .collect::<Vec<_>>();
        refusals.push(format!("{absent}: {}", places.join(", ")));
    }
    ensure(refusals.is_empty(), || refusals.join("\n"))
}

/// Requires that Kani's summary shows every one of the `declared` harnesses verified and no failure, and that the verified harnesses are the declared ones by their full paths.
fn check(output: &str, declared: &[Harness]) -> Result<()> {
    let [verified_count, failures, total] =
        summary(output).ok_or_else(|| Failure::new("Kani printed no summary line"))?;
    let count = declared.len();
    ensure(
        failures == 0 && verified_count == count && total == count,
        || {
            format!(
                "Kani verified {verified_count} of {total} harnesses with {failures} failures, and {SOURCES} declares {count}"
            )
        },
    )?;
    let (unverified, undeclared) = unmatched(declared, verified(output), |harness, path| {
        harness.path == *path
    });
    mismatch(
        &format!("Kani verified these harnesses, which {SOURCES} doesn't declare"),
        &undeclared
            .into_iter()
            .map(str::to_owned)
            .collect::<Vec<_>>(),
        &format!("{SOURCES} declares these harnesses, which Kani didn't verify"),
        &unverified,
    )
}

/// The file and the full path of each harness in the listing that `cargo kani list --format json` writes.
/// The contract harnesses count like the standard ones.
fn listed(text: &str) -> Result<Vec<(String, String)>> {
    let listing = json::parse(text)
        .map_err(|error| Failure::new(format!("Kani's listing isn't JSON: {error}")))?;
    ensure(
        listing.get("file-version").and_then(Value::as_str) == Some(LISTING_VERSION),
        || {
            format!(
                "Kani's listing lacks the file version {LISTING_VERSION}, the only form that the check reads"
            )
        },
    )?;
    let mut harnesses = Vec::new();
    for kind in ["standard-harnesses", "contract-harnesses"] {
        let unread = || {
            Failure::new(format!(
                "Kani's listing holds no {kind} as an object of files, each with an array of harness paths"
            ))
        };
        let files = listing
            .get(kind)
            .and_then(Value::as_object)
            .ok_or_else(unread)?;
        for (file, paths) in files {
            for path in paths.as_array().ok_or_else(unread)? {
                let path = path.as_str().ok_or_else(unread)?;
                harnesses.push((file.clone(), path.to_owned()));
            }
        }
    }
    Ok(harnesses)
}

/// Requires that Kani lists exactly the `declared` harnesses, each from the file that declares it.
/// Each declared harness lies in a scanned source, so a harness from a file that the scan skips has no declared match and stops the run.
fn agree(declared: &[Harness], listed: &[(String, String)]) -> Result<()> {
    let (unlisted, undeclared) = unmatched(declared, listed, |harness, (file, path)| {
        harness.file == *file && harness.path == *path
    });
    mismatch(
        &format!("Kani lists these harnesses, which no scanned source of {SOURCES} declares"),
        &undeclared
            .into_iter()
            .map(|(file, path)| format!("{path} in {file}"))
            .collect::<Vec<_>>(),
        &format!("{SOURCES} declares these harnesses, which Kani doesn't list"),
        &unlisted,
    )
}

/// Refuses two harnesses of one full path, since Kani compiles one of them at most and the other goes unverified.
fn distinct(declared: &[Harness]) -> Result<()> {
    let mut sorted = declared.iter().collect::<Vec<_>>();
    sorted.sort_by(|first, second| first.path.cmp(&second.path));
    let mut shared = Vec::new();
    for group in sorted.chunk_by(|first, second| first.path == second.path) {
        if let [first, others @ ..] = group
            && !others.is_empty()
        {
            let places = group
                .iter()
                .map(|harness| harness.place())
                .collect::<Vec<_>>();
            shared.push(format!("{} at {}", first.path, places.join(" and ")));
        }
    }
    ensure(shared.is_empty(), || {
        format!(
            "These harnesses share one full path, so Kani compiles one of them at most and the other goes unverified:\n{}",
            shared.join("\n")
        )
    })
}

/// Reads the harnesses that the sources of xtask declare, and refuses a tree without one or with two of one full path.
pub fn declared(host: &mut impl Host, root: &Path) -> Result<Vec<Harness>> {
    let files = host
        .files(&root.join(SOURCES))
        .context(|| format!("Read {SOURCES}"))?;
    let mut declared = Vec::new();
    for file in files
        .iter()
        .filter(|file| file.extension().is_some_and(|extension| extension == "rs"))
    {
        let source = host
            .read(file)
            .context(|| format!("Read {}", file.display()))?;
        let relative = file
            .strip_prefix(root)
            .unwrap_or(file)
            .display()
            .to_string();
        declared.extend(harnesses(&relative, &source)?);
    }
    ensure(!declared.is_empty(), || {
        format!("{SOURCES} declares no Kani harness ({HARNESS}), so Kani has nothing to verify")
    })?;
    distinct(&declared)?;
    Ok(declared)
}

/// Removes `file` when it exists.
fn discard(host: &mut impl Host, file: &Path) -> Result<()> {
    if host.exists(file) {
        host.remove_file(file)
            .context(|| format!("Remove {}", file.display()))?;
    }
    Ok(())
}

/// Lists the harnesses that Kani compiles from the package, each with its file.
/// The listing of an earlier run goes first, and this run's listing goes after every outcome, so only this run's listing counts and none stays among the sources.
fn list(host: &mut impl Host, root: &Path, image: &Image) -> Result<Vec<(String, String)>> {
    let written = root.join(PACKAGE).join(LISTING);
    discard(host, &written)?;
    let directory = format!("{WORK}/{PACKAGE}");
    let step = Step {
        image,
        directory: &directory,
        command: ["cargo", "kani", "list", "--format", "json"]
            .map(str::to_owned)
            .to_vec(),
        reading: Reading::Shown,
        mount: Mount::Writable,
    };
    let outcome = bounded::run(host, root, &step, &[0])
        .and_then(|_| {
            host.read(&written)
                .context(|| format!("Read {}", written.display()))
        })
        .and_then(|text| listed(&text));
    match (outcome, discard(host, &written)) {
        (Ok(listed), Ok(())) => Ok(listed),
        (Err(failure), Ok(())) | (Ok(_), Err(failure)) => Err(failure),
        (Err(first), Err(later)) => Err(first.followed_by(&later)),
    }
}

/// Lists the harnesses of xtask and runs Kani over the `declared` ones, and returns their number.
pub fn verify(host: &mut impl Host, root: &Path, declared: &[Harness]) -> Result<usize> {
    let image = bounded::build(host, root, Toolset::Rust)?;
    agree(declared, &list(host, root, &image)?)?;
    let step = Step {
        image: &image,
        directory: WORK,
        command: ["cargo", "kani", "--package", PACKAGE]
            .map(str::to_owned)
            .to_vec(),
        reading: Reading::ShownThenRead,
        mount: Mount::Writable,
    };
    let finished = bounded::run(host, root, &step, &[0])?;
    check(&finished.output, declared)?;
    Ok(declared.len())
}

#[cfg(test)]
pub mod tests {
    use super::*;
    use crate::host::fake::{Ending, FakeHost};

    /// Kani's report of the two harnesses of `with_harnesses`, verified.
    pub const VERIFIED: &str = "Kani Rust Verifier 0.68.0 (cargo plugin)\nChecking harness json::proofs::reads...\nVERIFICATION:- SUCCESSFUL\nVerification Time: 0.009s\nChecking harness host::fake::walks...\n ** 0 of 2 failed\nVERIFICATION:- SUCCESSFUL\n\nComplete - 2 successfully verified harnesses, 0 failures, 2 total.\n";

    /// Kani's listing of the two harnesses of `with_harnesses`, in the form of Kani 0.68.0.
    pub const LISTED: &str = "{\n  \"kani-version\": \"0.68.0\",\n  \"file-version\": \"0.1\",\n  \"standard-harnesses\": {\n    \"xtask/src/host/fake.rs\": [\n      \"host::fake::walks\"\n    ],\n    \"xtask/src/json.rs\": [\n      \"json::proofs::reads\"\n    ]\n  },\n  \"contract-harnesses\": {},\n  \"contracts\": [],\n  \"totals\": {\n    \"standard-harnesses\": 2,\n    \"contract-harnesses\": 0,\n    \"functions-under-contract\": 0\n  }\n}\n";

    /// The listing that Kani 0.68.0 wrote for a scratch package with seven harnesses.
    /// They lie at the root, in nested inline modules, in a module that the attribute `path` moves, in a file that `include!` brings in, and in a macro.
    const OBSERVED_LISTING: &str = "{\n  \"kani-version\": \"0.68.0\",\n  \"file-version\": \"0.1\",\n  \"standard-harnesses\": {\n    \"xtask/src/../../elsewhere/far.rs\": [\n      \"far::from_far_away\"\n    ],\n    \"xtask/src/host/fake.rs\": [\n      \"host::fake::walks\"\n    ],\n    \"xtask/src/json.rs\": [\n      \"json::checks::deeper::nested_twice\",\n      \"json::checks::doubles_without_overflow\"\n    ],\n    \"xtask/src/main.rs\": [\n      \"at_the_root\",\n      \"made_by_a_macro\"\n    ],\n    \"xtask/src/quiet.txt\": [\n      \"json::quiet::stays_below_two_hundred\"\n    ]\n  },\n  \"contract-harnesses\": {},\n  \"contracts\": [],\n  \"totals\": {\n    \"standard-harnesses\": 7,\n    \"contract-harnesses\": 0,\n    \"functions-under-contract\": 0\n  }\n}";

    /// The file that the listing step writes in the fake repository.
    const WRITTEN: &str = "/repo/xtask/kani-list.json";

    /// Adds two sources with one harness each, and Kani's listing and report of both.
    pub fn with_harnesses(host: &mut FakeHost) {
        with_sources(host);
        host.writes("\"kani\" \"list\"", WRITTEN, LISTED);
    }

    /// Adds two sources with one harness each, and Kani's report of both, where the listing step writes no listing.
    fn with_sources(host: &mut FakeHost) {
        host.file(
            "/repo/xtask/src/json.rs",
            "fn a() {}\n#[cfg(kani)]\nmod proofs {\n    #[kani::proof]\n    fn reads() {}\n}\n",
        );
        host.file(
            "/repo/xtask/src/host/fake.rs",
            "#[kani::proof]\n#[kani::unwind(3)]\nfn walks() {}\n",
        );
        host.file("/repo/xtask/src/notes.md", "#[kani::proof]\n");
        host.prints("\"kani\"", VERIFIED);
    }

    fn harness(path: &str, file: &str, line: usize) -> Harness {
        Harness {
            path: path.to_owned(),
            file: file.to_owned(),
            line,
        }
    }

    /// The harnesses of `json.rs` and `host/fake.rs` in `with_harnesses`.
    fn both() -> [Harness; 2] {
        [
            harness("host::fake::walks", "xtask/src/host/fake.rs", 1),
            harness("json::proofs::reads", "xtask/src/json.rs", 4),
        ]
    }

    /// Each listed harness as its file and its path.
    fn pairs(listed: &[(&str, &str)]) -> Vec<(String, String)> {
        listed
            .iter()
            .map(|(file, path)| ((*file).to_owned(), (*path).to_owned()))
            .collect()
    }

    /// The words that `code` keeps on each line of `text`, with one space between them.
    fn kept(text: &str) -> Vec<String> {
        code(text)
            .lines()
            .map(|line| line.split_whitespace().collect::<Vec<_>>().join(" "))
            .collect()
    }

    #[test]
    fn the_code_turns_comments_and_literals_into_spaces_and_keeps_every_line() {
        let text = "a // b\n/* c\n/* d */ e */ f \"g\\\"\nh\" i '\"' j r#\"k \" l\"# m";
        assert_eq!(code(text).chars().count(), text.chars().count());
        assert_eq!(kept(text), ["a", "", "f", "i j m"]);
        for (text, expected) in [
            ("a // b\nc", &["a", "c"][..]),
            ("/// A doc.\n//! An inner doc.\nd", &["", "", "d"]),
            ("a /* b /* c */ d */ e", &["a e"]),
            ("a /* b\nc */ d", &["a", "d"]),
            ("a /* b", &["a"]),
            ("a */ b / c * d", &["a */ b / c * d"]),
            ("\"x\\\"y\" z", &["z"]),
            ("\"a\\\\\" b", &["b"]),
            ("\"// /* '\" c", &["c"]),
            ("\"a\nb\" c", &["", "c"]),
            ("r\"a\\\" b", &["b"]),
            ("r#\"a \" b\"# c", &["c"]),
            ("r##\"a \"# b\"## c", &["c"]),
            ("r#\"a\nb\"# c", &["", "c"]),
            ("r#\"a\"## b", &["# b"]),
            ("f(\"a\\\"b\") c", &["f( ) c"]),
            ("br\"x\" y", &["b y"]),
            ("r#type r #x", &["r#type r #x"]),
            ("'\"' a", &["a"]),
            ("'\\'' a", &["a"]),
            ("'\\\\' a \"b\"", &["a"]),
            ("'\\u{22}' a", &["a"]),
            ("b'\"' a", &["b a"]),
            ("'x' '{' a", &["a"]),
            (
                "fn f<'a>(x: &'a str) -> &'static str { \"}\" }",
                &["fn f<'a>(x: &'a str) -> &'static str { }"],
            ),
            (
                "'outer: loop { break 'outer; }",
                &["'outer: loop { break 'outer; }"],
            ),
            ("'\\n", &[""]),
        ] {
            assert_eq!(kept(text), expected, "{text:?}");
            assert_eq!(code(text).lines().count(), text.lines().count(), "{text:?}");
        }
    }

    #[test]
    fn the_tokens_are_whole_identifiers_and_single_characters() {
        assert_eq!(
            tokens("#[kani::proof]\n  fn r#a_1(x: u8) {}"),
            [
                (0, "#"),
                (1, "["),
                (2, "kani"),
                (6, ":"),
                (7, ":"),
                (8, "proof"),
                (13, "]"),
                (17, "fn"),
                (20, "r"),
                (21, "#"),
                (22, "a_1"),
                (25, "("),
                (26, "x"),
                (27, ":"),
                (29, "u8"),
                (31, ")"),
                (33, "{"),
                (34, "}"),
            ]
        );
        assert_eq!(tokens("été ü"), [(0, "été"), (6, "ü")]);
        assert_eq!(tokens(""), []);
        assert_eq!(tokens("  \n\t"), []);
    }

    #[test]
    fn the_pattern_white_space_of_rust_separates_tokens() {
        assert_eq!(
            tokens("#\u{200E}[path]"),
            [(0, "#"), (4, "["), (5, "path"), (9, "]")]
        );
        assert_eq!(
            tokens("a\u{200F}b\u{2028}c\u{2029}d\u{85}e\r\u{B}\u{C}f"),
            [
                (0, "a"),
                (4, "b"),
                (8, "c"),
                (12, "d"),
                (15, "e"),
                (19, "f")
            ]
        );
        assert_eq!(tokens("\u{200E}\u{200F}\u{2028}\u{2029}\u{85} \t\n"), []);
        assert_eq!(tokens("a\u{200B}b"), [(0, "a"), (1, "\u{200B}"), (4, "b")]);
    }

    #[test]
    fn the_module_path_of_a_source_follows_its_file() {
        for (file, expected) in [
            ("xtask/src/main.rs", &[][..]),
            ("xtask/src/json.rs", &["json"]),
            ("xtask/src/host.rs", &["host"]),
            ("xtask/src/host/fake.rs", &["host", "fake"]),
            ("xtask/src/host/mod.rs", &["host"]),
            ("xtask/src/a/b/c.rs", &["a", "b", "c"]),
            ("xtask/src/a/main.rs", &["a", "main"]),
        ] {
            assert_eq!(module(file), expected, "{file}");
        }
    }

    /// The harnesses that `source` declares as `xtask/src/a.rs`.
    fn declared_in(source: &str) -> Result<Vec<Harness>> {
        harnesses("xtask/src/a.rs", source)
    }

    /// The harnesses of `xtask/src/a.rs` at these full paths and lines.
    fn at(expected: &[(&str, usize)]) -> Result<Vec<Harness>> {
        Ok(expected
            .iter()
            .map(|(path, line)| harness(path, "xtask/src/a.rs", *line))
            .collect())
    }

    #[test]
    fn a_harness_is_the_function_under_an_attribute_at_the_start_of_its_line() {
        for (source, expected) in [
            ("", &[][..]),
            ("#[kani::proof]\nfn a() {}\n", &[("a::a", 1)]),
            (
                "  #[kani::proof]\nfn a() {}\n\t#[kani::proof] // b\nfn b() {}\n",
                &[("a::a", 1), ("a::b", 3)],
            ),
            (
                "const HARNESS: &str = \"#[kani::proof]\";\n// #[kani::proof]\n/* #[cfg_attr(kani, kani::proof)] */\n#[kani::proof_for_contract(f)]\n#[kani::unwind(2)]\nfn c() {}\n",
                &[],
            ),
            (
                "#[kani::proof]\n#[kani::unwind(3)]\n/// Walks.\npub fn walks() {}\n",
                &[("a::walks", 1)],
            ),
            (
                "#[cfg(kani)]\nmod proofs {\n    use super::*;\n\n    #[kani::proof]\n    fn reads() {\n        let x: u8 = kani::any();\n    }\n}\n",
                &[("a::proofs::reads", 5)],
            ),
            ("#[kani::proof] fn same_line() {}", &[("a::same_line", 1)]),
            ("#[kani::proof]\n\n\nfn\nspread() {}", &[("a::spread", 1)]),
        ] {
            assert_eq!(declared_in(source), at(expected), "{source:?}");
        }
    }

    #[test]
    fn each_inline_module_adds_its_name_to_the_path_up_to_its_closing_brace() {
        let nested = "#[cfg(kani)]\nmod checks {\n    #[kani::proof]\n    fn a() {}\n\n    mod deeper {\n        #[kani::proof]\n        fn b() {\n            if true { let _ = [0]; }\n        }\n    }\n\n    #[kani::proof]\n    fn c() {}\n}\n#[kani::proof]\nfn d() {}\n";
        assert_eq!(
            declared_in(nested),
            at(&[
                ("a::checks::a", 3),
                ("a::checks::deeper::b", 7),
                ("a::checks::c", 13),
                ("a::d", 16)
            ])
        );
        for (source, expected) in [
            (
                "mod declared;\n#[kani::proof]\nfn e() {}\n",
                &[("a::e", 2)][..],
            ),
            (
                "pub(crate) mod m {\n    const A: &str = \"}\";\n    const B: char = '}';\n    /* } */\n    #[kani::proof]\n    fn g() {}\n}\n",
                &[("a::m::g", 5)],
            ),
            (
                "mod m {\n    fn f() {}\n}\nmod n {}\n#[kani::proof]\nfn h() {}\n",
                &[("a::h", 5)],
            ),
            (
                "fn f() {\n    mod inner {}\n}\n#[kani::proof]\nfn i() {}\n",
                &[("a::i", 4)],
            ),
            (
                "mod m { mod n { }\n#[kani::proof] fn j() {} }",
                &[("a::m::j", 2)],
            ),
        ] {
            assert_eq!(declared_in(source), at(expected), "{source:?}");
        }
        assert_eq!(
            harnesses(
                "xtask/src/main.rs",
                "#[kani::proof]\nfn root() {}\nmod m {\n    #[kani::proof]\n    fn inner() {}\n}\n"
            ),
            Ok(vec![
                harness("root", "xtask/src/main.rs", 1),
                harness("m::inner", "xtask/src/main.rs", 4)
            ])
        );
    }

    #[test]
    fn every_other_form_of_kani_proof_is_refused_with_its_place() {
        let outside = "names proof outside an attribute #[kani::proof] alone at the start of its line, so Kani may verify a harness that the check can't match";
        for (source, line) in [
            ("#[cfg_attr(kani, kani::proof)]\nfn a() {}\n", 1),
            ("fn a() {}\n#[kani :: proof]\nfn b() {}\n", 2),
            ("#[::kani::proof]\nfn a() {}\n", 1),
            ("use kani::proof as harness;\n#[harness]\nfn a() {}\n", 1),
            ("use kani::*;\n\n#[proof]\nfn a() {}\n", 3),
            ("#[kanitool::proof]\nfn a() {}\n", 1),
            ("let proof = 1;\n", 1),
            ("x #[kani::proof]\nfn a() {}\n", 1),
            ("#[kani::proof(x)]\nfn a() {}\n", 1),
            ("#[kani::\nproof]\nfn a() {}\n", 2),
            (
                "#[cfg(kani)]\nmod p {\n    #[kani::proof] #[cfg_attr(kani, kani::proof)]\n    fn a() {}\n}\n",
                3,
            ),
        ] {
            assert_eq!(
                declared_in(source),
                Err(Failure::new(format!("xtask/src/a.rs:{line}: {outside}"))),
                "{source:?}"
            );
        }
        assert_eq!(
            declared_in(
                "#[kani::proof]\n#[cfg_attr(kani, kani::proof)]\nfn a() {}\nstruct B;\n#[kani::proof]\n"
            ),
            Err(Failure::new(format!(
                "xtask/src/a.rs:2: {outside}\nxtask/src/a.rs:5: #[kani::proof] marks no function"
            )))
        );
    }

    #[test]
    fn include_and_the_attribute_path_are_refused_with_their_place() {
        let included =
            "names include, whose macro brings in code from a file that the check doesn't scan";
        let moved = "names path in an attribute, which moves a module away from the file that its module path names";
        for (source, expected) in [
            (
                "#[cfg(kani)]\nmod quiet {\n    include!(\"quiet.txt\");\n}\n",
                format!("xtask/src/a.rs:3: {included}"),
            ),
            (
                "fn a() {}\nstd::include ! (concat!(env!(\"OUT_DIR\"), \"/h.rs\"));\n",
                format!("xtask/src/a.rs:2: {included}"),
            ),
            (
                "use core::include as bring;\nbring!(\"quiet.txt\");\n",
                format!("xtask/src/a.rs:1: {included}"),
            ),
            (
                "macro_rules! bring {\n    ($file:literal) => {\n        include!($file)\n    };\n}\n",
                format!("xtask/src/a.rs:3: {included}"),
            ),
            (
                "#[path = \"../../elsewhere/far.rs\"]\nmod far;\n",
                format!("xtask/src/a.rs:1: {moved}"),
            ),
            ("#![path = \"x\"]\n", format!("xtask/src/a.rs:1: {moved}")),
            (
                "#\u{200E}[path = \"elsewhere/near.rs\"]\nmod near;\n",
                format!("xtask/src/a.rs:1: {moved}"),
            ),
            (
                "#!\u{2029}[path = \"x\"]\n#\u{200F}\n[path = \"y\"]\nmod near;\n",
                format!("xtask/src/a.rs:1: {moved}\nxtask/src/a.rs:3: {moved}"),
            ),
            (
                "fn a() {}\n#[cfg_attr(kani, path = \"far.rs\")]\nmod far;\n",
                format!("xtask/src/a.rs:2: {moved}"),
            ),
            (
                "#[cfg_attr(all(kani, any(unix, windows)), path = \"far.rs\")]\nmod far;\n",
                format!("xtask/src/a.rs:1: {moved}"),
            ),
            (
                "#[cfg_attr(kani, doc[x], marker[[y]], path = \"far.rs\")]\nmod far;\n",
                format!("xtask/src/a.rs:1: {moved}"),
            ),
            (
                "include!(\"a.rs\");\n#[path = \"b.rs\"]\nmod b;\n",
                format!("xtask/src/a.rs:1: {included}\nxtask/src/a.rs:2: {moved}"),
            ),
        ] {
            assert_eq!(
                declared_in(source),
                Err(Failure::new(expected)),
                "{source:?}"
            );
        }
        for source in [
            "let path = include_str!(\"a.txt\");\n",
            "fn f(path: &Path) -> bool { path.exists() }\n",
            "#[doc = \"path\"]\n/// include!(\"x\")\nfn g() {}\n",
            "#[expect(clippy::all)]\nfn path() {}\n",
            "const A: [u8; 2] = [1, 2];\nlet b = !a[0] != x[path];\n",
            "let v = vec![path];\nlet w = ![path];\n",
            "let included = 1;\nlet c = include_bytes!(\"a\");\nlet d = r#includes;\n",
            "macro_rules! m { ($(#[$meta:meta])* $name:ident) => {}; }\nlet path = 1;\n",
        ] {
            assert_eq!(declared_in(source), Ok(vec![]), "{source:?}");
        }
    }

    #[test]
    fn a_harness_whose_name_a_macro_fills_in_is_refused() {
        assert_eq!(
            declared_in(
                "macro_rules! harness {\n    ($name:ident) => {\n        #[kani::proof]\n        fn $name() {}\n    };\n}\nharness!(made_by_a_macro);\n"
            ),
            Err(Failure::new(format!("xtask/src/a.rs:3: {IN_A_MACRO}")))
        );
        assert_eq!(
            declared_in("#[kani::proof]\nfn $name() {}\n"),
            Err(Failure::new(
                "xtask/src/a.rs:1: #[kani::proof] marks a function whose name a macro fills in, so the check can't name the harness"
            ))
        );
    }

    /// The refusal of `proof` in the body of a macro.
    const IN_A_MACRO: &str = "names proof in the body of a macro, so a harness that the macro makes takes the module path of each place that invokes the macro, which the check can't name";

    #[test]
    fn proof_in_the_body_of_a_macro_is_refused_with_its_place() {
        for (source, line) in [
            (
                "macro_rules! stand_in {\n    () => {\n        #[kani::proof]\n        fn holds() {}\n    };\n}\n",
                3,
            ),
            (
                "macro_rules ! stand_in (\n    () => { #[kani::proof] fn holds() {} }\n);\n",
                2,
            ),
            (
                "macro_rules! stand_in [\n    () => {}; ($x:tt) => { [($x)] };\n    () => {\n        #[kani::proof]\n        fn holds() {}\n    }\n];\n",
                4,
            ),
            (
                "macro_rules! r#stand_in {\n    () => {\n        #[kani::proof]\n        fn holds() {}\n    };\n}\n",
                3,
            ),
            (
                "macro stand_in() {\n    #[kani::proof]\n    fn holds() {}\n}\n",
                2,
            ),
            (
                "macro stand_in($name:ident) {\n    #[kani::proof]\n    fn holds() {}\n}\n",
                2,
            ),
            (
                "macro stand_in {\n    () => {\n        #[kani::proof]\n        fn holds() {}\n    }\n}\n",
                3,
            ),
            (
                "macro_rules! outer {\n    () => {\n        macro_rules! inner { () => {} }\n        #[kani::proof]\n        fn holds() {}\n    };\n}\n",
                4,
            ),
            (
                "macro_rules! unclosed {\n    () => {\n        #[kani::proof]\n        fn holds() {}\n",
                3,
            ),
        ] {
            assert_eq!(
                declared_in(source),
                Err(Failure::new(format!("xtask/src/a.rs:{line}: {IN_A_MACRO}"))),
                "{source:?}"
            );
        }
        for (source, expected) in [
            (
                "macro_rules! m { ($x:expr) => { [($x)] }; }\n#[kani::proof]\nfn after() {}\n",
                &[("a::after", 2)][..],
            ),
            (
                "macro_rules! m ( () => {} );\n#[kani::proof]\nfn after() {}\n",
                &[("a::after", 2)],
            ),
            (
                "macro m { () => {} }\n#[kani::proof]\nfn after() {}\n",
                &[("a::after", 2)],
            ),
            (
                "macro m($x:ident) { let _ = [$x]; }\n#[kani::proof]\nfn after() {}\n",
                &[("a::after", 2)],
            ),
            (
                "fn f() {\n    macro_rules! m { () => {} }\n    {\n        #[kani::proof]\n        fn in_a_block() {}\n    }\n}\n",
                &[("a::in_a_block", 4)],
            ),
            (
                "let r#macro = 1;\nmod m {\n    #[kani::proof]\n    fn after() {}\n}\nlet macro_rules = 2;\nmod n {\n    #[kani::proof]\n    fn later() {}\n}\n",
                &[("a::m::after", 3), ("a::n::later", 8)],
            ),
            ("stand_in!();\nmacro_rules!", &[]),
        ] {
            assert_eq!(declared_in(source), at(expected), "{source:?}");
        }
    }

    #[test]
    fn the_harness_that_a_macro_makes_for_a_declared_one_is_refused_before_kani_runs() {
        // The plant of the verifier: the macro's harness takes both full paths that the sources declare, and the declared twin under `cfg(any())` never compiles.
        let plant = "#[cfg(kani)]\nmacro_rules! stand_in {\n    () => {\n        #[kani::proof]\n        fn holds() {}\n    };\n}\n\n#[cfg(kani)]\nstand_in!();\n\n#[cfg(kani)]\nmod checks {\n    stand_in!();\n}\n\n#[cfg(any())]\nmod checks {\n    #[kani::proof]\n    fn holds() {\n        assert!(false);\n    }\n}\n";
        let root = Path::new("/repo");
        let mut host = FakeHost::new();
        host.file("/repo/xtask/src/json.rs", plant);
        assert_eq!(
            declared(&mut host, root),
            Err(Failure::new(format!("xtask/src/json.rs:4: {IN_A_MACRO}")))
        );
        assert_eq!(
            host.transcript(),
            ["files /repo/xtask/src", "read /repo/xtask/src/json.rs"]
        );
    }

    #[test]
    fn the_compensating_pair_is_refused_before_kani_runs() {
        let source = "#[cfg(kani)]\nmod proofs {\n    #[kani::proof]\n    fn a_null_holds_no_text() {}\n\n    #[cfg(any())]\n    #[kani::proof]\n    fn never_compiled_and_false() {\n        assert!(false);\n    }\n\n    #[cfg_attr(kani, kani::proof)]\n    fn written_with_cfg_attr() {}\n}\n";
        let root = Path::new("/repo");
        let mut host = FakeHost::new();
        host.file("/repo/xtask/src/json.rs", source);
        assert_eq!(
            declared(&mut host, root),
            Err(Failure::new(
                "xtask/src/json.rs:12: names proof outside an attribute #[kani::proof] alone at the start of its line, so Kani may verify a harness that the check can't match"
            ))
        );
        assert_eq!(
            host.transcript(),
            ["files /repo/xtask/src", "read /repo/xtask/src/json.rs"]
        );
    }

    #[test]
    fn the_summary_line_reads_as_kani_writes_it() {
        assert_eq!(summary(VERIFIED), Some([2, 0, 2]));
        assert_eq!(
            summary("Complete - 0 successfully verified harnesses, 1 failures, 1 total."),
            Some([0, 1, 1])
        );
        assert_eq!(
            summary(
                "Complete - 1 successfully verified harnesses, 0 failures, 1 total.\nComplete - 3 successfully verified harnesses, 0 failures, 3 total.\n"
            ),
            Some([3, 0, 3])
        );
        for refused in [
            "",
            "Complete - 2 successfully verified harnesses, 0 failures, 2 total",
            "Complete - two successfully verified harnesses, 0 failures, 2 total.",
            "Complete - 2 verified harnesses, 0 failures, 2 total.",
            "Complete - 2 successfully verified harnesses, 0 failures 2 total.",
            "Complete - 2 successfully verified harnesses, -1 failures, 2 total.",
            "Complete - 2 successfully verified harnesses, 0 failures, 2.",
            "Done - 2 successfully verified harnesses, 0 failures, 2 total.",
        ] {
            assert_eq!(summary(refused), None, "{refused:?}");
        }
    }

    /// The report of Kani 0.68.0 over a scratch crate, trimmed to the lines that name a harness or its outcome.
    const OBSERVED: &str = "Kani Rust Verifier 0.68.0 (cargo plugin)\nChecking harness inner::nested::doubles_without_overflow...\nStarting Bounded Model Checking\n ** 0 of 2 failed\nVERIFICATION:- SUCCESSFUL\nVerification Time: 0.009459268s\nChecking harness at_the_root...\nVERIFICATION:- SUCCESSFUL\nChecking harness proofs::fails_on_purpose...\n ** 1 of 2 failed\nFailed Checks: assertion failed: super::double(value) < 100\nVERIFICATION:- FAILED\nVerification Time: 0.008433761s\nChecking harness proofs::doubles_without_overflow...\nVERIFICATION:- SUCCESSFUL\nManual Harness Summary:\nVerification failed for - proofs::fails_on_purpose\nComplete - 3 successfully verified harnesses, 1 failures, 4 total.\n";

    #[test]
    fn each_harness_counts_as_verified_only_under_its_own_successful_outcome() {
        assert_eq!(
            verified(OBSERVED),
            [
                "inner::nested::doubles_without_overflow",
                "at_the_root",
                "proofs::doubles_without_overflow"
            ]
        );
        assert_eq!(
            verified(
                "Checking harness a...\nVERIFICATION:- FAILED\nVERIFICATION:- SUCCESSFUL\nChecking harness b...\nChecking harness c...\nVERIFICATION:- SUCCESSFUL\nChecking harness d\nVERIFICATION:- SUCCESSFUL\n  Checking harness e...  \n  VERIFICATION:- SUCCESSFUL  \n"
            ),
            ["c", "e"]
        );
        assert_eq!(verified("VERIFICATION:- SUCCESSFUL\n"), Vec::<&str>::new());
        assert_eq!(verified(""), Vec::<&str>::new());
    }

    #[test]
    fn every_declared_harness_must_be_verified_without_a_failure() {
        assert_eq!(check(VERIFIED, &both()), Ok(()));
        let [walks, reads] = both();
        assert_eq!(
            check(
                VERIFIED,
                &[walks, reads, harness("c::c", "xtask/src/c.rs", 1)]
            ),
            Err(Failure::new(
                "Kani verified 2 of 2 harnesses with 0 failures, and xtask/src declares 3"
            ))
        );
        assert_eq!(
            check(VERIFIED, &both()[..1]),
            Err(Failure::new(
                "Kani verified 2 of 2 harnesses with 0 failures, and xtask/src declares 1"
            ))
        );
        for (summary, counts) in [
            (
                "1 successfully verified harnesses, 1 failures, 2 total.",
                "1 of 2 harnesses with 1",
            ),
            (
                "2 successfully verified harnesses, 0 failures, 3 total.",
                "2 of 3 harnesses with 0",
            ),
            (
                "2 successfully verified harnesses, 1 failures, 2 total.",
                "2 of 2 harnesses with 1",
            ),
        ] {
            assert_eq!(
                check(&format!("Complete - {summary}"), &both()),
                Err(Failure::new(format!(
                    "Kani verified {counts} failures, and xtask/src declares 2"
                ))),
                "{summary}"
            );
        }
        assert_eq!(
            check("VERIFICATION:- SUCCESSFUL\n", &both()[..1]),
            Err(Failure::new("Kani printed no summary line"))
        );
    }

    #[test]
    fn the_verified_harnesses_must_be_the_declared_ones_by_their_full_paths() {
        let declared = [
            harness("json::proofs::a_null_holds_no_text", "xtask/src/json.rs", 4),
            harness(
                "json::proofs::never_compiled_and_false",
                "xtask/src/json.rs",
                8,
            ),
        ];
        let compensated = "Checking harness json::proofs::a_null_holds_no_text...\nVERIFICATION:- SUCCESSFUL\nChecking harness json::proofs::written_with_cfg_attr...\nVERIFICATION:- SUCCESSFUL\nComplete - 2 successfully verified harnesses, 0 failures, 2 total.\n";
        assert_eq!(
            check(compensated, &declared),
            Err(Failure::new(
                "Kani verified these harnesses, which xtask/src doesn't declare: json::proofs::written_with_cfg_attr\nxtask/src declares these harnesses, which Kani didn't verify: json::proofs::never_compiled_and_false at xtask/src/json.rs:8"
            ))
        );
        let declared = [
            harness(
                "json::checks::doubles_without_overflow",
                "xtask/src/json.rs",
                3,
            ),
            harness(
                "json::checks::stays_below_two_hundred",
                "xtask/src/json.rs",
                10,
            ),
        ];
        let stood_in = "Checking harness json::checks::doubles_without_overflow...\nVERIFICATION:- SUCCESSFUL\nChecking harness json::quiet::stays_below_two_hundred...\nVERIFICATION:- SUCCESSFUL\nComplete - 2 successfully verified harnesses, 0 failures, 2 total.\n";
        assert_eq!(
            check(stood_in, &declared),
            Err(Failure::new(
                "Kani verified these harnesses, which xtask/src doesn't declare: json::quiet::stays_below_two_hundred\nxtask/src declares these harnesses, which Kani didn't verify: json::checks::stays_below_two_hundred at xtask/src/json.rs:10"
            ))
        );
        let declared = [harness("a::x", "a.rs", 1), harness("b::y", "b.rs", 2)];
        let twice = "Checking harness a::x...\nVERIFICATION:- SUCCESSFUL\nChecking harness b::x...\nVERIFICATION:- SUCCESSFUL\nComplete - 2 successfully verified harnesses, 0 failures, 2 total.\n";
        assert_eq!(
            check(twice, &declared),
            Err(Failure::new(
                "Kani verified these harnesses, which xtask/src doesn't declare: b::x\nxtask/src declares these harnesses, which Kani didn't verify: b::y at b.rs:2"
            ))
        );
        let unnamed = "Checking harness a::x...\nVERIFICATION:- SUCCESSFUL\nVERIFICATION:- SUCCESSFUL\nComplete - 2 successfully verified harnesses, 0 failures, 2 total.\n";
        assert_eq!(
            check(unnamed, &declared),
            Err(Failure::new(
                "xtask/src declares these harnesses, which Kani didn't verify: b::y at b.rs:2"
            ))
        );
        let extra = "Checking harness a::x...\nVERIFICATION:- SUCCESSFUL\nChecking harness b::y...\nVERIFICATION:- SUCCESSFUL\nChecking harness z...\nVERIFICATION:- SUCCESSFUL\nComplete - 2 successfully verified harnesses, 0 failures, 2 total.\n";
        assert_eq!(
            check(extra, &declared),
            Err(Failure::new(
                "Kani verified these harnesses, which xtask/src doesn't declare: z"
            ))
        );
        let shortened = "Checking harness x...\nVERIFICATION:- SUCCESSFUL\nChecking harness y...\nVERIFICATION:- SUCCESSFUL\nComplete - 2 successfully verified harnesses, 0 failures, 2 total.\n";
        assert_eq!(
            check(shortened, &declared),
            Err(Failure::new(
                "Kani verified these harnesses, which xtask/src doesn't declare: x, y\nxtask/src declares these harnesses, which Kani didn't verify: a::x at a.rs:1, b::y at b.rs:2"
            ))
        );
    }

    #[test]
    fn harnesses_of_one_name_in_two_modules_are_told_apart_by_their_paths() {
        let root = Path::new("/repo");
        let mut host = FakeHost::new();
        with_harnesses(&mut host);
        host.file(
            "/repo/xtask/src/lean.rs",
            "#[kani::proof]\nfn walks() {}\n#[kani::proof]\nfn reads() {}\n#[kani::proof]\nfn holds() {}\n",
        );
        let [walks, reads] = both();
        assert_eq!(
            declared(&mut host, root),
            Ok(vec![
                walks,
                reads,
                harness("lean::walks", "xtask/src/lean.rs", 1),
                harness("lean::reads", "xtask/src/lean.rs", 3),
                harness("lean::holds", "xtask/src/lean.rs", 5),
            ])
        );
    }

    #[test]
    fn two_harnesses_of_one_full_path_are_refused_since_kani_compiles_one_at_most() {
        let root = Path::new("/repo");
        let mut host = FakeHost::new();
        with_harnesses(&mut host);
        host.file(
            "/repo/xtask/src/lean.rs",
            "#[cfg(unix)]\n#[kani::proof]\nfn walks() {}\n#[cfg(not(unix))]\n#[kani::proof]\nfn walks() {}\nmod m {\n    #[cfg(unix)]\n    #[kani::proof]\n    fn holds() {}\n    #[cfg(not(unix))]\n    #[kani::proof]\n    fn holds() {}\n}\n",
        );
        assert_eq!(
            declared(&mut host, root),
            Err(Failure::new(
                "These harnesses share one full path, so Kani compiles one of them at most and the other goes unverified:\nlean::m::holds at xtask/src/lean.rs:9 and xtask/src/lean.rs:12\nlean::walks at xtask/src/lean.rs:2 and xtask/src/lean.rs:5"
            ))
        );
    }

    #[test]
    fn the_sources_declare_their_harnesses_in_path_order() {
        let root = Path::new("/repo");
        let mut host = FakeHost::new();
        with_harnesses(&mut host);
        assert_eq!(declared(&mut host, root), Ok(Vec::from(both())));
        assert_eq!(
            host.transcript(),
            [
                "files /repo/xtask/src",
                "read /repo/xtask/src/host/fake.rs",
                "read /repo/xtask/src/json.rs",
            ]
        );
    }

    #[test]
    fn the_listing_reads_each_harness_with_its_file() {
        assert_eq!(
            listed(OBSERVED_LISTING),
            Ok(pairs(&[
                ("xtask/src/../../elsewhere/far.rs", "far::from_far_away"),
                ("xtask/src/host/fake.rs", "host::fake::walks"),
                ("xtask/src/json.rs", "json::checks::deeper::nested_twice"),
                (
                    "xtask/src/json.rs",
                    "json::checks::doubles_without_overflow"
                ),
                ("xtask/src/main.rs", "at_the_root"),
                ("xtask/src/main.rs", "made_by_a_macro"),
                (
                    "xtask/src/quiet.txt",
                    "json::quiet::stays_below_two_hundred"
                ),
            ]))
        );
        assert_eq!(
            listed(&LISTED.replace(
                "\"contract-harnesses\": {}",
                "\"contract-harnesses\": {\"xtask/src/a.rs\": [\"a::c\"]}"
            )),
            Ok(pairs(&[
                ("xtask/src/host/fake.rs", "host::fake::walks"),
                ("xtask/src/json.rs", "json::proofs::reads"),
                ("xtask/src/a.rs", "a::c"),
            ]))
        );
        assert_eq!(
            listed(
                "{\"file-version\": \"0.1\", \"standard-harnesses\": {\"xtask/src/main.rs\": []}, \"contract-harnesses\": {}}"
            ),
            Ok(vec![])
        );
    }

    #[test]
    fn a_listing_in_another_form_is_refused() {
        let unread = |kind: &str| {
            format!(
                "Kani's listing holds no {kind} as an object of files, each with an array of harness paths"
            )
        };
        let version =
            "Kani's listing lacks the file version 0.1, the only form that the check reads";
        for (from, to, expected) in [
            (
                "\"file-version\": \"0.1\"",
                "\"file-version\": \"0.2\"",
                version.to_owned(),
            ),
            (
                "\"file-version\": \"0.1\"",
                "\"file-version\": 0.1",
                version.to_owned(),
            ),
            ("\"file-version\": \"0.1\",", "", version.to_owned()),
            (
                "\"standard-harnesses\": {",
                "\"other\": {",
                unread("standard-harnesses"),
            ),
            (
                "\"contract-harnesses\": {}",
                "\"contract-harnesses\": []",
                unread("contract-harnesses"),
            ),
            (
                "\"contract-harnesses\": {},",
                "",
                unread("contract-harnesses"),
            ),
            (
                "[\n      \"json::proofs::reads\"\n    ]",
                "\"json::proofs::reads\"",
                unread("standard-harnesses"),
            ),
            (
                "\"json::proofs::reads\"",
                "{\"name\": \"json::proofs::reads\"}",
                unread("standard-harnesses"),
            ),
        ] {
            let text = LISTED.replacen(from, to, 1);
            assert_ne!(text, LISTED, "{from}");
            assert_eq!(listed(&text), Err(Failure::new(expected)), "{from} {to}");
        }
        assert_eq!(listed("[]"), Err(Failure::new(version)));
        assert_eq!(
            listed("{\"file-version\": \"0.1\",}"),
            Err(Failure::new(
                "Kani's listing isn't JSON: expected a name at byte 23"
            ))
        );
    }

    #[test]
    fn kani_must_list_exactly_the_declared_harnesses_each_from_its_file() {
        let listed = pairs(&[
            ("xtask/src/host/fake.rs", "host::fake::walks"),
            ("xtask/src/json.rs", "json::proofs::reads"),
        ]);
        assert_eq!(agree(&both(), &listed), Ok(()));
        let declared = [
            harness(
                "json::checks::doubles_without_overflow",
                "xtask/src/json.rs",
                3,
            ),
            harness(
                "json::checks::stays_below_two_hundred",
                "xtask/src/json.rs",
                10,
            ),
        ];
        let included = pairs(&[
            (
                "xtask/src/json.rs",
                "json::checks::doubles_without_overflow",
            ),
            (
                "xtask/src/quiet.txt",
                "json::quiet::stays_below_two_hundred",
            ),
        ]);
        assert_eq!(
            agree(&declared, &included),
            Err(Failure::new(
                "Kani lists these harnesses, which no scanned source of xtask/src declares: json::quiet::stays_below_two_hundred in xtask/src/quiet.txt\nxtask/src declares these harnesses, which Kani doesn't list: json::checks::stays_below_two_hundred at xtask/src/json.rs:10"
            ))
        );
        let moved = pairs(&[
            (
                "xtask/src/json.rs",
                "json::checks::doubles_without_overflow",
            ),
            ("xtask/src/json.rs", "json::checks::stays_below_two_hundred"),
            ("xtask/src/../../elsewhere/far.rs", "far::from_far_away"),
        ]);
        assert_eq!(
            agree(&declared, &moved),
            Err(Failure::new(
                "Kani lists these harnesses, which no scanned source of xtask/src declares: far::from_far_away in xtask/src/../../elsewhere/far.rs"
            ))
        );
        let elsewhere = pairs(&[
            (
                "xtask/src/json.rs",
                "json::checks::doubles_without_overflow",
            ),
            ("xtask/src/lean.rs", "json::checks::stays_below_two_hundred"),
        ]);
        assert_eq!(
            agree(&declared, &elsewhere),
            Err(Failure::new(
                "Kani lists these harnesses, which no scanned source of xtask/src declares: json::checks::stays_below_two_hundred in xtask/src/lean.rs\nxtask/src declares these harnesses, which Kani doesn't list: json::checks::stays_below_two_hundred at xtask/src/json.rs:10"
            ))
        );
        assert_eq!(
            agree(&declared, &listed[..0]),
            Err(Failure::new(
                "xtask/src declares these harnesses, which Kani doesn't list: json::checks::doubles_without_overflow at xtask/src/json.rs:3, json::checks::stays_below_two_hundred at xtask/src/json.rs:10"
            ))
        );
        let once = pairs(&[(
            "xtask/src/json.rs",
            "json::checks::doubles_without_overflow",
        )]);
        let [doubles, _] = declared;
        let twice = [
            doubles,
            harness(
                "json::checks::doubles_without_overflow",
                "xtask/src/json.rs",
                7,
            ),
        ];
        assert_eq!(
            agree(&twice, &once),
            Err(Failure::new(
                "xtask/src declares these harnesses, which Kani doesn't list: json::checks::doubles_without_overflow at xtask/src/json.rs:7"
            ))
        );
    }

    /// The command of each container that the run created, which follows the time limit on its command line.
    fn commands(host: &FakeHost) -> Vec<String> {
        host.transcript()
            .iter()
            .filter_map(|line| line.split_once("\"900s\" "))
            .map(|(_, command)| command.replace('"', ""))
            .collect()
    }

    #[test]
    fn kani_lists_then_verifies_the_package_after_the_harnesses_are_read() {
        let root = Path::new("/repo");
        let mut host = FakeHost::new();
        with_harnesses(&mut host);
        assert_eq!(verify(&mut host, root, &both()), Ok(2));
        assert_eq!(
            commands(&host),
            [
                "cargo kani list --format json",
                "cargo kani --package xtask"
            ]
        );
        let lines = host.transcript();
        let id = |made: usize| format!("{made:064x}");
        assert_eq!(
            lines[0],
            "capture \"docker\" \"build\" \"--quiet\" \"--tag\" \"gymemo-rust:proofs\" \"/repo/xtask/proofs/rust\""
        );
        assert_eq!(lines[1], format!("exists {WRITTEN}"));
        assert!(
            lines[2].ends_with("\"--workdir\" \"/work/xtask\" \"--env\" \"CARGO_TARGET_DIR=/work/target/container\" \"sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\" \"timeout\" \"--kill-after=1s\" \"900s\" \"cargo\" \"kani\" \"list\" \"--format\" \"json\""),
            "{}",
            lines[2]
        );
        assert_eq!(
            lines[3],
            format!("show \"docker\" \"start\" \"--attach\" \"{}\"", id(1))
        );
        assert_eq!(
            lines[5..9],
            [
                format!("capture \"docker\" \"rm\" \"--force\" \"{}\"", id(1)),
                format!("read {WRITTEN}"),
                format!("exists {WRITTEN}"),
                format!("remove {WRITTEN}"),
            ]
        );
        assert!(
            lines[9].ends_with("\"--workdir\" \"/work\" \"--env\" \"CARGO_TARGET_DIR=/work/target/container\" \"sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\" \"timeout\" \"--kill-after=1s\" \"900s\" \"cargo\" \"kani\" \"--package\" \"xtask\""),
            "{}",
            lines[9]
        );
        assert_eq!(
            lines[10],
            format!("show \"docker\" \"start\" \"--attach\" \"{}\"", id(2))
        );
        assert_eq!(
            lines[12],
            format!("capture \"docker\" \"logs\" \"{}\"", id(2))
        );
        assert_eq!(lines.len(), 14);
        assert!(!host.exists(Path::new(WRITTEN)));
        assert_eq!(host.containers(), 0);
    }

    #[test]
    fn a_harness_from_a_file_outside_the_scan_stops_the_run_before_kani_verifies() {
        let root = Path::new("/repo");
        let mut host = FakeHost::new();
        with_harnesses(&mut host);
        let included = LISTED.replace(
            "\"xtask/src/json.rs\": [",
            "\"xtask/src/quiet.txt\": [\n      \"json::quiet::stays_below_two_hundred\"\n    ],\n    \"xtask/src/json.rs\": [",
        );
        host.writes("\"kani\" \"list\"", WRITTEN, &included);
        assert_eq!(
            verify(&mut host, root, &both()),
            Err(Failure::new(
                "Kani lists these harnesses, which no scanned source of xtask/src declares: json::quiet::stays_below_two_hundred in xtask/src/quiet.txt"
            ))
        );
        assert_eq!(commands(&host), ["cargo kani list --format json"]);
        assert!(!host.exists(Path::new(WRITTEN)));
        assert_eq!(host.containers(), 0);
    }

    #[test]
    fn only_the_listing_of_this_run_counts_and_none_stays_among_the_sources() {
        let root = Path::new("/repo");
        let mut host = FakeHost::new();
        with_sources(&mut host);
        host.file(WRITTEN, LISTED);
        assert_eq!(
            verify(&mut host, root, &both()),
            Err(Failure::new(
                "Read /repo/xtask/kani-list.json: no such file"
            ))
        );
        assert_eq!(
            host.transcript()[1..3],
            [format!("exists {WRITTEN}"), format!("remove {WRITTEN}")]
        );
        assert_eq!(commands(&host), ["cargo kani list --format json"]);

        let mut host = FakeHost::new();
        with_harnesses(&mut host);
        host.writes("\"kani\" \"list\"", WRITTEN, "{\"file-version\": \"0.1\"}");
        assert_eq!(
            verify(&mut host, root, &both()),
            Err(Failure::new(
                "Kani's listing holds no standard-harnesses as an object of files, each with an array of harness paths"
            ))
        );
        assert!(!host.exists(Path::new(WRITTEN)));
        assert_eq!(commands(&host), ["cargo kani list --format json"]);
    }

    #[test]
    fn a_refused_removal_of_the_listing_fails_the_run_after_any_earlier_failure() {
        let root = Path::new("/repo");
        let removal = "Remove /repo/xtask/kani-list.json: no permission";
        let mut host = FakeHost::new();
        with_harnesses(&mut host);
        host.file(WRITTEN, LISTED);
        host.refuse_removing(WRITTEN);
        assert_eq!(verify(&mut host, root, &both()), Err(Failure::new(removal)));
        assert_eq!(commands(&host), Vec::<String>::new());

        let mut host = FakeHost::new();
        with_harnesses(&mut host);
        host.refuse_removing(WRITTEN);
        assert_eq!(verify(&mut host, root, &both()), Err(Failure::new(removal)));
        assert_eq!(commands(&host), ["cargo kani list --format json"]);

        let mut host = FakeHost::new();
        with_harnesses(&mut host);
        host.writes("\"kani\" \"list\"", WRITTEN, "[]");
        host.refuse_removing(WRITTEN);
        assert_eq!(
            verify(&mut host, root, &both()),
            Err(Failure::new(format!(
                "Kani's listing lacks the file version 0.1, the only form that the check reads\n{removal}"
            )))
        );

        let mut host = FakeHost::new();
        with_harnesses(&mut host);
        host.ends("\"kani\" \"list\"", Ending::Exit(124));
        host.refuse_removing(WRITTEN);
        let stopped = verify(&mut host, root, &both());
        assert_eq!(
            stopped,
            Err(Failure::inconclusive(
                "`cargo kani list --format json` stopped at the time limit of 900 seconds with exit code 124"
            )
            .followed_by(&Failure::new(removal)))
        );
        assert_eq!(stopped.map_err(|failure| failure.code()), Err(75));
        assert_eq!(commands(&host), ["cargo kani list --format json"]);
    }

    #[test]
    fn a_tree_without_a_harness_refuses_before_any_container() {
        let root = Path::new("/repo");
        let mut host = FakeHost::new();
        host.file("/repo/xtask/src/main.rs", "fn main() {}\n");
        assert_eq!(
            declared(&mut host, root),
            Err(Failure::new(
                "xtask/src declares no Kani harness (#[kani::proof]), so Kani has nothing to verify"
            ))
        );
        assert_eq!(
            host.transcript(),
            ["files /repo/xtask/src", "read /repo/xtask/src/main.rs"]
        );
        let mut host = FakeHost::new();
        assert_eq!(
            declared(&mut host, root),
            Err(Failure::new("Read xtask/src: no such directory"))
        );
    }

    #[test]
    fn a_failed_or_stopped_kani_run_fails_or_stays_inconclusive() {
        let root = Path::new("/repo");
        for (part, command) in [
            ("\"kani\" \"list\"", "cargo kani list --format json"),
            ("\"kani\" \"--package\"", "cargo kani --package xtask"),
        ] {
            let mut host = FakeHost::new();
            with_harnesses(&mut host);
            host.ends(part, Ending::Exit(1));
            assert_eq!(
                verify(&mut host, root, &both()),
                Err(Failure::new(format!(
                    "`{command}` failed with exit code 1 in its container"
                ))),
                "{part}"
            );
            for ending in [Ending::Exit(124), Ending::OutOfMemory(137)] {
                let mut host = FakeHost::new();
                with_harnesses(&mut host);
                host.ends(part, ending);
                assert_eq!(
                    verify(&mut host, root, &both()).map_err(|failure| failure.code()),
                    Err(75),
                    "{part} {ending:?}"
                );
                assert_eq!(host.containers(), 0, "{part} {ending:?}");
                assert!(!host.exists(Path::new(WRITTEN)), "{part} {ending:?}");
            }
        }
        let mut host = FakeHost::new();
        with_harnesses(&mut host);
        host.ends("\"kani\" \"list\"", Ending::Exit(1));
        assert!(verify(&mut host, root, &both()).is_err());
        assert_eq!(commands(&host), ["cargo kani list --format json"]);

        let mut host = FakeHost::new();
        with_harnesses(&mut host);
        host.prints(
            "\"kani\"",
            "Complete - 1 successfully verified harnesses, 0 failures, 1 total.\n",
        );
        assert_eq!(
            verify(&mut host, root, &both()),
            Err(Failure::new(
                "Kani verified 1 of 1 harnesses with 0 failures, and xtask/src declares 2"
            ))
        );
    }
}
