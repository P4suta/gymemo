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

/// The call that draws a random identifier.
const RANDOM_IDENTIFIER: &str = "UUID()";

/// The planted lines that the check must refuse, which show that it reads what it claims to read.
const PLANTED: [&str; 4] = [
    "let today = Date()\n",
    "let id = SetID(UUID())\n",
    "import os\n",
    "let pick = values.randomElement()\n",
];

/// Each effect that `source` names, with its file and line.
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
        if line.contains(RANDOM_IDENTIFIER) {
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
}
