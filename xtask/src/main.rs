//! Repository checks and simulator runs for gymemo.

mod app_version;
mod bounded;
mod cargo_mutants;
#[cfg(test)]
mod contrast;
mod delivery_setup;
mod failure;
mod host;
mod json;
mod kani;
mod lean;
mod literals;
mod logging;
mod native_candidate;
mod offline;
mod purity;
mod qualification;
mod required_reasons;
mod sbom;
#[cfg(test)]
mod scratch;
mod simulator;
mod store_metadata;
mod swift_mutation;
mod swift_source;
mod system_design;

use bounded::Toolset;
use failure::{Failure, Result, ensure};
use host::{Host, Local};
use simulator::Appearance;
use std::{env, path::Path, process::ExitCode};

const USAGE: &str = "Usage: xtask <COMMAND>

Commands:
  generate-version                  Generate the Xcode version setting from the canonical app version
  prepare-store-metadata            Prepare localized metadata for the canonical app version
  check-store                       Validate the generated store metadata with the provider CLI
  check-sbom native|website VERSION FILE
                                    Validate the preserved product and dependency inventory
  seal-native PLATFORM SHA RUN
                                    Inspect and preserve an unsigned archive, SBOM, and candidate manifest
  verify-native PLATFORM SHA RUN
                                    Admit preserved candidate bytes before protected signing
  gates                             Check the Swift sources for departures from the system design, text outside the catalog, effects in the core, console output, networking, and required reason APIs
  ui-test [--only light|dark|contrast|dark-contrast] [XCODEBUILD_ARGUMENT]...
                                    Run the UI tests on the dedicated simulator: light, dark, and both with Increase Contrast
  ui-test-on DEVICE [XCODEBUILD_ARGUMENT]...
                                    Run the same four appearance passes on a selected simulator
  screenshots                       Export the screenshots of the latest UI test run into a new directory
  app [LAUNCH_ARGUMENT]...          Build the app and open it on the dedicated simulator
  proofs                            Build the Lean proofs, hold their theorems to the standard axioms, replay each module, and verify the Kani harnesses, each tool in a bounded container
  mutate [SWIFT_MUTATION_TESTING_ARGUMENT]...
                                    Mutate the package sources and fail on each change that the package tests miss
  mutate-xtask [CARGO_MUTANTS_ARGUMENT]...
                                    Mutate xtask in bounded containers and fail on each mutant that its tests miss
  setup-delivery WORKPLACE [--apply] Preview or prepare the website's protected workload identity
  inspect-delivery WORKPLACE         Inspect delivery integration metadata without reading secret values
  setup-native-delivery WORKPLACE INTEGRATION signing|upload|version-preparation [--apply]
                                    Plan or configure the native environment's Doppler Secrets sync
  qualify SHA FLOOR IPAD DUO WATCH VISION [--run]
                                    Plan or run the local release checks for a clean main commit and five simulator identifiers
  require-qualification SHA         Require the owner's successful local checks for the exact main commit
  help                              Print this message";

#[derive(Debug, PartialEq, Eq)]
enum Task {
    GenerateVersion,
    PrepareStoreMetadata,
    CheckStore,
    CheckSbom(Vec<String>),
    SealNative(Vec<String>),
    VerifyNative(Vec<String>),
    Gates,
    UiTest {
        only: Option<Appearance>,
        arguments: Vec<String>,
    },
    UiTestOn {
        device: String,
        arguments: Vec<String>,
    },
    Screenshots,
    App(Vec<String>),
    Proofs,
    Mutate(Vec<String>),
    MutateXtask(Vec<String>),
    SetupDelivery {
        workplace: String,
        apply: bool,
    },
    Qualify(Vec<String>),
    InspectDelivery(String),
    SetupNativeDelivery(Vec<String>),
    RequireQualification(String),
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

/// The arguments that `command` passes on to its tool, unless one names an option among `owned`, which the command chooses itself.
fn passed_on(
    command: &str,
    owned: &str,
    refused: fn(&[String]) -> Option<&str>,
    arguments: impl Iterator<Item = String>,
) -> Result<Vec<String>> {
    let arguments = arguments.collect::<Vec<_>>();
    match refused(&arguments) {
        None => Ok(arguments),
        Some(argument) => Err(Failure::new(format!(
            "{command} chooses {owned} itself, and it received {argument}\n\n{USAGE}"
        ))),
    }
}

fn parse(mut arguments: impl Iterator<Item = String>) -> Result<Task> {
    let Some(command) = arguments.next() else {
        return Err(Failure::new(USAGE));
    };
    match command.as_str() {
        "generate-version" => alone("generate-version", Task::GenerateVersion, arguments),
        "prepare-store-metadata" => alone("prepare-store-metadata", Task::PrepareStoreMetadata, arguments),
        "check-store" => alone("check-store", Task::CheckStore, arguments),
        "check-sbom" => Ok(Task::CheckSbom(arguments.collect())),
        "seal-native" => Ok(Task::SealNative(arguments.collect())),
        "verify-native" => Ok(Task::VerifyNative(arguments.collect())),
        "gates" => alone("gates", Task::Gates, arguments),
        "screenshots" => alone("screenshots", Task::Screenshots, arguments),
        "ui-test" => ui_test(arguments),
        "ui-test-on" => {
            let device = arguments.next().ok_or_else(|| Failure::new(USAGE))?;
            Ok(Task::UiTestOn { device, arguments: arguments.collect() })
        }
        "app" => Ok(Task::App(arguments.collect())),
        "qualify" => Ok(Task::Qualify(arguments.collect())),
        "setup-native-delivery" => Ok(Task::SetupNativeDelivery(arguments.collect())),
        "inspect-delivery" => {
            let workplace = arguments.next().ok_or_else(|| Failure::new(USAGE))?;
            alone("inspect-delivery", Task::InspectDelivery(workplace), arguments)
        }
        "require-qualification" => {
            let source = arguments.next().ok_or_else(|| Failure::new(USAGE))?;
            alone("require-qualification", Task::RequireQualification(source), arguments)
        }
        "proofs" => alone("proofs", Task::Proofs, arguments),
        "mutate" => passed_on(
            "mutate",
            "--output, --max-integrity-warnings, --plan, --shard, --exclude, --operator, --operator-tier, and --disable-mutator",
            swift_mutation::refused,
            arguments,
        )
        .map(Task::Mutate),
        "mutate-xtask" => passed_on(
            "mutate-xtask",
            "--shard, --output, --list, --in-place, --package, --baseline, --jobs, --dir, --manifest-path, and --gitignore",
            cargo_mutants::refused,
            arguments,
        )
        .map(Task::MutateXtask),
        "help" | "--help" | "-h" => Ok(Task::Help),
        "setup-delivery" => {
            let workplace = arguments.next().ok_or_else(|| Failure::new(USAGE))?;
            let apply = match arguments.next().as_deref() {
                None => false,
                Some("--apply") => true,
                Some(_) => return Err(Failure::new(USAGE)),
            };
            alone("setup-delivery", Task::SetupDelivery { workplace, apply }, arguments)
        }
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

/// Checks the Lean proofs and the Kani harnesses, each tool in a bounded container, and stops at the first step that fails or stays inconclusive.
/// The checks of the sources run before any container starts.
fn proofs(host: &mut impl Host, root: &Path) -> Result<()> {
    lean::check_release(host, root)?;
    let modules = lean::modules(host, root)?;
    let declared = kani::declared(host, root)?;
    let image = bounded::build(host, root, Toolset::Lean)?;
    lean::build(host, root, &image)?;
    let theorems = lean::axioms(host, root, &image)?;
    lean::replay(host, root, &image, &modules)?;
    let harnesses = kani::verify(host, root, &declared)?;
    host.print(&format!(
        "PASS proofs: {} modules built, {theorems} theorems held to the standard axioms, {} modules replayed, {harnesses} harnesses verified",
        modules.len(),
        modules.len()
    ));
    Ok(())
}

/// Runs `task` on the repository at `root`, where the commands reach programs, directories, and output streams through `host`.
fn execute(task: Task, host: &mut impl Host, root: &Path) -> Result<()> {
    match task {
        Task::GenerateVersion => app_version::generate(host, root),
        Task::PrepareStoreMetadata => {
            let directory = store_metadata::prepare(host, root)?;
            host.print(&format!(
                "Prepared store metadata at {}",
                directory.display()
            ));
            Ok(())
        }
        Task::CheckStore => store_metadata::check(host, root),
        Task::CheckSbom(arguments) => sbom::check(host, root, &arguments),
        Task::SealNative(arguments) => native_candidate::run(host, root, &arguments, true),
        Task::VerifyNative(arguments) => native_candidate::run(host, root, &arguments, false),
        Task::Gates => gates(host, root),
        Task::UiTest { only, arguments } => simulator::ui_test(host, root, only, &arguments),
        Task::UiTestOn { device, arguments } => {
            simulator::ui_test_on(host, root, &device, &arguments)
        }
        Task::Screenshots => simulator::screenshots(host, root).map(|_| ()),
        Task::App(arguments) => simulator::app(host, root, &arguments),
        Task::Proofs => proofs(host, root),
        Task::SetupNativeDelivery(arguments) => delivery_setup::run_native(host, root, &arguments),
        Task::Mutate(arguments) => swift_mutation::mutate(host, root, &arguments),
        Task::MutateXtask(arguments) => cargo_mutants::mutate(host, root, &arguments),
        Task::SetupDelivery { workplace, apply } => {
            delivery_setup::run(host, root, &workplace, apply)
        }
        Task::Qualify(arguments) => qualification::run(host, root, &arguments),
        Task::InspectDelivery(workplace) => delivery_setup::inspect(host, root, &workplace),
        Task::RequireQualification(source) => qualification::require(host, root, &source),
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
        host::fake::{DEVICE, Ending, FakeHost, Fault},
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
    fn delivery_setup_requires_a_workplace_and_an_explicit_apply_flag() {
        for (arguments, apply) in [
            (vec!["setup-delivery", "selected"], false),
            (vec!["setup-delivery", "selected", "--apply"], true),
        ] {
            assert_eq!(
                task(&arguments),
                Ok(Task::SetupDelivery {
                    workplace: "selected".into(),
                    apply
                })
            );
        }
        for arguments in [
            vec!["setup-delivery"],
            vec!["setup-delivery", "selected", "unexpected"],
            vec!["setup-delivery", "selected", "--apply", "extra"],
        ] {
            assert!(task(&arguments).is_err());
        }
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
    fn the_verification_commands_parse_with_the_arguments_that_they_pass_on() {
        assert_eq!(task(&["proofs"]), Ok(Task::Proofs));
        assert_eq!(task(&["mutate"]), Ok(Task::Mutate(vec![])));
        let swift = [
            "--sources-path",
            "Sources/GymemoCopy",
            "--concurrency",
            "4",
            "--no-cache",
        ];
        assert_eq!(
            task(&[&["mutate"], &swift[..]].concat()),
            Ok(Task::Mutate(texts(&swift)))
        );
        assert_eq!(task(&["mutate-xtask"]), Ok(Task::MutateXtask(vec![])));
        let rust = ["--file", "xtask/src/failure.rs", "--", "--output", "-p"];
        assert_eq!(
            task(&[&["mutate-xtask"], &rust[..]].concat()),
            Ok(Task::MutateXtask(texts(&rust)))
        );
    }

    #[test]
    fn a_verification_command_refuses_the_options_that_it_chooses_itself() {
        assert_eq!(
            task(&["proofs", "--fast"]),
            refusal("proofs takes no argument, and it received --fast")
        );
        for owned in [
            "--output",
            "--output=report.json",
            "--max-integrity-warnings",
            "--max-integrity-warnings=3",
            "--plan",
            "--shard=0/2",
            "--exclude",
            "--operator",
            "--operator-tier=conservative",
            "--disable-mutator",
        ] {
            assert_eq!(
                task(&["mutate", "--concurrency", "4", owned]),
                refusal(&format!(
                    "mutate chooses --output, --max-integrity-warnings, --plan, --shard, --exclude, --operator, --operator-tier, and --disable-mutator itself, and it received {owned}"
                )),
                "{owned}"
            );
        }
        for owned in [
            "--shard",
            "--output=x",
            "-o",
            "--list",
            "--in-place",
            "--package",
            "-pxtask",
            "--baseline",
            "--baseline=skip",
            "--jobs",
            "-j4",
            "--dir",
            "-d",
            "--manifest-path",
            "--gitignore=false",
        ] {
            assert_eq!(
                task(&["mutate-xtask", "--file", "a.rs", owned, "skip"]),
                refusal(&format!(
                    "mutate-xtask chooses --shard, --output, --list, --in-place, --package, --baseline, --jobs, --dir, --manifest-path, and --gitignore itself, and it received {owned}"
                )),
                "{owned}"
            );
        }
    }

    #[test]
    fn the_proofs_hold_every_step_and_print_one_line_with_the_numbers() {
        let root = Path::new("/repo");
        let mut host = lean::tests::repository();
        kani::tests::with_harnesses(&mut host);
        assert_eq!(execute(Task::Proofs, &mut host, root), Ok(()));
        assert_eq!(
            host.output,
            [
                "PASS proofs: 3 modules built, 4 theorems held to the standard axioms, 3 modules replayed, 2 harnesses verified"
            ]
        );
        assert_eq!(host.errors, Vec::<String>::new());
        let commands = host
            .transcript()
            .iter()
            .filter_map(|line| line.split_once("\"900s\" "))
            .map(|(_, command)| command.replace('"', ""))
            .collect::<Vec<_>>();
        assert_eq!(
            commands,
            [
                "lake build --wfail",
                "lake env lean Axioms.lean",
                "lake env leanchecker --fresh Gymemo",
                "lake env leanchecker --fresh Gymemo.Log",
                "lake env leanchecker --fresh Gymemo.Strength",
                "cargo kani list --format json",
                "cargo kani --package xtask",
            ]
        );
        let volumes = host
            .transcript()
            .iter()
            .filter_map(|line| line.split_once("\"--volume\" "))
            .filter_map(|(_, rest)| rest.split_once(' '))
            .map(|(volume, _)| volume.replace('"', ""))
            .collect::<Vec<_>>();
        assert_eq!(
            volumes,
            [
                "/repo:/work",
                "/repo:/work:ro",
                "/repo:/work:ro",
                "/repo:/work:ro",
                "/repo:/work:ro",
                "/repo:/work",
                "/repo:/work",
            ]
        );
        assert_eq!(
            host.transcript()
                .iter()
                .filter(|line| line.starts_with("capture \"docker\" \"build\""))
                .collect::<Vec<_>>(),
            [
                "capture \"docker\" \"build\" \"--quiet\" \"--tag\" \"gymemo-lean:proofs\" \"/repo/xtask/proofs/lean\"",
                "capture \"docker\" \"build\" \"--quiet\" \"--tag\" \"gymemo-rust:proofs\" \"/repo/xtask/proofs/rust\""
            ]
        );
        assert_eq!(host.containers(), 0);
    }

    #[test]
    fn the_proofs_stop_at_the_first_step_that_fails_or_stays_inconclusive() {
        let root = Path::new("/repo");
        let mut host = lean::tests::repository();
        host.file("/repo/xtask/src/main.rs", "fn main() {}\n");
        assert_eq!(run(texts(&["proofs"]).into_iter(), &mut host, root), 1);
        assert_eq!(
            host.errors,
            ["xtask/src declares no Kani harness (#[kani::proof]), so Kani has nothing to verify"]
        );
        assert_eq!(host.output, Vec::<String>::new());
        assert!(!host.transcript().iter().any(|line| line.contains("docker")));

        let mut host = lean::tests::repository();
        kani::tests::with_harnesses(&mut host);
        host.file(
            "/repo/xtask/src/json.rs",
            "#[cfg_attr(kani, kani::proof)]\nfn hidden() {}\n",
        );
        assert_eq!(run(texts(&["proofs"]).into_iter(), &mut host, root), 1);
        assert_eq!(
            host.errors,
            [
                "xtask/src/json.rs:1: names proof outside an attribute #[kani::proof] alone at the start of its line, so Kani may verify a harness that the check can't match"
            ]
        );
        assert!(!host.transcript().iter().any(|line| line.contains("docker")));

        let mut host = lean::tests::repository();
        host.file(
            "/repo/specs/lean/lean-toolchain",
            "leanprover/lean4:v4.35.0\n",
        );
        assert_eq!(run(texts(&["proofs"]).into_iter(), &mut host, root), 1);
        assert!(!host.transcript().iter().any(|line| line.contains("docker")));

        let mut host = lean::tests::repository();
        host.file("/repo/specs/lean/Gymemo/Extra.lean", "");
        assert_eq!(run(texts(&["proofs"]).into_iter(), &mut host, root), 1);
        assert!(!host.transcript().iter().any(|line| line.contains("docker")));

        let mut host = lean::tests::repository();
        kani::tests::with_harnesses(&mut host);
        host.file("/repo/specs/lean/Gymemo/Strength.lean", lean::tests::FORGED);
        assert_eq!(run(texts(&["proofs"]).into_iter(), &mut host, root), 1);
        assert_eq!(
            host.errors,
            [
                "These lines declare code that runs whenever Lean imports the library, and such code runs inside the process that prints the axiom listing:\nspecs/lean/Gymemo/Strength.lean:7: initialize"
            ]
        );
        assert!(!host.transcript().iter().any(|line| line.contains("docker")));

        let mut host = lean::tests::repository();
        host.file(
            "/repo/specs/lean/Gymemo.lean",
            "import Gymemo.Log\nimport Gymemo.Strength\ntheorem bogus : 1 = 2 := sorry\n",
        );
        assert_eq!(run(texts(&["proofs"]).into_iter(), &mut host, root), 1);
        assert!(!host.transcript().iter().any(|line| line.contains("docker")));

        let mut host = lean::tests::repository();
        kani::tests::with_harnesses(&mut host);
        host.ends("\"lake\" \"build\"", Ending::Exit(124));
        assert_eq!(run(texts(&["proofs"]).into_iter(), &mut host, root), 75);
        assert_eq!(
            host.errors,
            [
                "INCONCLUSIVE: `lake build --wfail` stopped at the time limit of 900 seconds with exit code 124"
            ]
        );
        assert_eq!(host.output, Vec::<String>::new());
        assert!(
            !host
                .transcript()
                .iter()
                .any(|line| line.contains("Axioms.lean"))
        );
        assert_eq!(host.containers(), 0);

        let mut host = lean::tests::repository();
        kani::tests::with_harnesses(&mut host);
        host.prints(
            "\"Axioms.lean\"",
            "theorems 1\ntheorem Gymemo.stored axioms sorryAx\n",
        );
        assert_eq!(run(texts(&["proofs"]).into_iter(), &mut host, root), 1);
        assert!(
            !host
                .transcript()
                .iter()
                .any(|line| line.contains("leanchecker"))
        );

        let mut host = lean::tests::repository();
        kani::tests::with_harnesses(&mut host);
        host.ends("\"Gymemo.Strength\"", Ending::Exit(1));
        assert_eq!(run(texts(&["proofs"]).into_iter(), &mut host, root), 1);
        assert!(!host.transcript().iter().any(|line| line.contains("kani")));
    }

    #[test]
    fn the_proofs_replay_the_theorems_of_the_root_module_too() {
        let root = Path::new("/repo");
        let mut host = lean::tests::repository();
        kani::tests::with_harnesses(&mut host);
        host.prints(
            "\"Axioms.lean\"",
            &format!(
                "theorems 5\ntheorem Gymemo.bogus axioms \n{}",
                lean::tests::LISTING
                    .split_once('\n')
                    .map_or("", |(_, theorems)| theorems)
            ),
        );
        host.ends("\"--fresh\" \"Gymemo\"", Ending::Exit(1));
        assert_eq!(run(texts(&["proofs"]).into_iter(), &mut host, root), 1);
        assert_eq!(
            host.errors,
            ["`lake env leanchecker --fresh Gymemo` failed with exit code 1 in its container"]
        );
        assert_eq!(host.output, Vec::<String>::new());
        assert!(!host.transcript().iter().any(|line| line.contains("kani")));
        assert_eq!(host.containers(), 0);
    }

    #[test]
    fn each_mutation_command_reaches_its_run_with_its_arguments() {
        let root = Path::new("/repo");
        let mut host = FakeHost::new();
        host.file(
            "/repo/mise.toml",
            "[tools]\n\"github:ericodx/swift-mutation-testing\" = \"1.6.4\"\n",
        );
        assert!(
            execute(
                Task::Mutate(texts(&["--sources-path", "Sources/GymemoCopy"])),
                &mut host,
                root
            )
            .is_err()
        );
        assert!(host.transcript().contains(
            &"show cd \"/repo\" && \"swift-mutation-testing\" \"run\" \".\" \"--no-cache\" \"--max-integrity-warnings\" \"0\" \"--output\" \"/repo/target/mutation/report.json\" \"--sources-path\" \"Sources/GymemoCopy\"".to_owned()
        ));
        let mut host = FakeHost::new();
        host.prints("\"--list\"", "xtask/src/failure.rs:1:1: replace\n");
        assert!(
            execute(
                Task::MutateXtask(texts(&["--file", "xtask/src/failure.rs"])),
                &mut host,
                root
            )
            .is_err()
        );
        assert!(host.transcript().iter().any(|line| line.ends_with(
            "\"cargo\" \"mutants\" \"--gitignore=true\" \"--package\" \"xtask\" \"--shard\" \"0/1\" \"--output\" \"/work/target/mutants/run-1/shard-0\" \"--file\" \"xtask/src/failure.rs\""
        )));
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
