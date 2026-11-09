//! Holds the screens to the system design: system colors, system materials, and the system's bars and sheets.
//!
//! [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) asks apps to remove custom backgrounds from bars and sheets and to avoid custom glass effects.
//! The [color guidance](https://developer.apple.com/design/human-interface-guidelines/color) asks apps to prefer system colors and to leave their values out of the code.
//! `docs/design.md` adds one accent color, which the asset catalog names.

use crate::{
    failure::{Context, Result, ensure},
    swift_source::{self, code_only, identifier},
};
use std::{fs, path::Path};

/// The screens that the rules cover.
const SCREENS: &str = "App";
/// The files whose settings could opt the app out of the system design.
const SETTINGS: [&str; 2] = ["project.yml", "Config/App-Info.plist"];

const COLOR: &str = "and the screens take their colors from the system and the asset catalog";
const BAR: &str = "and the system draws the background of each bar";
const SHEET: &str = "and the system draws the background of each sheet";
const APPEARANCE: &str = "and the app follows the system appearance";
const GLASS: &str = "and Liquid Glass stays in the layer that the system draws";
const HIERARCHY: &str = "and a hierarchical style takes the tint inside a button and ignores Increase Contrast, unlike Color.primary and Color.secondary";
const TEXT: &str = "and text takes the system text styles so that it follows Dynamic Type";
const WRAP: &str =
    "and text wraps at every text size, because the UI tests leave clipped text to this check";

/// Types that author a color, a gradient, a glass effect, or a bar appearance in code.
const REFUSED_TYPES: [(&str, &str); 12] = [
    ("UIFont", TEXT),
    ("UIColor", COLOR),
    ("CGColor", COLOR),
    ("Gradient", COLOR),
    ("LinearGradient", COLOR),
    ("RadialGradient", COLOR),
    ("AngularGradient", COLOR),
    ("MeshGradient", COLOR),
    ("GlassEffectContainer", GLASS),
    ("UINavigationBarAppearance", BAR),
    ("UITabBarAppearance", BAR),
    ("UIToolbarAppearance", BAR),
];

/// Modifiers that replace what the system draws or that cut text short, refused wherever the code calls them.
const REFUSED_CALLS: [(&str, &str); 11] = [
    ("lineLimit", WRAP),
    ("minimumScaleFactor", WRAP),
    ("truncationMode", WRAP),
    ("toolbarBackground", BAR),
    ("toolbarBackgroundVisibility", BAR),
    ("toolbarColorScheme", BAR),
    ("presentationBackground", SHEET),
    ("preferredColorScheme", APPEARANCE),
    ("glassEffect", GLASS),
    ("glassEffectID", GLASS),
    ("glassEffectUnion", GLASS),
];

/// Fixed hues, refused as members such as `.fill(.blue)` and `Color.white`.
/// The accent comes from the asset catalog, and `.red` stays for the symbol beside a problem.
const REFUSED_HUES: [&str; 14] = [
    "white", "black", "gray", "orange", "yellow", "green", "mint", "teal", "cyan", "blue",
    "indigo", "purple", "pink", "brown",
];

/// The hierarchical styles, refused as members such as `.foregroundStyle(.secondary)` and `.tint(.primary)`.
/// Each one derives from the foreground style around it, so it takes the tint inside a button.
/// `Color.secondary` darkens when Increase Contrast is on, and the hierarchical style keeps its lightness.
const HIERARCHICAL_STYLES: [&str; 4] = ["primary", "secondary", "tertiary", "quaternary"];

/// Settings that opt the whole app out, with what each one does.
const REFUSED_SETTINGS: [(&str, &str); 2] = [
    (
        "UIDesignRequiresCompatibility",
        "which turns the system design off",
    ),
    ("UIUserInterfaceStyle", "which fixes the appearance"),
];

/// The planted lines that the check must refuse, one for each kind of rule.
const PLANTED: [&str; 7] = [
    "Text(\"a\").foregroundStyle(.secondary)\n",
    "Text(\"a\").font(.system(size: 17))\n",
    "Rectangle().fill(Color(red: 0.4, green: 0.3, blue: 0.9))\n",
    "Text(\"a\").foregroundStyle(.blue)\n",
    "List {}.toolbarBackground(.visible, for: .tabBar)\n",
    "Form {}.presentationBackground(.thinMaterial)\n",
    "Text(\"a\").glassEffect()\n",
];

/// The identifier that starts at byte `at` of `line`, or an empty string.
fn word(line: &str, at: usize) -> &str {
    let rest = &line[at..];
    &rest[..rest.find(|c: char| !identifier(c)).unwrap_or(rest.len())]
}

/// What the code at byte `at` of `line` uses against the system design, with the reason.
fn refused(line: &str, at: usize) -> Option<(String, &'static str)> {
    let before = &line[..at];
    let previous = before.chars().next_back();
    let rest = &line[at..];
    let character = rest.chars().next()?;
    if rest.starts_with("#colorLiteral") {
        return Some(("#colorLiteral".to_owned(), COLOR));
    }
    if character == '.' {
        let name = word(line, at + 1);
        let called = line[at + 1 + name.len()..].starts_with('(');
        if called && let Some((_, reason)) = REFUSED_CALLS.iter().find(|(call, _)| *call == name) {
            return Some((name.to_owned(), reason));
        }
        let implicit =
            !previous.is_some_and(|c| identifier(c) || matches!(c, ')' | ']' | '?' | '!'));
        let on_color = before.ends_with("Color")
            && !before[..before.len() - "Color".len()]
                .chars()
                .next_back()
                .is_some_and(identifier);
        if implicit && !called && HIERARCHICAL_STYLES.contains(&name) {
            return Some((format!(".{name}"), HIERARCHY));
        }
        let sized = name == "system" && line[at + 1 + name.len()..].starts_with("(size");
        if called && (sized || name == "custom") {
            return Some((format!(".{name}"), TEXT));
        }
        let hue = !called && REFUSED_HUES.contains(&name);
        return (hue && (implicit || on_color)).then(|| (format!(".{name}"), COLOR));
    }
    if !identifier(character) || previous.is_some_and(|c| identifier(c) || c == '.') {
        return None;
    }
    let name = word(line, at);
    if name == "Color" && line[at + name.len()..].starts_with('(') {
        return Some(("Color(…)".to_owned(), COLOR));
    }
    REFUSED_TYPES
        .iter()
        .find(|(refused, _)| *refused == name)
        .map(|(_, reason)| (name.to_owned(), *reason))
}

/// Each finding of `source`, with its file and line.
fn findings(source: &str, file: &str) -> Vec<String> {
    let code = code_only(source);
    let mut found = Vec::new();
    for (number, line) in code.lines().enumerate() {
        for (at, _) in line.char_indices() {
            if let Some((name, reason)) = refused(line, at) {
                found.push(format!("{file}:{} uses {name}, {reason}", number + 1));
            }
        }
    }
    found
}

/// Each setting in `text` that opts the app out of the system design.
fn opt_outs(text: &str, file: &str) -> Vec<String> {
    let mut found = Vec::new();
    for (number, line) in text.lines().enumerate() {
        for (setting, effect) in REFUSED_SETTINGS {
            if line.contains(setting) {
                found.push(format!("{file}:{} sets {setting}, {effect}", number + 1));
            }
        }
    }
    found
}

/// Scans the screens and the settings, and refuses anything that replaces the system design.
pub fn check(root: &Path) -> Result<String> {
    let screens = swift_source::read(root, &[SCREENS])?;
    ensure(!screens.is_empty(), || {
        "The system design check found no screens".to_owned()
    })?;
    let mut found = screens
        .iter()
        .flat_map(|screen| findings(&screen.text, &screen.file))
        .collect::<Vec<_>>();
    for file in SETTINGS {
        let text = fs::read_to_string(root.join(file)).context(|| format!("Read {file}"))?;
        found.extend(opt_outs(&text, file));
    }
    ensure(found.is_empty(), || {
        format!(
            "The screens replace part of the system design:\n{}",
            found.join("\n")
        )
    })?;
    for planted in PLANTED {
        ensure(!findings(planted, "planted.swift").is_empty(), || {
            format!("The system design check accepted a planted line: {planted}")
        })?;
    }
    Ok(format!(
        "{} screens keep to the system design, and {} planted lines fail",
        screens.len(),
        PLANTED.len()
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn system_styles_pass() {
        for allowed in [
            ".foregroundStyle(Color.primary)\n",
            ".tint(Color.primary)\n",
            ".foregroundStyle(Color.secondary)\n",
            ".font(.subheadline)\n",
            ".font(.title3.bold())\n",
            ".foregroundStyle(.tint)\n",
            ".foregroundStyle(.red)\n",
            ".listRowBackground(Color.clear)\n",
            "Label(title, systemImage: symbol).foregroundStyle(Color.accentColor)\n",
            ".background(.background)\n",
            "let text = \"Color(red: 1)\" // UIColor.white\n",
            ".buttonStyle(.borderedProminent)\n",
            "struct ColorfulRow: View {}\n",
            ".presentationDetents([.medium, .large])\n",
            ".toolbar { ToolbarItem(placement: .confirmationAction) { save } }\n",
        ] {
            assert!(findings(allowed, "a.swift").is_empty(), "{allowed}");
        }
    }

    #[test]
    fn colors_built_in_code_fail() {
        for refused in [
            "Rectangle().fill(Color(red: 0.4, green: 0.3, blue: 0.9))\n",
            "let ink = Color(\"Ink\")\n",
            "let x = UIColor.systemIndigo\n",
            ".foregroundStyle(.indigo)\n",
            ".tint(.orange)\n",
            ".background(Color.white)\n",
            ".fill(LinearGradient(colors: [a, b], startPoint: .top, endPoint: .bottom))\n",
            "let c = #colorLiteral(red: 1, green: 0, blue: 0, alpha: 1)\n",
        ] {
            assert_eq!(findings(refused, "a.swift").len(), 1, "{refused}");
        }
    }

    #[test]
    fn custom_bars_sheets_glass_and_fixed_appearances_fail() {
        for refused in [
            ".toolbarBackground(.surface, for: .navigationBar)\n",
            ".toolbarBackgroundVisibility(.visible, for: .tabBar)\n",
            ".presentationBackground(.thinMaterial)\n",
            ".toolbarColorScheme(.dark, for: .navigationBar)\n",
            ".preferredColorScheme(.dark)\n",
            "Text(title).glassEffect()\n",
            "GlassEffectContainer { row }\n",
            "let bar = UINavigationBarAppearance()\n",
            "Text(title).foregroundStyle(.primary)\n",
            "Button(name, action: pick).tint(.primary)\n",
            "Text(title).foregroundStyle(.secondary)\n",
            "Image(systemName: symbol).foregroundStyle(.tertiary)\n",
            "Text(title).lineLimit(1)\n",
            "Text(title).minimumScaleFactor(0.5)\n",
            "Text(title).truncationMode(.middle)\n",
            "Text(title).font(.system(size: 17))\n",
            "Text(title).font(.custom(name, size: 17))\n",
            "let font = UIFont.systemFont(ofSize: 17)\n",
        ] {
            assert_eq!(findings(refused, "a.swift").len(), 1, "{refused}");
        }
        assert_eq!(
            findings("\n.preferredColorScheme(.dark)\n", "a.swift"),
            ["a.swift:2 uses preferredColorScheme, and the app follows the system appearance"]
        );
    }

    /// Writes a small repository under the temporary directory and returns its root.
    fn tree(name: &str, screen: &str, settings: &str) -> Result<std::path::PathBuf> {
        let root = std::env::temp_dir().join(format!(
            "gymemo-system-design-{name}-{}",
            std::process::id()
        ));
        fs::create_dir_all(root.join("App")).context(|| "Create the screens".to_owned())?;
        fs::create_dir_all(root.join("Config")).context(|| "Create the settings".to_owned())?;
        fs::write(root.join("App/Screen.swift"), screen)
            .context(|| "Write the screen".to_owned())?;
        fs::write(root.join("project.yml"), settings).context(|| "Write the project".to_owned())?;
        fs::write(root.join("Config/App-Info.plist"), "<plist/>\n")
            .context(|| "Write the property list".to_owned())?;
        Ok(root)
    }

    #[test]
    fn a_whole_tree_passes_only_without_findings() -> Result<()> {
        let screen = "List { Text(title).foregroundStyle(Color.secondary) }\n";
        let good = tree("good", screen, "name: gymemo\n")?;
        assert!(check(&good)?.starts_with("1 screens keep to the system design"));
        let styled = tree(
            "styled",
            "List {}.toolbarBackground(.visible)\n",
            "name: gymemo\n",
        )?;
        assert!(check(&styled).is_err());
        let opted = tree("opted", screen, "UIDesignRequiresCompatibility: true\n")?;
        assert!(check(&opted).is_err());
        for root in [good, styled, opted] {
            fs::remove_dir_all(root).context(|| "Remove the tree".to_owned())?;
        }
        Ok(())
    }

    #[test]
    fn the_shipped_screens_pass() -> Result<()> {
        check(&Path::new(env!("CARGO_MANIFEST_DIR")).join("..")).map(|_| ())
    }

    #[test]
    fn settings_that_opt_out_fail() {
        assert!(opt_outs("IPHONEOS_DEPLOYMENT_TARGET: \"26.0\"\n", "project.yml").is_empty());
        assert_eq!(
            opt_outs("a\n  UIDesignRequiresCompatibility: true\n", "project.yml"),
            ["project.yml:2 sets UIDesignRequiresCompatibility, which turns the system design off"]
        );
        assert_eq!(
            opt_outs("<key>UIUserInterfaceStyle</key>\n", "Info.plist").len(),
            1
        );
    }
}
