//! Runs the app's UI tests on a simulator that only these checks use, and exports what they captured.
//!
//! Every program, every directory, and every message goes through the host, so a test reads each decision of a run from the fake host.

use crate::{
    failure::{Context, Failure, Result, ensure},
    host::{Host, Invocation, Streams},
};
use std::path::{Path, PathBuf};

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

/// The highest run number among `existing` names.
fn latest_run(existing: &[String]) -> Option<u32> {
    existing.iter().filter_map(|name| run_number(name)).max()
}

/// Runs `invocation` and returns its standard output, or the failure with its standard error.
fn output(host: &mut impl Host, invocation: &Invocation) -> Result<String> {
    let result = host
        .run(invocation, Streams::Captured)
        .context(|| format!("Start {invocation}"))?;
    ensure(result.status.success(), || {
        format!(
            "{invocation} failed with {}:\n{}",
            result.status,
            String::from_utf8_lossy(&result.stderr)
        )
    })?;
    String::from_utf8(result.stdout).context(|| format!("Read the output of {invocation}"))
}

/// The dedicated simulator's identifier, creating the simulator when it doesn't exist yet.
fn device(host: &mut impl Host) -> Result<String> {
    let listing = output(
        host,
        &Invocation::new("xcrun").args(["simctl", "list", "devices"]),
    )?;
    if let Some(found) = identifier(&listing, RUNTIME_SECTION, DEVICE_NAME) {
        return Ok(found);
    }
    let created = output(
        host,
        &Invocation::new("xcrun").args(["simctl", "create", DEVICE_NAME, DEVICE_TYPE, RUNTIME]),
    )?;
    let created = created.trim();
    ensure(is_device_identifier(created), || {
        format!("simctl create printed no device identifier: {created}")
    })?;
    Ok(created.to_owned())
}

/// The two settings that give the simulator the display of `appearance`: the interface style, then Increase Contrast.
fn settings(device: &str, appearance: Appearance) -> [Invocation; 2] {
    let contrast = if appearance.increases_contrast() {
        "enabled"
    } else {
        "disabled"
    };
    [
        Invocation::new("xcrun").args(["simctl", "ui", device, "appearance", appearance.style()]),
        Invocation::new("xcrun").args(["simctl", "ui", device, "increase_contrast", contrast]),
    ]
}

/// Gives the simulator the display of `appearance` before a pass, and stops at the first setting that fails.
fn set_appearance(host: &mut impl Host, device: &str, appearance: Appearance) -> Result<()> {
    for setting in settings(device, appearance) {
        output(host, &setting)?;
    }
    Ok(())
}

/// The outcome of two steps that both ran: each failure, in the order of the steps.
fn both(first: Result<()>, second: Result<()>) -> Result<()> {
    match (first, second) {
        (Err(first), Err(second)) => Err(first.followed_by(&second)),
        (first, second) => first.and(second),
    }
}

/// Returns the simulator to the light appearance at the default contrast.
/// Each setting runs even after the other one failed, so one failure never leaves the other setting behind.
fn restore(host: &mut impl Host, device: &str) -> Result<()> {
    let [style, contrast] =
        settings(device, Appearance::Light).map(|setting| output(host, &setting).map(|_| ()));
    both(style, contrast)
}

/// The names in `directory`, which the call creates when it doesn't exist yet.
fn entries(host: &mut impl Host, directory: &Path) -> Result<Vec<String>> {
    host.create_directories(directory)
        .context(|| format!("Create {}", directory.display()))?;
    host.list(directory)
        .context(|| format!("Read {}", directory.display()))
}

fn bundle(results: &Path, run: u32, appearance: Appearance) -> PathBuf {
    results.join(format!("run-{run}-{}.xcresult", appearance.name()))
}

/// Runs the tests of one appearance and writes their result bundle.
fn pass(
    host: &mut impl Host,
    root: &Path,
    device: &str,
    bundle: &Path,
    appearance: Appearance,
    arguments: &[String],
) -> Result<()> {
    let status = host
        .run(
            &Invocation::new("xcodebuild")
                .current_dir(root)
                .args(["test", "-project", PROJECT, "-scheme", SCHEME])
                .arg("-destination")
                .arg(format!("platform=iOS Simulator,id={device}"))
                .args(["-derivedDataPath", "DerivedData"])
                .arg("-resultBundlePath")
                .arg(bundle)
                .args(appearance.selection())
                .args(arguments),
            Streams::Shown,
        )
        .context(|| "Start xcodebuild".to_owned())?
        .status;
    if status.success() {
        host.print(&format!(
            "PASS ui-test {}: the result bundle is {}",
            appearance.name(),
            bundle.display()
        ));
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
pub fn ui_test(
    host: &mut impl Host,
    root: &Path,
    only: Option<Appearance>,
    arguments: &[String],
) -> Result<()> {
    let device = device(host)?;
    output(
        host,
        &Invocation::new("xcrun").args(["simctl", "bootstatus", &device, "-b"]),
    )?;
    let results = root.join(RESULTS);
    let run = latest_run(&entries(host, &results)?).map_or(1, |last| last + 1);
    let mut outcome = Ok(());
    for appearance in Appearance::ALL {
        if only.is_some_and(|kept| kept != appearance) {
            continue;
        }
        outcome = set_appearance(host, &device, appearance).and_then(|()| {
            pass(
                host,
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
    // The simulator returns to the light appearance at the default contrast, and a failure to return follows a test failure without hiding it.
    let restored = restore(host, &device);
    both(outcome, restored)
}

/// Runs `invocation` with its output on the terminal, and fails with its exit code.
fn run(host: &mut impl Host, invocation: &Invocation) -> Result<()> {
    let status = host
        .run(invocation, Streams::Shown)
        .context(|| format!("Start {invocation}"))?
        .status;
    if status.success() {
        return Ok(());
    }
    let code = status
        .code()
        .and_then(|code| u8::try_from(code).ok())
        .unwrap_or(1);
    Err(Failure::exit(
        format!("{invocation} failed with {status}"),
        code,
    ))
}

/// Builds the app, installs it on the dedicated simulator, and opens it there.
/// `arguments` go to the app as launch arguments.
pub fn app(host: &mut impl Host, root: &Path, arguments: &[String]) -> Result<()> {
    let device = device(host)?;
    output(
        host,
        &Invocation::new("xcrun").args(["simctl", "bootstatus", &device, "-b"]),
    )?;
    run(
        host,
        &Invocation::new("xcodebuild")
            .current_dir(root)
            .args(["build", "-project", PROJECT, "-scheme", SCHEME])
            .arg("-destination")
            .arg(format!("platform=iOS Simulator,id={device}"))
            .args(["-derivedDataPath", "DerivedData", "-quiet"]),
    )?;
    let bundle = root.join("DerivedData/Build/Products/Debug-iphonesimulator/gymemo.app");
    output(
        host,
        &Invocation::new("xcrun")
            .args(["simctl", "install", &device])
            .arg(&bundle),
    )?;
    output(
        host,
        &Invocation::new("xcrun")
            .args([
                "simctl",
                "launch",
                "--terminate-running-process",
                &device,
                BUNDLE_IDENTIFIER,
            ])
            .args(arguments),
    )?;
    let opened = match window(host) {
        Some(application) => {
            format!(
                "PASS app: gymemo runs on the simulator {DEVICE_NAME}, and {application} is open"
            )
        }
        None => format!(
            "PASS app: gymemo runs on the simulator {DEVICE_NAME}, and no app for its window opened"
        ),
    };
    host.print(&opened);
    Ok(())
}

/// Opens the app that holds the simulator's window and returns its name.
/// Xcode 27.2 holds Device Hub and no Simulator app, and the launch succeeds without either one.
fn window(host: &mut impl Host) -> Option<&'static str> {
    const APPLICATIONS: [(&str, [&str; 2]); 2] = [
        ("Simulator", ["-a", "Simulator"]),
        ("Device Hub", ["-b", "com.apple.dt.Devices"]),
    ];
    APPLICATIONS.into_iter().find_map(|(name, arguments)| {
        let opened = host
            .run(
                &Invocation::new("open").args(arguments),
                Streams::ShownWithoutErrors,
            )
            .is_ok_and(|result| result.status.success());
        opened.then_some(name)
    })
}

/// The images that one export wrote.
#[derive(Debug, PartialEq, Eq)]
pub struct Export {
    /// The UI test run that attached the images.
    pub run: u32,
    /// The number of exported images over every appearance.
    pub images: usize,
    /// The new directory, which holds one directory for each appearance.
    pub destination: PathBuf,
}

/// Exports the screenshots that the UI test run with the highest number attached, into a new directory for each appearance.
pub fn screenshots(host: &mut impl Host, root: &Path) -> Result<Export> {
    let results = root.join(RESULTS);
    let latest = latest_run(&entries(host, &results)?).ok_or_else(|| {
        Failure::new("No UI test run exists yet, so run `just ui-test` first".to_owned())
    })?;
    let exports = root.join(SCREENSHOTS);
    let next = latest_run(&entries(host, &exports)?).map_or(1, |last| last + 1);
    let destination = exports.join(format!("run-{next}"));
    let mut exported = 0;
    for appearance in Appearance::ALL {
        let bundle = bundle(&results, latest, appearance);
        if !host.exists(&bundle) {
            continue;
        }
        let directory = destination.join(appearance.name());
        output(
            host,
            &Invocation::new("xcrun")
                .args(["xcresulttool", "export", "attachments", "--path"])
                .arg(&bundle)
                .arg("--output-path")
                .arg(&directory)
                .args(["--filter", "*.png"]),
        )?;
        exported += entries(host, &directory)?
            .iter()
            .filter(|name| name.ends_with(".png"))
            .count();
    }
    ensure(exported > 0, || {
        format!("Run {latest} in {} holds no screenshot", results.display())
    })?;
    let export = Export {
        run: latest,
        images: exported,
        destination,
    };
    host.print(&format!(
        "PASS screenshots: {} images of run {} are in {}",
        export.images,
        export.run,
        export.destination.display()
    ));
    Ok(export)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::host::fake::{CREATED, DEVICE, FakeHost, Fault};
    use std::{os::unix::process::ExitStatusExt, process::ExitStatus};

    const ROOT: &str = "/repo";

    /// Each appearance with the name that the command line gives it.
    const PASSES: [(Appearance, &str); 4] = [
        (Appearance::Light, "light"),
        (Appearance::Dark, "dark"),
        (Appearance::Contrast, "contrast"),
        (Appearance::DarkContrast, "dark-contrast"),
    ];

    /// Every call of a whole run on a simulator that exists, with `{device}` for the identifier of the simulator.
    /// Two lines find and boot the simulator, two read the results, three belong to each pass, and two return the simulator to light.
    const WHOLE_RUN: &str = r#"
capture "xcrun" "simctl" "list" "devices"
capture "xcrun" "simctl" "bootstatus" "{device}" "-b"
create /repo/target/ui-test
list /repo/target/ui-test
capture "xcrun" "simctl" "ui" "{device}" "appearance" "light"
capture "xcrun" "simctl" "ui" "{device}" "increase_contrast" "disabled"
show cd "/repo" && "xcodebuild" "test" "-project" "gymemo.xcodeproj" "-scheme" "gymemo" "-destination" "platform=iOS Simulator,id={device}" "-derivedDataPath" "DerivedData" "-resultBundlePath" "/repo/target/ui-test/run-1-light.xcresult" "-skip-testing:gymemoUITests/DarkAppearanceTests" "-skip-testing:gymemoUITests/IncreasedContrastTests" "-skip-testing:gymemoUITests/DarkIncreasedContrastTests"
capture "xcrun" "simctl" "ui" "{device}" "appearance" "dark"
capture "xcrun" "simctl" "ui" "{device}" "increase_contrast" "disabled"
show cd "/repo" && "xcodebuild" "test" "-project" "gymemo.xcodeproj" "-scheme" "gymemo" "-destination" "platform=iOS Simulator,id={device}" "-derivedDataPath" "DerivedData" "-resultBundlePath" "/repo/target/ui-test/run-1-dark.xcresult" "-only-testing:gymemoUITests/DarkAppearanceTests"
capture "xcrun" "simctl" "ui" "{device}" "appearance" "light"
capture "xcrun" "simctl" "ui" "{device}" "increase_contrast" "enabled"
show cd "/repo" && "xcodebuild" "test" "-project" "gymemo.xcodeproj" "-scheme" "gymemo" "-destination" "platform=iOS Simulator,id={device}" "-derivedDataPath" "DerivedData" "-resultBundlePath" "/repo/target/ui-test/run-1-contrast.xcresult" "-only-testing:gymemoUITests/IncreasedContrastTests"
capture "xcrun" "simctl" "ui" "{device}" "appearance" "dark"
capture "xcrun" "simctl" "ui" "{device}" "increase_contrast" "enabled"
show cd "/repo" && "xcodebuild" "test" "-project" "gymemo.xcodeproj" "-scheme" "gymemo" "-destination" "platform=iOS Simulator,id={device}" "-derivedDataPath" "DerivedData" "-resultBundlePath" "/repo/target/ui-test/run-1-dark-contrast.xcresult" "-only-testing:gymemoUITests/DarkIncreasedContrastTests"
capture "xcrun" "simctl" "ui" "{device}" "appearance" "light"
capture "xcrun" "simctl" "ui" "{device}" "increase_contrast" "disabled"
"#;

    /// Every call of a launch with two launch arguments, while the Simulator app exists.
    const LAUNCH: &str = r#"
capture "xcrun" "simctl" "list" "devices"
capture "xcrun" "simctl" "bootstatus" "{device}" "-b"
show cd "/repo" && "xcodebuild" "build" "-project" "gymemo.xcodeproj" "-scheme" "gymemo" "-destination" "platform=iOS Simulator,id={device}" "-derivedDataPath" "DerivedData" "-quiet"
capture "xcrun" "simctl" "install" "{device}" "/repo/DerivedData/Build/Products/Debug-iphonesimulator/gymemo.app"
capture "xcrun" "simctl" "launch" "--terminate-running-process" "{device}" "com.p4suta.gymemo" "-gymemo-sample" "-AppleLanguages (ja)"
show-without-errors "open" "-a" "Simulator"
"#;

    /// Every call of an export of run 3, which holds the bundles of the light and the contrast pass.
    const EXPORT: &str = r#"
create /repo/target/ui-test
list /repo/target/ui-test
create /repo/target/screenshots
list /repo/target/screenshots
exists /repo/target/ui-test/run-3-light.xcresult
capture "xcrun" "xcresulttool" "export" "attachments" "--path" "/repo/target/ui-test/run-3-light.xcresult" "--output-path" "/repo/target/screenshots/run-1/light" "--filter" "*.png"
create /repo/target/screenshots/run-1/light
list /repo/target/screenshots/run-1/light
exists /repo/target/ui-test/run-3-dark.xcresult
exists /repo/target/ui-test/run-3-contrast.xcresult
capture "xcrun" "xcresulttool" "export" "attachments" "--path" "/repo/target/ui-test/run-3-contrast.xcresult" "--output-path" "/repo/target/screenshots/run-1/contrast" "--filter" "*.png"
create /repo/target/screenshots/run-1/contrast
list /repo/target/screenshots/run-1/contrast
exists /repo/target/ui-test/run-3-dark-contrast.xcresult
"#;

    /// The lines of a transcript that a test writes out, with the identifier of the simulator in place of `{device}`.
    fn lines(transcript: &str) -> Vec<String> {
        transcript
            .lines()
            .filter(|line| !line.is_empty())
            .map(|line| line.replace("{device}", DEVICE))
            .collect()
    }

    /// Whether a line of a transcript starts a program.
    fn starts_program(line: &str) -> bool {
        ["capture ", "show ", "show-without-errors "]
            .iter()
            .any(|verb| line.starts_with(verb))
    }

    /// The transcript up to the program at `position`, which no later call follows.
    fn through(transcript: &[String], position: usize) -> Vec<String> {
        let end = transcript
            .iter()
            .enumerate()
            .filter(|(_, line)| starts_program(line))
            .nth(position)
            .map_or(transcript.len(), |(index, _)| index + 1);
        transcript[..end].to_vec()
    }

    /// The command line of the program at `position`, as a failure names it.
    fn command_line(transcript: &[String], position: usize) -> &str {
        transcript
            .iter()
            .filter(|line| starts_program(line))
            .nth(position)
            .and_then(|line| line.split_once(' '))
            .map_or("", |(_, command_line)| command_line)
    }

    /// The whole run, or the run that keeps only the pass called `only`.
    fn run_of(only: Option<&str>) -> Vec<String> {
        let whole = lines(WHOLE_RUN);
        let Some(name) = only else {
            return whole;
        };
        let bundle = format!("run-1-{name}.xcresult\"");
        let kept = whole[4..16]
            .chunks(3)
            .find(|pass| pass[2].contains(&bundle))
            .unwrap_or_default();
        [&whole[..4], kept, &whole[16..]].concat()
    }

    fn display(host: &FakeHost) -> (&str, &str) {
        (host.appearance.as_str(), host.contrast.as_str())
    }

    /// The message of a pass of run 1 whose tests passed, which names the result bundle of the pass.
    fn pass_message(name: &str) -> String {
        format!(
            "PASS ui-test {name}: the result bundle is /repo/target/ui-test/run-1-{name}.xcresult"
        )
    }

    /// The message of a launch whose window opened in `application`.
    fn launch_message(application: &str) -> String {
        format!("PASS app: gymemo runs on the simulator gymemo checks, and {application} is open")
    }

    /// The message of the standard library for output that isn't text.
    fn not_text() -> String {
        String::from_utf8(vec![0xff])
            .err()
            .map(|error| error.to_string())
            .unwrap_or_default()
    }

    /// A host whose results hold run 3 with the bundles of the light and the contrast pass, next to an older run.
    fn host_with_run_3() -> FakeHost {
        let mut host = FakeHost::new();
        host.directory(
            "/repo/target/ui-test",
            &[
                "notes.txt",
                "run-2-dark.xcresult",
                "run-3-contrast.xcresult",
                "run-3-light.xcresult",
            ],
        );
        host.attachments.insert(
            "run-3-light.xcresult",
            vec!["log-en.png", "log-ja.png", "manifest.json"],
        );
        host.attachments
            .insert("run-3-contrast.xcresult", vec!["log-contrast.png"]);
        host
    }

    #[test]
    fn a_whole_run_makes_these_calls_in_this_order() {
        let mut host = FakeHost::new();
        assert_eq!(ui_test(&mut host, Path::new(ROOT), None, &[]), Ok(()));
        assert_eq!(host.transcript(), lines(WHOLE_RUN));
        assert_eq!(host.output, PASSES.map(|(_, name)| pass_message(name)));
        assert_eq!(host.errors, Vec::<String>::new());
    }

    #[test]
    fn each_test_class_runs_under_the_display_settings_of_its_pass() {
        let mut host = FakeHost::new();
        assert_eq!(ui_test(&mut host, Path::new(ROOT), None, &[]), Ok(()));
        assert_eq!(
            host.passes,
            [
                "light disabled: -skip-testing:gymemoUITests/DarkAppearanceTests -skip-testing:gymemoUITests/IncreasedContrastTests -skip-testing:gymemoUITests/DarkIncreasedContrastTests",
                "dark disabled: -only-testing:gymemoUITests/DarkAppearanceTests",
                "light enabled: -only-testing:gymemoUITests/IncreasedContrastTests",
                "dark enabled: -only-testing:gymemoUITests/DarkIncreasedContrastTests",
            ]
        );
        assert_eq!(display(&host), ("light", "disabled"));
    }

    #[test]
    fn only_keeps_one_pass_and_the_simulator_still_returns_to_light() {
        for (appearance, name) in PASSES {
            let mut host = FakeHost::new();
            let outcome = ui_test(&mut host, Path::new(ROOT), Some(appearance), &[]);
            assert_eq!(outcome, Ok(()), "{name}");
            assert_eq!(host.transcript(), run_of(Some(name)), "{name}");
            assert_eq!(host.passes.len(), 1, "{name}");
            assert_eq!(host.output, [pass_message(name)], "{name}");
            assert_eq!(display(&host), ("light", "disabled"), "{name}");
        }
    }

    #[test]
    fn the_arguments_of_the_caller_follow_the_selection_of_each_pass() {
        let arguments = [
            "-only-testing:gymemoUITests/LogTests".to_owned(),
            "-quiet".to_owned(),
        ];
        let mut host = FakeHost::new();
        assert_eq!(
            ui_test(&mut host, Path::new(ROOT), None, &arguments),
            Ok(())
        );
        let expected = lines(WHOLE_RUN)
            .into_iter()
            .map(|line| {
                if line.starts_with("show ") {
                    format!("{line} \"-only-testing:gymemoUITests/LogTests\" \"-quiet\"")
                } else {
                    line
                }
            })
            .collect::<Vec<_>>();
        assert_eq!(host.transcript(), expected);
    }

    #[test]
    fn a_run_takes_the_number_after_the_latest_result() {
        let mut host = FakeHost::new();
        host.directory(
            "/repo/target/ui-test",
            &["notes.txt", "run-1-light.xcresult", "run-3-dark.xcresult"],
        );
        let outcome = ui_test(&mut host, Path::new(ROOT), Some(Appearance::Dark), &[]);
        assert_eq!(outcome, Ok(()));
        let expected = run_of(Some("dark"))
            .into_iter()
            .map(|line| line.replace("run-1-dark", "run-4-dark"))
            .collect::<Vec<_>>();
        assert_eq!(host.transcript(), expected);
        assert_eq!(
            host.output,
            ["PASS ui-test dark: the result bundle is /repo/target/ui-test/run-4-dark.xcresult"]
        );
    }

    #[test]
    fn a_run_after_a_failed_run_takes_a_new_number() {
        let mut host = FakeHost::new();
        host.fail_at(4, Fault::Exit(65, ""));
        assert!(ui_test(&mut host, Path::new(ROOT), Some(Appearance::Light), &[]).is_err());
        let first = host.transcript().len();
        assert_eq!(
            ui_test(&mut host, Path::new(ROOT), Some(Appearance::Light), &[]),
            Ok(())
        );
        let expected = run_of(Some("light"))
            .into_iter()
            .map(|line| line.replace("run-1-light", "run-2-light"))
            .collect::<Vec<_>>();
        assert_eq!(host.transcript()[first..], expected);
    }

    #[test]
    fn a_missing_simulator_is_created_before_the_run_uses_it() {
        let mut host = FakeHost::new();
        host.listing = "== Devices ==\n-- iOS 27.1 --\n    gymemo checks (9B2E7D10-AAAA-4BBB-8CCC-0123456789AB) (Booted) \n".to_owned();
        let outcome = ui_test(&mut host, Path::new(ROOT), Some(Appearance::Light), &[]);
        assert_eq!(outcome, Ok(()));
        let mut expected = run_of(Some("light"))
            .into_iter()
            .map(|line| line.replace(DEVICE, CREATED))
            .collect::<Vec<_>>();
        expected.insert(
            1,
            r#"capture "xcrun" "simctl" "create" "gymemo checks" "iPhone 17 Pro" "com.apple.CoreSimulator.SimRuntime.iOS-27-0""#
                .to_owned(),
        );
        assert_eq!(host.transcript(), expected);
    }

    #[test]
    fn a_created_simulator_without_an_identifier_ends_the_run() {
        for printed in [
            "",
            "An error was encountered\n",
            "BBBBBBBB-1111-4111-8111\n",
            "BBBBBBBB\n",
            "zzzzzzzz-1111-4111-8111-0123456789AB\n",
            "BBBBBBBB-1111-4111-8111-0123456789ABC\n",
        ] {
            let mut host = FakeHost::new();
            host.listing = String::new();
            host.created = printed.to_owned();
            assert_eq!(
                ui_test(&mut host, Path::new(ROOT), None, &[]),
                Err(Failure::new(format!(
                    "simctl create printed no device identifier: {}",
                    printed.trim()
                ))),
                "{printed}"
            );
            assert_eq!(host.transcript().len(), 2, "{printed}");
        }
    }

    #[test]
    fn a_device_identifier_is_hexadecimal_digits_in_groups_of_8_4_4_4_and_12() {
        const SHAPE: &str = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx";
        assert!(is_device_identifier(DEVICE));
        assert!(is_device_identifier("abcdef01-2345-6789-abcd-ef0123456789"));
        for (position, class) in SHAPE.char_indices() {
            for candidate in (0..=127u8).map(char::from) {
                let mut changed = DEVICE.to_owned();
                changed.replace_range(position..=position, candidate.encode_utf8(&mut [0; 4]));
                let fits = if class == '-' {
                    candidate == '-'
                } else {
                    candidate.is_ascii_hexdigit()
                };
                assert_eq!(is_device_identifier(&changed), fits, "{changed:?}");
            }
        }
        for length in 0..DEVICE.len() {
            assert!(!is_device_identifier(&DEVICE[..length]), "{length}");
        }
        assert!(!is_device_identifier(&format!("{DEVICE}0")));
        assert!(!is_device_identifier(&"é".repeat(18)));
        assert!(!is_device_identifier(&"z".repeat(36)));
    }

    #[test]
    fn a_failure_before_the_first_pass_ends_the_run_and_changes_no_setting() {
        let whole = lines(WHOLE_RUN);
        let list = command_line(&whole, 0);
        let boot = command_line(&whole, 1);
        let killed = ExitStatus::from_raw(9);
        let cases = [
            (
                0,
                Fault::Exit(1, "boom"),
                format!("{list} failed with exit status: 1:\nboom"),
            ),
            (0, Fault::Missing, format!("Start {list}: no such program")),
            (
                0,
                Fault::Garbled,
                format!("Read the output of {list}: {}", not_text()),
            ),
            (
                1,
                Fault::Exit(149, "Unable to boot"),
                format!("{boot} failed with exit status: 149:\nUnable to boot"),
            ),
            (
                1,
                Fault::Signal(9),
                format!("{boot} failed with {killed}:\n"),
            ),
        ];
        for (position, fault, message) in cases {
            let mut host = FakeHost::new();
            host.fail_at(position, fault);
            assert_eq!(
                ui_test(&mut host, Path::new(ROOT), None, &[]),
                Err(Failure::new(message))
            );
            assert_eq!(host.transcript(), through(&whole, position));
            assert_eq!(display(&host), ("unset", "unset"));
            assert_eq!(host.output, Vec::<String>::new());
        }
    }

    #[test]
    fn a_simulator_that_cannot_be_created_ends_the_run() {
        let mut host = FakeHost::new();
        host.listing = String::new();
        host.fail("\"create\"", Fault::Exit(1, "Invalid runtime"));
        assert_eq!(
            ui_test(&mut host, Path::new(ROOT), None, &[]),
            Err(Failure::new(
                "\"xcrun\" \"simctl\" \"create\" \"gymemo checks\" \"iPhone 17 Pro\" \"com.apple.CoreSimulator.SimRuntime.iOS-27-0\" failed with exit status: 1:\nInvalid runtime"
            ))
        );
        assert_eq!(host.transcript().len(), 2);
    }

    #[test]
    fn results_that_cannot_be_read_end_the_run_before_the_first_pass() {
        let whole = lines(WHOLE_RUN);
        let mut host = FakeHost::new();
        host.refuse_creating("/repo/target/ui-test");
        assert_eq!(
            ui_test(&mut host, Path::new(ROOT), None, &[]),
            Err(Failure::new("Create /repo/target/ui-test: no permission"))
        );
        assert_eq!(host.transcript(), &whole[..3]);
        let mut host = FakeHost::new();
        host.refuse_listing("/repo/target/ui-test");
        assert_eq!(
            ui_test(&mut host, Path::new(ROOT), None, &[]),
            Err(Failure::new("Read /repo/target/ui-test: no permission"))
        );
        assert_eq!(host.transcript(), &whole[..4]);
        assert_eq!(display(&host), ("unset", "unset"));
    }

    #[test]
    fn a_failed_pass_ends_the_passes_with_the_exit_code_of_its_tests() {
        let whole = lines(WHOLE_RUN);
        let mut host = FakeHost::new();
        host.fail(
            "-only-testing:gymemoUITests/DarkAppearanceTests",
            Fault::Exit(65, ""),
        );
        assert_eq!(
            ui_test(&mut host, Path::new(ROOT), None, &[]),
            Err(Failure::exit(
                "The dark UI tests failed with exit status: 65, and the result bundle is /repo/target/ui-test/run-1-dark.xcresult",
                65
            ))
        );
        assert_eq!(
            host.transcript(),
            [through(&whole, 7), whole[16..].to_vec()].concat()
        );
        assert_eq!(host.passes.len(), 1);
        assert_eq!(host.output, [pass_message("light")]);
        assert_eq!(display(&host), ("light", "disabled"));
    }

    #[test]
    fn a_pass_that_a_signal_ends_or_that_does_not_start_fails_with_code_1() {
        let whole = lines(WHOLE_RUN);
        let stopped = ExitStatus::from_raw(15);
        let cases = [
            (
                Fault::Signal(15),
                format!(
                    "The light UI tests failed with {stopped}, and the result bundle is /repo/target/ui-test/run-1-light.xcresult"
                ),
            ),
            (
                Fault::Missing,
                "Start xcodebuild: no such program".to_owned(),
            ),
        ];
        for (fault, message) in cases {
            let mut host = FakeHost::new();
            host.fail_at(4, fault);
            assert_eq!(
                ui_test(&mut host, Path::new(ROOT), None, &[]),
                Err(Failure::new(message))
            );
            assert_eq!(
                host.transcript(),
                [through(&whole, 4), whole[16..].to_vec()].concat()
            );
            assert_eq!(host.output, Vec::<String>::new());
            assert_eq!(display(&host), ("light", "disabled"));
        }
    }

    #[test]
    fn a_setting_that_fails_skips_its_pass_and_the_simulator_returns_to_light() {
        let whole = lines(WHOLE_RUN);
        for position in [5, 6] {
            let mut host = FakeHost::new();
            host.fail_at(position, Fault::Exit(1, "busy"));
            assert_eq!(
                ui_test(&mut host, Path::new(ROOT), None, &[]),
                Err(Failure::new(format!(
                    "{} failed with exit status: 1:\nbusy",
                    command_line(&whole, position)
                )))
            );
            assert_eq!(
                host.transcript(),
                [through(&whole, position), whole[16..].to_vec()].concat()
            );
            assert_eq!(host.passes.len(), 1);
            assert_eq!(host.output, [pass_message("light")]);
            assert_eq!(display(&host), ("light", "disabled"));
        }
    }

    #[test]
    fn a_failed_return_to_light_fails_a_run_whose_passes_all_passed() {
        let whole = lines(WHOLE_RUN);
        let mut host = FakeHost::new();
        host.fail_at(15, Fault::Exit(1, "busy"));
        assert_eq!(
            ui_test(&mut host, Path::new(ROOT), None, &[]),
            Err(Failure::new(format!(
                "{} failed with exit status: 1:\nbusy",
                command_line(&whole, 15)
            )))
        );
        assert_eq!(host.transcript(), whole);
        assert_eq!(host.passes.len(), 4);
    }

    #[test]
    fn a_failed_return_to_the_light_appearance_still_turns_increase_contrast_off() {
        let whole = run_of(Some("dark-contrast"));
        let mut host = FakeHost::new();
        host.fail("\"appearance\" \"light\"", Fault::Exit(1, "busy"));
        let outcome = ui_test(
            &mut host,
            Path::new(ROOT),
            Some(Appearance::DarkContrast),
            &[],
        );
        assert_eq!(host.contrast, "disabled");
        assert_eq!(host.transcript(), whole);
        assert_eq!(
            outcome,
            Err(Failure::new(format!(
                "{} failed with exit status: 1:\nbusy",
                command_line(&whole, 5)
            )))
        );
    }

    #[test]
    fn a_failed_return_to_light_is_reported_after_the_failure_that_came_first() {
        let whole = run_of(Some("dark-contrast"));
        let style = format!(
            "{} failed with exit status: 1:\nbusy",
            command_line(&whole, 5)
        );
        let contrast = format!(
            "{} failed with exit status: 1:\ngone",
            command_line(&whole, 6)
        );
        let tests = "The dark-contrast UI tests failed with exit status: 65, and the result bundle is /repo/target/ui-test/run-1-dark-contrast.xcresult";
        let cases = [
            (
                vec![(4, Fault::Exit(65, "")), (5, Fault::Exit(1, "busy"))],
                Failure::exit(format!("{tests}\n{style}"), 65),
            ),
            (
                vec![(4, Fault::Exit(65, "")), (6, Fault::Exit(1, "gone"))],
                Failure::exit(format!("{tests}\n{contrast}"), 65),
            ),
            (
                vec![
                    (4, Fault::Exit(65, "")),
                    (5, Fault::Exit(1, "busy")),
                    (6, Fault::Exit(1, "gone")),
                ],
                Failure::exit(format!("{tests}\n{style}\n{contrast}"), 65),
            ),
            (
                vec![(5, Fault::Exit(1, "busy")), (6, Fault::Exit(1, "gone"))],
                Failure::new(format!("{style}\n{contrast}")),
            ),
        ];
        for (faults, failure) in cases {
            let mut host = FakeHost::new();
            for (position, fault) in faults {
                host.fail_at(position, fault);
            }
            let outcome = ui_test(
                &mut host,
                Path::new(ROOT),
                Some(Appearance::DarkContrast),
                &[],
            );
            assert_eq!(outcome, Err(failure));
            assert_eq!(host.transcript(), whole);
        }
    }

    /// Every set of up to three positions among `programs` started programs.
    fn fault_sets(programs: usize) -> Vec<Vec<usize>> {
        let mut sets = vec![Vec::new()];
        for first in 0..programs {
            sets.push(vec![first]);
            for second in first + 1..programs {
                sets.push(vec![first, second]);
                for third in second + 1..programs {
                    sets.push(vec![first, second, third]);
                }
            }
        }
        sets
    }

    /// The message and the exit code that a program reports when it ends with exit code 3, from its line in a transcript.
    fn reported(line: &str) -> (String, u8) {
        let (verb, command_line) = line.split_once(' ').unwrap_or_default();
        if verb == "capture" {
            return (
                format!("{command_line} failed with exit status: 3:\nboom"),
                1,
            );
        }
        let bundle = command_line
            .split("\"-resultBundlePath\" \"")
            .nth(1)
            .and_then(|rest| rest.split('"').next())
            .unwrap_or_default();
        let name = bundle
            .rsplit("/run-1-")
            .next()
            .and_then(|file| file.strip_suffix(".xcresult"))
            .unwrap_or_default();
        (
            format!(
                "The {name} UI tests failed with exit status: 3, and the result bundle is {bundle}"
            ),
            3,
        )
    }

    /// A run ends its passes at the first program that fails, and then it starts only the two programs that return the simulator to light.
    /// That order lets at most three programs fail in one run, and the sets of up to three failing positions reach every run that any set of failures reaches.
    #[test]
    fn whatever_fails_the_run_reports_each_failure_and_returns_the_simulator_to_light() {
        let choices = [(None, None)].into_iter().chain(
            PASSES
                .into_iter()
                .map(|(appearance, name)| (Some(appearance), Some(name))),
        );
        let mut runs = 0;
        for (only, name) in choices {
            let whole = run_of(name);
            let programs = whole.iter().filter(|line| starts_program(line)).count();
            let mut clean = FakeHost::new();
            assert_eq!(ui_test(&mut clean, Path::new(ROOT), only, &[]), Ok(()));
            for faults in fault_sets(programs) {
                let mut host = FakeHost::new();
                for position in &faults {
                    host.fail_at(*position, Fault::Exit(3, "boom"));
                }
                let outcome = ui_test(&mut host, Path::new(ROOT), only, &[]);
                runs += 1;
                // The first failure before the return to light decides how far the run gets.
                let first = faults
                    .iter()
                    .copied()
                    .find(|position| *position < programs - 2);
                let transcript = match first {
                    Some(position) if position < 2 => through(&whole, position),
                    Some(position) => {
                        [through(&whole, position), whole[whole.len() - 2..].to_vec()].concat()
                    }
                    None => whole.clone(),
                };
                let started = transcript
                    .iter()
                    .filter(|line| starts_program(line))
                    .collect::<Vec<_>>();
                let failed = started
                    .iter()
                    .enumerate()
                    .filter(|(position, _)| faults.contains(position))
                    .map(|(_, line)| reported(line))
                    .collect::<Vec<_>>();
                let expected = match failed.first() {
                    None => Ok(()),
                    Some((_, code)) => Err(Failure::exit(
                        failed
                            .iter()
                            .map(|(message, _)| message.as_str())
                            .collect::<Vec<_>>()
                            .join("\n"),
                        *code,
                    )),
                };
                assert_eq!(host.transcript(), transcript, "{name:?} {faults:?}");
                assert_eq!(outcome, expected, "{name:?} {faults:?}");
                if first.is_some_and(|position| position < 2) {
                    assert_eq!(display(&host), ("unset", "unset"), "{name:?} {faults:?}");
                } else {
                    if !faults.contains(&(started.len() - 2)) {
                        assert_eq!(host.appearance, "light", "{name:?} {faults:?}");
                    }
                    if !faults.contains(&(started.len() - 1)) {
                        assert_eq!(host.contrast, "disabled", "{name:?} {faults:?}");
                    }
                }
                let passed = started
                    .iter()
                    .enumerate()
                    .filter(|(position, line)| {
                        line.starts_with("show ") && !faults.contains(position)
                    })
                    .count();
                assert_eq!(host.passes, clean.passes[..passed], "{name:?} {faults:?}");
                // Each pass whose tests passed names its result bundle, and a failure reaches the caller only through the result.
                assert_eq!(host.output, clean.output[..passed], "{name:?} {faults:?}");
                assert_eq!(host.errors, Vec::<String>::new(), "{name:?} {faults:?}");
            }
        }
        assert_eq!(runs, 697 + 4 * 64);
    }

    #[test]
    fn a_launch_builds_installs_and_starts_the_app_and_then_opens_the_simulator_window() {
        let arguments = [
            "-gymemo-sample".to_owned(),
            "-AppleLanguages (ja)".to_owned(),
        ];
        let mut host = FakeHost::new();
        assert_eq!(app(&mut host, Path::new(ROOT), &arguments), Ok(()));
        assert_eq!(host.transcript(), lines(LAUNCH));
        assert_eq!(host.output, [launch_message("Simulator")]);
        assert_eq!(host.errors, Vec::<String>::new());
        let mut host = FakeHost::new();
        assert_eq!(app(&mut host, Path::new(ROOT), &[]), Ok(()));
        assert_eq!(
            host.transcript()[4],
            format!(
                "capture \"xcrun\" \"simctl\" \"launch\" \"--terminate-running-process\" \"{DEVICE}\" \"com.p4suta.gymemo\""
            )
        );
    }

    #[test]
    fn a_launch_without_the_simulator_app_opens_device_hub_and_succeeds_without_either() {
        let simulator = "show-without-errors \"open\" \"-a\" \"Simulator\"";
        let device_hub = "show-without-errors \"open\" \"-b\" \"com.apple.dt.Devices\"";
        let mut host = FakeHost::new();
        host.applications = vec!["com.apple.dt.Devices"];
        assert_eq!(window(&mut host), Some("Device Hub"));
        assert_eq!(host.transcript(), [simulator, device_hub]);
        let mut host = FakeHost::new();
        assert_eq!(window(&mut host), Some("Simulator"));
        assert_eq!(host.transcript(), [simulator]);
        let mut host = FakeHost::new();
        host.fail("\"-a\"", Fault::Missing);
        assert_eq!(window(&mut host), Some("Device Hub"));
        assert_eq!(host.transcript(), [simulator, device_hub]);
        let mut host = FakeHost::new();
        host.fail("\"open\"", Fault::Missing);
        assert_eq!(window(&mut host), None);
        assert_eq!(host.transcript(), [simulator, device_hub]);
        let mut host = FakeHost::new();
        host.applications = vec!["com.apple.dt.Devices"];
        assert_eq!(app(&mut host, Path::new(ROOT), &[]), Ok(()));
        assert_eq!(host.transcript()[5..], [simulator, device_hub]);
        assert_eq!(host.output, [launch_message("Device Hub")]);
        let mut host = FakeHost::new();
        host.applications = Vec::new();
        assert_eq!(app(&mut host, Path::new(ROOT), &[]), Ok(()));
        assert_eq!(host.transcript()[5..], [simulator, device_hub]);
        assert_eq!(
            host.output,
            [
                "PASS app: gymemo runs on the simulator gymemo checks, and no app for its window opened"
            ]
        );
    }

    #[test]
    fn a_failed_step_of_a_launch_ends_the_launch_and_names_the_step() {
        let whole = lines(LAUNCH);
        let build = command_line(&whole, 2);
        let killed = ExitStatus::from_raw(9);
        let cases = [
            (
                0,
                Fault::Exit(1, "boom"),
                Failure::new(format!(
                    "{} failed with exit status: 1:\nboom",
                    command_line(&whole, 0)
                )),
            ),
            (
                1,
                Fault::Exit(149, "Unable to boot"),
                Failure::new(format!(
                    "{} failed with exit status: 149:\nUnable to boot",
                    command_line(&whole, 1)
                )),
            ),
            (
                2,
                Fault::Exit(70, "ignored"),
                Failure::exit(format!("{build} failed with exit status: 70"), 70),
            ),
            (
                2,
                Fault::Signal(9),
                Failure::new(format!("{build} failed with {killed}")),
            ),
            (
                2,
                Fault::Missing,
                Failure::new(format!("Start {build}: no such program")),
            ),
            (
                3,
                Fault::Exit(1, "No such file"),
                Failure::new(format!(
                    "{} failed with exit status: 1:\nNo such file",
                    command_line(&whole, 3)
                )),
            ),
            (
                4,
                Fault::Exit(4, "denied"),
                Failure::new(format!(
                    "{} failed with exit status: 4:\ndenied",
                    command_line(&whole, 4)
                )),
            ),
        ];
        let arguments = [
            "-gymemo-sample".to_owned(),
            "-AppleLanguages (ja)".to_owned(),
        ];
        for (position, fault, failure) in cases {
            let mut host = FakeHost::new();
            host.fail_at(position, fault);
            assert_eq!(app(&mut host, Path::new(ROOT), &arguments), Err(failure));
            assert_eq!(host.transcript(), through(&whole, position));
            assert_eq!(host.output, Vec::<String>::new());
        }
    }

    #[test]
    fn an_export_writes_the_images_of_the_latest_run_into_a_new_directory() {
        let mut host = host_with_run_3();
        assert_eq!(
            screenshots(&mut host, Path::new(ROOT)),
            Ok(Export {
                run: 3,
                images: 3,
                destination: PathBuf::from("/repo/target/screenshots/run-1"),
            })
        );
        assert_eq!(host.transcript(), lines(EXPORT));
        assert_eq!(
            host.output,
            ["PASS screenshots: 3 images of run 3 are in /repo/target/screenshots/run-1"]
        );
        assert_eq!(host.errors, Vec::<String>::new());
    }

    #[test]
    fn an_export_takes_the_number_after_the_latest_export() {
        let mut host = host_with_run_3();
        host.directory("/repo/target/screenshots", &["run-1", "run-4", "notes.txt"]);
        assert_eq!(
            screenshots(&mut host, Path::new(ROOT)),
            Ok(Export {
                run: 3,
                images: 3,
                destination: PathBuf::from("/repo/target/screenshots/run-5"),
            })
        );
        let expected = lines(EXPORT)
            .into_iter()
            .map(|line| line.replace("screenshots/run-1", "screenshots/run-5"))
            .collect::<Vec<_>>();
        assert_eq!(host.transcript(), expected);
        assert_eq!(
            host.output,
            ["PASS screenshots: 3 images of run 3 are in /repo/target/screenshots/run-5"]
        );
    }

    #[test]
    fn an_export_without_a_run_or_without_an_image_fails() {
        let mut host = FakeHost::new();
        assert_eq!(
            screenshots(&mut host, Path::new(ROOT)),
            Err(Failure::new(
                "No UI test run exists yet, so run `just ui-test` first"
            ))
        );
        assert_eq!(host.transcript(), &lines(EXPORT)[..2]);
        let mut host = host_with_run_3();
        host.attachments.clear();
        host.attachments
            .insert("run-3-light.xcresult", vec!["manifest.json"]);
        assert_eq!(
            screenshots(&mut host, Path::new(ROOT)),
            Err(Failure::new(
                "Run 3 in /repo/target/ui-test holds no screenshot"
            ))
        );
        assert_eq!(host.transcript(), lines(EXPORT));
        let mut host = FakeHost::new();
        host.directory("/repo/target/ui-test", &["run-5"]);
        assert_eq!(
            screenshots(&mut host, Path::new(ROOT)),
            Err(Failure::new(
                "Run 5 in /repo/target/ui-test holds no screenshot"
            ))
        );
        assert!(!host.transcript().iter().any(|line| starts_program(line)));
        assert_eq!(host.output, Vec::<String>::new());
    }

    #[test]
    fn a_failed_step_of_an_export_ends_the_export_and_names_the_step() {
        let whole = lines(EXPORT);
        let mut host = host_with_run_3();
        host.fail("run-3-contrast.xcresult", Fault::Exit(1, "broken bundle"));
        assert_eq!(
            screenshots(&mut host, Path::new(ROOT)),
            Err(Failure::new(format!(
                "{} failed with exit status: 1:\nbroken bundle",
                command_line(&whole, 1)
            )))
        );
        assert_eq!(host.transcript(), &whole[..11]);
        // Each directory fails once when the export creates it and once when the export reads it, after this many calls.
        let refusals = [
            ("Create", "/repo/target/ui-test", 1),
            ("Read", "/repo/target/ui-test", 2),
            ("Create", "/repo/target/screenshots", 3),
            ("Read", "/repo/target/screenshots", 4),
            ("Create", "/repo/target/screenshots/run-1/light", 7),
            ("Read", "/repo/target/screenshots/run-1/light", 8),
        ];
        for (operation, directory, calls) in refusals {
            let mut host = host_with_run_3();
            if operation == "Create" {
                host.refuse_creating(directory);
            } else {
                host.refuse_listing(directory);
            }
            assert_eq!(
                screenshots(&mut host, Path::new(ROOT)),
                Err(Failure::new(format!(
                    "{operation} {directory}: no permission"
                )))
            );
            assert_eq!(host.transcript(), &whole[..calls]);
            assert_eq!(host.output, Vec::<String>::new());
        }
    }

    #[test]
    fn every_appearance_has_one_name_and_the_light_pass_skips_what_the_others_run() {
        for (appearance, name) in PASSES {
            assert_eq!(Appearance::parse(name), Some(appearance));
        }
        assert_eq!(Appearance::ALL, PASSES.map(|(appearance, _)| appearance));
        for unknown in ["", "Light", "dark ", "dark-contrast-", "contrast-dark"] {
            assert_eq!(Appearance::parse(unknown), None, "{unknown}");
        }
        let run_elsewhere = PASSES[1..]
            .iter()
            .flat_map(|(appearance, _)| appearance.selection())
            .map(|only| only.replacen("-only-testing:", "-skip-testing:", 1))
            .collect::<Vec<_>>();
        assert_eq!(Appearance::Light.selection(), run_elsewhere);
    }

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
