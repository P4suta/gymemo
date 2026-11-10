//! Keeps clocks, randomness, files, processes, and traps out of the pure core.
//!
//! `Sources/GymemoCore` decides from values alone, and `docs/adr/derive-every-screen-from-one-immutable-training-log.md` relies on that.
//! SwiftLint refuses force unwrapping, `try!`, and `as!`, so this check covers the names.

use crate::{
    failure::{Result, ensure},
    swift_source::{self, code_only, names},
};
use std::path::Path;

const CORE: &str = "Sources/GymemoCore";

/// The one module the core may import, for value types such as `UUID` and `Data`.
const PERMITTED_IMPORT: &str = "Foundation";

/// Names that read the world, write to it, or stop the process.
const REFUSED_NAMES: [&str; 28] = [
    "Date",
    "Calendar",
    "TimeZone",
    "Locale",
    "FileManager",
    "FileHandle",
    "UserDefaults",
    "ProcessInfo",
    "URLSession",
    "DispatchQueue",
    "Thread",
    "Task",
    "Logger",
    "print",
    "debugPrint",
    "dump",
    "NSLog",
    "fatalError",
    "preconditionFailure",
    "precondition",
    "assertionFailure",
    "assert",
    "exit",
    "abort",
    "random",
    "randomElement",
    "shuffled",
    "SystemRandomNumberGenerator",
];

/// The type whose call without arguments draws a random identifier.
const RANDOM_IDENTIFIER: &str = "UUID";

/// The planted lines that the check must refuse, which show that it reads what it claims to read.
const PLANTED: [&str; 4] = [
    "let today = Date()\n",
    "let id = SetID(UUID())\n",
    "import os\n",
    "let pick = values.randomElement()\n",
];

/// Whether `line` calls `UUID` without arguments.
/// Blanks may stand before and inside the parentheses, as they do where the code-only view hides a comment.
fn draws_identifier(line: &str) -> bool {
    line.match_indices(RANDOM_IDENTIFIER).any(|(at, name)| {
        line[at + name.len()..]
            .trim_start()
            .strip_prefix('(')
            .is_some_and(|arguments| arguments.trim_start().starts_with(')'))
    })
}

/// Each effect that `source` names, located by its file and its line.
fn findings(source: &str, file: &str) -> Vec<String> {
    let mut found = Vec::new();
    for (index, line) in code_only(source).lines().enumerate() {
        let place = format!("{file}:{}", index + 1);
        if let Some(module) = line.trim().strip_prefix("import ")
            && module.trim() != PERMITTED_IMPORT
        {
            found.push(format!(
                "{place} imports {}, and the core imports only {PERMITTED_IMPORT}",
                module.trim()
            ));
        }
        for name in REFUSED_NAMES {
            if names(line, name) {
                found.push(format!(
                    "{place} names {name}, and the core decides from values alone"
                ));
            }
        }
        if draws_identifier(line) {
            found.push(format!(
                "{place} draws a random identifier, and an adapter passes identifiers in"
            ));
        }
    }
    found
}

/// Scans the core and refuses any named effect.
pub fn check(root: &Path) -> Result<String> {
    let sources = swift_source::read(root, &[CORE])?;
    let found = sources
        .iter()
        .flat_map(|source| findings(&source.text, &source.file))
        .collect::<Vec<_>>();
    ensure(found.is_empty(), || {
        format!("The core names an effect:\n{}", found.join("\n"))
    })?;
    for planted in PLANTED {
        ensure(!findings(planted, "planted.swift").is_empty(), || {
            format!("The purity check accepted a planted line: {planted}")
        })?;
    }
    Ok(format!(
        "{} core files decide from values alone, and {} planted effects fail",
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
    fn values_pass_and_effects_fail() {
        for allowed in [
            "import Foundation\n",
            "let id = SetID(UUID(uuid: bytes))\n",
            "let text = \"Date()\" // Date()\n",
            "let updated = candidate.day\n",
            "func validate(_ day: LocalDay) -> Bool { true }\n",
        ] {
            assert!(findings(allowed, "a.swift").is_empty(), "{allowed}");
        }
        for refused in [
            "let now = Date.now\n",
            "let zone = TimeZone.current\n",
            "let value = Int.random(in: 0..<3)\n",
            "fatalError(\"unreachable\")\n",
            "import os.log\n",
            "print(log)\n",
        ] {
            assert_eq!(findings(refused, "a.swift").len(), 1, "{refused}");
        }
        for planted in PLANTED {
            assert!(!findings(planted, "planted.swift").is_empty(), "{planted}");
        }
    }

    #[test]
    fn the_shipped_core_passes() -> Result<()> {
        check(&Path::new(env!("CARGO_MANIFEST_DIR")).join("..")).map(|_| ())
    }

    /// A repository whose core holds one file with `text`.
    fn core(name: &str, text: &str) -> Result<Tree> {
        Tree::new(name, &[("Sources/GymemoCore/Rows.swift", text)])
    }

    /// The refusal that names `findings` of the one file of `core`.
    fn refusal(findings: &[&str]) -> Result<String> {
        let found = findings
            .iter()
            .map(|finding| format!("Sources/GymemoCore/Rows.swift:{finding}"))
            .collect::<Vec<_>>();
        Err(Failure::new(format!(
            "The core names an effect:\n{}",
            found.join("\n")
        )))
    }

    #[test]
    fn a_clean_core_passes_with_the_number_of_its_files() -> Result<()> {
        let tree = Tree::new(
            "purity-clean",
            &[
                ("Sources/GymemoCore/Day.swift", "import Foundation\n"),
                ("Sources/GymemoCore/Sets/Reps.swift", "struct Reps {}\n"),
                ("Sources/GymemoCore/Notes.md", "Date()\n"),
            ],
        )?;
        assert_eq!(
            check(tree.root()),
            Ok("2 core files decide from values alone, and 4 planted effects fail".to_owned())
        );
        Ok(())
    }

    #[test]
    fn each_effect_in_the_core_is_refused_with_its_file_and_line() -> Result<()> {
        let tree = core(
            "purity-effects",
            "import Foundation\n\nlet today = Date()\nimport os\nlet id = SetID(UUID())\n",
        )?;
        assert_eq!(
            check(tree.root()),
            refusal(&[
                "3 names Date, and the core decides from values alone",
                "4 imports os, and the core imports only Foundation",
                "5 draws a random identifier, and an adapter passes identifiers in",
            ])
        );
        Ok(())
    }

    #[test]
    fn a_core_without_swift_files_is_refused() -> Result<()> {
        let tree = Tree::new(
            "purity-empty",
            &[("Sources/GymemoCore/Notes.md", "notes\n")],
        )?;
        assert_eq!(
            check(tree.root()),
            Err(Failure::new(
                "Found no Swift files under Sources/GymemoCore"
            ))
        );
        Ok(())
    }

    #[test]
    fn a_line_that_a_backslash_continues_keeps_the_number_of_each_later_line() -> Result<()> {
        let tree = core(
            "purity-continued-line",
            "let row = \"\"\"\n  {\"id\":\\(id),\\\n  \"name\":\\(name)}\n  \"\"\"\nlet today = Date()\n",
        )?;
        assert_eq!(
            check(tree.root()),
            refusal(&["5 names Date, and the core decides from values alone"])
        );
        Ok(())
    }

    #[test]
    fn an_effect_after_a_multiline_literal_that_holds_a_quote_is_refused() -> Result<()> {
        let tree = core(
            "purity-quote",
            "let note = \"\"\"\n  say \"hi\n  \"\"\"\nlet today = Date()\n",
        )?;
        assert_eq!(
            check(tree.root()),
            refusal(&["4 names Date, and the core decides from values alone"])
        );
        Ok(())
    }

    #[test]
    fn an_effect_after_a_nested_comment_is_refused() -> Result<()> {
        let tree = core(
            "purity-nested-comment",
            "/* outer /* inner */ \" still the comment */\nlet today = Date()\n",
        )?;
        assert_eq!(
            check(tree.root()),
            refusal(&["2 names Date, and the core decides from values alone"])
        );
        Ok(())
    }

    #[test]
    fn an_effect_after_a_raw_literal_is_refused() -> Result<()> {
        let tree = core(
            "purity-raw-literal",
            "let slash = #\"\\\"#\nlet today = Date()\n",
        )?;
        assert_eq!(
            check(tree.root()),
            refusal(&["2 names Date, and the core decides from values alone"])
        );
        Ok(())
    }

    #[test]
    fn an_effect_inside_an_interpolation_is_refused() -> Result<()> {
        let tree = core("purity-interpolation", "let stamp = \"at \\(Date())\"\n")?;
        assert_eq!(
            check(tree.root()),
            refusal(&["1 names Date, and the core decides from values alone"])
        );
        Ok(())
    }

    #[test]
    fn an_effect_after_a_comment_mark_inside_a_regular_expression_is_refused() -> Result<()> {
        let tree = core(
            "purity-regular-expression",
            "let r = #/a/*b/#\nlet s = 1 /* z */; let d = Date()\nlet q = /\\/*/\nlet t = 2 /* z */; let e = Date()\n",
        )?;
        assert_eq!(
            check(tree.root()),
            refusal(&[
                "2 names Date, and the core decides from values alone",
                "4 names Date, and the core decides from values alone",
            ])
        );
        Ok(())
    }

    #[test]
    fn a_random_identifier_with_blanks_or_a_comment_around_its_parentheses_is_refused() -> Result<()>
    {
        let tree = core(
            "purity-spaced-identifier",
            "let a = UUID(/* c */)\nlet b = UUID( )\nlet c = UUID ()\nlet d = UUID/**/()\nlet e = UUID(uuid: bytes)\n",
        )?;
        assert_eq!(
            check(tree.root()),
            refusal(&[
                "1 draws a random identifier, and an adapter passes identifiers in",
                "2 draws a random identifier, and an adapter passes identifiers in",
                "3 draws a random identifier, and an adapter passes identifiers in",
                "4 draws a random identifier, and an adapter passes identifiers in",
            ])
        );
        Ok(())
    }

    #[test]
    fn an_effect_after_a_comment_or_a_regular_expression_that_holds_quotes_is_refused() -> Result<()>
    {
        let tree = Tree::new("purity-slashes", &after_slashes(CORE, "let now = Date()"))?;
        let found = places_after_slashes(CORE)
            .iter()
            .map(|place| format!("{place} names Date, and the core decides from values alone"))
            .collect::<Vec<_>>();
        assert_eq!(
            check(tree.root()),
            Err(Failure::new(format!(
                "The core names an effect:\n{}",
                found.join("\n")
            )))
        );
        Ok(())
    }

    #[test]
    fn an_effect_between_the_slash_of_an_operator_and_a_division_is_refused() -> Result<()> {
        let tree = Tree::new(
            "purity-operators",
            &around_operators(CORE, "let now = Date()"),
        )?;
        let found = places_around_operators(CORE)
            .iter()
            .map(|place| format!("{place} names Date, and the core decides from values alone"))
            .collect::<Vec<_>>();
        assert_eq!(
            check(tree.root()),
            Err(Failure::new(format!(
                "The core names an effect:\n{}",
                found.join("\n")
            )))
        );
        Ok(())
    }

    #[test]
    fn an_effect_beside_a_raw_identifier_is_refused() -> Result<()> {
        let tree = Tree::new(
            "purity-raw-identifiers",
            &around_raw_identifiers(CORE, "let now = Date()"),
        )?;
        let found = places_around_raw_identifiers(CORE)
            .iter()
            .map(|place| format!("{place} names Date, and the core decides from values alone"))
            .collect::<Vec<_>>();
        assert_eq!(
            check(tree.root()),
            Err(Failure::new(format!(
                "The core names an effect:\n{}",
                found.join("\n")
            )))
        );
        Ok(())
    }

    /// Each file of `AFTER_PATTERNS` names its effect on the line after its regular expression literal, and the screens of `OPERATOR_SCREEN` and `KEYWORD_SCREEN` name their effects on line 8.
    #[test]
    fn an_effect_after_a_regular_expression_that_holds_quotes_or_a_comment_mark_is_refused()
    -> Result<()> {
        let mut files = after_patterns(CORE, "let now = Date()");
        files.push((format!("{CORE}/Screen.swift"), KEYWORD_SCREEN.to_owned()));
        files.push((format!("{CORE}/Operator.swift"), OPERATOR_SCREEN.to_owned()));
        let tree = Tree::new("purity-keywords", &files)?;
        let mut found = vec![format!(
            "{CORE}/Operator.swift:1 imports SwiftUI, and the core imports only Foundation"
        )];
        for name in ["Date", "UserDefaults", "URLSession", "print"] {
            found.push(format!(
                "{CORE}/Operator.swift:8 names {name}, and the core decides from values alone"
            ));
        }
        found.extend(
            places_after_patterns(CORE)
                .iter()
                .map(|place| format!("{place} names Date, and the core decides from values alone")),
        );
        found.push(format!(
            "{CORE}/Screen.swift:1 imports SwiftUI, and the core imports only Foundation"
        ));
        for name in ["Date", "URLSession", "print"] {
            found.push(format!(
                "{CORE}/Screen.swift:8 names {name}, and the core decides from values alone"
            ));
        }
        assert_eq!(
            check(tree.root()),
            Err(Failure::new(format!(
                "The core names an effect:\n{}",
                found.join("\n")
            )))
        );
        Ok(())
    }

    #[test]
    fn a_comment_between_two_names_keeps_them_apart() {
        assert_eq!(
            findings("return/**/Date()\n", "a.swift"),
            ["a.swift:1 names Date, and the core decides from values alone"]
        );
    }
}
