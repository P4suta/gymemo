//! Repository checks and simulator runs for gymemo.

mod colors;
mod failure;
mod logging;
mod purity;
mod required_reasons;
mod simulator;
mod swift_source;

use failure::{Failure, Result, ensure};
use std::{env, path::Path, process::ExitCode};

const USAGE: &str = "Usage: xtask <COMMAND>

Commands:
  gates                             Check the Swift sources for authored colors, effects in the core, console output, and required reason APIs
  ui-test [XCODEBUILD_ARGUMENT]...  Run the UI tests on the dedicated simulator
  help                              Print this message";

#[derive(Debug, PartialEq, Eq)]
enum Task {
    Gates,
    UiTest(Vec<String>),
    Help,
}

fn parse(mut arguments: impl Iterator<Item = String>) -> Result<Task> {
    let Some(command) = arguments.next() else {
        return Err(Failure::new(USAGE));
    };
    match command.as_str() {
        "gates" => match arguments.next() {
            None => Ok(Task::Gates),
            Some(extra) => Err(Failure::new(format!(
                "gates takes no argument, and it received {extra}\n\n{USAGE}"
            ))),
        },
        "ui-test" => Ok(Task::UiTest(arguments.collect())),
        "help" | "--help" | "-h" => Ok(Task::Help),
        unknown => Err(Failure::new(format!(
            "Unknown command {unknown}\n\n{USAGE}"
        ))),
    }
}

type Gate = fn(&Path) -> Result<String>;

/// The source checks, each of which refuses its own planted violations before it passes.
const GATES: [(&str, Gate); 4] = [
    ("colors", colors::check),
    ("purity", purity::check),
    ("logging", logging::check),
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
        Task::UiTest(arguments) => simulator::ui_test(&root, &arguments),
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
        assert_eq!(
            task(&["ui-test", "-only-testing:gymemoUITests/LogTests"]),
            Ok(Task::UiTest(vec![
                "-only-testing:gymemoUITests/LogTests".to_owned()
            ]))
        );
        assert_eq!(task(&["--help"]), Ok(Task::Help));
        assert!(task(&[]).is_err());
        assert!(task(&["gates", "extra"]).is_err());
        assert!(task(&["deploy"]).is_err());
    }
}
