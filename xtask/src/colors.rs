//! Requires the app's screens to draw with the two named colors, the surface and the ink.
//!
//! The [Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode) guidelines ask apps to follow the system appearance.
//! The app follows it by swapping black and white, so `docs/design.md` permits no other color and no gray step.

use crate::{
    failure::{Result, ensure},
    swift_source::{self, code_only, identifier},
};
use std::path::Path;

/// The screens that the rule covers.
const SCREENS: &str = "App";
/// The one file that defines the surface and the ink from black and white.
const PALETTE: &str = "App/Palette.swift";

/// SwiftUI color names and system styles, refused as implicit members such as `.fill(.gray)`.
const REFUSED_COLORS: [&str; 21] = [
    "white",
    "black",
    "gray",
    "red",
    "orange",
    "yellow",
    "green",
    "mint",
    "teal",
    "cyan",
    "blue",
    "indigo",
    "purple",
    "pink",
    "brown",
    "clear",
    "primary",
    "secondary",
    "tertiary",
    "quaternary",
    "accentColor",
];

/// Modifiers that draw a gray step or a color of their own, refused wherever the code calls them.
const REFUSED_MODIFIERS: [&str; 3] = ["opacity", "foregroundColor", "shadow"];

/// Type names that author a color, a gradient, or a translucent surface directly.
const REFUSED_TYPES: [&str; 8] = [
    "Color",
    "UIColor",
    "CGColor",
    "Gradient",
    "LinearGradient",
    "RadialGradient",
    "AngularGradient",
    "Material",
];

/// The planted lines that the check must refuse, which show that it reads what it claims to read.
const PLANTED: [&str; 3] = [
    "Text(\"a\").foregroundStyle(.gray)\n",
    "Rectangle().fill(Color(red: 0.5, green: 0.5, blue: 0.5))\n",
    "Text(\"a\").opacity(0.5)\n",
];

/// The identifier that starts at byte `at` of `line`, or an empty string.
fn word(line: &str, at: usize) -> &str {
    let rest = &line[at..];
    &rest[..rest.find(|c: char| !identifier(c)).unwrap_or(rest.len())]
}

/// What the code at byte `at` of `line` authors, if it authors a color.
fn authored(line: &str, at: usize) -> Option<String> {
    let previous = line[..at].chars().next_back();
    let character = line[at..].chars().next()?;
    if character == '.' {
        let name = word(line, at + 1);
        let called = line[at + 1 + name.len()..].starts_with('(');
        let implicit =
            !previous.is_some_and(|c| identifier(c) || matches!(c, ')' | ']' | '?' | '!'));
        let refused = (implicit && REFUSED_COLORS.contains(&name))
            || (called && REFUSED_MODIFIERS.contains(&name));
        return refused.then(|| format!(".{name}"));
    }
    let starts = identifier(character) && !previous.is_some_and(|c| identifier(c) || c == '.');
    let name = word(line, at);
    (starts && REFUSED_TYPES.contains(&name)).then(|| name.to_owned())
}

/// Each authored color in `source`, with its file and line.
fn findings(source: &str, file: &str) -> Vec<String> {
    let code = code_only(source);
    let mut found = Vec::new();
    for (number, line) in code.lines().enumerate() {
        for (at, _) in line.char_indices() {
            if let Some(name) = authored(line, at) {
                found.push(format!(
                    "{file}:{} names {name}, and the screens draw only .surface and .ink",
                    number + 1
                ));
            }
        }
    }
    found
}

/// Scans the screens and refuses any authored color outside the palette.
pub fn check(root: &Path) -> Result<String> {
    let mut screens = swift_source::read(root, &[SCREENS])?;
    ensure(screens.iter().any(|screen| screen.file == PALETTE), || {
        format!("The color check found no {PALETTE}")
    })?;
    screens.retain(|screen| screen.file != PALETTE);
    ensure(!screens.is_empty(), || {
        "The color check found no screens".to_owned()
    })?;
    let found = screens
        .iter()
        .flat_map(|screen| findings(&screen.text, &screen.file))
        .collect::<Vec<_>>();
    ensure(found.is_empty(), || {
        format!(
            "The screens author a color outside the palette:\n{}",
            found.join("\n")
        )
    })?;
    for planted in PLANTED {
        ensure(!findings(planted, "planted.swift").is_empty(), || {
            format!("The color check accepted a planted line: {planted}")
        })?;
    }
    Ok(format!(
        "{} screens draw only the surface and the ink, and {} planted colors fail",
        screens.len(),
        PLANTED.len()
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn named_colors_pass_and_authored_colors_fail() {
        for allowed in [
            ".background(.surface).foregroundStyle(.ink)\n",
            "let text = \".gray\" // .black\n",
            ".trimmingCharacters(in: .whitespacesAndNewlines)\n",
            "await model.clear(day)\n",
            "MyColor(x)\n",
        ] {
            assert!(findings(allowed, "a.swift").is_empty(), "{allowed}");
        }
        assert_eq!(
            findings("\n.fill(.gray)\n", "a.swift"),
            ["a.swift:2 names .gray, and the screens draw only .surface and .ink"]
        );
        for refused in [
            "Color(uiColor: x)\n",
            "let x = UIColor.white\n",
            "Text(\"a\")\n  .opacity(0.5)\n",
            ".foregroundStyle(.secondary)\n",
            "Text(\"a\").foregroundColor(.ink)\n",
            "Text(\"a\").shadow(radius: 2)\n",
            ".background(Material.thin)\n",
        ] {
            assert_eq!(findings(refused, "a.swift").len(), 1, "{refused}");
        }
    }

    #[test]
    fn the_shipped_screens_pass() -> Result<()> {
        check(&Path::new(env!("CARGO_MANIFEST_DIR")).join("..")).map(|_| ())
    }
}
