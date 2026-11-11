//! Keeps sentences and labels out of the screens' string literals.
//!
//! `docs/adr/localize-with-one-tested-string-catalog.md` decides that every word the app shows comes from the catalog.
//! A literal in a screen may hold a symbol name, an identifier, or a filename, and never text for a reader.
//! One lowercase word such as a unit passes the check, and the review of each screen has to catch it.
//! Compiler-required App Intents metadata literals must reference fully translated catalogs in the canonical adapter.

use crate::{
    failure::{Context, Failure, Result, ensure},
    json::{self, Value},
    swift_source::{self, Literal},
};
use std::path::Path;

const SCREENS: &str = "App";
const INTENT_ADAPTER: &str = "App/LogShortcut.swift";
const APPLICATION_NAME: &str = "${applicationName}";
const LANGUAGES: [&str; 4] = ["en", "ja", "zh-Hans", "zh-Hant"];

struct MetadataCatalogs {
    titles: Value,
    phrases: Value,
}

impl MetadataCatalogs {
    fn read(root: &Path) -> Result<Self> {
        fn catalog(root: &Path, file: &str) -> Result<Value> {
            let path = root.join(file);
            let text =
                std::fs::read_to_string(&path).context(|| format!("Read {}", path.display()))?;
            json::parse(&text)
                .map_err(|error| Failure::new(format!("Read {}: {error}", path.display())))
        }
        Ok(Self {
            titles: catalog(root, "Sources/GymemoCopy/Localizable.xcstrings")?,
            phrases: catalog(root, "App/AppShortcuts.xcstrings")?,
        })
    }

    fn allows(&self, literal: &Literal, interpolations: &[swift_source::Interpolation]) -> bool {
        let parameters = interpolations
            .iter()
            .filter(|parameter| parameter.line == literal.line)
            .collect::<Vec<_>>();
        if let Some(title) = self
            .titles
            .get("strings")
            .and_then(|keys| keys.get(&literal.text))
        {
            return parameters.is_empty()
                && LANGUAGES
                    .iter()
                    .all(|language| translated(title, language).is_some());
        }
        let Some(phrases) = self.phrases.get("strings").and_then(Value::as_object) else {
            return false;
        };
        parameters.len() == 1
            && parameters[0].code.trim() == ".applicationName"
            && phrases.iter().any(|(key, entry)| {
                key.matches(APPLICATION_NAME).count() == 1
                    && key.replace(APPLICATION_NAME, "") == literal.text
                    && LANGUAGES.iter().all(|language| {
                        translated(entry, language).is_some_and(|value| {
                            value.matches(APPLICATION_NAME).count() == 1
                                && (*language != "en" || value == key)
                        })
                    })
            })
    }
}

fn translated<'a>(entry: &'a Value, language: &str) -> Option<&'a str> {
    let unit = entry
        .get("localizations")?
        .get(language)?
        .get("stringUnit")?;
    if unit.get("state")?.as_str()? != "translated" {
        return None;
    }
    unit.get("value")?
        .as_str()
        .filter(|value| !value.trim().is_empty())
}

/// Literals with capital letters that name a key of the system instead of showing text.
const SYSTEM_KEYS: [&str; 2] = ["CFBundleShortVersionString", "CFBundleVersion"];

/// The planted lines that the check must refuse, which show that it reads what it claims to read.
const PLANTED: [&str; 4] = [
    "Text(\"Log set\")\n",
    "Label(\"記録\", systemImage: \"plus\")\n",
    "Button(\"Save\") { save() }\n",
    "Text(\"\\(count) sets\")\n",
];

/// Whether a literal's fixed text is a symbol name, an identifier, a filename, a system key, or SwiftUI's external-event wildcard.
/// An escape writes a character for a reader, and the blank that stands for it in the fixed text makes the literal count as text.
fn is_name(text: &str) -> bool {
    text == "*"
        || SYSTEM_KEYS.contains(&text)
        || text.chars().all(|character| {
            character.is_ascii_lowercase()
                || character.is_ascii_digit()
                || matches!(character, '.' | '-' | '_')
        })
}

/// Each literal in `source` that holds text for a reader, located by its file and its line.
fn findings(source: &str, file: &str) -> Vec<String> {
    findings_with_metadata(source, file, None)
}

fn findings_with_metadata(
    source: &str,
    file: &str,
    catalogs: Option<&MetadataCatalogs>,
) -> Vec<String> {
    let metadata = catalogs.filter(|_| Path::new(file) == Path::new(INTENT_ADAPTER));
    let interpolations = if metadata.is_some() {
        swift_source::interpolations(source)
    } else {
        Vec::new()
    };
    swift_source::literals(source)
        .into_iter()
        .filter(|literal| {
            !is_name(&literal.text)
                && !metadata.is_some_and(|catalogs| catalogs.allows(literal, &interpolations))
        })
        .map(|Literal { line, text }| {
            format!("{file}:{line} writes \"{text}\" as a literal, and the screens read their words from the catalog")
        })
        .collect()
}

/// Scans the screens and refuses any literal that holds text for a reader.
pub fn check(root: &Path) -> Result<String> {
    let screens = swift_source::read(root, &[SCREENS])?;
    let catalogs = screens
        .iter()
        .any(|screen| Path::new(&screen.file) == Path::new(INTENT_ADAPTER))
        .then(|| MetadataCatalogs::read(root))
        .transpose()?;
    let found = screens
        .iter()
        .flat_map(|screen| findings_with_metadata(&screen.text, &screen.file, catalogs.as_ref()))
        .collect::<Vec<_>>();
    ensure(found.is_empty(), || {
        format!(
            "The screens hold text outside the catalog:\n{}",
            found.join("\n")
        )
    })?;
    for planted in PLANTED {
        ensure(!findings(planted, "planted.swift").is_empty(), || {
            format!("The literal check accepted a planted line: {planted}")
        })?;
    }
    Ok(format!(
        "{} screens read their words from the catalog, and {} planted literals fail",
        screens.len(),
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

    const INTENT_SOURCE: &str = "static let title: LocalizedStringResource = \"openLog\"\nlet phrases = [\"Open the log in \\(.applicationName)\"]\n";
    const TITLE_CATALOG: &str = r#"{"strings":{"openLog":{"localizations":{
      "en":{"stringUnit":{"state":"translated","value":"Open Log"}},
      "ja":{"stringUnit":{"state":"translated","value":"記録を開く"}},
      "zh-Hans":{"stringUnit":{"state":"translated","value":"打开记录"}},
      "zh-Hant":{"stringUnit":{"state":"translated","value":"開啟紀錄"}}
    }}}}"#;
    const PHRASE_CATALOG: &str = r#"{"strings":{"Open the log in ${applicationName}":{"localizations":{
      "en":{"stringUnit":{"state":"translated","value":"Open the log in ${applicationName}"}},
      "ja":{"stringUnit":{"state":"translated","value":"${applicationName}で記録を開く"}},
      "zh-Hans":{"stringUnit":{"state":"translated","value":"在${applicationName}中打开记录"}},
      "zh-Hant":{"stringUnit":{"state":"translated","value":"在${applicationName}中開啟紀錄"}}
    }}}}"#;

    #[test]
    fn intent_metadata_requires_translated_catalog_keys_and_system_phrase_parameters() -> Result<()>
    {
        let tree = Tree::new(
            "intent-literals",
            &[
                ("App/LogShortcut.swift", INTENT_SOURCE),
                ("Sources/GymemoCopy/Localizable.xcstrings", TITLE_CATALOG),
                ("App/AppShortcuts.xcstrings", PHRASE_CATALOG),
            ],
        )?;
        assert!(check(tree.root()).is_ok());
        for source in [
            INTENT_SOURCE.replace("openLog", "missingKey"),
            INTENT_SOURCE.replace("Open the log in", "Untranslated words in"),
            INTENT_SOURCE.replace(".applicationName", "exercise.name"),
            "Text(\"Untranslated help\")".to_owned(),
        ] {
            let tree = Tree::new(
                "invalid-intent-literals",
                &[
                    ("App/LogShortcut.swift", source.as_str()),
                    ("Sources/GymemoCopy/Localizable.xcstrings", TITLE_CATALOG),
                    ("App/AppShortcuts.xcstrings", PHRASE_CATALOG),
                ],
            )?;
            assert!(check(tree.root()).is_err(), "{source}");
        }
        Ok(())
    }

    #[test]
    fn intent_catalog_admission_never_relaxes_other_screens() -> Result<()> {
        let tree = Tree::new(
            "intent-scope",
            &[
                ("App/LogShortcut.swift", INTENT_SOURCE),
                ("App/Other.swift", INTENT_SOURCE),
                ("Sources/GymemoCopy/Localizable.xcstrings", TITLE_CATALOG),
                ("App/AppShortcuts.xcstrings", PHRASE_CATALOG),
            ],
        )?;
        assert!(check(tree.root()).is_err());
        Ok(())
    }

    #[test]
    fn incomplete_or_malformed_intent_catalogs_are_refused() -> Result<()> {
        for (title, phrases) in [
            (
                TITLE_CATALOG.replace("\"ja\"", "\"fr\""),
                PHRASE_CATALOG.to_owned(),
            ),
            (
                TITLE_CATALOG.replace("translated", "new"),
                PHRASE_CATALOG.to_owned(),
            ),
            (
                TITLE_CATALOG.to_owned(),
                PHRASE_CATALOG.replace("\"ja\"", "\"fr\""),
            ),
            (
                TITLE_CATALOG.to_owned(),
                PHRASE_CATALOG.replace("translated", "new"),
            ),
            (
                TITLE_CATALOG.to_owned(),
                PHRASE_CATALOG.replace("${applicationName}で", "で"),
            ),
            (
                TITLE_CATALOG.to_owned(),
                PHRASE_CATALOG.replace(
                    "${applicationName}で",
                    "${applicationName}${applicationName}で",
                ),
            ),
            (TITLE_CATALOG.to_owned(), "{".to_owned()),
            ("{".to_owned(), PHRASE_CATALOG.to_owned()),
        ] {
            let tree = Tree::new(
                "invalid-intent-catalogs",
                &[
                    ("App/LogShortcut.swift", INTENT_SOURCE),
                    ("Sources/GymemoCopy/Localizable.xcstrings", title.as_str()),
                    ("App/AppShortcuts.xcstrings", phrases.as_str()),
                ],
            )?;
            assert!(check(tree.root()).is_err(), "{title}\n{phrases}");
        }
        Ok(())
    }

    #[test]
    fn names_pass_and_text_for_a_reader_fails() {
        for allowed in [
            "Image(systemName: \"chevron.right\")\n",
            ".accessibilityIdentifier(\"set-\\(number)\")\n",
            "let version = info?[\"CFBundleVersion\"] as? String ?? \"\"\n",
            "let name = \"gymemo-backup-\\(model.today.iso)\"\n",
            ".handlesExternalEvents(preferring: [\"*\"], allowing: [\"*\"])\n",
            "Text(copy[.logSet]) // \"Log set\"\n",
            "/* Text(\"Log set\") */\n",
            "Text(\"\\(copy.day(day, .long))\")\n",
        ] {
            assert!(findings(allowed, "a.swift").is_empty(), "{allowed}");
        }
        for refused in [
            "Text(\"History\")\n",
            ".navigationTitle(\"履歴\")\n",
            "Text(\"a b\")\n",
            "Text(\"line\\nbreak\")\n",
            "Text(\"\"\"\nTwo words\n\"\"\")\n",
            "Text(\"\\(names.joined(separator: \", \"))\")\n",
        ] {
            assert_eq!(findings(refused, "a.swift").len(), 1, "{refused}");
        }
        assert_eq!(
            findings("\n\nText(\"Save\")\n", "a.swift"),
            [
                "a.swift:3 writes \"Save\" as a literal, and the screens read their words from the catalog"
            ]
        );
        for planted in PLANTED {
            assert!(!findings(planted, "planted.swift").is_empty(), "{planted}");
        }
    }

    #[test]
    fn the_shipped_screens_pass() -> Result<()> {
        check(&Path::new(env!("CARGO_MANIFEST_DIR")).join("..")).map(|_| ())
    }

    /// The finding that `text` gives on `line` of `a.swift`.
    fn finding(line: usize, text: &str) -> String {
        format!(
            "a.swift:{line} writes \"{text}\" as a literal, and the screens read their words from the catalog"
        )
    }

    #[test]
    fn screens_without_text_pass_with_their_number() -> Result<()> {
        let tree = Tree::new(
            "literals-clean",
            &[
                (
                    "App/Screen.swift",
                    "Image(systemName: \"plus\")\n.accessibilityIdentifier(\"set-\\(number)\")\n",
                ),
                ("App/Rows/Row.swift", "Text(copy[.logSet])\n"),
            ],
        )?;
        assert_eq!(
            check(tree.root()),
            Ok(
                "2 screens read their words from the catalog, and 4 planted literals fail"
                    .to_owned()
            )
        );
        Ok(())
    }

    #[test]
    fn text_in_a_screen_is_refused_with_its_file_and_line() -> Result<()> {
        let tree = Tree::new(
            "literals-text",
            &[(
                "App/Screen.swift",
                "Image(systemName: \"plus\")\nText(\"Log set\")\n",
            )],
        )?;
        assert_eq!(
            check(tree.root()),
            Err(Failure::new(
                "The screens hold text outside the catalog:\n\
                 App/Screen.swift:2 writes \"Log set\" as a literal, and the screens read their words from the catalog"
            ))
        );
        Ok(())
    }

    #[test]
    fn a_literal_inside_an_interpolation_is_read_before_the_literal_around_it() {
        assert_eq!(
            findings(
                "Text(\"Sets \\(names.joined(separator: \", \")) done\")\n",
                "a.swift"
            ),
            [finding(1, ", "), finding(1, "Sets  done")]
        );
    }

    #[test]
    fn a_literal_keeps_the_line_of_its_opening_quote() {
        let source = "let row = \"\"\"\n  {\"id\":\\(id),\\\n  \"name\":\\(name)}\n  \"\"\"\nText(\"Save\")\n";
        assert_eq!(
            findings(source, "a.swift"),
            [
                finding(1, "\n  {\"id\":,   \"name\":}\n  "),
                finding(5, "Save")
            ]
        );
    }

    #[test]
    fn a_raw_literal_is_read_with_its_own_delimiters() {
        assert!(
            findings(
                ".accessibilityIdentifier(#\"set-\\#(number)\"#)\n",
                "a.swift"
            )
            .is_empty()
        );
        assert_eq!(
            findings(
                "Text(#\"Save \"now\"\"#)\nImage(systemName: \"plus\")\n",
                "a.swift"
            ),
            [finding(1, "Save \"now\"")]
        );
        assert_eq!(
            findings("Image(systemName: #\"a\\\"#)\nText(\"Save\")\n", "a.swift"),
            [finding(1, "a\\"), finding(2, "Save")]
        );
    }

    #[test]
    fn a_literal_inside_a_nested_comment_is_no_text() {
        assert!(findings("/* a /* b */ Text(\"Log set\") */\n", "a.swift").is_empty());
        assert_eq!(
            findings("/* a /* b */ \" */ Text(\"Log set\")\n", "a.swift"),
            [finding(1, "Log set")]
        );
    }

    #[test]
    fn a_regular_expression_holds_no_text_and_hides_no_later_literal() {
        assert_eq!(
            findings(
                "let r = #/a/*b/#\nlet s = 1 /* z */; Text(\"Log set\")\n",
                "a.swift"
            ),
            [finding(2, "Log set")]
        );
        assert!(findings("let r = #/\"Two words\"/#\n", "a.swift").is_empty());
    }

    #[test]
    fn text_after_a_comment_or_a_regular_expression_that_holds_quotes_is_refused_on_its_line()
    -> Result<()> {
        let tree = Tree::new(
            "literals-slashes",
            &after_slashes(SCREENS, "Text(\"Log set\")"),
        )?;
        let mut found = places_after_slashes(SCREENS)
            .iter()
            .map(|place| {
                format!(
                    "{place} writes \"Log set\" as a literal, and the screens read their words from the catalog"
                )
            })
            .collect::<Vec<_>>();
        // The eighth beginning holds a raw literal between three quotes, whose text a reader would see.
        found.insert(
            7,
            format!(
                "{SCREENS}/Slash08.swift:1 writes \"\n  a \"# b\n  \" as a literal, and the screens read their words from the catalog"
            ),
        );
        assert_eq!(
            check(tree.root()),
            Err(Failure::new(format!(
                "The screens hold text outside the catalog:\n{}",
                found.join("\n")
            )))
        );
        Ok(())
    }

    #[test]
    fn text_between_the_slash_of_an_operator_and_a_division_is_refused_on_its_line() -> Result<()> {
        let tree = Tree::new(
            "literals-operators",
            &around_operators(SCREENS, "Text(\"Log set\")"),
        )?;
        let found = places_around_operators(SCREENS)
            .iter()
            .map(|place| {
                format!(
                    "{place} writes \"Log set\" as a literal, and the screens read their words from the catalog"
                )
            })
            .collect::<Vec<_>>();
        assert_eq!(
            check(tree.root()),
            Err(Failure::new(format!(
                "The screens hold text outside the catalog:\n{}",
                found.join("\n")
            )))
        );
        Ok(())
    }

    #[test]
    fn text_beside_a_raw_identifier_is_refused_on_its_line() -> Result<()> {
        let tree = Tree::new(
            "literals-raw-identifiers",
            &around_raw_identifiers(SCREENS, "Text(\"Log set\")"),
        )?;
        let found = places_around_raw_identifiers(SCREENS)
            .iter()
            .map(|place| {
                format!(
                    "{place} writes \"Log set\" as a literal, and the screens read their words from the catalog"
                )
            })
            .collect::<Vec<_>>();
        assert_eq!(
            check(tree.root()),
            Err(Failure::new(format!(
                "The screens hold text outside the catalog:\n{}",
                found.join("\n")
            )))
        );
        Ok(())
    }

    /// Each file of `AFTER_PATTERNS` shows text on the line after its regular expression literal, and the screens of `OPERATOR_SCREEN` and `KEYWORD_SCREEN` show text on line 9.
    /// The quotes inside each regular expression literal are no text.
    #[test]
    fn text_after_a_regular_expression_that_holds_quotes_or_a_comment_mark_is_refused_on_its_line()
    -> Result<()> {
        let mut files = after_patterns(SCREENS, "Text(\"Log set\")");
        files.push((format!("{SCREENS}/Screen.swift"), KEYWORD_SCREEN.to_owned()));
        files.push((
            format!("{SCREENS}/Operator.swift"),
            OPERATOR_SCREEN.to_owned(),
        ));
        let tree = Tree::new("literals-keywords", &files)?;
        let found = [format!("{SCREENS}/Operator.swift:9")]
            .into_iter()
            .chain(places_after_patterns(SCREENS))
            .chain([format!("{SCREENS}/Screen.swift:9")])
            .map(|place| {
                format!(
                    "{place} writes \"Log set\" as a literal, and the screens read their words from the catalog"
                )
            })
            .collect::<Vec<_>>();
        assert_eq!(
            check(tree.root()),
            Err(Failure::new(format!(
                "The screens hold text outside the catalog:\n{}",
                found.join("\n")
            )))
        );
        Ok(())
    }

    #[test]
    fn a_slash_alone_starts_no_comment() {
        assert_eq!(
            findings(
                "Text(total / count > 1 ? \"Sets done\" : \"plus\")\n",
                "a.swift"
            ),
            [finding(1, "Sets done")]
        );
    }
}
