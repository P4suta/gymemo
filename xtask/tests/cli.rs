//! Runs the built command as a developer does, and reads its exit code, its standard output, and its standard error.
//!
//! No test here reaches a simulator command past its refusal, and the command finds no program on the search path that the tests give it.

use std::{env, io, process::Command};

/// The usage as the command prints it, written out here so that a changed message fails a test.
const USAGE: &str = "Usage: xtask <COMMAND>

Commands:
  gates                             Check the Swift sources for departures from the system design, text outside the catalog, effects in the core, console output, networking, and required reason APIs
  ui-test [--only light|dark|contrast|dark-contrast] [XCODEBUILD_ARGUMENT]...
                                    Run the UI tests on the dedicated simulator: light, dark, and both with Increase Contrast
  screenshots                       Export the screenshots of the latest UI test run into a new directory
  app [LAUNCH_ARGUMENT]...          Build the app and open it on the dedicated simulator
  help                              Print this message
";

const CHECKS: [&str; 6] = [
    "system design",
    "literals",
    "purity",
    "logging",
    "offline",
    "required reasons",
];

/// What one run of the command left behind.
#[derive(Debug, PartialEq, Eq)]
struct Run {
    code: Option<i32>,
    output: String,
    error: String,
}

/// Runs the built command from a directory outside every repository, so the command works on the repository that holds the crate.
fn xtask(arguments: &[&str]) -> io::Result<Run> {
    let result = Command::new(env!("CARGO_BIN_EXE_xtask"))
        .args(arguments)
        .current_dir(env::temp_dir())
        .env("PATH", "/gymemo-xtask-holds-no-program")
        .output()?;
    Ok(Run {
        code: result.status.code(),
        output: String::from_utf8_lossy(&result.stdout).into_owned(),
        error: String::from_utf8_lossy(&result.stderr).into_owned(),
    })
}

/// The names of the checks that `lines` report with `verdict`, in their order.
fn reported<'a>(lines: &'a str, verdict: &str) -> Vec<&'a str> {
    lines
        .lines()
        .filter_map(|line| line.strip_prefix(verdict))
        .filter_map(|rest| rest.split_once(": "))
        .map(|(name, _)| name)
        .collect()
}

#[test]
fn a_command_line_without_a_command_fails_with_the_usage() -> io::Result<()> {
    assert_eq!(
        xtask(&[])?,
        Run {
            code: Some(1),
            output: String::new(),
            error: USAGE.to_owned(),
        }
    );
    Ok(())
}

#[test]
fn a_refused_command_line_fails_with_its_reason_above_the_usage() -> io::Result<()> {
    let refusals = [
        (&["deploy"][..], "Unknown command deploy"),
        (
            &["gates", "extra"][..],
            "gates takes no argument, and it received extra",
        ),
        (
            &["screenshots", "extra"][..],
            "screenshots takes no argument, and it received extra",
        ),
        (
            &["ui-test", "--only", "sepia"][..],
            "--only takes light, dark, contrast, or dark-contrast, and it received `sepia`",
        ),
        (
            &["ui-test", "-quiet", "--only"][..],
            "--only takes light, dark, contrast, or dark-contrast, and it received ``",
        ),
    ];
    for (arguments, reason) in refusals {
        assert_eq!(
            xtask(arguments)?,
            Run {
                code: Some(1),
                output: String::new(),
                error: format!("{reason}\n\n{USAGE}"),
            },
            "{arguments:?}"
        );
    }
    Ok(())
}

#[test]
fn help_prints_the_usage_and_succeeds() -> io::Result<()> {
    for help in ["help", "--help", "-h"] {
        assert_eq!(
            xtask(&[help])?,
            Run {
                code: Some(0),
                output: USAGE.to_owned(),
                error: String::new(),
            },
            "{help}"
        );
    }
    Ok(())
}

#[test]
fn the_source_checks_pass_over_the_repository_that_holds_the_crate() -> io::Result<()> {
    let run = xtask(&["gates"])?;
    assert_eq!((run.code, run.error.as_str()), (Some(0), ""));
    assert_eq!(reported(&run.output, "PASS "), CHECKS);
    assert_eq!(run.output.lines().count(), CHECKS.len());
    Ok(())
}
