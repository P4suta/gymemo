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

/// Each networking API that `source` names, located by its file and its line.
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
    use crate::{
        failure::Failure,
        swift_source::fixture::{
            KEYWORD_SCREEN, OPERATOR_SCREEN, Tree, after_patterns, after_slashes, around_operators,
            around_raw_identifiers, places_after_patterns, places_after_slashes,
            places_around_operators, places_around_raw_identifiers,
        },
    };

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

    /// A repository with one screen and one store file that holds `text`.
    fn shipped(name: &str, text: &str) -> Result<Tree> {
        Tree::new(
            name,
            &[
                ("App/Screen.swift", "import SwiftUI\n"),
                ("Sources/GymemoKit/Store.swift", text),
            ],
        )
    }

    #[test]
    fn code_without_networking_passes_with_the_number_of_its_files() -> Result<()> {
        let tree = shipped("offline-clean", "let file = URL(fileURLWithPath: path)\n")?;
        assert_eq!(
            check(tree.root()),
            Ok("2 Swift files name no networking API, and 3 planted lines fail".to_owned())
        );
        Ok(())
    }

    #[test]
    fn each_networking_api_is_refused_with_its_file_and_line() -> Result<()> {
        let tree = shipped(
            "offline-network",
            "import Foundation\nimport Network\n\nlet monitor = NWPathMonitor()\n",
        )?;
        assert_eq!(
            check(tree.root()),
            Err(Failure::new(
                "The shipped code names a networking API:\n\
                 Sources/GymemoKit/Store.swift:2 imports Network, and the app never uses the network\n\
                 Sources/GymemoKit/Store.swift:4 names NWPathMonitor, and the app never uses the network"
            ))
        );
        Ok(())
    }

    #[test]
    fn a_networking_api_after_a_literal_that_never_closes_is_refused() -> Result<()> {
        let tree = shipped(
            "offline-open-literal",
            "let name = \"store\nlet session = URLSession.shared\n",
        )?;
        assert_eq!(
            check(tree.root()),
            Err(Failure::new(
                "The shipped code names a networking API:\n\
                 Sources/GymemoKit/Store.swift:2 names URLSession, and the app never uses the network"
            ))
        );
        Ok(())
    }

    #[test]
    fn a_networking_api_after_a_comment_or_a_regular_expression_that_holds_quotes_is_refused()
    -> Result<()> {
        let mut files = after_slashes("Sources/GymemoKit", "let session = URLSession.shared");
        files.push(("App/Screen.swift".to_owned(), "import SwiftUI\n".to_owned()));
        let tree = Tree::new("offline-slashes", &files)?;
        let found = places_after_slashes("Sources/GymemoKit")
            .iter()
            .map(|place| format!("{place} names URLSession, and the app never uses the network"))
            .collect::<Vec<_>>();
        assert_eq!(
            check(tree.root()),
            Err(Failure::new(format!(
                "The shipped code names a networking API:\n{}",
                found.join("\n")
            )))
        );
        Ok(())
    }

    #[test]
    fn a_networking_api_between_the_slash_of_an_operator_and_a_division_is_refused() -> Result<()> {
        let mut files = around_operators("Sources/GymemoKit", "let session = URLSession.shared");
        files.push(("App/Screen.swift".to_owned(), "import SwiftUI\n".to_owned()));
        let tree = Tree::new("offline-operators", &files)?;
        let found = places_around_operators("Sources/GymemoKit")
            .iter()
            .map(|place| format!("{place} names URLSession, and the app never uses the network"))
            .collect::<Vec<_>>();
        assert_eq!(
            check(tree.root()),
            Err(Failure::new(format!(
                "The shipped code names a networking API:\n{}",
                found.join("\n")
            )))
        );
        Ok(())
    }

    #[test]
    fn a_networking_api_beside_a_raw_identifier_is_refused() -> Result<()> {
        let mut files =
            around_raw_identifiers("Sources/GymemoKit", "let session = URLSession.shared");
        files.push(("App/Screen.swift".to_owned(), "import SwiftUI\n".to_owned()));
        let tree = Tree::new("offline-raw-identifiers", &files)?;
        let found = places_around_raw_identifiers("Sources/GymemoKit")
            .iter()
            .map(|place| format!("{place} names URLSession, and the app never uses the network"))
            .collect::<Vec<_>>();
        assert_eq!(
            check(tree.root()),
            Err(Failure::new(format!(
                "The shipped code names a networking API:\n{}",
                found.join("\n")
            )))
        );
        Ok(())
    }

    /// Each file of `AFTER_PATTERNS` names the network on the line after its regular expression literal, and the screens of `OPERATOR_SCREEN` and `KEYWORD_SCREEN` name it on line 8.
    #[test]
    fn a_networking_api_after_a_regular_expression_that_holds_quotes_or_a_comment_mark_is_refused()
    -> Result<()> {
        let mut files = after_patterns("Sources/GymemoKit", "let session = URLSession.shared");
        files.push(("App/Screen.swift".to_owned(), KEYWORD_SCREEN.to_owned()));
        files.push(("App/Operator.swift".to_owned(), OPERATOR_SCREEN.to_owned()));
        let tree = Tree::new("offline-keywords", &files)?;
        let found = ["App/Operator.swift:8", "App/Screen.swift:8"]
            .map(str::to_owned)
            .into_iter()
            .chain(places_after_patterns("Sources/GymemoKit"))
            .map(|place| format!("{place} names URLSession, and the app never uses the network"))
            .collect::<Vec<_>>();
        assert_eq!(
            check(tree.root()),
            Err(Failure::new(format!(
                "The shipped code names a networking API:\n{}",
                found.join("\n")
            )))
        );
        Ok(())
    }

    #[test]
    fn a_networking_api_inside_a_nested_comment_passes() {
        let commented = "/* let a = 1 /* inner */ let session = URLSession.shared */\n";
        assert!(findings(commented, "a.swift").is_empty());
    }
}
