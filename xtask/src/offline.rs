//! Keeps networking APIs out of the shipped Swift code.
//!
//! `docs/adr/keep-records-on-the-device-and-back-up-through-files.md` decides that the app never uses the network.

use crate::{
    failure::{Result, ensure},
    swift_source::{self, SHIPPED, code_only, names},
};
use std::path::Path;

/// Types that open a connection or load remote content.
const REFUSED_NAMES: [&str; 9] = [
    "URLSession",
    "URLRequest",
    "URLSessionConfiguration",
    "NWConnection",
    "NWListener",
    "NWPathMonitor",
    "WKWebView",
    "SFSafariViewController",
    "CKContainer",
];

/// Modules whose only purpose is networking or cloud storage.
const REFUSED_IMPORTS: [&str; 4] = ["Network", "CFNetwork", "WebKit", "CloudKit"];

/// The planted lines that the check must refuse, which show that it reads what it claims to read.
const PLANTED: [&str; 3] = [
    "let (data, _) = try await URLSession.shared.data(from: url)\n",
    "import Network\n",
    "let monitor = NWPathMonitor()\n",
];

/// Each networking API that `source` names, with its file and line.
fn findings(source: &str, file: &str) -> Vec<String> {
    let mut found = Vec::new();
    for (index, line) in code_only(source).lines().enumerate() {
        let place = format!("{file}:{}", index + 1);
        if let Some(module) = line.trim().strip_prefix("import ")
            && REFUSED_IMPORTS.contains(&module.trim())
        {
            found.push(format!(
                "{place} imports {}, and the app never uses the network",
                module.trim()
            ));
        }
        for name in REFUSED_NAMES {
            if names(line, name) {
                found.push(format!(
                    "{place} names {name}, and the app never uses the network"
                ));
            }
        }
    }
    found
}

/// Scans the shipped Swift code and refuses any networking API.
pub fn check(root: &Path) -> Result<String> {
    let sources = swift_source::read(root, &SHIPPED)?;
    let found = sources
        .iter()
        .flat_map(|source| findings(&source.text, &source.file))
        .collect::<Vec<_>>();
    ensure(found.is_empty(), || {
        format!(
            "The shipped code names a networking API:\n{}",
            found.join("\n")
        )
    })?;
    for planted in PLANTED {
        ensure(!findings(planted, "planted.swift").is_empty(), || {
            format!("The offline check accepted a planted line: {planted}")
        })?;
    }
    Ok(format!(
        "{} Swift files name no networking API, and {} planted lines fail",
        sources.len(),
        PLANTED.len()
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn file_urls_pass_and_connections_fail() {
        for allowed in [
            "let file = URL(fileURLWithPath: path)\n",
            "import Foundation\n",
            "let text = \"URLSession\" // URLSession\n",
            "let networkName = name\n",
        ] {
            assert!(findings(allowed, "a.swift").is_empty(), "{allowed}");
        }
        for refused in [
            "var request = URLRequest(url: url)\n",
            "import CloudKit\n",
            "let view = WKWebView()\n",
        ] {
            assert_eq!(findings(refused, "a.swift").len(), 1, "{refused}");
        }
        for planted in PLANTED {
            assert!(!findings(planted, "planted.swift").is_empty(), "{planted}");
        }
    }

    #[test]
    fn the_shipped_swift_code_passes() -> Result<()> {
        check(&Path::new(env!("CARGO_MANIFEST_DIR")).join("..")).map(|_| ())
    }
}
