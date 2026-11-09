//! Runs the app's UI tests on a simulator that only these checks use.

use crate::failure::{Context, Failure, Result, ensure};
use std::{
    fs,
    path::{Path, PathBuf},
    process::Command,
};

const DEVICE_NAME: &str = "gymemo checks";
const DEVICE_TYPE: &str = "iPhone 17 Pro";
const PROJECT: &str = "gymemo.xcodeproj";
const SCHEME: &str = "gymemo";
const RESULTS: &str = "target/ui-test";

fn is_device_identifier(text: &str) -> bool {
    text.len() == 36
        && text.chars().enumerate().all(|(index, character)| {
            if [8, 13, 18, 23].contains(&index) {
                character == '-'
            } else {
                character.is_ascii_hexdigit()
            }
        })
}

/// The identifier of the available simulator called `name` in the output of `xcrun simctl list devices`.
fn identifier(listing: &str, name: &str) -> Option<String> {
    let mut available = false;
    for line in listing.lines() {
        if let Some(section) = line.strip_prefix("-- ") {
            available = !section.starts_with("Unavailable");
            continue;
        }
        let candidate = line
            .trim_start()
            .strip_prefix(name)
            .and_then(|rest| rest.strip_prefix(" ("))
            .and_then(|rest| rest.split(')').next());
        if let Some(candidate) = candidate
            && available
            && is_device_identifier(candidate)
        {
            return Some(candidate.to_owned());
        }
    }
    None
}

/// The first unused result bundle path, so a run never overwrites an earlier one.
fn fresh_result(existing: &[String]) -> String {
    let next = existing
        .iter()
        .filter_map(|name| {
            name.strip_prefix("run-")?
                .strip_suffix(".xcresult")?
                .parse::<u32>()
                .ok()
        })
        .max()
        .map_or(1, |last| last + 1);
    format!("run-{next}.xcresult")
}

/// Runs `command` and returns its standard output, or the failure with its standard error.
fn output(command: &mut Command) -> Result<String> {
    let described = format!("{command:?}");
    let result = command.output().context(|| format!("Start {described}"))?;
    ensure(result.status.success(), || {
        format!(
            "{described} failed with {}:\n{}",
            result.status,
            String::from_utf8_lossy(&result.stderr)
        )
    })?;
    String::from_utf8(result.stdout).context(|| format!("Read the output of {described}"))
}

/// The dedicated simulator's identifier, creating the simulator when it doesn't exist yet.
fn device() -> Result<String> {
    let listing = output(Command::new("xcrun").args(["simctl", "list", "devices"]))?;
    if let Some(found) = identifier(&listing, DEVICE_NAME) {
        return Ok(found);
    }
    let created =
        output(Command::new("xcrun").args(["simctl", "create", DEVICE_NAME, DEVICE_TYPE]))?;
    let created = created.trim();
    ensure(is_device_identifier(created), || {
        format!("simctl create printed no device identifier: {created}")
    })?;
    Ok(created.to_owned())
}

fn result_bundle(root: &Path) -> Result<PathBuf> {
    let directory = root.join(RESULTS);
    fs::create_dir_all(&directory).context(|| format!("Create {}", directory.display()))?;
    let mut existing = Vec::new();
    for entry in fs::read_dir(&directory).context(|| format!("Read {}", directory.display()))? {
        let entry = entry.context(|| format!("Read {}", directory.display()))?;
        existing.push(entry.file_name().to_string_lossy().into_owned());
    }
    Ok(directory.join(fresh_result(&existing)))
}

/// Runs the UI tests on the dedicated simulator and passes `arguments` on to `xcodebuild`.
pub fn ui_test(root: &Path, arguments: &[String]) -> Result<()> {
    let device = device()?;
    let bundle = result_bundle(root)?;
    let status = Command::new("xcodebuild")
        .current_dir(root)
        .args(["test", "-project", PROJECT, "-scheme", SCHEME])
        .arg("-destination")
        .arg(format!("platform=iOS Simulator,id={device}"))
        .args(["-derivedDataPath", "DerivedData"])
        .arg("-resultBundlePath")
        .arg(&bundle)
        .args(arguments)
        .status()
        .context(|| "Start xcodebuild".to_owned())?;
    if status.success() {
        println!("PASS ui-test: the result bundle is {}", bundle.display());
        return Ok(());
    }
    let code = status
        .code()
        .and_then(|code| u8::try_from(code).ok())
        .unwrap_or(1);
    Err(Failure::exit(
        format!(
            "The UI tests failed with {status}, and the result bundle is {}",
            bundle.display()
        ),
        code,
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    const LISTING: &str = "== Devices ==\n-- iOS 27.1 --\n    iPhone 17 Pro (5F0A1C2E-0000-4000-8000-0123456789AB) (Shutdown) \n    gymemo checks (9B2E7D10-AAAA-4BBB-8CCC-0123456789AB) (Booted) \n-- Unavailable: com.apple.CoreSimulator.SimRuntime.iOS-18-0 --\n    old checks (11111111-2222-4333-8444-555555555555) (Shutdown) (unavailable, runtime profile not found)\n";

    #[test]
    fn an_available_simulator_is_found_by_its_whole_name() {
        assert_eq!(
            identifier(LISTING, "gymemo checks").as_deref(),
            Some("9B2E7D10-AAAA-4BBB-8CCC-0123456789AB")
        );
        assert_eq!(identifier(LISTING, "gymemo"), None);
        assert_eq!(identifier(LISTING, "old checks"), None);
        assert_eq!(identifier("", "gymemo checks"), None);
    }

    #[test]
    fn a_result_bundle_never_reuses_a_number() {
        assert_eq!(fresh_result(&[]), "run-1.xcresult");
        let existing = ["run-1.xcresult", "run-7.xcresult", "notes.txt"].map(str::to_owned);
        assert_eq!(fresh_result(&existing), "run-8.xcresult");
    }
}
