//! Keeps sentences and labels out of the screens' string literals.
//!
//! `docs/adr/localize-with-one-tested-string-catalog.md` decides that every word the app shows comes from the catalog.
//! A literal in a screen may hold a symbol name, an identifier, or a file name, and never text for a reader.
//! One lowercase word such as a unit passes the check, and the review of each screen has to catch it.

use crate::{
    failure::{Result, ensure},
    swift_source,
};
use std::path::Path;

const SCREENS: &str = "App";

/// Literals with capital letters that name a key of the system instead of showing text.
const SYSTEM_KEYS: [&str; 2] = ["CFBundleShortVersionString", "CFBundleVersion"];

/// The planted lines that the check must refuse, which show that it reads what it claims to read.
const PLANTED: [&str; 4] = [
    "Text(\"Log set\")\n",
    "Label(\"記録\", systemImage: \"plus\")\n",
    "Button(\"Save\") { save() }\n",
    "Text(\"\\(count) sets\")\n",
];

/// Reads Swift source and collects the fixed text of each string literal with its line.
struct Scanner {
    characters: Vec<char>,
    at: usize,
    line: usize,
    found: Vec<(usize, String)>,
}

impl Scanner {
    fn peek(&self, ahead: usize) -> Option<char> {
        self.characters.get(self.at + ahead).copied()
    }

    fn advance(&mut self) -> Option<char> {
        let character = self.peek(0)?;
        self.at += 1;
        if character == '\n' {
            self.line += 1;
        }
        Some(character)
    }

    fn starts_with(&self, text: &str) -> bool {
        text.chars()
            .enumerate()
            .all(|(index, character)| self.peek(index) == Some(character))
    }

    /// Reads code up to the end of the source, or up to the parenthesis that closes an interpolation.
    fn code(&mut self, interpolation: bool) {
        let mut depth = 0usize;
        while let Some(character) = self.advance() {
            match character {
                '/' if self.peek(0) == Some('/') => {
                    while self.peek(0).is_some_and(|next| next != '\n') {
                        self.advance();
                    }
                }
                '/' if self.peek(0) == Some('*') => {
                    while self.peek(0).is_some() && !self.starts_with("*/") {
                        self.advance();
                    }
                    self.advance();
                    self.advance();
                }
                '"' => self.string(),
                '(' => depth += 1,
                ')' if interpolation && depth == 0 => return,
                ')' => depth = depth.saturating_sub(1),
                _ => {}
            }
        }
    }

    /// Reads a literal after its opening quote and records the text outside its interpolations.
    fn string(&mut self) {
        let line = self.line;
        let multiline = self.starts_with("\"\"");
        if multiline {
            self.advance();
            self.advance();
        }
        let mut text = String::new();
        while let Some(character) = self.advance() {
            match character {
                '\\' if self.peek(0) == Some('(') => {
                    self.advance();
                    self.code(true);
                }
                // Any other escape writes a character for a reader, so the literal counts as text.
                '\\' => {
                    self.advance();
                    text.push(' ');
                }
                '"' if !multiline => break,
                '"' if self.starts_with("\"\"") => {
                    self.advance();
                    self.advance();
                    break;
                }
                _ => text.push(character),
            }
        }
        self.found.push((line, text));
    }
}

fn literals(source: &str) -> Vec<(usize, String)> {
    let mut scanner = Scanner {
        characters: source.chars().collect(),
        at: 0,
        line: 1,
        found: Vec::new(),
    };
    scanner.code(false);
    scanner.found
}

/// Whether a literal's fixed text is a symbol name, an identifier, a file name, or a system key.
fn is_name(text: &str) -> bool {
    SYSTEM_KEYS.contains(&text)
        || text.chars().all(|character| {
            character.is_ascii_lowercase()
                || character.is_ascii_digit()
                || matches!(character, '.' | '-' | '_')
        })
}

/// Each literal in `source` that holds text for a reader, with its file and line.
fn findings(source: &str, file: &str) -> Vec<String> {
    literals(source)
        .into_iter()
        .filter(|(_, text)| !is_name(text))
        .map(|(line, text)| {
            format!("{file}:{line} writes \"{text}\" as a literal, and the screens read their words from the catalog")
        })
        .collect()
}

/// Scans the screens and refuses any literal that holds text for a reader.
pub fn check(root: &Path) -> Result<String> {
    let screens = swift_source::read(root, &[SCREENS])?;
    let found = screens
        .iter()
        .flat_map(|screen| findings(&screen.text, &screen.file))
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

    #[test]
    fn names_pass_and_text_for_a_reader_fails() {
        for allowed in [
            "Image(systemName: \"chevron.right\")\n",
            ".accessibilityIdentifier(\"set-\\(number)\")\n",
            "let version = info?[\"CFBundleVersion\"] as? String ?? \"\"\n",
            "let name = \"gymemo-backup-\\(model.today.iso)\"\n",
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
}
