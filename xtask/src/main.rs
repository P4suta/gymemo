//! Repository checks and simulator runs for gymemo.

#[cfg(test)]
mod contrast;
mod failure;
mod host;
mod literals;
mod logging;
mod offline;
mod purity;
mod required_reasons;
#[cfg(test)]
mod scratch;
mod simulator;
mod swift_source;
mod system_design;

use failure::{Failure, Result, ensure};
use host::{Host, Local};
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
/// Each check writes its summary to the standard output or its failure to the standard error.
fn gates(host: &mut impl Host, root: &Path) -> Result<()> {
    let mut failed = Vec::new();
    for (name, gate) in GATES {
        match gate(root) {
            Ok(summary) => host.print(&format!("PASS {name}: {summary}")),
            Err(failure) => {
                host.print_error(&format!("FAIL {name}: {failure}"));
                failed.push(name);
            }
        }
    }
    ensure(failed.is_empty(), || {
        format!("These source checks failed: {}", failed.join(", "))
    })
}

/// Runs `task` on the repository at `root`, where the commands reach programs, directories, and output streams through `host`.
fn execute(task: Task, host: &mut impl Host, root: &Path) -> Result<()> {
    match task {
        Task::Gates => gates(host, root),
        Task::UiTest { only, arguments } => simulator::ui_test(host, root, only, &arguments),
        Task::Screenshots => simulator::screenshots(host, root).map(|_| ()),
        Task::App(arguments) => simulator::app(host, root, &arguments),
        Task::Help => {
            host.print(USAGE);
            Ok(())
        }
    }
}

/// Runs the command line `arguments` on the repository at `root` and returns the exit code of the process.
/// A failure goes to the standard error, and its code becomes the exit code.
fn run(arguments: impl Iterator<Item = String>, host: &mut impl Host, root: &Path) -> u8 {
    match parse(arguments).and_then(|task| execute(task, host, root)) {
        Ok(()) => 0,
        Err(failure) => {
            host.print_error(&failure.to_string());
            failure.code()
        }
    }
}

fn main() -> ExitCode {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("..");
    ExitCode::from(run(env::args().skip(1), &mut Local, &root))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        host::fake::{DEVICE, FakeHost, Fault},
        scratch::Scratch,
    };
    use std::io;

    fn task(arguments: &[&str]) -> Result<Task> {
        parse(arguments.iter().map(|argument| (*argument).to_owned()))
    }

    fn texts(arguments: &[&str]) -> Vec<String> {
        arguments
            .iter()
            .map(|argument| (*argument).to_owned())
            .collect()
    }

    /// The refusal of a command line, which shows the usage under its reason and exits with 1.
    fn refusal(reason: &str) -> Result<Task> {
        Err(Failure::new(format!("{reason}\n\n{USAGE}")))
    }

    /// The names of the source checks that `messages` report with `verdict`, in their order.
    fn reported<'a>(messages: &'a [String], verdict: &str) -> Vec<&'a str> {
        messages
            .iter()
            .filter_map(|message| message.strip_prefix(verdict))
            .filter_map(|rest| rest.split_once(": "))
            .map(|(name, _)| name)
            .collect()
    }

    /// The names of the source checks other than `refused`, in the order of the run.
    fn passed_except(refused: &[&str]) -> Vec<&'static str> {
        GATES
            .map(|(name, _)| name)
            .into_iter()
            .filter(|name| !refused.contains(name))
            .collect()
    }

    #[test]
    fn every_command_parses_to_its_task() {
        assert_eq!(task(&["gates"]), Ok(Task::Gates));
        assert_eq!(task(&["screenshots"]), Ok(Task::Screenshots));
        for help in ["help", "--help", "-h"] {
            assert_eq!(task(&[help]), Ok(Task::Help), "{help}");
        }
        assert_eq!(task(&["help", "gates"]), Ok(Task::Help));
        assert_eq!(task(&["app"]), Ok(Task::App(vec![])));
        let launch = ["-gymemo-sample", "--only", "dark", "gates", "--help"];
        assert_eq!(
            task(&[&["app"], &launch[..]].concat()),
            Ok(Task::App(texts(&launch)))
        );
        assert_eq!(
            task(&["ui-test"]),
            Ok(Task::UiTest {
                only: None,
                arguments: vec![]
            })
        );
    }

    #[test]
    fn only_names_one_appearance_and_every_other_argument_goes_to_xcodebuild() {
        for (name, appearance) in [
            ("light", Appearance::Light),
            ("dark", Appearance::Dark),
            ("contrast", Appearance::Contrast),
            ("dark-contrast", Appearance::DarkContrast),
        ] {
            assert_eq!(
                task(&["ui-test", "--only", name]),
                Ok(Task::UiTest {
                    only: Some(appearance),
                    arguments: vec![]
                }),
                "{name}"
            );
        }
        assert_eq!(
            task(&["ui-test", "-quiet", "--only", "dark", "-only-testing:a/b"]),
            Ok(Task::UiTest {
                only: Some(Appearance::Dark),
                arguments: texts(&["-quiet", "-only-testing:a/b"])
            })
        );
        assert_eq!(
            task(&["ui-test", "--only", "dark", "--only", "light"]),
            Ok(Task::UiTest {
                only: Some(Appearance::Light),
                arguments: vec![]
            })
        );
        assert_eq!(
            task(&["ui-test", "--only-testing", "-only", "only", "help"]),
            Ok(Task::UiTest {
                only: None,
                arguments: texts(&["--only-testing", "-only", "only", "help"])
            })
        );
    }

    #[test]
    fn every_refusal_names_what_it_received_and_shows_the_usage() {
        assert_eq!(task(&[]), Err(Failure::new(USAGE)));
        assert_eq!(task(&["deploy"]), refusal("Unknown command deploy"));
        assert_eq!(task(&["Gates"]), refusal("Unknown command Gates"));
        assert_eq!(task(&[""]), refusal("Unknown command "));
        assert_eq!(task(&["--only", "dark"]), refusal("Unknown command --only"));
        assert_eq!(
            task(&["gates", "extra", "more"]),
            refusal("gates takes no argument, and it received extra")
        );
        assert_eq!(
            task(&["screenshots", "--only"]),
            refusal("screenshots takes no argument, and it received --only")
        );
        assert_eq!(
            task(&["ui-test", "--only"]),
            refusal("--only takes light, dark, contrast, or dark-contrast, and it received ``")
        );
        assert_eq!(
            task(&["ui-test", "-quiet", "--only", "sepia", "--only", "dark"]),
            refusal(
                "--only takes light, dark, contrast, or dark-contrast, and it received `sepia`"
            )
        );
        assert_eq!(
            task(&["ui-test", "--only", "Dark"]),
            refusal("--only takes light, dark, contrast, or dark-contrast, and it received `Dark`")
        );
    }

    #[test]
    fn a_tree_that_every_check_accepts_passes_the_source_checks() -> io::Result<()> {
        let repository = Scratch::repository("gates-accepted")?;
        let mut host = FakeHost::new();
        assert_eq!(gates(&mut host, repository.path()), Ok(()));
        assert_eq!(reported(&host.output, "PASS "), GATES.map(|(name, _)| name));
        assert_eq!(host.output.len(), GATES.len());
        assert_eq!(host.errors, Vec::<String>::new());
        let mut host = FakeHost::new();
        assert_eq!(
            run(texts(&["gates"]).into_iter(), &mut host, repository.path()),
            0
        );
        assert_eq!(reported(&host.output, "PASS "), GATES.map(|(name, _)| name));
        assert_eq!(host.errors, Vec::<String>::new());
        assert!(host.transcript().is_empty());
        Ok(())
    }

    #[test]
    fn a_refused_source_check_fails_the_command_after_every_check_reported() -> io::Result<()> {
        let repository = Scratch::repository("run-refused")?;
        repository.write("App/Screen.swift", "print(count)\n")?;
        let mut host = FakeHost::new();
        assert_eq!(
            run(texts(&["gates"]).into_iter(), &mut host, repository.path()),
            1
        );
        assert_eq!(reported(&host.output, "PASS "), passed_except(&["logging"]));
        assert_eq!(host.output.len(), GATES.len() - 1);
        assert_eq!(host.errors.len(), 2, "{:?}", host.errors);
        assert!(
            host.errors[0].starts_with("FAIL logging: Logging breaks the privacy rule:\n"),
            "{:?}",
            host.errors
        );
        assert_eq!(host.errors[1], "These source checks failed: logging");
        Ok(())
    }

    #[test]
    fn a_tree_without_sources_fails_every_source_check() -> io::Result<()> {
        let empty = Scratch::new("run-empty")?;
        let mut host = FakeHost::new();
        assert_eq!(
            run(texts(&["gates"]).into_iter(), &mut host, empty.path()),
            1
        );
        assert_eq!(host.output, Vec::<String>::new());
        assert_eq!(reported(&host.errors, "FAIL "), GATES.map(|(name, _)| name));
        assert_eq!(
            host.errors.last().map(String::as_str),
            Some(
                "These source checks failed: system design, literals, purity, logging, offline, required reasons"
            )
        );
        assert_eq!(host.errors.len(), GATES.len() + 1);
        Ok(())
    }

    #[test]
    fn a_command_writes_its_failure_to_the_standard_error_and_exits_with_the_code_of_the_failure() {
        let root = Path::new("/repo");
        let mut host = FakeHost::new();
        assert_eq!(run(texts(&["deploy"]).into_iter(), &mut host, root), 1);
        assert_eq!(host.errors, [format!("Unknown command deploy\n\n{USAGE}")]);
        assert_eq!(host.output, Vec::<String>::new());
        assert!(host.transcript().is_empty());

        let mut host = FakeHost::new();
        host.fail("\"build\"", Fault::Exit(70, "ignored"));
        assert_eq!(run(texts(&["app"]).into_iter(), &mut host, root), 70);
        assert_eq!(
            host.errors,
            [format!(
                "cd \"/repo\" && \"xcodebuild\" \"build\" \"-project\" \"gymemo.xcodeproj\" \"-scheme\" \"gymemo\" \"-destination\" \"platform=iOS Simulator,id={DEVICE}\" \"-derivedDataPath\" \"DerivedData\" \"-quiet\" failed with exit status: 70"
            )]
        );

        for help in ["help", "--help", "-h"] {
            let mut host = FakeHost::new();
            assert_eq!(
                run(texts(&[help]).into_iter(), &mut host, root),
                0,
                "{help}"
            );
            assert_eq!(host.output, [USAGE], "{help}");
            assert_eq!(host.errors, Vec::<String>::new(), "{help}");
        }
    }

    #[test]
    fn each_source_check_fails_the_run_under_its_own_name() -> io::Result<()> {
        let planted = [
            (
                "system design",
                "project.yml",
                "name: gymemo\nUIUserInterfaceStyle: Light\n",
            ),
            ("literals", "App/Screen.swift", "Text(\"Log set\")\n"),
            (
                "purity",
                "Sources/GymemoCore/Rule.swift",
                "let today = Date()\n",
            ),
            ("logging", "Sources/GymemoKit/Store.swift", "print(count)\n"),
            (
                "offline",
                "Sources/GymemoKit/Store.swift",
                "import Network\n",
            ),
            (
                "required reasons",
                "Config/PrivacyInfo.xcprivacy",
                "<string>NSPrivacyAccessedAPICategoryUserDefaults</string>\n",
            ),
        ];
        assert_eq!(
            planted.map(|(name, _, _)| name),
            GATES.map(|(name, _)| name)
        );
        for (name, file, text) in planted {
            let repository = Scratch::repository(&format!("gates-{}", name.replace(' ', "-")))?;
            repository.write(file, text)?;
            let mut host = FakeHost::new();
            assert_eq!(
                gates(&mut host, repository.path()),
                Err(Failure::new(format!("These source checks failed: {name}"))),
                "{name}"
            );
            assert_eq!(reported(&host.output, "PASS "), passed_except(&[name]));
            assert_eq!(reported(&host.errors, "FAIL "), [name]);
            assert_eq!(host.errors.len(), 1, "{name}");
        }
        Ok(())
    }

    #[test]
    fn one_run_names_every_source_check_that_fails() -> io::Result<()> {
        let repository = Scratch::repository("gates-two")?;
        repository.write("App/Screen.swift", "Text(\"Log set\")\nprint(count)\n")?;
        let mut host = FakeHost::new();
        assert_eq!(
            gates(&mut host, repository.path()),
            Err(Failure::new(
                "These source checks failed: literals, logging"
            ))
        );
        assert_eq!(
            reported(&host.output, "PASS "),
            passed_except(&["literals", "logging"])
        );
        assert_eq!(reported(&host.errors, "FAIL "), ["literals", "logging"]);
        let empty = Scratch::new("gates-empty")?;
        let mut host = FakeHost::new();
        assert_eq!(
            gates(&mut host, empty.path()),
            Err(Failure::new(
                "These source checks failed: system design, literals, purity, logging, offline, required reasons"
            ))
        );
        assert_eq!(host.output, Vec::<String>::new());
        assert_eq!(reported(&host.errors, "FAIL "), GATES.map(|(name, _)| name));
        Ok(())
    }

    #[test]
    fn each_simulator_command_reaches_its_run_with_its_arguments() {
        let root = Path::new("/repo");
        let mut host = FakeHost::new();
        let launch = Task::App(texts(&["-gymemo-sample"]));
        assert_eq!(execute(launch, &mut host, root), Ok(()));
        assert_eq!(
            host.transcript()[4],
            format!(
                "capture \"xcrun\" \"simctl\" \"launch\" \"--terminate-running-process\" \"{DEVICE}\" \"com.p4suta.gymemo\" \"-gymemo-sample\""
            )
        );

        let mut host = FakeHost::new();
        let tests = Task::UiTest {
            only: Some(Appearance::Dark),
            arguments: texts(&["-quiet"]),
        };
        assert_eq!(execute(tests, &mut host, root), Ok(()));
        let passes = host
            .transcript()
            .iter()
            .filter(|line| line.starts_with("show "))
            .collect::<Vec<_>>();
        assert_eq!(passes.len(), 1);
        assert!(
            passes[0].ends_with(
                "\"/repo/target/ui-test/run-1-dark.xcresult\" \"-only-testing:gymemoUITests/DarkAppearanceTests\" \"-quiet\""
            ),
            "{passes:?}"
        );

        let mut host = FakeHost::new();
        host.directory("/repo/target/ui-test", &["run-1-light.xcresult"]);
        host.attachments
            .insert("run-1-light.xcresult", vec!["log.png"]);
        assert_eq!(execute(Task::Screenshots, &mut host, root), Ok(()));
        assert!(
            host.transcript()
                .contains(&"create /repo/target/screenshots/run-1/light".to_owned())
        );
    }

    #[test]
    fn a_failed_simulator_command_keeps_its_message_and_its_exit_code() {
        let root = Path::new("/repo");
        let mut host = FakeHost::new();
        assert_eq!(
            execute(Task::Screenshots, &mut host, root),
            Err(Failure::new(
                "No UI test run exists yet, so run `just ui-test` first"
            ))
        );
        let mut host = FakeHost::new();
        host.fail("\"build\"", Fault::Exit(70, ""));
        assert_eq!(
            execute(Task::App(vec![]), &mut host, root).map_err(|failure| failure.code()),
            Err(70)
        );
        let mut host = FakeHost::new();
        host.fail("\"test\"", Fault::Exit(65, ""));
        let tests = Task::UiTest {
            only: None,
            arguments: vec![],
        };
        assert_eq!(
            execute(tests, &mut host, root).map_err(|failure| failure.code()),
            Err(65)
        );
    }

    #[test]
    fn help_and_the_source_checks_start_no_program() -> io::Result<()> {
        let mut host = FakeHost::new();
        assert_eq!(execute(Task::Help, &mut host, Path::new("/repo")), Ok(()));
        assert_eq!(host.output, [USAGE]);
        let repository = Scratch::repository("execute-gates")?;
        assert_eq!(execute(Task::Gates, &mut host, repository.path()), Ok(()));
        repository.write("Sources/GymemoKit/Store.swift", "import Network\n")?;
        assert_eq!(
            execute(Task::Gates, &mut host, repository.path()),
            Err(Failure::new("These source checks failed: offline"))
        );
        assert!(host.transcript().is_empty());
        Ok(())
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
