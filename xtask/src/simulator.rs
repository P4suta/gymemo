//! Runs the app's UI tests on a simulator that only these checks use, and exports what they captured.

use crate::failure::{Context, Failure, Result, ensure};
use std::{
    fs,
    path::{Path, PathBuf},
    process::{Command, Stdio},
};

const DEVICE_NAME: &str = "gymemo checks";
const DEVICE_TYPE: &str = "iPhone 17 Pro";
/// The runtime that the checks bind their results to, as `simctl create` names it.
/// The iOS 27.1 runtime of Xcode 27.2 offers no iPhone 17 device type.
const RUNTIME: &str = "com.apple.CoreSimulator.SimRuntime.iOS-27-0";
/// The same runtime as `simctl list devices` heads its section.
const RUNTIME_SECTION: &str = "iOS 27.0";
const PROJECT: &str = "gymemo.xcodeproj";
const SCHEME: &str = "gymemo";
const BUNDLE_IDENTIFIER: &str = "com.p4suta.gymemo";
const RESULTS: &str = "target/ui-test";
const SCREENSHOTS: &str = "target/screenshots";
/// The test class that runs only while the simulator shows the dark appearance.
const DARK_TESTS: &str = "gymemoUITests/DarkAppearanceTests";
/// The test class that runs only while the simulator increases the contrast in the light appearance.
const CONTRAST_TESTS: &str = "gymemoUITests/IncreasedContrastTests";
/// The test class that runs only while the simulator increases the contrast in the dark appearance.
const DARK_CONTRAST_TESTS: &str = "gymemoUITests/DarkIncreasedContrastTests";

/// The display settings of the simulator during one pass of the UI tests: light, dark, and each of the two with Increase Contrast.
/// The accessibility guidance asks an app to check the contrast in both appearances.
/// `XCUIDevice` doesn't change these settings on the pinned simulator, so `simctl` sets them around each pass.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Appearance {
    Light,
    Dark,
    Contrast,
    DarkContrast,
}

impl Appearance {
    const ALL: [Appearance; 4] = [
        Appearance::Light,
        Appearance::Dark,
        Appearance::Contrast,
        Appearance::DarkContrast,
    ];

    pub fn parse(text: &str) -> Option<Self> {
        Self::ALL
            .into_iter()
            .find(|appearance| appearance.name() == text)
    }

    fn name(self) -> &'static str {
        match self {
            Appearance::Light => "light",
            Appearance::Dark => "dark",
            Appearance::Contrast => "contrast",
            Appearance::DarkContrast => "dark-contrast",
        }
    }

    /// The interface style of the pass.
    fn style(self) -> &'static str {
        match self {
            Appearance::Dark | Appearance::DarkContrast => "dark",
            Appearance::Light | Appearance::Contrast => "light",
        }
    }

    /// Whether the pass turns Increase Contrast on.
    fn increases_contrast(self) -> bool {
        matches!(self, Appearance::Contrast | Appearance::DarkContrast)
    }

    /// The `xcodebuild` arguments that give each special test class to its own pass and every other test to the light pass.
    fn selection(self) -> Vec<String> {
        match self {
            Appearance::Light => vec![
                format!("-skip-testing:{DARK_TESTS}"),
                format!("-skip-testing:{CONTRAST_TESTS}"),
                format!("-skip-testing:{DARK_CONTRAST_TESTS}"),
            ],
            Appearance::Dark => vec![format!("-only-testing:{DARK_TESTS}")],
            Appearance::Contrast => vec![format!("-only-testing:{CONTRAST_TESTS}")],
            Appearance::DarkContrast => vec![format!("-only-testing:{DARK_CONTRAST_TESTS}")],
        }
    }
}

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

/// The identifier of the simulator called `name` under the `runtime` section of `xcrun simctl list devices`.
fn identifier(listing: &str, runtime: &str, name: &str) -> Option<String> {
    let mut in_runtime = false;
    for line in listing.lines() {
        if let Some(section) = line.strip_prefix("-- ") {
            in_runtime = section.strip_suffix(" --") == Some(runtime);
            continue;
        }
        let candidate = line
            .trim_start()
            .strip_prefix(name)
            .and_then(|rest| rest.strip_prefix(" ("))
            .and_then(|rest| rest.split(')').next());
        if let Some(candidate) = candidate
            && in_runtime
            && is_device_identifier(candidate)
        {
            return Some(candidate.to_owned());
        }
    }
    None
}

/// The number of an entry named `run-N` or `run-N-…`.
fn run_number(name: &str) -> Option<u32> {
    let rest = name.strip_prefix("run-")?;
    let digits = rest
        .find(|character: char| !character.is_ascii_digit())
        .map_or(rest, |end| &rest[..end]);
    digits.parse().ok()
}

/// The number of the latest run among `existing` names.
fn latest_run(existing: &[String]) -> Option<u32> {
    existing.iter().filter_map(|name| run_number(name)).max()
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
    if let Some(found) = identifier(&listing, RUNTIME_SECTION, DEVICE_NAME) {
        return Ok(found);
    }
    let created = output(Command::new("xcrun").args([
        "simctl",
        "create",
        DEVICE_NAME,
        DEVICE_TYPE,
        RUNTIME,
    ]))?;
    let created = created.trim();
    ensure(is_device_identifier(created), || {
        format!("simctl create printed no device identifier: {created}")
    })?;
    Ok(created.to_owned())
}

fn set_appearance(device: &str, appearance: Appearance) -> Result<()> {
    output(Command::new("xcrun").args(["simctl", "ui", device, "appearance", appearance.style()]))?;
    let contrast = if appearance.increases_contrast() {
        "enabled"
    } else {
        "disabled"
    };
    output(Command::new("xcrun").args(["simctl", "ui", device, "increase_contrast", contrast]))
        .map(|_| ())
}

/// The names in `directory`, which the call creates when it doesn't exist yet.
fn entries(directory: &Path) -> Result<Vec<String>> {
    fs::create_dir_all(directory).context(|| format!("Create {}", directory.display()))?;
    let mut names = Vec::new();
    for entry in fs::read_dir(directory).context(|| format!("Read {}", directory.display()))? {
        let entry = entry.context(|| format!("Read {}", directory.display()))?;
        names.push(entry.file_name().to_string_lossy().into_owned());
    }
    Ok(names)
}

fn bundle(results: &Path, run: u32, appearance: Appearance) -> PathBuf {
    results.join(format!("run-{run}-{}.xcresult", appearance.name()))
}

/// Runs the tests of one appearance and writes their result bundle.
fn pass(
    root: &Path,
    device: &str,
    bundle: &Path,
    appearance: Appearance,
    arguments: &[String],
) -> Result<()> {
    let status = Command::new("xcodebuild")
        .current_dir(root)
        .args(["test", "-project", PROJECT, "-scheme", SCHEME])
        .arg("-destination")
        .arg(format!("platform=iOS Simulator,id={device}"))
        .args(["-derivedDataPath", "DerivedData"])
        .arg("-resultBundlePath")
        .arg(bundle)
        .args(appearance.selection())
        .args(arguments)
        .status()
        .context(|| "Start xcodebuild".to_owned())?;
    if status.success() {
        println!(
            "PASS ui-test {}: the result bundle is {}",
            appearance.name(),
            bundle.display()
        );
        return Ok(());
    }
    let code = status
        .code()
        .and_then(|code| u8::try_from(code).ok())
        .unwrap_or(1);
    Err(Failure::exit(
        format!(
            "The {} UI tests failed with {status}, and the result bundle is {}",
            appearance.name(),
            bundle.display()
        ),
        code,
    ))
}

/// Runs the UI tests on the dedicated simulator: in the light appearance, in the dark one, and in both with Increase Contrast.
/// `only` keeps one of the passes, and `arguments` go on to `xcodebuild`.
/// Each run writes new result bundles, so a run never overwrites an earlier one.
pub fn ui_test(root: &Path, only: Option<Appearance>, arguments: &[String]) -> Result<()> {
    let device = device()?;
    output(Command::new("xcrun").args(["simctl", "bootstatus", &device, "-b"]))?;
    let results = root.join(RESULTS);
    let run = latest_run(&entries(&results)?).map_or(1, |last| last + 1);
    let mut outcome = Ok(());
    for appearance in Appearance::ALL {
        if only.is_some_and(|kept| kept != appearance) {
            continue;
        }
        outcome = set_appearance(&device, appearance).and_then(|()| {
            pass(
                root,
                &device,
                &bundle(&results, run, appearance),
                appearance,
                arguments,
            )
        });
        if outcome.is_err() {
            break;
        }
    }
    // The simulator returns to the light appearance at the default contrast, and a failure to return never hides a test failure.
    let restored = set_appearance(&device, Appearance::Light);
    outcome.and(restored)
}

/// Runs `command` with its output on the terminal, and fails with its exit code.
fn run(command: &mut Command) -> Result<()> {
    let described = format!("{command:?}");
    let status = command.status().context(|| format!("Start {described}"))?;
    if status.success() {
        return Ok(());
    }
    let code = status
        .code()
        .and_then(|code| u8::try_from(code).ok())
        .unwrap_or(1);
    Err(Failure::exit(
        format!("{described} failed with {status}"),
        code,
    ))
}

/// Builds the app, installs it on the dedicated simulator, and opens it there.
/// `arguments` go to the app as launch arguments.
pub fn app(root: &Path, arguments: &[String]) -> Result<()> {
    let device = device()?;
    output(Command::new("xcrun").args(["simctl", "bootstatus", &device, "-b"]))?;
    run(Command::new("xcodebuild")
        .current_dir(root)
        .args(["build", "-project", PROJECT, "-scheme", SCHEME])
        .arg("-destination")
        .arg(format!("platform=iOS Simulator,id={device}"))
        .args(["-derivedDataPath", "DerivedData", "-quiet"]))?;
    let bundle = root.join("DerivedData/Build/Products/Debug-iphonesimulator/gymemo.app");
    output(
        Command::new("xcrun")
            .args(["simctl", "install", &device])
            .arg(&bundle),
    )?;
    output(
        Command::new("xcrun")
            .args([
                "simctl",
                "launch",
                "--terminate-running-process",
                &device,
                BUNDLE_IDENTIFIER,
            ])
            .args(arguments),
    )?;
    match window() {
        Some(application) => {
            println!(
                "PASS app: gymemo runs on the simulator {DEVICE_NAME}, and {application} is open"
            );
        }
        None => println!(
            "PASS app: gymemo runs on the simulator {DEVICE_NAME}, and no app for its window opened"
        ),
    }
    Ok(())
}

/// Opens the app that holds the simulator's window and returns its name.
/// Xcode 27.2 holds Device Hub and no Simulator app, and the launch succeeds without either one.
fn window() -> Option<&'static str> {
    const APPLICATIONS: [(&str, [&str; 2]); 2] = [
        ("Simulator", ["-a", "Simulator"]),
        ("Device Hub", ["-b", "com.apple.dt.Devices"]),
    ];
    APPLICATIONS.into_iter().find_map(|(name, arguments)| {
        let opened = Command::new("open")
            .args(arguments)
            .stderr(Stdio::null())
            .status()
            .is_ok_and(|status| status.success());
        opened.then_some(name)
    })
}

/// Exports the screenshots that the latest UI test run attached, into a new directory for each appearance.
pub fn screenshots(root: &Path) -> Result<PathBuf> {
    let results = root.join(RESULTS);
    let latest = latest_run(&entries(&results)?).ok_or_else(|| {
        Failure::new("No UI test run exists yet, so run `just ui-test` first".to_owned())
    })?;
    let exports = root.join(SCREENSHOTS);
    let next = latest_run(&entries(&exports)?).map_or(1, |last| last + 1);
    let destination = exports.join(format!("run-{next}"));
    let mut exported = 0;
    for appearance in Appearance::ALL {
        let bundle = bundle(&results, latest, appearance);
        if !bundle.exists() {
            continue;
        }
        let directory = destination.join(appearance.name());
        output(
            Command::new("xcrun")
                .args(["xcresulttool", "export", "attachments", "--path"])
                .arg(&bundle)
                .arg("--output-path")
                .arg(&directory)
                .args(["--filter", "*.png"]),
        )?;
        exported += entries(&directory)?
            .iter()
            .filter(|name| name.ends_with(".png"))
            .count();
    }
    ensure(exported > 0, || {
        format!("Run {latest} in {} holds no screenshot", results.display())
    })?;
    println!(
        "PASS screenshots: {exported} images of run {latest} are in {}",
        destination.display()
    );
    Ok(destination)
}

#[cfg(test)]
mod tests {
    use super::*;

    const LISTING: &str = "== Devices ==\n-- iOS 27.0 --\n    gymemo checks (AAAAAAAA-0000-4000-8000-0123456789AB) (Shutdown) \n-- iOS 27.1 --\n    iPhone 17 Pro (5F0A1C2E-0000-4000-8000-0123456789AB) (Shutdown) \n    gymemo checks (9B2E7D10-AAAA-4BBB-8CCC-0123456789AB) (Booted) \n-- Unavailable: com.apple.CoreSimulator.SimRuntime.iOS-18-0 --\n    old checks (11111111-2222-4333-8444-555555555555) (Shutdown) (unavailable, runtime profile not found)\n";

    #[test]
    fn a_simulator_is_found_by_its_whole_name_under_its_runtime() {
        assert_eq!(
            identifier(LISTING, "iOS 27.1", "gymemo checks").as_deref(),
            Some("9B2E7D10-AAAA-4BBB-8CCC-0123456789AB")
        );
        assert_eq!(
            identifier(LISTING, "iOS 27.0", "gymemo checks").as_deref(),
            Some("AAAAAAAA-0000-4000-8000-0123456789AB")
        );
        assert_eq!(identifier(LISTING, "iOS 27.1", "gymemo"), None);
        assert_eq!(identifier(LISTING, "iOS 27.1", "old checks"), None);
        assert_eq!(identifier(LISTING, "iOS 27", "gymemo checks"), None);
        assert_eq!(identifier("", "iOS 27.1", "gymemo checks"), None);
    }

    #[test]
    fn the_latest_run_reads_the_number_after_the_prefix() {
        assert_eq!(latest_run(&[]), None);
        let existing = [
            "run-1-light.xcresult",
            "run-7-dark.xcresult",
            "notes.txt",
            "run-9",
            "run-x",
        ]
        .map(str::to_owned);
        assert_eq!(latest_run(&existing), Some(9));
        assert_eq!(run_number("run-12-light.xcresult"), Some(12));
        assert_eq!(run_number("run-"), None);
    }

    #[test]
    fn each_appearance_selects_its_own_tests() {
        assert_eq!(Appearance::parse("dark"), Some(Appearance::Dark));
        assert_eq!(Appearance::parse("light"), Some(Appearance::Light));
        assert_eq!(Appearance::parse("sepia"), None);
        assert_eq!(Appearance::parse("contrast"), Some(Appearance::Contrast));
        assert_eq!(
            Appearance::parse("dark-contrast"),
            Some(Appearance::DarkContrast)
        );
        assert_eq!(
            Appearance::Light.selection(),
            [
                "-skip-testing:gymemoUITests/DarkAppearanceTests",
                "-skip-testing:gymemoUITests/IncreasedContrastTests",
                "-skip-testing:gymemoUITests/DarkIncreasedContrastTests"
            ]
        );
        assert_eq!(
            Appearance::DarkContrast.selection(),
            ["-only-testing:gymemoUITests/DarkIncreasedContrastTests"]
        );
        assert_eq!(Appearance::DarkContrast.style(), "dark");
        assert!(Appearance::DarkContrast.increases_contrast());
        assert!(!Appearance::Dark.increases_contrast());
        assert_eq!(
            Appearance::Dark.selection(),
            ["-only-testing:gymemoUITests/DarkAppearanceTests"]
        );
        assert_eq!(
            Appearance::Contrast.selection(),
            ["-only-testing:gymemoUITests/IncreasedContrastTests"]
        );
        assert_eq!(Appearance::Dark.style(), "dark");
        assert_eq!(Appearance::Contrast.style(), "light");
        assert!(Appearance::Contrast.increases_contrast());
        assert!(!Appearance::Light.increases_contrast());
    }
}
