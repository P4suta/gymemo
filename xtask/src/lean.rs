//! Checks the Lean project under `specs/lean`: its pinned release, its module list, its build, the axioms under its theorems, and a replay of each module.
//!
//! The check catches the mistakes and unsound shortcuts of a cooperating contributor, such as `sorry`, `native_decide`, or an added axiom.
//! It doesn't withstand a committer who writes code to detect or deceive the check.
//!
//! The build, the listing, and the replay run in the Lean image under the resource policy.
//! The library may declare no code that runs on import, since such code would run inside the process that prints the axiom listing.
//! The listing and the replay get the repository without write access, so they can't rewrite what a later step reads.

use crate::{
    bounded::{self, Image, Mount, Reading, Step},
    failure::{Context, Failure, Result, ensure},
    host::Host,
};
use std::{
    collections::BTreeSet,
    iter,
    path::{Path, PathBuf},
};

const TOOLCHAIN: &str = "specs/lean/lean-toolchain";
const DOCKERFILE: &str = "xtask/proofs/lean/Dockerfile";
const PROJECT: &str = "specs/lean";
/// The file that imports every module of the library, which `lake build` builds.
const LIBRARY: &str = "specs/lean/Gymemo.lean";
/// The module of the library file, which the replay checks like the other modules.
const LIBRARY_MODULE: &str = "Gymemo";
/// The directory of the library's modules.
const MODULES: &str = "specs/lean/Gymemo";
/// The project directory in the container.
const CONTAINER_PROJECT: &str = "/work/specs/lean";
/// The axioms of Lean's standard foundations, which every theorem may rest on.
const STANDARD_AXIOMS: [&str; 3] = ["propext", "Classical.choice", "Quot.sound"];

/// One line of the axiom listing.
#[derive(Debug, PartialEq, Eq)]
struct Theorem {
    name: String,
    axioms: Vec<String>,
}

fn read(host: &mut impl Host, root: &Path, file: &str) -> Result<String> {
    host.read(&root.join(file))
        .context(|| format!("Read {file}"))
}

/// The release `X.Y.Z` that a toolchain file pins as `leanprover/lean4:vX.Y.Z`.
fn toolchain_release(text: &str) -> Option<&str> {
    let release = text.trim().strip_prefix("leanprover/lean4:v")?;
    (!release.is_empty() && !release.contains(char::is_whitespace)).then_some(release)
}

/// The release of the first `ARG LEAN_VERSION=` line of the Dockerfile.
fn image_release(dockerfile: &str) -> Option<&str> {
    dockerfile
        .lines()
        .find_map(|line| line.trim().strip_prefix("ARG LEAN_VERSION="))
        .filter(|release| !release.is_empty())
}

/// Refuses a Lean image whose release differs from the one that the project pins.
pub fn check_release(host: &mut impl Host, root: &Path) -> Result<()> {
    let toolchain = read(host, root, TOOLCHAIN)?;
    let dockerfile = read(host, root, DOCKERFILE)?;
    let pinned = toolchain_release(&toolchain).ok_or_else(|| {
        Failure::new(format!(
            "{TOOLCHAIN} pins no release as leanprover/lean4:vX.Y.Z: {}",
            toolchain.trim()
        ))
    })?;
    let built = image_release(&dockerfile).ok_or_else(|| {
        Failure::new(format!(
            "{DOCKERFILE} sets no release as ARG LEAN_VERSION=X.Y.Z"
        ))
    })?;
    ensure(pinned == built, || {
        format!("{TOOLCHAIN} pins Lean {pinned}, and {DOCKERFILE} builds Lean {built}")
    })
}

/// Where the scan of Lean text stands.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Lexing {
    Code,
    /// In a comment from `--` to the end of its line.
    LineComment,
    /// In a comment between `/-` and `-/`, which nests to this depth.
    BlockComment(usize),
    /// In a string literal between double quotes.
    Text,
}

/// The rest of each character literal that holds a double quote after its opening `'`, which the scan keeps out of a string literal.
const QUOTE_LITERALS: [&str; 2] = ["\"'", "\\\"'"];

/// The text with every character of its comments and its string literals turned into a space and every line break kept, so each line keeps its number.
/// A block comment nests, and a comment or a string literal that doesn't end turns the rest of the text into spaces, which the build refuses anyway.
fn code(text: &str) -> String {
    let mut code = String::with_capacity(text.len());
    let mut characters = text.chars();
    let mut lexing = Lexing::Code;
    while let Some(character) = characters.next() {
        let rest = characters.as_str();
        let quote = QUOTE_LITERALS
            .iter()
            .find(|literal| rest.starts_with(*literal))
            .map_or(0, |literal| literal.len());
        // The characters after this one that the step reads too, whether the code keeps them, and where the scan stands after them.
        let (further, kept, after) = match (lexing, character, rest.chars().next()) {
            (Lexing::Code, '\'', _) => (quote, true, Lexing::Code),
            (Lexing::Code, '-', Some('-')) => (1, false, Lexing::LineComment),
            (Lexing::Code, '/', Some('-')) => (1, false, Lexing::BlockComment(1)),
            (Lexing::Code, '"', _) => (0, false, Lexing::Text),
            (Lexing::Code, _, _) => (0, true, Lexing::Code),
            (Lexing::LineComment, '\n', _) => (0, false, Lexing::Code),
            (Lexing::BlockComment(depth), '/', Some('-')) => {
                (1, false, Lexing::BlockComment(depth + 1))
            }
            (Lexing::BlockComment(depth), '-', Some('/')) => match depth - 1 {
                0 => (1, false, Lexing::Code),
                outer => (1, false, Lexing::BlockComment(outer)),
            },
            (Lexing::Text, '\\', _) => (1, false, Lexing::Text),
            (Lexing::Text, '"', _) => (0, false, Lexing::Code),
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

/// The lines of the library file that hold more than an import outside its comments.
fn beyond_imports(library: &str) -> Vec<&str> {
    code(library)
        .lines()
        .zip(library.lines())
        .filter(|(code, _)| !code.trim().is_empty() && !code.starts_with("import "))
        .map(|(_, line)| line.trim())
        .collect()
}

/// The modules that the library file imports, in its order.
fn imports(library: &str) -> Vec<&str> {
    library
        .lines()
        .filter_map(|line| line.strip_prefix("import "))
        .flat_map(str::split_whitespace)
        .collect()
}

/// The module name of a source file under the project, such as `Gymemo.Log` for `Gymemo/Log.lean`.
fn module_name(file: &Path) -> Option<String> {
    let stem = file.to_str()?.strip_suffix(".lean")?;
    Some(stem.replace('/', "."))
}

/// Each Lean file under the directory of the library's modules, with the name of its module.
fn module_files(host: &mut impl Host, root: &Path) -> Result<Vec<(PathBuf, String)>> {
    let project = root.join(PROJECT);
    let files = host
        .files(&root.join(MODULES))
        .context(|| format!("Read {MODULES}"))?;
    Ok(files
        .into_iter()
        .filter_map(|file| {
            let module = module_name(file.strip_prefix(&project).ok()?)?;
            Some((file, module))
        })
        .collect())
}

/// The words that declare code which runs whenever Lean imports the module.
/// Such code runs inside the process that prints the axiom listing, so it could rewrite the listing.
const INITIALIZERS: [&str; 2] = ["initialize", "builtin_initialize"];

/// The place of each word of `text` outside comments and string literals that declares code which runs on import, as `FILE:LINE: WORD`.
fn initializers(file: &str, text: &str) -> Vec<String> {
    words(&code(text))
        .into_iter()
        .filter(|(_, word)| INITIALIZERS.contains(word))
        .map(|(line, word)| format!("{file}:{}: {word}", line + 1))
        .collect()
}

/// Refuses the `places` of code that runs on import.
fn no_initializers(places: &[String]) -> Result<()> {
    ensure(places.is_empty(), || {
        format!(
            "These lines declare code that runs whenever Lean imports the library, and such code runs inside the process that prints the axiom listing:\n{}",
            places.join("\n")
        )
    })
}

/// The path of `file` under the repository at `root`.
fn relative(root: &Path, file: &Path) -> String {
    file.strip_prefix(root)
        .unwrap_or(file)
        .display()
        .to_string()
}

/// Refuses a library file with more than imports and comments, a module file that the library file doesn't import, and an import without its file.
/// It also refuses code that runs on import in the library file and in each module.
/// Returns the module of the library file and then the imported modules in name order.
pub fn modules(host: &mut impl Host, root: &Path) -> Result<Vec<String>> {
    let library = read(host, root, LIBRARY)?;
    no_initializers(&initializers(LIBRARY, &library))?;
    let beyond = beyond_imports(&library);
    ensure(beyond.is_empty(), || {
        format!(
            "{LIBRARY} may hold only imports and comments, so that every declaration lives in a module under {MODULES}, and it also holds:\n{}",
            beyond.join("\n")
        )
    })?;
    let imported = imports(&code(&library))
        .into_iter()
        .map(str::to_owned)
        .collect::<BTreeSet<_>>();
    ensure(!imported.is_empty(), || {
        format!("{LIBRARY} imports no module")
    })?;
    let files = module_files(host, root)?;
    let present = files
        .iter()
        .map(|(_, module)| module.clone())
        .collect::<BTreeSet<_>>();
    let mut refusals = Vec::new();
    let escaped = present.difference(&imported).cloned().collect::<Vec<_>>();
    if !escaped.is_empty() {
        refusals.push(format!(
            "{LIBRARY} leaves these modules out of the build: {}",
            escaped.join(", ")
        ));
    }
    let missing = imported.difference(&present).cloned().collect::<Vec<_>>();
    if !missing.is_empty() {
        refusals.push(format!(
            "{LIBRARY} imports these modules without a file under {MODULES}: {}",
            missing.join(", ")
        ));
    }
    ensure(refusals.is_empty(), || refusals.join("\n"))?;
    let mut places = Vec::new();
    for (file, _) in &files {
        let path = relative(root, file);
        let text = host.read(file).context(|| format!("Read {path}"))?;
        places.extend(initializers(&path, &text));
    }
    no_initializers(&places)?;
    Ok(iter::once(LIBRARY_MODULE.to_owned())
        .chain(imported)
        .collect())
}

/// Runs `command` in the project directory of the Lean image, and returns what the step reads.
fn run(
    host: &mut impl Host,
    root: &Path,
    image: &Image,
    command: &[&str],
    reading: Reading,
    mount: Mount,
) -> Result<String> {
    let step = Step {
        image,
        directory: CONTAINER_PROJECT,
        command: command.iter().map(|word| (*word).to_owned()).collect(),
        reading,
        mount,
    };
    bounded::run(host, root, &step, &[0]).map(|finished| finished.output)
}

/// Builds the library and turns every warning into a failure, so a `sorry` fails the build.
/// The build is the only Lean step that writes into the repository, since it writes the compiled modules.
pub fn build(host: &mut impl Host, root: &Path, image: &Image) -> Result<()> {
    run(
        host,
        root,
        image,
        &["lake", "build", "--wfail"],
        Reading::Shown,
        Mount::Writable,
    )
    .map(|_| ())
}

/// One line `theorem NAME axioms A B C`, where the axioms may be none.
fn theorem_line(line: &str) -> Option<Theorem> {
    let (name, axioms) = line.strip_prefix("theorem ")?.split_once(" axioms")?;
    if name.is_empty() || name.contains(char::is_whitespace) {
        return None;
    }
    if !axioms.is_empty() && !axioms.starts_with(' ') {
        return None;
    }
    Some(Theorem {
        name: name.to_owned(),
        axioms: axioms.split_whitespace().map(str::to_owned).collect(),
    })
}

/// The listing that `Axioms.lean` prints.
#[derive(Debug, PartialEq, Eq)]
struct Listing {
    /// Each theorem of the library and each other declaration whose type is a proposition.
    theorems: Vec<Theorem>,
    /// Each axiom that the library declares.
    axioms: Vec<String>,
}

/// The name in one line `axiom NAME`.
fn axiom_line(line: &str) -> Option<&str> {
    let name = line.strip_prefix("axiom ")?;
    (!name.is_empty() && !name.contains(char::is_whitespace)).then_some(name)
}

/// The theorems and the axioms of the listing that `Axioms.lean` prints, after its count line agrees with the theorems.
fn listing(text: &str) -> Result<Listing> {
    let mut lines = text.lines();
    let first = lines.next().unwrap_or_default();
    let count = first
        .strip_prefix("theorems ")
        .and_then(|count| count.parse::<usize>().ok())
        .ok_or_else(|| {
            Failure::new(format!(
                "The axiom listing of Axioms.lean starts without its count: {first}"
            ))
        })?;
    let mut theorems = Vec::new();
    let mut axioms = Vec::new();
    for line in lines {
        match (theorem_line(line), axiom_line(line)) {
            (Some(theorem), _) => theorems.push(theorem),
            (None, Some(axiom)) => axioms.push(axiom.to_owned()),
            (None, None) => {
                return Err(Failure::new(format!(
                    "The axiom listing of Axioms.lean holds a malformed line: {line}"
                )));
            }
        }
    }
    ensure(theorems.len() == count, || {
        format!(
            "The axiom listing of Axioms.lean counts {count} theorems and lists {}",
            theorems.len()
        )
    })?;
    Ok(Listing { theorems, axioms })
}

/// Refuses each axiom that the library declares, since a proof may rest on it whatever the axioms under the theorems show.
fn no_axioms(axioms: &[String]) -> Result<()> {
    ensure(axioms.is_empty(), || {
        format!(
            "The library declares these axioms, and its proofs may rest only on propext, Classical.choice, and Quot.sound: {}",
            axioms.join(", ")
        )
    })
}

/// Refuses each theorem that rests on an axiom beyond the standard ones.
fn standard_axioms(theorems: &[Theorem]) -> Result<()> {
    let beyond = theorems
        .iter()
        .filter_map(|theorem| {
            let others = theorem
                .axioms
                .iter()
                .map(String::as_str)
                .filter(|axiom| !STANDARD_AXIOMS.contains(axiom))
                .collect::<Vec<_>>();
            (!others.is_empty()).then(|| format!("{}: {}", theorem.name, others.join(", ")))
        })
        .collect::<Vec<_>>();
    ensure(beyond.is_empty(), || {
        format!(
            "These theorems rest on axioms beyond propext, Classical.choice, and Quot.sound:\n{}",
            beyond.join("\n")
        )
    })
}

/// The source file of one module of the library.
struct Source {
    /// The path under the repository.
    file: String,
    module: String,
    text: String,
}

/// A scope that `namespace`, `section`, or `mutual` opens and `end` closes, with one component of the name after `namespace` or `section`.
struct Scope<'a> {
    /// The component, which is empty for a section without a name and for `mutual`.
    name: &'a str,
    /// Whether the component joins the namespace of the declarations in the scope.
    namespace: bool,
}

/// The modifiers that may stand between the attributes of a declaration and its keyword.
const MODIFIERS: [&str; 6] = [
    "private",
    "protected",
    "noncomputable",
    "unsafe",
    "partial",
    "nonrec",
];

/// The words of Lean code with the index of their line, where whitespace, brackets, braces, parentheses, and commas end a word.
fn words(code: &str) -> Vec<(usize, &str)> {
    code.lines()
        .enumerate()
        .flat_map(|(line, text)| {
            text.split(|character: char| {
                character.is_whitespace() || "()[]{}⦃⦄,".contains(character)
            })
            .filter(|word| !word.is_empty())
            .map(move |word| (line, word))
        })
        .collect()
}

/// The name in the word after `theorem`, which ends before a colon or before the universe parameters of `NAME.{u}`.
fn theorem_name(word: &str) -> Option<&str> {
    let name = word.split(':').next().unwrap_or_default();
    let name = name.strip_suffix('.').unwrap_or(name);
    (!name.is_empty()).then_some(name)
}

/// Closes the scopes that `end` with this name closes, one for each component, or the one scope without a name that a bare `end` closes.
/// Returns false at a scope of another name.
fn close(scopes: &mut Vec<Scope>, name: Option<&str>) -> bool {
    name.unwrap_or_default()
        .split('.')
        .rev()
        .all(|component| scopes.pop().is_some_and(|scope| scope.name == component))
}

/// The names that Lean gives the theorems that `source` declares, in their order, with `_private.MODULE.0.` before the name of a private theorem.
/// The scan follows `namespace`, `section`, `mutual`, and `end` outside comments and string literals.
/// It fails at an `end` that closes no open scope of its name, since it then no longer knows the namespace.
fn declared(source: &Source) -> Result<Vec<String>> {
    let code = code(&source.text);
    let words = words(&code);
    let mut scopes = Vec::<Scope>::new();
    let mut names = Vec::new();
    for (index, &(line, word)) in words.iter().enumerate() {
        let following = words.get(index + 1).map(|&(_, next)| next);
        // The name after `section` or `end` stands on its line, since both may also stand alone.
        let named = words
            .get(index + 1)
            .filter(|&&(next_line, _)| next_line == line)
            .map(|&(_, next)| next);
        match word {
            "namespace" => scopes.extend(following.into_iter().flat_map(|name| {
                name.split('.').map(|name| Scope {
                    name,
                    namespace: true,
                })
            })),
            "section" => scopes.extend(named.unwrap_or_default().split('.').map(|name| Scope {
                name,
                namespace: false,
            })),
            "mutual" => scopes.push(Scope {
                name: "",
                namespace: false,
            }),
            "end" => ensure(close(&mut scopes, named), || {
                format!(
                    "{}:{}: `{}` closes no open namespace, section, or mutual block of that name, so the scan can't name the theorems after it",
                    source.file,
                    line + 1,
                    ["end"]
                        .into_iter()
                        .chain(named)
                        .collect::<Vec<_>>()
                        .join(" ")
                )
            })?,
            "theorem" => {
                let Some(name) = following.and_then(theorem_name) else {
                    continue;
                };
                let full = match name.strip_prefix("_root_.") {
                    Some(rooted) => rooted.to_owned(),
                    None => scopes
                        .iter()
                        .filter(|scope| scope.namespace)
                        .map(|scope| scope.name)
                        .chain(iter::once(name))
                        .collect::<Vec<_>>()
                        .join("."),
                };
                let private = words[..index]
                    .iter()
                    .rev()
                    .map(|&(_, before)| before)
                    .take_while(|before| MODIFIERS.contains(before))
                    .any(|before| before == "private");
                names.push(if private {
                    format!("_private.{}.0.{full}", source.module)
                } else {
                    full
                });
            }
            _ => {}
        }
    }
    Ok(names)
}

/// Refuses each theorem that a source declares and the listing leaves out, matched by the full name that Lean gives the theorem.
fn complete(sources: &[Source], theorems: &[Theorem]) -> Result<()> {
    let listed = theorems
        .iter()
        .map(|theorem| theorem.name.as_str())
        .collect::<BTreeSet<_>>();
    let mut missing = Vec::new();
    for source in sources {
        missing.extend(
            declared(source)?
                .into_iter()
                .filter(|name| !listed.contains(name.as_str()))
                .map(|name| format!("{}: {name}", source.file)),
        );
    }
    ensure(missing.is_empty(), || {
        format!(
            "These theorems of the sources have no line in the axiom listing:\n{}",
            missing.join("\n")
        )
    })
}

/// Lists the axioms under every theorem of the library and refuses an axiom that the library declares.
/// It holds the theorems to the standard axioms and requires a line for each theorem of the sources.
/// Returns the number of theorems in the listing, the ones that Lean derives and the other declarations of a proposition included.
pub fn axioms(host: &mut impl Host, root: &Path, image: &Image) -> Result<usize> {
    let printed = run(
        host,
        root,
        image,
        &["lake", "env", "lean", "Axioms.lean"],
        Reading::Captured,
        Mount::ReadOnly,
    )?;
    let Listing { theorems, axioms } = listing(&printed)?;
    no_axioms(&axioms)?;
    ensure(!theorems.is_empty(), || {
        "The axiom listing of Axioms.lean holds no theorem".to_owned()
    })?;
    standard_axioms(&theorems)?;
    let mut sources = Vec::new();
    for (file, module) in module_files(host, root)? {
        let path = relative(root, &file);
        let text = host.read(&file).context(|| format!("Read {path}"))?;
        sources.push(Source {
            file: path,
            module,
            text,
        });
    }
    complete(&sources, &theorems)?;
    Ok(theorems.len())
}

/// Replays each module from a fresh environment, so the kernel checks every declaration again.
pub fn replay(host: &mut impl Host, root: &Path, image: &Image, modules: &[String]) -> Result<()> {
    for module in modules {
        run(
            host,
            root,
            image,
            &["lake", "env", "leanchecker", "--fresh", module],
            Reading::Shown,
            Mount::ReadOnly,
        )?;
    }
    Ok(())
}

#[cfg(test)]
pub mod tests {
    use super::*;
    use crate::{
        bounded::Toolset,
        host::fake::{Ending, FakeHost, Fault},
    };

    /// A listing that holds the theorems of `repository`, one of them derived.
    pub const LISTING: &str = "theorems 4\ntheorem Gymemo.Strength.step_zero axioms Classical.choice Quot.sound propext\ntheorem Gymemo.Strength.step_zero.eq_1 axioms \ntheorem Gymemo.stored axioms \ntheorem _private.Gymemo.Log.0.Gymemo.hidden axioms propext\n";

    /// A host whose repository holds a Lean project with two modules and three theorems, which the listing of `Axioms.lean` covers.
    pub fn repository() -> FakeHost {
        let mut host = FakeHost::new();
        host.file(
            "/repo/specs/lean/lean-toolchain",
            "leanprover/lean4:v4.34.1\n",
        );
        host.file(
            "/repo/xtask/proofs/lean/Dockerfile",
            "# The host.\nARG LEAN_VERSION=4.34.1\n\nFROM scratch\n",
        );
        host.file(
            "/repo/specs/lean/Gymemo.lean",
            "import Gymemo.Log\nimport Gymemo.Strength\n",
        );
        host.file(
            "/repo/specs/lean/Gymemo/Log.lean",
            "namespace Gymemo\n\ntheorem stored : True := trivial\n/-- A theorem in prose. -/\nprivate theorem hidden : True := trivial\n",
        );
        host.file(
            "/repo/specs/lean/Gymemo/Strength.lean",
            "namespace Gymemo\n\n@[simp] theorem Strength.step_zero (n : Nat) : n + 0 = n := rfl\n\nend Gymemo\n",
        );
        host.prints("\"Axioms.lean\"", LISTING);
        host
    }

    /// The source of `module` at its path under the repository.
    fn source(module: &str, text: &str) -> Source {
        Source {
            file: format!("specs/lean/{}.lean", module.replace('.', "/")),
            module: module.to_owned(),
            text: text.to_owned(),
        }
    }

    /// The names that `declared` reads from `text` as the source of `Gymemo.Log`.
    fn names(text: &str) -> Result<Vec<String>> {
        declared(&source("Gymemo.Log", text))
    }

    fn image(host: &mut FakeHost) -> Result<Image> {
        bounded::build(host, Path::new("/repo"), Toolset::Lean)
    }

    /// The command of each container that the run created, which follows the time limit on its command line.
    fn commands(host: &FakeHost) -> Vec<String> {
        host.transcript()
            .iter()
            .filter_map(|line| line.split_once("\"900s\" "))
            .map(|(_, command)| command.replace('"', ""))
            .collect()
    }

    /// The volume of each container that the run created.
    fn volumes(host: &FakeHost) -> Vec<String> {
        host.transcript()
            .iter()
            .filter_map(|line| line.split_once("\"--volume\" \""))
            .filter_map(|(_, rest)| rest.split_once('"'))
            .map(|(volume, _)| volume.to_owned())
            .collect()
    }

    fn theorem(name: &str, axioms: &[&str]) -> Theorem {
        Theorem {
            name: name.to_owned(),
            axioms: axioms.iter().map(|axiom| (*axiom).to_owned()).collect(),
        }
    }

    #[test]
    fn a_release_reads_from_the_toolchain_and_from_the_dockerfile() {
        assert_eq!(
            toolchain_release("leanprover/lean4:v4.34.1\n"),
            Some("4.34.1")
        );
        assert_eq!(
            toolchain_release("  leanprover/lean4:v4.35.0-rc1  "),
            Some("4.35.0-rc1")
        );
        for refused in [
            "leanprover/lean4:4.34.1",
            "leanprover/lean4:v",
            "lean4:v4.34.1",
            "",
            "leanprover/lean4:v4.34.1 extra",
        ] {
            assert_eq!(toolchain_release(refused), None, "{refused:?}");
        }
        assert_eq!(
            image_release("ARG KANI=1\nARG LEAN_VERSION=4.34.1\nARG LEAN_VERSION=9.9.9\n"),
            Some("4.34.1")
        );
        assert_eq!(
            image_release("  ARG LEAN_VERSION=4.34.1  \n"),
            Some("4.34.1")
        );
        for refused in [
            "ARG LEAN_VERSION\n",
            "ARG LEAN_VERSION=\n",
            "# ARG LEAN_VERSION=4.34.1\n",
            "ENV LEAN_VERSION=4.34.1\n",
        ] {
            assert_eq!(image_release(refused), None, "{refused:?}");
        }
    }

    #[test]
    fn the_image_must_build_the_release_that_the_project_pins() {
        let root = Path::new("/repo");
        let mut host = repository();
        assert_eq!(check_release(&mut host, root), Ok(()));
        assert_eq!(
            host.transcript(),
            [
                "read /repo/specs/lean/lean-toolchain",
                "read /repo/xtask/proofs/lean/Dockerfile"
            ]
        );
        host.file(
            "/repo/specs/lean/lean-toolchain",
            "leanprover/lean4:v4.35.0\n",
        );
        assert_eq!(
            check_release(&mut host, root),
            Err(Failure::new(
                "specs/lean/lean-toolchain pins Lean 4.35.0, and xtask/proofs/lean/Dockerfile builds Lean 4.34.1"
            ))
        );
        host.file("/repo/specs/lean/lean-toolchain", "stable\n");
        assert_eq!(
            check_release(&mut host, root),
            Err(Failure::new(
                "specs/lean/lean-toolchain pins no release as leanprover/lean4:vX.Y.Z: stable"
            ))
        );
        let mut host = repository();
        host.file("/repo/xtask/proofs/lean/Dockerfile", "FROM scratch\n");
        assert_eq!(
            check_release(&mut host, root),
            Err(Failure::new(
                "xtask/proofs/lean/Dockerfile sets no release as ARG LEAN_VERSION=X.Y.Z"
            ))
        );
        let mut host = FakeHost::new();
        assert_eq!(
            check_release(&mut host, root),
            Err(Failure::new("Read specs/lean/lean-toolchain: no such file"))
        );
    }

    #[test]
    fn imports_and_module_names_read_as_lean_writes_them() {
        assert_eq!(
            imports(
                "import Gymemo.Log\n\nimport Gymemo.A Gymemo.B\n-- import Gymemo.C\nimporter X\n"
            ),
            ["Gymemo.Log", "Gymemo.A", "Gymemo.B"]
        );
        assert_eq!(
            module_name(Path::new("Gymemo/Log.lean")),
            Some("Gymemo.Log".to_owned())
        );
        assert_eq!(
            module_name(Path::new("Gymemo/Sub/Deep.lean")),
            Some("Gymemo.Sub.Deep".to_owned())
        );
        assert_eq!(module_name(Path::new("Gymemo/notes.md")), None);
        assert_eq!(module_name(Path::new("Gymemo/Log.olean")), None);
    }

    /// The words that `code` keeps on each line of `text`, with one space between them.
    fn kept(text: &str) -> Vec<String> {
        code(text)
            .lines()
            .map(|line| line.split_whitespace().collect::<Vec<_>>().join(" "))
            .collect()
    }

    #[test]
    fn the_code_turns_comments_and_string_literals_into_spaces_and_keeps_every_line() {
        let text = "a -- b\n/- c\n/- d -/ e -/ f \"g\\\"\nh\" i '\"' j";
        assert_eq!(code(text).chars().count(), text.chars().count());
        assert_eq!(kept(text), ["a", "", "f", "i '\"' j"]);
        assert_eq!(
            kept("theorem a -- theorem b\ntheorem c"),
            ["theorem a", "theorem c"]
        );
        assert_eq!(kept("a/- b -/c"), ["a c"]);
        assert_eq!(kept("/-- A docstring. -/ theorem k"), ["theorem k"]);
        assert_eq!(
            kept("a /- b\nnamespace X\n/- nested -/ end X -/ c\nd"),
            ["a", "", "c", "d"]
        );
        assert_eq!(kept("a -/ b"), ["a -/ b"]);
        assert_eq!(kept("/- -- -/ a"), ["a"]);
        assert_eq!(kept("-- /- \na"), ["", "a"]);
        assert_eq!(kept("a /- b\nc"), ["a", ""]);
        assert_eq!(
            kept("def s := \"/- -- \\\" \"\ntheorem p"),
            ["def s :=", "theorem p"]
        );
        assert_eq!(kept("\"a\\\\\" b"), ["b"]);
        assert_eq!(kept("\"a\nb"), ["", ""]);
        assert_eq!(
            kept("def c := '\"'\ntheorem q"),
            ["def c := '\"'", "theorem q"]
        );
        assert_eq!(
            kept("def c := '\\\"' -- x\ntheorem r"),
            ["def c := '\\\"'", "theorem r"]
        );
        assert_eq!(kept("h' -- x\ny"), ["h'", "y"]);
    }

    #[test]
    fn the_library_file_may_hold_imports_comments_and_blank_lines_only() {
        assert_eq!(
            beyond_imports(
                "/-! The library. -/\nimport Gymemo.Log -- the log\n\n/- A note\n   over two lines. -/\nimport Gymemo.A Gymemo.B\n"
            ),
            Vec::<&str>::new()
        );
        assert_eq!(
            beyond_imports(
                "import Gymemo.Log\n  import Gymemo.A\nimporter X\n#eval 1 /- note -/\nimport\n"
            ),
            [
                "import Gymemo.A",
                "importer X",
                "#eval 1 /- note -/",
                "import"
            ]
        );
    }

    #[test]
    fn every_module_file_is_imported_and_every_import_has_its_file() {
        let root = Path::new("/repo");
        let mut host = repository();
        host.file("/repo/specs/lean/Gymemo/README.md", "");
        assert_eq!(
            modules(&mut host, root),
            Ok(vec![
                "Gymemo".to_owned(),
                "Gymemo.Log".to_owned(),
                "Gymemo.Strength".to_owned()
            ])
        );
        assert_eq!(
            host.transcript(),
            [
                "read /repo/specs/lean/Gymemo.lean",
                "files /repo/specs/lean/Gymemo",
                "read /repo/specs/lean/Gymemo/Log.lean",
                "read /repo/specs/lean/Gymemo/Strength.lean"
            ]
        );
        host.file("/repo/specs/lean/Gymemo/Sub/Extra.lean", "");
        host.file("/repo/specs/lean/Gymemo/Other.lean", "");
        assert_eq!(
            modules(&mut host, root),
            Err(Failure::new(
                "specs/lean/Gymemo.lean leaves these modules out of the build: Gymemo.Other, Gymemo.Sub.Extra"
            ))
        );
        let mut host = repository();
        host.file(
            "/repo/specs/lean/Gymemo.lean",
            "import Gymemo.Log\nimport Gymemo.Strength\nimport Gymemo.Gone\nimport Lean\n",
        );
        assert_eq!(
            modules(&mut host, root),
            Err(Failure::new(
                "specs/lean/Gymemo.lean imports these modules without a file under specs/lean/Gymemo: Gymemo.Gone, Lean"
            ))
        );
        host.file("/repo/specs/lean/Gymemo/Other.lean", "");
        assert_eq!(
            modules(&mut host, root),
            Err(Failure::new(
                "specs/lean/Gymemo.lean leaves these modules out of the build: Gymemo.Other\nspecs/lean/Gymemo.lean imports these modules without a file under specs/lean/Gymemo: Gymemo.Gone, Lean"
            ))
        );
        let mut host = repository();
        host.file("/repo/specs/lean/Gymemo.lean", "-- Nothing.\n");
        assert!(modules(&mut host, root).is_err());
        let mut host = FakeHost::new();
        host.file("/repo/specs/lean/Gymemo.lean", "");
        host.directory("/repo/specs/lean/Gymemo", &[]);
        assert_eq!(
            modules(&mut host, root),
            Err(Failure::new("specs/lean/Gymemo.lean imports no module"))
        );
        let mut host = FakeHost::new();
        host.file("/repo/specs/lean/Gymemo.lean", "import Gymemo.Log\n");
        assert_eq!(
            modules(&mut host, root),
            Err(Failure::new("Read specs/lean/Gymemo: no such directory"))
        );
    }

    /// A listing of `theorems` without an axiom.
    fn only(theorems: Vec<Theorem>) -> Listing {
        Listing {
            theorems,
            axioms: Vec::new(),
        }
    }

    #[test]
    fn the_listing_reads_one_theorem_on_each_line_under_its_count() {
        assert_eq!(
            listing(LISTING),
            Ok(only(vec![
                theorem(
                    "Gymemo.Strength.step_zero",
                    &["Classical.choice", "Quot.sound", "propext"]
                ),
                theorem("Gymemo.Strength.step_zero.eq_1", &[]),
                theorem("Gymemo.stored", &[]),
                theorem("_private.Gymemo.Log.0.Gymemo.hidden", &["propext"]),
            ]))
        );
        assert_eq!(listing("theorems 0\n"), Ok(only(vec![])));
        assert_eq!(
            listing(
                "theorems 1\ntheorem planted_false axioms cheat\naxiom cheat\naxiom Gymemo.other\n"
            ),
            Ok(Listing {
                theorems: vec![theorem("planted_false", &["cheat"])],
                axioms: vec!["cheat".to_owned(), "Gymemo.other".to_owned()],
            })
        );
        assert_eq!(
            listing("theorems 1\naxiom cheat\n"),
            Err(Failure::new(
                "The axiom listing of Axioms.lean counts 1 theorems and lists 0"
            ))
        );
        assert_eq!(
            listing("theorem a axioms\ntheorem b axioms propext"),
            Err(Failure::new(
                "The axiom listing of Axioms.lean starts without its count: theorem a axioms"
            ))
        );
        assert_eq!(
            listing(""),
            Err(Failure::new(
                "The axiom listing of Axioms.lean starts without its count: "
            ))
        );
        for count in [
            "theorems",
            "theorems -1",
            "theorems two",
            "theorems 1 2",
            "Theorems 1",
        ] {
            assert_eq!(
                listing(&format!("{count}\ntheorem a axioms")),
                Err(Failure::new(format!(
                    "The axiom listing of Axioms.lean starts without its count: {count}"
                ))),
                "{count}"
            );
        }
        assert_eq!(
            listing("theorems 3\ntheorem a axioms\ntheorem b axioms propext\n"),
            Err(Failure::new(
                "The axiom listing of Axioms.lean counts 3 theorems and lists 2"
            ))
        );
        assert_eq!(
            listing("theorems 1\ntheorem a axioms\ntheorem b axioms\n"),
            Err(Failure::new(
                "The axiom listing of Axioms.lean counts 1 theorems and lists 2"
            ))
        );
        for malformed in [
            "theorem a",
            "theorem  axioms",
            "theorem a b axioms",
            "theorem a axiomspropext",
            "theorem a axioms_x",
            "lemma a axioms",
            "",
            "warning: declaration uses 'sorry'",
            "axiom",
            "axiom ",
            "axiom a b",
            "axioms a",
            "axiom\ta",
        ] {
            assert_eq!(
                listing(&format!("theorems 2\ntheorem a axioms\n{malformed}\n")),
                Err(Failure::new(format!(
                    "The axiom listing of Axioms.lean holds a malformed line: {malformed}"
                ))),
                "{malformed:?}"
            );
        }
    }

    #[test]
    fn only_the_standard_axioms_are_accepted() {
        assert_eq!(
            standard_axioms(&[
                theorem("a", &[]),
                theorem("b", &["Classical.choice", "Quot.sound", "propext"]),
                theorem("c", &["propext"]),
            ]),
            Ok(())
        );
        assert_eq!(
            standard_axioms(&[
                theorem("a", &["propext", "sorryAx"]),
                theorem("b", &["propext"]),
                theorem("c", &["Lean.ofReduceBool", "Lean.trustCompiler"]),
                theorem("d", &["Gymemo.cheat"]),
                theorem("e", &["Classical.choic", "propext2", "quot.sound"]),
            ]),
            Err(Failure::new(
                "These theorems rest on axioms beyond propext, Classical.choice, and Quot.sound:\na: sorryAx\nc: Lean.ofReduceBool, Lean.trustCompiler\nd: Gymemo.cheat\ne: Classical.choic, propext2, quot.sound"
            ))
        );
    }

    #[test]
    fn the_library_may_declare_no_axiom() {
        assert_eq!(no_axioms(&[]), Ok(()));
        assert_eq!(
            no_axioms(&["cheat".to_owned(), "Gymemo.Log.trusted".to_owned()]),
            Err(Failure::new(
                "The library declares these axioms, and its proofs may rest only on propext, Classical.choice, and Quot.sound: cheat, Gymemo.Log.trusted"
            ))
        );
    }

    #[test]
    fn a_declaration_names_its_theorem_after_its_attributes_and_modifiers() {
        for (text, expected) in [
            ("theorem stored : True := trivial", &["stored"][..]),
            ("theorem key_of_find? {Row : Type}", &["key_of_find?"]),
            (
                "private theorem bne_of_ne {a b : Nat}",
                &["_private.Gymemo.Log.0.bne_of_ne"],
            ),
            ("protected theorem Log.le(a : Nat)", &["Log.le"]),
            ("@[simp] theorem step_zero (n : Nat)", &["step_zero"]),
            (
                "@[simp, grind =] private theorem a:True",
                &["_private.Gymemo.Log.0.a"],
            ),
            ("@[simp]theorem b[Inhabited α]", &["b"]),
            ("theorem c⦃a : Nat⦄", &["c"]),
            ("private protected theorem d", &["_private.Gymemo.Log.0.d"]),
            ("theorem e\t: True", &["e"]),
            ("theorem f{a : Nat}", &["f"]),
            ("  theorem indented : True", &["indented"]),
            ("noncomputable theorem g", &["g"]),
            ("private nonrec theorem h", &["_private.Gymemo.Log.0.h"]),
            ("protected unsafe partial theorem i", &["i"]),
            ("open Nat in theorem j : True", &["j"]),
            ("/-- A docstring. -/ theorem k", &["k"]),
            ("theorem l.{u} (α : Sort u)", &["l"]),
            ("theorem\n  m : True", &["m"]),
            ("private\ntheorem n", &["_private.Gymemo.Log.0.n"]),
            ("private def o := 1\ntheorem p", &["p"]),
            ("@[simp theorem broken", &["broken"]),
            ("-- theorem commented", &[]),
            ("/-- theorem in a docstring -/", &[]),
            ("theorems are listed", &[]),
            ("def notATheorem : Nat := 1", &[]),
            ("theorem ", &[]),
            ("theorem : True", &[]),
        ] {
            assert_eq!(
                names(text),
                Ok(expected.iter().map(|name| (*name).to_owned()).collect()),
                "{text:?}"
            );
        }
    }

    #[test]
    fn a_theorem_takes_the_namespaces_around_it() {
        for (text, expected) in [
            (
                "namespace Gymemo.Log\ntheorem a : True\nend Gymemo.Log\ntheorem b : True\n",
                &["Gymemo.Log.a", "b"][..],
            ),
            (
                "namespace A\nnamespace B\ntheorem c\nend B\ntheorem d\nend A\n",
                &["A.B.c", "A.d"],
            ),
            (
                "namespace A.B\nend B\ntheorem e\nend A\ntheorem f",
                &["A.e", "f"],
            ),
            (
                "namespace A\nsection\ntheorem g\nend\nsection S.T\nnamespace N\ntheorem h\nend N\nend S.T\nnoncomputable section\ntheorem i\nend\nend A\n",
                &["A.g", "A.N.h", "A.i"],
            ),
            (
                "namespace A\nmutual\n  theorem j : True\n  private theorem k : True\nend\ntheorem l\n",
                &["A.j", "_private.Gymemo.Log.0.A.k", "A.l"],
            ),
            (
                "namespace A\ntheorem _root_.m : True\ntheorem n\n",
                &["m", "A.n"],
            ),
            (
                "/- namespace X\nend Y -/\nnamespace A -- end A\ntheorem o\n",
                &["A.o"],
            ),
            ("namespace\n  A\ntheorem p", &["A.p"]),
        ] {
            assert_eq!(
                names(text),
                Ok(expected.iter().map(|name| (*name).to_owned()).collect()),
                "{text:?}"
            );
        }
    }

    #[test]
    fn an_end_without_its_open_scope_stops_the_scan() {
        for (text, end) in [
            ("namespace A\nend B\ntheorem x", "2: `end B`"),
            ("end\ntheorem x", "1: `end`"),
            ("namespace A\nend\n", "2: `end`"),
            ("section S\nend\n", "2: `end`"),
            ("namespace A\nend A.B\n", "2: `end A.B`"),
            ("namespace A.B\nend A\n", "2: `end A`"),
        ] {
            assert_eq!(
                names(text),
                Err(Failure::new(format!(
                    "specs/lean/Gymemo/Log.lean:{end} closes no open namespace, section, or mutual block of that name, so the scan can't name the theorems after it"
                ))),
                "{text:?}"
            );
        }
    }

    #[test]
    fn every_declared_theorem_needs_a_line_in_the_listing() {
        let listed = [
            theorem("Gymemo.Strength.step_zero", &[]),
            theorem("_private.Gymemo.Log.0.Gymemo.hidden", &[]),
            theorem("Gymemo.stored", &[]),
        ];
        let sources = |log: &str| {
            vec![
                source("Gymemo.Log", &format!("namespace Gymemo\n{log}")),
                source(
                    "Gymemo.Strength",
                    "namespace Gymemo\ntheorem Strength.step_zero : True := trivial\ntheorem Strength.gone : True := trivial\nend Gymemo\n",
                ),
            ]
        };
        assert_eq!(
            complete(
                &sources("theorem stored : True\nprivate theorem hidden : True\n"),
                &listed
            ),
            Err(Failure::new(
                "These theorems of the sources have no line in the axiom listing:\nspecs/lean/Gymemo/Strength.lean: Gymemo.Strength.gone"
            ))
        );
        assert_eq!(
            complete(
                &sources(
                    "theorem store : True\ntheorem hidden.stored : True\ntheorem idden : True\n"
                ),
                &listed
            ),
            Err(Failure::new(
                "These theorems of the sources have no line in the axiom listing:\nspecs/lean/Gymemo/Log.lean: Gymemo.store\nspecs/lean/Gymemo/Log.lean: Gymemo.hidden.stored\nspecs/lean/Gymemo/Log.lean: Gymemo.idden\nspecs/lean/Gymemo/Strength.lean: Gymemo.Strength.gone"
            ))
        );
        assert_eq!(
            complete(&sources("theorem stored : True\n")[..1], &listed),
            Ok(())
        );
        assert_eq!(complete(&[], &[]), Ok(()));
        assert_eq!(
            complete(&[source("Gymemo.Log", "end Gymemo\n")], &listed),
            Err(Failure::new(
                "specs/lean/Gymemo/Log.lean:1: `end Gymemo` closes no open namespace, section, or mutual block of that name, so the scan can't name the theorems after it"
            ))
        );
    }

    #[test]
    fn a_listed_theorem_covers_no_other_theorem_that_shares_the_last_part_of_its_name() {
        let sources = [source(
            "Gymemo.StrengthProofs",
            "namespace Gymemo.Strength\ntheorem units_bound : True := trivial\nnamespace Planted\ntheorem units_bound : 2 + 2 = 4 := by native_decide\nend Planted\nend Gymemo.Strength\n",
        )];
        assert_eq!(
            complete(&sources, &[theorem("Gymemo.Strength.units_bound", &[])]),
            Err(Failure::new(
                "These theorems of the sources have no line in the axiom listing:\nspecs/lean/Gymemo/StrengthProofs.lean: Gymemo.Strength.Planted.units_bound"
            ))
        );
        let hidden = "namespace Gymemo\nprivate theorem hidden : True := trivial\n";
        assert_eq!(
            complete(
                &[
                    source("Gymemo.Log", hidden),
                    source("Gymemo.LogRun", hidden)
                ],
                &[theorem("_private.Gymemo.Log.0.Gymemo.hidden", &[])]
            ),
            Err(Failure::new(
                "These theorems of the sources have no line in the axiom listing:\nspecs/lean/Gymemo/LogRun.lean: _private.Gymemo.LogRun.0.Gymemo.hidden"
            ))
        );
        assert_eq!(
            complete(
                &[source("Gymemo.Log", hidden)],
                &[theorem("Gymemo.hidden", &[])]
            ),
            Err(Failure::new(
                "These theorems of the sources have no line in the axiom listing:\nspecs/lean/Gymemo/Log.lean: _private.Gymemo.Log.0.Gymemo.hidden"
            ))
        );
    }

    /// The refusal of code that runs whenever Lean imports the library, which precedes its places.
    const ON_IMPORT: &str = "These lines declare code that runs whenever Lean imports the library, and such code runs inside the process that prints the axiom listing:";

    /// The module of the verifier's plant, whose initializer reruns the listing and prints it without the planted axiom.
    pub const FORGED: &str = "namespace Gymemo.Strength\n\naxiom cheat : False\n\ntheorem planted : 1 = 2 := cheat.elim\n\ninitialize\n  let cmdline ← IO.FS.readFile \"/proc/self/cmdline\"\n  let inner ← IO.getEnv \"GYMEMO_VERIFIER_INNER\"\n  if inner.isNone && (cmdline.splitOn \"Axioms.lean\").length > 1 then\n    let child ← IO.Process.output {\n      cmd := \"lean\", args := #[\"Axioms.lean\"],\n      env := #[(\"GYMEMO_VERIFIER_INNER\", some \"1\")] }\n    for line in child.stdout.splitOn \"\\n\" do\n      unless line.isEmpty || line.startsWith \"axiom \" do\n        IO.println (line.replace \" axioms Gymemo.Strength.cheat\" \" axioms\")\n    IO.Process.exit 0\n\nend Gymemo.Strength\n";

    #[test]
    fn each_initializer_is_found_by_its_word_outside_comments_and_strings() {
        let file = "specs/lean/Gymemo/Log.lean";
        for (text, expected) in [
            ("initialize\n  pure ()\n", &["1: initialize"][..]),
            (
                "def a := 1\n\nbuiltin_initialize registry : IO.Ref Nat ← IO.mkRef 0\n",
                &["3: builtin_initialize"],
            ),
            (
                "private initialize\n@[simp] initialize\n/-- A docstring. -/initialize(pure ())\n  builtin_initialize\n",
                &[
                    "1: initialize",
                    "2: initialize",
                    "3: initialize",
                    "4: builtin_initialize",
                ],
            ),
            (FORGED, &["7: initialize"]),
            (
                "-- initialize\n/- initialize\nbuiltin_initialize -/\ndef s := \"initialize\"\ndef initialized := 1\ntheorem initialize_ok : True := trivial\n#check Gymemo.initialize\ndef builtin_initializer := 2\n",
                &[],
            ),
            ("", &[]),
        ] {
            assert_eq!(
                initializers(file, text),
                expected
                    .iter()
                    .map(|place| format!("{file}:{place}"))
                    .collect::<Vec<_>>(),
                "{text:?}"
            );
        }
    }

    #[test]
    fn a_module_or_a_library_file_with_an_initializer_is_refused_with_its_place() {
        let root = Path::new("/repo");
        let mut host = repository();
        host.file("/repo/specs/lean/Gymemo/Strength.lean", FORGED);
        host.file(
            "/repo/specs/lean/Gymemo/Log.lean",
            "namespace Gymemo\nbuiltin_initialize pure ()\n",
        );
        assert_eq!(
            modules(&mut host, root),
            Err(Failure::new(format!(
                "{ON_IMPORT}\nspecs/lean/Gymemo/Log.lean:2: builtin_initialize\nspecs/lean/Gymemo/Strength.lean:7: initialize"
            )))
        );
        assert_eq!(
            host.transcript(),
            [
                "read /repo/specs/lean/Gymemo.lean",
                "files /repo/specs/lean/Gymemo",
                "read /repo/specs/lean/Gymemo/Log.lean",
                "read /repo/specs/lean/Gymemo/Strength.lean"
            ]
        );
        let mut host = repository();
        host.file(
            "/repo/specs/lean/Gymemo.lean",
            "import Gymemo.Log\nimport Gymemo.Strength\n\ninitialize pure ()\n",
        );
        assert_eq!(
            modules(&mut host, root),
            Err(Failure::new(format!(
                "{ON_IMPORT}\nspecs/lean/Gymemo.lean:4: initialize"
            )))
        );
        assert_eq!(host.transcript(), ["read /repo/specs/lean/Gymemo.lean"]);
    }

    #[test]
    fn the_library_file_holds_only_imports_and_comments() {
        let root = Path::new("/repo");
        let mut host = repository();
        host.file(
            "/repo/specs/lean/Gymemo.lean",
            "import Gymemo.Log\nimport Gymemo.Strength\n\nset_option debug.skipKernelTC true in\ntheorem bogus : 1 = 2 := sorry\n",
        );
        assert_eq!(
            modules(&mut host, root),
            Err(Failure::new(
                "specs/lean/Gymemo.lean may hold only imports and comments, so that every declaration lives in a module under specs/lean/Gymemo, and it also holds:\nset_option debug.skipKernelTC true in\ntheorem bogus : 1 = 2 := sorry"
            ))
        );
        assert_eq!(host.transcript(), ["read /repo/specs/lean/Gymemo.lean"]);
        host.file(
            "/repo/specs/lean/Gymemo.lean",
            "/-! The library. -/\n/-\nimport Gymemo.Strength\n-/\nimport Gymemo.Log -- the log\n",
        );
        assert_eq!(
            modules(&mut host, root),
            Err(Failure::new(
                "specs/lean/Gymemo.lean leaves these modules out of the build: Gymemo.Strength"
            ))
        );
    }

    #[test]
    fn the_axioms_step_lists_holds_and_completes_the_theorems() {
        let root = Path::new("/repo");
        let mut host = repository();
        host.file(
            "/repo/specs/lean/Gymemo/README.md",
            "theorem ghost : True\n",
        );
        let lean = image(&mut host);
        assert_eq!(lean.and_then(|lean| axioms(&mut host, root, &lean)), Ok(4));
        assert_eq!(commands(&host), ["lake env lean Axioms.lean"]);
        assert_eq!(volumes(&host), ["/repo:/work:ro"]);
        assert!(host.transcript().iter().any(|line| line
            == "capture \"docker\" \"start\" \"--attach\" \"0000000000000000000000000000000000000000000000000000000000000001\""));
        assert!(
            host.transcript()
                .iter()
                .any(|line| line.contains("\"--workdir\" \"/work/specs/lean\""))
        );
        assert_eq!(
            host.transcript()
                .iter()
                .filter(|line| line.starts_with("read ") || line.starts_with("files "))
                .collect::<Vec<_>>(),
            [
                "files /repo/specs/lean/Gymemo",
                "read /repo/specs/lean/Gymemo/Log.lean",
                "read /repo/specs/lean/Gymemo/Strength.lean"
            ]
        );
        assert_eq!(host.containers(), 0);

        let mut host = repository();
        host.prints(
            "\"Axioms.lean\"",
            "theorems 1\ntheorem Gymemo.stored axioms propext sorryAx\n",
        );
        let lean = image(&mut host);
        assert_eq!(
            lean.and_then(|lean| axioms(&mut host, root, &lean)),
            Err(Failure::new(
                "These theorems rest on axioms beyond propext, Classical.choice, and Quot.sound:\nGymemo.stored: sorryAx"
            ))
        );
        let mut host = repository();
        host.prints(
            "\"Axioms.lean\"",
            &format!("{LISTING}theorem planted_false axioms cheat\naxiom cheat\n").replacen(
                "theorems 4",
                "theorems 5",
                1,
            ),
        );
        let lean = image(&mut host);
        assert_eq!(
            lean.and_then(|lean| axioms(&mut host, root, &lean)),
            Err(Failure::new(
                "The library declares these axioms, and its proofs may rest only on propext, Classical.choice, and Quot.sound: cheat"
            ))
        );
        let mut host = repository();
        host.prints("\"Axioms.lean\"", &format!("{LISTING}axiom cheat\n"));
        let lean = image(&mut host);
        assert_eq!(
            lean.and_then(|lean| axioms(&mut host, root, &lean)),
            Err(Failure::new(
                "The library declares these axioms, and its proofs may rest only on propext, Classical.choice, and Quot.sound: cheat"
            ))
        );
        let mut host = repository();
        host.prints(
            "\"Axioms.lean\"",
            "theorems 1\ntheorem Gymemo.stored axioms \n",
        );
        let lean = image(&mut host);
        assert_eq!(
            lean.and_then(|lean| axioms(&mut host, root, &lean)),
            Err(Failure::new(
                "These theorems of the sources have no line in the axiom listing:\nspecs/lean/Gymemo/Log.lean: _private.Gymemo.Log.0.Gymemo.hidden\nspecs/lean/Gymemo/Strength.lean: Gymemo.Strength.step_zero"
            ))
        );
        let mut host = repository();
        host.file(
            "/repo/specs/lean/Gymemo/Strength.lean",
            "namespace Gymemo\nend Gymemo.Strength\n",
        );
        let lean = image(&mut host);
        assert_eq!(
            lean.and_then(|lean| axioms(&mut host, root, &lean)),
            Err(Failure::new(
                "specs/lean/Gymemo/Strength.lean:2: `end Gymemo.Strength` closes no open namespace, section, or mutual block of that name, so the scan can't name the theorems after it"
            ))
        );
        let mut host = repository();
        host.prints("\"Axioms.lean\"", "theorems 0\n");
        host.file("/repo/specs/lean/Gymemo/Log.lean", "");
        host.file("/repo/specs/lean/Gymemo/Strength.lean", "");
        let lean = image(&mut host);
        assert_eq!(
            lean.and_then(|lean| axioms(&mut host, root, &lean)),
            Err(Failure::new(
                "The axiom listing of Axioms.lean holds no theorem"
            ))
        );
        let mut host = repository();
        host.ends("\"Axioms.lean\"", Ending::Exit(1));
        host.prints(
            "\"Axioms.lean\"",
            "Axioms.lean:1:0: error: unknown module\n",
        );
        let lean = image(&mut host);
        assert_eq!(
            lean.and_then(|lean| axioms(&mut host, root, &lean)),
            Err(Failure::new(
                "`lake env lean Axioms.lean` failed with exit code 1 in its container:\nAxioms.lean:1:0: error: unknown module"
            ))
        );
    }

    #[test]
    fn the_build_and_the_replay_run_each_in_its_own_bounded_step() {
        let root = Path::new("/repo");
        let modules = ["Gymemo.Log".to_owned(), "Gymemo.Strength".to_owned()];
        let mut host = repository();
        let lean = image(&mut host);
        assert_eq!(
            lean.and_then(|lean| build(&mut host, root, &lean)
                .and_then(|()| replay(&mut host, root, &lean, &modules))),
            Ok(())
        );
        assert_eq!(
            commands(&host),
            [
                "lake build --wfail",
                "lake env leanchecker --fresh Gymemo.Log",
                "lake env leanchecker --fresh Gymemo.Strength"
            ]
        );
        assert_eq!(
            volumes(&host),
            ["/repo:/work", "/repo:/work:ro", "/repo:/work:ro"]
        );
        assert_eq!(
            host.transcript()
                .iter()
                .filter(|line| line.starts_with("show \"docker\" \"start\""))
                .count(),
            3
        );
        assert_eq!(host.containers(), 0);

        let mut host = repository();
        host.ends("\"Gymemo.Log\"", Ending::OutOfMemory(137));
        let lean = image(&mut host);
        let replayed = lean.and_then(|lean| replay(&mut host, root, &lean, &modules));
        assert_eq!(
            replayed,
            Err(Failure::inconclusive(
                "`lake env leanchecker --fresh Gymemo.Log` reached the memory limit of 2 GiB without swap"
            ))
        );
        assert_eq!(commands(&host), ["lake env leanchecker --fresh Gymemo.Log"]);

        let mut host = repository();
        host.ends("\"lake\" \"build\"", Ending::Exit(1));
        let lean = image(&mut host);
        assert_eq!(
            lean.and_then(|lean| build(&mut host, root, &lean)),
            Err(Failure::new(
                "`lake build --wfail` failed with exit code 1 in its container"
            ))
        );
        let mut host = repository();
        host.fail("\"create\"", Fault::Missing);
        let lean = image(&mut host);
        assert!(lean.and_then(|lean| build(&mut host, root, &lean)).is_err());
    }
}
