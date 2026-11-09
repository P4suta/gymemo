//! Repository checks and simulator runs for gymemo.

#[cfg(test)]
mod contrast;
mod failure;
mod literals;
mod logging;
mod offline;
mod purity;
mod required_reasons;
mod simulator;
mod swift_source;
mod system_design;

use failure::{Failure, Result, ensure};
use simulator::Appearance;
use std::{env, path::Path, process::ExitCode};

const USAGE: &str = "Usage: xtask <COMMAND>

Commands:
  gates                             Check the Swift sources for departures from the system design, text outside the catalog, effects in the core, console output, networking, and required reason APIs
  ui-test [--only light|dark|contrast|dark-contrast] [XCODEBUILD_ARGUMENT]...
                                    Run the UI tests on the dedicated simulator: light, dark, and both with Increase Contrast
  screenshots                       Export the screenshots of the latest UI test run into a new directory
  app [LAUNCH_ARGUMENT]...          Build the app and open it on the dedicated simulator
  help                              Print this message";

#[derive(Debug, PartialEq, Eq)]
enum Task {
    Gates,
    UiTest {
        only: Option<Appearance>,
        arguments: Vec<String>,
    },
    Screenshots,
    App(Vec<String>),
    Help,
}

/// Reads the optional `--only APPEARANCE` and leaves the rest for `xcodebuild`.
fn ui_test(mut arguments: impl Iterator<Item = String>) -> Result<Task> {
    let mut rest = Vec::new();
    let mut only = None;
    while let Some(argument) = arguments.next() {
        if argument != "--only" {
            rest.push(argument);
            continue;
        }
        let name = arguments.next().unwrap_or_default();
        only = Some(Appearance::parse(&name).ok_or_else(|| {
            Failure::new(format!(
                "--only takes light, dark, contrast, or dark-contrast, and it received `{name}`\n\n{USAGE}"
            ))
        })?);
    }
    Ok(Task::UiTest {
        only,
        arguments: rest,
    })
}

/// `task` when `command` received no further argument.
fn alone(command: &str, task: Task, mut arguments: impl Iterator<Item = String>) -> Result<Task> {
    match arguments.next() {
        None => Ok(task),
        Some(extra) => Err(Failure::new(format!(
            "{command} takes no argument, and it received {extra}\n\n{USAGE}"
        ))),
    }
}

fn parse(mut arguments: impl Iterator<Item = String>) -> Result<Task> {
    let Some(command) = arguments.next() else {
        return Err(Failure::new(USAGE));
    };
    match command.as_str() {
        "gates" => alone("gates", Task::Gates, arguments),
        "screenshots" => alone("screenshots", Task::Screenshots, arguments),
        "ui-test" => ui_test(arguments),
        "app" => Ok(Task::App(arguments.collect())),
        "help" | "--help" | "-h" => Ok(Task::Help),
        unknown => Err(Failure::new(format!(
            "Unknown command {unknown}\n\n{USAGE}"
        ))),
    }
}

type Gate = fn(&Path) -> Result<String>;

/// The source checks, each of which refuses its own planted violations before it passes.
const GATES: [(&str, Gate); 6] = [
    ("system design", system_design::check),
    ("literals", literals::check),
    ("purity", purity::check),
    ("logging", logging::check),
    ("offline", offline::check),
    ("required reasons", required_reasons::check),
];

/// Runs every source check, so one run reports every failure.
fn gates(root: &Path) -> Result<()> {
    let mut failed = Vec::new();
    for (name, gate) in GATES {
        match gate(root) {
            Ok(summary) => println!("PASS {name}: {summary}"),
            Err(failure) => {
                eprintln!("FAIL {name}: {failure}");
                failed.push(name);
            }
        }
    }
    ensure(failed.is_empty(), || {
        format!("These source checks failed: {}", failed.join(", "))
    })
}

fn main() -> ExitCode {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("..");
    let outcome = parse(env::args().skip(1)).and_then(|task| match task {
        Task::Gates => gates(&root),
        Task::UiTest { only, arguments } => simulator::ui_test(&root, only, &arguments),
        Task::Screenshots => simulator::screenshots(&root).map(|_| ()),
        Task::App(arguments) => simulator::app(&root, &arguments),
        Task::Help => {
            println!("{USAGE}");
            Ok(())
        }
    });
    match outcome {
        Ok(()) => ExitCode::SUCCESS,
        Err(failure) => {
            eprintln!("{failure}");
            ExitCode::from(failure.code())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn task(arguments: &[&str]) -> Result<Task> {
        parse(arguments.iter().map(|argument| (*argument).to_owned()))
    }

    #[test]
    fn each_command_parses_and_anything_else_is_refused() {
        assert_eq!(task(&["gates"]), Ok(Task::Gates));
        assert_eq!(task(&["screenshots"]), Ok(Task::Screenshots));
        assert_eq!(
            task(&["app", "-gymemo-sample"]),
            Ok(Task::App(vec!["-gymemo-sample".to_owned()]))
        );
        assert!(task(&["screenshots", "extra"]).is_err());
        assert_eq!(
            task(&["ui-test", "-only-testing:gymemoUITests/LogTests"]),
            Ok(Task::UiTest {
                only: None,
                arguments: vec!["-only-testing:gymemoUITests/LogTests".to_owned()]
            })
        );
        assert_eq!(
            task(&["ui-test", "--only", "dark"]),
            Ok(Task::UiTest {
                only: Some(Appearance::Dark),
                arguments: vec![]
            })
        );
        assert!(task(&["ui-test", "--only", "sepia"]).is_err());
        assert!(task(&["ui-test", "--only"]).is_err());
        assert_eq!(task(&["--help"]), Ok(Task::Help));
        assert!(task(&[]).is_err());
        assert!(task(&["gates", "extra"]).is_err());
        assert!(task(&["deploy"]).is_err());
    }
}
