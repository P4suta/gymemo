//! Keeps required reason APIs out of the shipped Swift code, so the privacy manifest's empty declaration stays true.
//!
//! The categories and their APIs come from Apple's [`NSPrivacyAccessedAPIType`](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype) list.
//! [Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) states that App Store Connect refuses an app that leaves such a use undeclared.

use crate::{
    failure::{Context, Result, ensure},
    swift_source::{self, SHIPPED, Source, code_only, names},
};
use std::{fs, path::Path};

const MANIFEST: &str = "Config/PrivacyInfo.xcprivacy";
/// The prefix of every category name that a manifest can declare.
const DECLARATION: &str = "NSPrivacyAccessedAPICategory";

/// Each category with the API names that it covers.
/// `attributesOfItem` isn't on Apple's list, and it stays here because its result carries the file timestamp keys.
const CATEGORIES: [(&str, &[&str]); 5] = [
    (
        "NSPrivacyAccessedAPICategoryFileTimestamp",
        &[
            "creationDate",
            "modificationDate",
            "fileModificationDate",
            "contentModificationDateKey",
            "creationDateKey",
            "getattrlist",
            "getattrlistbulk",
            "fgetattrlist",
            "stat",
            "fstat",
            "fstatat",
            "lstat",
            "getattrlistat",
            "attributesOfItem",
        ],
    ),
    (
        "NSPrivacyAccessedAPICategorySystemBootTime",
        &["systemUptime", "mach_absolute_time"],
    ),
    (
        "NSPrivacyAccessedAPICategoryDiskSpace",
        &[
            "volumeAvailableCapacityKey",
            "volumeAvailableCapacityForImportantUsageKey",
            "volumeAvailableCapacityForOpportunisticUsageKey",
            "volumeTotalCapacityKey",
            "systemFreeSize",
            "systemSize",
            "statfs",
            "statvfs",
            "fstatfs",
            "fstatvfs",
        ],
    ),
    (
        "NSPrivacyAccessedAPICategoryActiveKeyboards",
        &["activeInputModes"],
    ),
    (
        "NSPrivacyAccessedAPICategoryUserDefaults",
        &["UserDefaults", "AppStorage", "SceneStorage"],
    ),
];

/// The planted files that the check must refuse, which show that it reads what it claims to read.
const PLANTED: [&str; 3] = [
    "var info = stat()\n_ = stat(path, &info)\n",
    "let date = values.modificationDate\n",
    "@AppStorage(\"unit\") private var unit = \"kg\"\n",
];

/// Each required reason API that the sources name, located by its file and its category.
fn findings(sources: &[Source]) -> Vec<String> {
    let mut found = Vec::new();
    for source in sources {
        let code = code_only(&source.text);
        for (category, apis) in CATEGORIES {
            for api in apis {
                if names(&code, api) {
                    found.push(format!(
                        "{} names {api}, and {MANIFEST} declares no reason for {category}",
                        source.file
                    ));
                }
            }
        }
    }
    found
}

/// Scans the shipped Swift code and the manifest, and refuses a required reason API or a declaration.
pub fn check(root: &Path) -> Result<String> {
    let sources = swift_source::read(root, &SHIPPED)?;
    let manifest =
        fs::read_to_string(root.join(MANIFEST)).context(|| format!("Read {MANIFEST}"))?;
    ensure(!manifest.contains(DECLARATION), || {
        format!(
            "{MANIFEST} declares a required reason category, and this check accepts only an empty declaration"
        )
    })?;
    let found = findings(&sources);
    ensure(found.is_empty(), || {
        format!("Undeclared required reason API:\n{}", found.join("\n"))
    })?;
    for planted in PLANTED {
        let planted_source = [Source {
            file: "planted.swift".to_owned(),
            text: planted.to_owned(),
        }];
        ensure(!findings(&planted_source).is_empty(), || {
            format!("The required reason check accepted a planted call: {planted}")
        })?;
    }
    Ok(format!(
        "{} Swift files name no required reason API, and {} planted calls fail",
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
            AFTER_PATTERNS, AFTER_SLASHES, AROUND_OPERATORS, AROUND_RAW_IDENTIFIERS,
            KEYWORD_SCREEN, OPERATOR_SCREEN, Tree, after_patterns, after_slashes, around_operators,
            around_raw_identifiers,
        },
    };

    fn source(text: &str) -> Vec<Source> {
        vec![Source {
            file: "a.swift".to_owned(),
            text: text.to_owned(),
        }]
    }

    #[test]
    fn whole_identifiers_count_and_text_does_not() {
        assert!(findings(&source("// stat(path)\nlet text = \"stat(x)\"\n")).is_empty());
        assert!(findings(&source("let status = state\n")).is_empty());
        assert_eq!(findings(&source("UserDefaults.standard")).len(), 1);
        let timestamp = findings(&source(
            "let size = try FileManager.default.attributesOfItem(atPath: p)",
        ));
        assert!(
            timestamp[0].contains("NSPrivacyAccessedAPICategoryFileTimestamp"),
            "{timestamp:?}"
        );
    }

    #[test]
    fn the_shipped_swift_code_passes() -> Result<()> {
        check(&Path::new(env!("CARGO_MANIFEST_DIR")).join("..")).map(|_| ())
    }

    const EMPTY_MANIFEST: &str =
        "<plist><dict><key>NSPrivacyAccessedAPITypes</key><array/></dict></plist>\n";

    /// A repository with one screen that holds `screen`, one store file, and a manifest that holds `manifest`.
    fn shipped(name: &str, screen: &str, manifest: &str) -> Result<Tree> {
        Tree::new(
            name,
            &[
                ("App/Screen.swift", screen),
                ("Sources/GymemoKit/Store.swift", "import Foundation\n"),
                (MANIFEST, manifest),
            ],
        )
    }

    #[test]
    fn code_without_required_reason_apis_passes_with_the_number_of_its_files() -> Result<()> {
        let tree = shipped("reasons-clean", "import SwiftUI\n", EMPTY_MANIFEST)?;
        assert_eq!(
            check(tree.root()),
            Ok("2 Swift files name no required reason API, and 3 planted calls fail".to_owned())
        );
        Ok(())
    }

    #[test]
    fn a_required_reason_api_is_refused_with_its_file_and_category() -> Result<()> {
        let tree = shipped(
            "reasons-defaults",
            "@AppStorage(\"unit\") private var unit = \"kg\"\n",
            EMPTY_MANIFEST,
        )?;
        assert_eq!(
            check(tree.root()),
            Err(Failure::new(
                "Undeclared required reason API:\n\
                 App/Screen.swift names AppStorage, and Config/PrivacyInfo.xcprivacy declares no reason for NSPrivacyAccessedAPICategoryUserDefaults"
            ))
        );
        Ok(())
    }

    #[test]
    fn a_manifest_that_declares_a_category_is_refused() -> Result<()> {
        let tree = shipped(
            "reasons-declared",
            "import SwiftUI\n",
            "<string>NSPrivacyAccessedAPICategoryUserDefaults</string>\n",
        )?;
        assert_eq!(
            check(tree.root()),
            Err(Failure::new(
                "Config/PrivacyInfo.xcprivacy declares a required reason category, and this check accepts only an empty declaration"
            ))
        );
        Ok(())
    }

    #[test]
    fn a_repository_without_a_manifest_is_refused() -> Result<()> {
        let tree = Tree::new(
            "reasons-no-manifest",
            &[
                ("App/Screen.swift", "import SwiftUI\n"),
                ("Sources/GymemoKit/Store.swift", "import Foundation\n"),
            ],
        )?;
        let refusal = check(tree.root()).map_err(|failure| failure.to_string());
        assert!(
            refusal
                .as_ref()
                .is_err_and(|message| message.starts_with("Read Config/PrivacyInfo.xcprivacy: ")),
            "{refusal:?}"
        );
        Ok(())
    }

    #[test]
    fn an_api_inside_a_nested_comment_passes() -> Result<()> {
        let tree = shipped(
            "reasons-nested-comment",
            "/* let a = 1 /* inner */ let defaults = UserDefaults.standard */\n",
            EMPTY_MANIFEST,
        )?;
        assert_eq!(
            check(tree.root()),
            Ok("2 Swift files name no required reason API, and 3 planted calls fail".to_owned())
        );
        Ok(())
    }

    #[test]
    fn an_api_after_a_comment_or_a_regular_expression_that_holds_quotes_is_refused() -> Result<()> {
        let mut files = after_slashes("App", "let defaults = UserDefaults.standard");
        files.push((
            "Sources/GymemoKit/Store.swift".to_owned(),
            "import Foundation\n".to_owned(),
        ));
        files.push((MANIFEST.to_owned(), EMPTY_MANIFEST.to_owned()));
        let tree = Tree::new("reasons-slashes", &files)?;
        let found = (1..=AFTER_SLASHES.len())
            .map(|number| {
                format!(
                    "App/Slash{number:02}.swift names UserDefaults, and {MANIFEST} declares no reason for NSPrivacyAccessedAPICategoryUserDefaults"
                )
            })
            .collect::<Vec<_>>();
        assert_eq!(
            check(tree.root()),
            Err(Failure::new(format!(
                "Undeclared required reason API:\n{}",
                found.join("\n")
            )))
        );
        Ok(())
    }

    #[test]
    fn an_api_between_the_slash_of_an_operator_and_a_division_is_refused() -> Result<()> {
        let mut files = around_operators("App", "let defaults = UserDefaults.standard");
        files.push((
            "Sources/GymemoKit/Store.swift".to_owned(),
            "import Foundation\n".to_owned(),
        ));
        files.push((MANIFEST.to_owned(), EMPTY_MANIFEST.to_owned()));
        let tree = Tree::new("reasons-operators", &files)?;
        let found = (1..=AROUND_OPERATORS.len())
            .map(|number| {
                format!(
                    "App/Operator{number:02}.swift names UserDefaults, and {MANIFEST} declares no reason for NSPrivacyAccessedAPICategoryUserDefaults"
                )
            })
            .collect::<Vec<_>>();
        assert_eq!(
            check(tree.root()),
            Err(Failure::new(format!(
                "Undeclared required reason API:\n{}",
                found.join("\n")
            )))
        );
        Ok(())
    }

    #[test]
    fn an_api_beside_a_raw_identifier_is_refused() -> Result<()> {
        let mut files = around_raw_identifiers("App", "let defaults = UserDefaults.standard");
        files.push((
            "Sources/GymemoKit/Store.swift".to_owned(),
            "import Foundation\n".to_owned(),
        ));
        files.push((MANIFEST.to_owned(), EMPTY_MANIFEST.to_owned()));
        let tree = Tree::new("reasons-raw-identifiers", &files)?;
        let found = (1..=AROUND_RAW_IDENTIFIERS.len())
            .map(|number| {
                format!(
                    "App/Raw{number:02}.swift names UserDefaults, and {MANIFEST} declares no reason for NSPrivacyAccessedAPICategoryUserDefaults"
                )
            })
            .collect::<Vec<_>>();
        assert_eq!(
            check(tree.root()),
            Err(Failure::new(format!(
                "Undeclared required reason API:\n{}",
                found.join("\n")
            )))
        );
        Ok(())
    }

    /// Each file of `AFTER_PATTERNS` names an API after its regular expression literal, the screen of `OPERATOR_SCREEN` names the user defaults, and the screen of `KEYWORD_SCREEN` names a file timestamp key.
    #[test]
    fn an_api_after_a_regular_expression_that_holds_quotes_or_a_comment_mark_is_refused()
    -> Result<()> {
        let mut files = after_patterns("Sources/GymemoKit", "let defaults = UserDefaults.standard");
        files.push(("App/Screen.swift".to_owned(), KEYWORD_SCREEN.to_owned()));
        files.push(("App/Operator.swift".to_owned(), OPERATOR_SCREEN.to_owned()));
        files.push((MANIFEST.to_owned(), EMPTY_MANIFEST.to_owned()));
        let tree = Tree::new("reasons-keywords", &files)?;
        let found = [
            format!(
                "App/Operator.swift names UserDefaults, and {MANIFEST} declares no reason for NSPrivacyAccessedAPICategoryUserDefaults"
            ),
            format!(
                "App/Screen.swift names contentModificationDateKey, and {MANIFEST} declares no reason for NSPrivacyAccessedAPICategoryFileTimestamp"
            ),
        ]
        .into_iter()
        .chain((1..=AFTER_PATTERNS.len()).map(|number| {
            format!(
                "Sources/GymemoKit/Pattern{number:02}.swift names UserDefaults, and {MANIFEST} declares no reason for NSPrivacyAccessedAPICategoryUserDefaults"
            )
        }))
        .collect::<Vec<_>>();
        assert_eq!(
            check(tree.root()),
            Err(Failure::new(format!(
                "Undeclared required reason API:\n{}",
                found.join("\n")
            )))
        );
        Ok(())
    }

    #[test]
    fn an_api_after_a_raw_literal_that_holds_a_quote_is_refused() -> Result<()> {
        let tree = shipped(
            "reasons-raw-literal",
            "let quote = #\"\"\"#\nlet uptime = ProcessInfo.processInfo.systemUptime\n",
            EMPTY_MANIFEST,
        )?;
        assert_eq!(
            check(tree.root()),
            Err(Failure::new(
                "Undeclared required reason API:\n\
                 App/Screen.swift names systemUptime, and Config/PrivacyInfo.xcprivacy declares no reason for NSPrivacyAccessedAPICategorySystemBootTime"
            ))
        );
        Ok(())
    }
}
