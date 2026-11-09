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

/// Each required reason API that the sources name, with its file and category.
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
}
