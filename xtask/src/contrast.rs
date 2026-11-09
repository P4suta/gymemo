//! Checks the contrast claims of `docs/design.md` about the accent color.
//!
//! The values come from the system color tables of the [color guidance](https://developer.apple.com/design/human-interface-guidelines/color), read on 2026-11-09.
//! Apple asks apps to keep these values out of the app's code, and this module is a design-time check that ships in no app.
//! The ratio follows the [contrast formula](https://www.w3.org/TR/WCAG22/#dfn-contrast-ratio) of the Web Content Accessibility Guidelines.

/// A color as its red, green, and blue channels from 0 to 255.
type Rgb = (u8, u8, u8);

/// A system color in the default and the increased contrast setting, each in the light and the dark appearance.
struct SystemColor {
    name: &'static str,
    light: Rgb,
    dark: Rgb,
    increased_light: Rgb,
    increased_dark: Rgb,
}

const fn color(
    name: &'static str,
    light: Rgb,
    dark: Rgb,
    increased_light: Rgb,
    increased_dark: Rgb,
) -> SystemColor {
    SystemColor {
        name,
        light,
        dark,
        increased_light,
        increased_dark,
    }
}

const SYSTEM_COLORS: [SystemColor; 12] = [
    color(
        "red",
        (255, 56, 60),
        (255, 66, 69),
        (233, 21, 45),
        (255, 97, 101),
    ),
    color(
        "orange",
        (255, 141, 40),
        (255, 146, 48),
        (197, 83, 0),
        (255, 160, 86),
    ),
    color(
        "yellow",
        (255, 204, 0),
        (255, 214, 0),
        (161, 106, 0),
        (254, 223, 67),
    ),
    color(
        "green",
        (52, 199, 89),
        (48, 209, 88),
        (0, 137, 50),
        (74, 217, 104),
    ),
    color(
        "mint",
        (0, 200, 179),
        (0, 218, 195),
        (0, 133, 117),
        (84, 223, 203),
    ),
    color(
        "teal",
        (0, 195, 208),
        (0, 210, 224),
        (0, 129, 152),
        (59, 221, 236),
    ),
    color(
        "cyan",
        (0, 192, 232),
        (60, 211, 254),
        (0, 126, 174),
        (109, 217, 255),
    ),
    color(
        "blue",
        (0, 136, 255),
        (0, 145, 255),
        (30, 110, 244),
        (92, 184, 255),
    ),
    color(
        "indigo",
        (97, 85, 245),
        (109, 124, 255),
        (86, 74, 222),
        (167, 170, 255),
    ),
    color(
        "purple",
        (203, 48, 224),
        (219, 52, 242),
        (176, 47, 194),
        (234, 141, 255),
    ),
    color(
        "pink",
        (255, 45, 85),
        (255, 55, 95),
        (231, 18, 77),
        (255, 138, 196),
    ),
    color(
        "brown",
        (172, 127, 94),
        (183, 138, 102),
        (149, 109, 81),
        (219, 166, 121),
    ),
];

const WHITE: Rgb = (255, 255, 255);
/// System gray 6 in the dark appearance, the fill of a row in a dark grouped list.
const DARK_ROW: Rgb = (28, 28, 30);
/// System gray 5 in the dark appearance, the fill of a row inside a dark sheet.
const DARK_SHEET_ROW: Rgb = (44, 44, 46);

/// The relative luminance of a color.
fn luminance((red, green, blue): Rgb) -> f64 {
    let linear = |channel: u8| {
        let value = f64::from(channel) / 255.0;
        if value <= 0.039_28 {
            value / 12.92
        } else {
            ((value + 0.055) / 1.055).powf(2.4)
        }
    };
    0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
}

/// The contrast ratio of two colors, from 1 to 21.
fn ratio(first: Rgb, second: Rgb) -> f64 {
    let (first, second) = (luminance(first), luminance(second));
    (first.max(second) + 0.05) / (first.min(second) + 0.05)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn indigo() -> &'static SystemColor {
        &SYSTEM_COLORS[8]
    }

    fn rounded(value: f64) -> f64 {
        (value * 10.0).round() / 10.0
    }

    #[test]
    fn the_formula_gives_the_known_extremes() {
        assert!((ratio(WHITE, (0, 0, 0)) - 21.0).abs() < 1e-9);
        assert!((ratio(WHITE, WHITE) - 1.0).abs() < 1e-9);
    }

    #[test]
    fn indigo_text_reaches_the_ratios_that_the_design_document_states() {
        let indigo = indigo();
        assert_eq!(indigo.name, "indigo");
        assert!((rounded(ratio(indigo.light, WHITE)) - 5.1).abs() < 1e-9);
        assert!((rounded(ratio(indigo.dark, DARK_ROW)) - 4.8).abs() < 1e-9);
        assert!((rounded(ratio(indigo.dark, DARK_SHEET_ROW)) - 4.0).abs() < 1e-9);
        assert!((rounded(ratio(indigo.increased_dark, DARK_SHEET_ROW)) - 6.5).abs() < 1e-9);
        assert!(ratio(indigo.increased_light, WHITE) >= 4.5);
    }

    #[test]
    fn a_white_symbol_on_an_indigo_fill_stays_legible() {
        assert!(ratio(WHITE, indigo().light) >= 4.5);
        assert!(ratio(WHITE, indigo().dark) >= 3.0);
    }

    #[test]
    fn no_other_system_color_reaches_the_text_ratio_on_white() {
        let passing = SYSTEM_COLORS
            .iter()
            .filter(|color| ratio(color.light, WHITE) >= 4.5)
            .map(|color| color.name)
            .collect::<Vec<_>>();
        assert_eq!(passing, ["indigo"]);
    }
}
