//! Keeps console output out of the shipped code and keeps the training log out of public log fields.
//!
//! Apple's [logging guide](https://developer.apple.com/documentation/os/generating-log-messages-from-your-code) asks apps to redact any value that contains sensitive user information.
//! The public marks and their values come from the code and the interpolations that the lexer reads.
//! A mark inside a comment or inside the text of a literal counts for nothing.

use crate::{
    failure::{Result, ensure},
    swift_source::{self, SHIPPED, code_only, interpolations},
};
use std::path::Path;

/// Functions that write to standard output or the console instead of the unified logging system.
const CONSOLE_CALLS: [&str; 4] = ["print", "debugPrint", "dump", "NSLog"];
/// The label and the value of the argument that marks a log value public, as in `privacy: .public`.
/// Any blanks and line feeds may stand between the two, and the code-only view also leaves blanks where a comment stood.
const PRIVACY: &str = "privacy:";
const PUBLIC: &str = ".public";
/// The characters that may stand between the label and the value of a mark.
const BLANKS: [char; 3] = [' ', '\t', '\n'];
/// What the check names in place of the expression of a public mark that ends no interpolation.
const UNREADABLE: &str = "an unreadable expression";

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
            for (at, _) in line.match_indices(call) {
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
            }
        }
    }
    found
}

/// The line of each mark `privacy: .public` in `code`, which is the line of its label, in the order of the marks.
fn public_marks(code: &str) -> Vec<usize> {
    code.match_indices(PRIVACY)
        .filter(|(at, label)| {
            code[at + label.len()..]
                .trim_start_matches(BLANKS)
                .starts_with(PUBLIC)
        })
        .map(|(at, _)| 1 + code[..at].matches('\n').count())
        .collect()
}

/// The line and the expression of each value that the code marks public, in the order of the lines.
/// The mark stands last in an interpolation, as in `\(expression, privacy: .public)`.
/// Anywhere else in the code it publishes a value that the check can't read.
/// Each value counts on the line of the label of its mark, so the marks of a line that no value takes are the unreadable ones.
fn public_interpolations(source: &str) -> Vec<(usize, String)> {
    let mut found = Vec::new();
    for interpolation in interpolations(source) {
        if let Some(value) = interpolation
            .code
            .trim_end()
            .strip_suffix(PUBLIC)
            .and_then(|rest| rest.trim_end_matches(BLANKS).strip_suffix(PRIVACY))
        {
            let line = interpolation.line + value.matches('\n').count();
            let value = value.trim_end();
            let value = value.strip_suffix(',').unwrap_or(value);
            let words = value.split_whitespace().collect::<Vec<_>>();
            found.push((line, words.join(" ")));
        }
    }
    for marks in public_marks(&code_only(source)).chunk_by(|one, other| one == other) {
        let line = marks[0];
        let read = found.iter().filter(|(at, _)| *at == line).count();
        for _ in read..marks.len() {
            found.push((line, UNREADABLE.to_owned()));
        }
    }
    found.sort_by_key(|(line, _)| *line);
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
    use crate::{
        failure::Failure,
        swift_source::fixture::{
            KEYWORD_SCREEN, OPERATOR_SCREEN, Tree, after_patterns, after_slashes, around_operators,
            around_raw_identifiers, places_after_patterns, places_after_slashes,
            places_around_operators, places_around_raw_identifiers,
        },
    };

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

    /// One public value as `public_interpolations` returns it.
    fn value(line: usize, expression: &str) -> (usize, String) {
        (line, expression.to_owned())
    }

    /// A repository with one screen and one store file that holds `text`.
    fn shipped(name: &str, text: &str) -> Result<Tree> {
        Tree::new(
            name,
            &[
                ("App/Screen.swift", "import SwiftUI\n"),
                ("Sources/GymemoKit/Trace.swift", text),
            ],
        )
    }

    #[test]
    fn silent_code_passes_with_the_numbers_of_its_files_and_public_values() -> Result<()> {
        let tree = shipped(
            "logging-clean",
            "import os\nlogger.error(\n  \"store.\\(operation.rawValue, privacy: .public) failed code=\\(code, privacy: .public)\")\nlogger.error(\"code=\\(code, privacy: .public)\")\n",
        )?;
        assert_eq!(
            check(tree.root()),
            Ok("2 Swift files keep the console silent, 3 public log values are listed codes, and 3 planted lines fail".to_owned())
        );
        Ok(())
    }

    #[test]
    fn console_output_and_an_unlisted_public_value_are_refused_with_their_file_and_line()
    -> Result<()> {
        let tree = shipped(
            "logging-loud",
            "import os\nprint(memo)\nlogger.info(\"memo=\\(memo.text, privacy: .public)\")\n",
        )?;
        assert_eq!(
            check(tree.root()),
            Err(Failure::new(
                "Logging breaks the privacy rule:\n\
                 Sources/GymemoKit/Trace.swift:2: print writes to the console\n\
                 Sources/GymemoKit/Trace.swift:3: a public log value is not a listed code: memo.text"
            ))
        );
        Ok(())
    }

    #[test]
    fn each_console_call_of_a_line_is_found_once() {
        assert_eq!(
            console_calls("print(a); print(b)\n\ndump(print(c))\n", "a.swift"),
            [
                "a.swift:1: print writes to the console",
                "a.swift:1: print writes to the console",
                "a.swift:3: print writes to the console",
                "a.swift:3: dump writes to the console",
            ]
        );
    }

    #[test]
    fn a_console_call_inside_an_interpolation_is_found() {
        assert_eq!(
            console_calls("let text = \"\\(print(x))\"\n", "a.swift"),
            ["a.swift:1: print writes to the console"]
        );
    }

    #[test]
    fn a_console_call_after_a_multiline_literal_that_holds_a_quote_is_found_on_its_line() {
        let source =
            "let row = \"\"\"\n  {\"id\":\\(id),\\\n  \"name\":\"\\(name)}\n  \"\"\"\nprint(row)\n";
        assert_eq!(
            console_calls(source, "a.swift"),
            ["a.swift:5: print writes to the console"]
        );
    }

    #[test]
    fn a_console_call_after_a_comment_or_a_regular_expression_that_holds_quotes_is_found()
    -> Result<()> {
        let mut files = after_slashes("Sources/GymemoKit", "print(x)");
        files.push(("App/Screen.swift".to_owned(), "import SwiftUI\n".to_owned()));
        let tree = Tree::new("logging-slashes", &files)?;
        let found = places_after_slashes("Sources/GymemoKit")
            .iter()
            .map(|place| format!("{place}: print writes to the console"))
            .collect::<Vec<_>>();
        assert_eq!(
            check(tree.root()),
            Err(Failure::new(format!(
                "Logging breaks the privacy rule:\n{}",
                found.join("\n")
            )))
        );
        Ok(())
    }

    #[test]
    fn a_console_call_between_the_slash_of_an_operator_and_a_division_is_found() -> Result<()> {
        let mut files = around_operators("Sources/GymemoKit", "print(x)");
        files.push(("App/Screen.swift".to_owned(), "import SwiftUI\n".to_owned()));
        let tree = Tree::new("logging-operators", &files)?;
        let found = places_around_operators("Sources/GymemoKit")
            .iter()
            .map(|place| format!("{place}: print writes to the console"))
            .collect::<Vec<_>>();
        assert_eq!(
            check(tree.root()),
            Err(Failure::new(format!(
                "Logging breaks the privacy rule:\n{}",
                found.join("\n")
            )))
        );
        Ok(())
    }

    #[test]
    fn a_console_call_beside_a_raw_identifier_is_found() -> Result<()> {
        let mut files = around_raw_identifiers("Sources/GymemoKit", "print(x)");
        files.push(("App/Screen.swift".to_owned(), "import SwiftUI\n".to_owned()));
        let tree = Tree::new("logging-raw-identifiers", &files)?;
        let found = places_around_raw_identifiers("Sources/GymemoKit")
            .iter()
            .map(|place| format!("{place}: print writes to the console"))
            .collect::<Vec<_>>();
        assert_eq!(
            check(tree.root()),
            Err(Failure::new(format!(
                "Logging breaks the privacy rule:\n{}",
                found.join("\n")
            )))
        );
        Ok(())
    }

    /// Each file of `AFTER_PATTERNS` writes to the console on the line after its regular expression literal, and the screens of `OPERATOR_SCREEN` and `KEYWORD_SCREEN` write on line 8.
    #[test]
    fn a_console_call_after_a_regular_expression_that_holds_quotes_or_a_comment_mark_is_found()
    -> Result<()> {
        let mut files = after_patterns("Sources/GymemoKit", "print(x)");
        files.push(("App/Screen.swift".to_owned(), KEYWORD_SCREEN.to_owned()));
        files.push(("App/Operator.swift".to_owned(), OPERATOR_SCREEN.to_owned()));
        let tree = Tree::new("logging-keywords", &files)?;
        let found = ["App/Operator.swift:8", "App/Screen.swift:8"]
            .map(str::to_owned)
            .into_iter()
            .chain(places_after_patterns("Sources/GymemoKit"))
            .map(|place| format!("{place}: print writes to the console"))
            .collect::<Vec<_>>();
        assert_eq!(
            check(tree.root()),
            Err(Failure::new(format!(
                "Logging breaks the privacy rule:\n{}",
                found.join("\n")
            )))
        );
        Ok(())
    }

    #[test]
    fn a_public_value_is_read_with_its_line_and_its_whole_expression() {
        assert_eq!(
            public_interpolations(
                "logger.error(\"store.\\(operation.rawValue, privacy: .public) code=\\(code, privacy: .public)\")\n"
            ),
            [value(1, "operation.rawValue"), value(1, "code")]
        );
        assert_eq!(
            public_interpolations(
                "\nlogger.error(\"failed \\(String(describing: error), privacy: .public)\")\n"
            ),
            [value(2, "String(describing: error)")]
        );
        assert_eq!(
            public_interpolations(
                "logger.info(\"count=\\(sets.count, format: .decimal, privacy: .public)\")\n"
            ),
            [value(1, "sets.count, format: .decimal")]
        );
        assert!(
            public_interpolations("logger.info(\"name=\\(name, privacy: .private)\")\n").is_empty()
        );
    }

    #[test]
    fn a_public_value_that_spans_lines_is_read_on_the_line_of_its_mark() {
        let source = "\nlogger.error(\n  \"\"\"\n  failed \\(\n    error.code,\n    privacy: .public)\n  \"\"\")\n";
        assert_eq!(public_interpolations(source), [value(6, "error.code")]);
    }

    #[test]
    fn a_parenthesis_inside_a_literal_of_the_expression_does_not_end_the_value() {
        let source =
            "logger.info(\"names=\\(names.joined(separator: \")\"), privacy: .public)\")\n";
        assert_eq!(
            public_interpolations(source),
            [value(1, "names.joined(separator: \" \")")]
        );
    }

    #[test]
    fn a_public_value_in_a_raw_literal_is_read() {
        assert_eq!(
            public_interpolations("logger.info(#\"memo=\\#(memo.text, privacy: .public)\"#)\n"),
            [value(1, "memo.text")]
        );
        assert!(
            findings(
                "logger.error(#\"code=\\#(code, privacy: .public)\"#)\n",
                "a.swift"
            )
            .is_empty()
        );
        assert!(public_interpolations("let text = #\"\\(code, privacy: .public)\"#\n").is_empty());
    }

    #[test]
    fn a_public_mark_in_a_comment_or_in_the_text_of_a_literal_is_no_value() {
        assert!(
            public_interpolations("// logger.info(\"memo=\\(memo.text, privacy: .public)\")\n")
                .is_empty()
        );
        assert!(public_interpolations("/* \\(memo.text, privacy: .public) */\n").is_empty());
        assert!(public_interpolations("let label = \"privacy: .public)\"\n").is_empty());
    }

    #[test]
    fn a_public_mark_outside_an_interpolation_is_refused_as_unreadable() {
        assert_eq!(
            public_interpolations(
                "logger.info(\"code=\\(code, privacy: .public)\")\nnote(memo.text, privacy: .public)\n"
            ),
            [value(1, "code"), value(2, "an unreadable expression")]
        );
        assert_eq!(
            public_interpolations(
                "logger.info(\"memo=\\(redact(memo.text, privacy: .public))\")\n"
            ),
            [value(1, "an unreadable expression")]
        );
        assert_eq!(
            findings("note(memo.text, privacy: .public)\n", "a.swift"),
            ["a.swift:1: a public log value is not a listed code: an unreadable expression"]
        );
    }

    #[test]
    fn a_public_mark_reads_with_any_blanks_between_its_label_and_its_value() {
        assert_eq!(
            public_interpolations(
                "logger.info(\"m=\\(memo.text, privacy:.public) c=\\(code, privacy:  /* c */ .public)\")\n"
            ),
            [value(1, "memo.text"), value(1, "code")]
        );
        assert_eq!(
            public_interpolations("note(memo.text, privacy:.public)\n"),
            [value(1, "an unreadable expression")]
        );
        assert_eq!(
            findings(
                "logger.info(\"m=\\(memo.text, privacy:.public)\")\n",
                "a.swift"
            ),
            ["a.swift:1: a public log value is not a listed code: memo.text"]
        );
    }

    /// A line feed may stand between the label and the value of a mark, inside an interpolation of a literal between three quotes and outside every literal.
    /// The check reads such a mark on the line of its label, so a value that ends an interpolation takes one mark of that line and leaves the others unreadable.
    #[test]
    fn a_public_mark_across_a_line_break_is_read_on_the_line_of_its_label() {
        let split = "let a = \"\"\"\n  \\(note(memo.text, privacy: .public)) \\(code, privacy:\n  .public)\n  \"\"\"\nnote(memo.text, privacy:\n\n  .public)\n";
        assert_eq!(
            public_interpolations(split),
            [
                value(2, "code"),
                value(2, "an unreadable expression"),
                value(5, "an unreadable expression")
            ]
        );
        assert_eq!(
            public_interpolations(
                "logger.info(\"\"\"\n  \\(memo.text, privacy:\n  .public)\n  \"\"\")\n"
            ),
            [value(2, "memo.text")]
        );
    }

    #[test]
    fn public_values_come_in_the_order_of_their_lines() {
        let source = "note(memo.text, privacy: .public)\nlogger.info(\"code=\\(code, privacy: .public)\")\nnote(memo.text, privacy: .public, 1)\n";
        assert_eq!(
            public_interpolations(source),
            [
                value(1, "an unreadable expression"),
                value(2, "code"),
                value(3, "an unreadable expression")
            ]
        );
    }
}
