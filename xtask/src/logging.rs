//! Keeps console output out of the shipped code and keeps the training log out of public log fields.
//!
//! Apple's [logging guide](https://developer.apple.com/documentation/os/generating-log-messages-from-your-code) asks apps to redact any value that contains sensitive user information.

use crate::{
    failure::{Result, ensure},
    swift_source::{self, SHIPPED, code_only},
};
use std::path::Path;

/// Functions that write to standard output or the console instead of the unified logging system.
const CONSOLE_CALLS: [&str; 4] = ["print", "debugPrint", "dump", "NSLog"];
const PUBLIC: &str = "privacy: .public)";

/// Every expression that a log line may mark `.public`.
/// Each one is an enum raw value or a result code, so none carries an exercise name, a memo, or a set.
const PUBLIC_VALUES: [&str; 2] = ["operation.rawValue", "code"];

/// The planted lines that the check must refuse, which show that it reads what it claims to read.
const PLANTED: [&str; 3] = [
    "print(\"store.load\")\n",
    "logger.error(\"failed \\(String(describing: error), privacy: .public)\")\n",
    "logger.info(\"memo=\\(memo.text, privacy: .public)\")\n",
];

fn console_calls(source: &str, file: &str) -> Vec<String> {
    let mut found = Vec::new();
    for (index, line) in code_only(source).lines().enumerate() {
        for call in CONSOLE_CALLS {
            let mut start = 0;
            while let Some(offset) = line[start..].find(call) {
                let at = start + offset;
                let before = line[..at].chars().next_back();
                let after = line[at + call.len()..].trim_start().chars().next();
                if !before.is_some_and(|c| c.is_alphanumeric() || c == '_' || c == '.')
                    && after == Some('(')
                {
                    found.push(format!(
                        "{file}:{}: {call} writes to the console",
                        index + 1
                    ));
                }
                start = at + call.len();
            }
        }
    }
    found
}

/// The line and the expression of each `\(expression, privacy: .public)` interpolation.
fn public_interpolations(source: &str) -> Vec<(usize, String)> {
    let mut found = Vec::new();
    let mut start = 0;
    while let Some(offset) = source[start..].find(PUBLIC) {
        let at = start + offset;
        let line = source[..at].matches('\n').count() + 1;
        let head = source[..at].trim_end();
        let head = head.strip_suffix(',').unwrap_or(head);
        let mut depth = 0usize;
        let mut expression = None;
        for (index, character) in head.char_indices().rev() {
            match character {
                ')' => depth += 1,
                '(' if depth == 0 => {
                    if head[..index].ends_with('\\') {
                        expression = Some(head[index + 1..].split_whitespace().collect::<Vec<_>>());
                    }
                    break;
                }
                '(' => depth -= 1,
                _ => {}
            }
        }
        found.push((
            line,
            expression.map_or_else(
                || "an unreadable expression".to_owned(),
                |words| words.join(" "),
            ),
        ));
        start = at + PUBLIC.len();
    }
    found
}

fn public_findings(source: &str, file: &str) -> Vec<String> {
    public_interpolations(source)
        .into_iter()
        .filter(|(_, expression)| !PUBLIC_VALUES.contains(&expression.as_str()))
        .map(|(line, expression)| {
            format!("{file}:{line}: a public log value is not a listed code: {expression}")
        })
        .collect()
}

fn findings(source: &str, file: &str) -> Vec<String> {
    let mut found = console_calls(source, file);
    found.extend(public_findings(source, file));
    found
}

/// Scans the shipped Swift code and refuses console output and unlisted public log values.
pub fn check(root: &Path) -> Result<String> {
    let sources = swift_source::read(root, &SHIPPED)?;
    let found = sources
        .iter()
        .flat_map(|source| findings(&source.text, &source.file))
        .collect::<Vec<_>>();
    ensure(found.is_empty(), || {
        format!("Logging breaks the privacy rule:\n{}", found.join("\n"))
    })?;
    for planted in PLANTED {
        ensure(!findings(planted, "planted.swift").is_empty(), || {
            format!("The log check accepted a planted line: {planted}")
        })?;
    }
    let public = sources
        .iter()
        .map(|source| public_interpolations(&source.text).len())
        .sum::<usize>();
    Ok(format!(
        "{} Swift files keep the console silent, {public} public log values are listed codes, and {} planted lines fail",
        sources.len(),
        PLANTED.len()
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn console_calls_count_only_in_code() {
        assert_eq!(console_calls("print(\"x\")\n", "a.swift").len(), 1);
        assert_eq!(console_calls("  NSLog (\"x\")\n", "a.swift").len(), 1);
        assert_eq!(console_calls("debugPrint(value)\n", "a.swift").len(), 1);
        assert!(console_calls("// print(\"x\")\n", "a.swift").is_empty());
        assert!(console_calls("/* dump(x) */\n", "a.swift").is_empty());
        assert!(console_calls("let text = \"print(x)\"\n", "a.swift").is_empty());
        assert!(console_calls("blueprint(x)\nlogger.dump(x)\nfootprint()\n", "a.swift").is_empty());
    }

    #[test]
    fn public_values_must_be_listed() {
        let valid = "logger.error(\"store.\\(operation.rawValue, privacy: .public) code=\\(code, privacy: .public)\")\n";
        assert!(findings(valid, "a.swift").is_empty());
        let private = "logger.error(\"name=\\(exercise.name.text, privacy: .private)\")\n";
        assert!(findings(private, "a.swift").is_empty());
        for planted in PLANTED {
            assert!(!findings(planted, "planted.swift").is_empty(), "{planted}");
        }
    }

    #[test]
    fn the_shipped_swift_code_passes() -> Result<()> {
        check(&Path::new(env!("CARGO_MANIFEST_DIR")).join("..")).map(|_| ())
    }
}
