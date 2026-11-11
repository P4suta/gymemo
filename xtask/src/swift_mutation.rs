//! Runs swift-mutation-testing over the package sources and reads its report, so each change that the package tests miss fails the run.
//!
//! The tool counts a timeout as detected and exits with 0 while changes survive, so the report decides and the exit code of the tool only adds a failure.
//! The tool also reports a change as `Killed` when the tests failed before the changed code ran, so such a change detects nothing here.

use crate::{
    failure::{Context, Failure, Result, ensure},
    host::{Host, Invocation, Streams},
    json::{self, Value},
};
use std::{path::Path, process::ExitStatus};

const TOOL: &str = "swift-mutation-testing";
const MISE: &str = "mise.toml";
/// The directory of the report.
const REPORTS: &str = "target/mutation";
/// The report that each run writes after the command removed the report of the run before.
const REPORT: &str = "report.json";
/// The options that the command chooses itself.
/// The integrity gate makes the tool exit with 2 when the tests failed or ran out of time before the changed code ran.
/// The run tests every change that the configuration plans.
/// A caller may not narrow the plan of release 1.6.4 to a shard, a stored plan, fewer files, or fewer operators.
/// A caller may still name the sources with `--sources-path`.
const OWNED: [&str; 8] = [
    "--output",
    "--max-integrity-warnings",
    "--plan",
    "--shard",
    "--exclude",
    "--operator",
    "--operator-tier",
    "--disable-mutator",
];

/// What the tool reports of one change.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Status {
    /// The tests failed with the change in place.
    Killed,
    /// The change didn't compile, so it changes no behavior.
    CompileError,
    /// The tests passed with the change in place.
    Survived,
    /// No test ran the changed code.
    NoCoverage,
    /// The tests ran past the time limit of the tool.
    Timeout,
}

/// One change of the report.
#[derive(Debug, PartialEq, Eq)]
struct Mutant {
    file: String,
    line: u64,
    mutator: String,
    description: String,
    status: Status,
    /// Whether the changed code ran in the tests, which a change that didn't compile never does.
    activated: bool,
}

#[derive(Debug, PartialEq, Eq)]
struct Report {
    version: String,
    mutants: Vec<Mutant>,
}

impl Status {
    /// The status as the report writes it.
    fn name(self) -> &'static str {
        match self {
            Status::Killed => "Killed",
            Status::CompileError => "CompileError",
            Status::Survived => "Survived",
            Status::NoCoverage => "NoCoverage",
            Status::Timeout => "Timeout",
        }
    }

    fn parse(text: &str) -> Option<Self> {
        [
            Status::Killed,
            Status::CompileError,
            Status::Survived,
            Status::NoCoverage,
            Status::Timeout,
        ]
        .into_iter()
        .find(|status| status.name() == text)
    }
}

/// The first argument that names an option that the command chooses itself, which a caller may not pass on.
pub fn refused(arguments: &[String]) -> Option<&str> {
    arguments.iter().map(String::as_str).find(|argument| {
        OWNED.iter().any(|owned| {
            argument
                .strip_prefix(owned)
                .is_some_and(|rest| rest.is_empty() || rest.starts_with('='))
        })
    })
}

/// The release of swift-mutation-testing that `mise.toml` pins.
fn pinned(mise: &str) -> Option<String> {
    let document = mise.parse::<toml::Table>().ok()?;
    let tools = document.get("tools")?.as_table()?;
    let mut matches = tools
        .iter()
        .filter(|(key, _)| key.rsplit(['/', ':']).next() == Some(TOOL));
    let (_, value) = matches.next()?;
    if matches.next().is_some() {
        return None;
    }
    let release = value
        .as_str()
        .or_else(|| value.as_table()?.get("version")?.as_str())?;
    (!release.is_empty()).then(|| release.to_owned())
}

/// The changes of the report with the release of the tool that wrote it.
fn report(text: &str) -> Result<Report> {
    let root = json::parse(text)
        .map_err(|error| Failure::new(format!("The mutation report isn't JSON: {error}")))?;
    let lacks = |field: String| Failure::new(format!("The mutation report lacks {field}"));
    let version = root
        .get("config")
        .and_then(|config| config.get("toolVersion"))
        .and_then(Value::as_str)
        .ok_or_else(|| lacks("config.toolVersion".to_owned()))?;
    let files = root
        .get("files")
        .and_then(Value::as_object)
        .ok_or_else(|| lacks("files".to_owned()))?;
    let mut mutants = Vec::new();
    for (file, entry) in files {
        let listed = entry
            .get("mutants")
            .and_then(Value::as_array)
            .ok_or_else(|| lacks(format!("mutants of {file}")))?;
        for (index, mutant) in listed.iter().enumerate() {
            let place = format!("of the change at index {index} of {file}");
            let text = |field: &str| {
                mutant
                    .get(field)
                    .and_then(Value::as_str)
                    .ok_or_else(|| lacks(format!("{field} {place}")))
            };
            let status = text("status")?;
            let status = Status::parse(status).ok_or_else(|| {
                Failure::new(format!(
                    "The mutation report gives the change at index {index} of {file} the unknown status `{status}`"
                ))
            })?;
            let line = mutant
                .get("location")
                .and_then(|location| location.get("start"))
                .and_then(|start| start.get("line"))
                .and_then(Value::as_u64)
                .ok_or_else(|| lacks(format!("location.start.line {place}")))?;
            // The pinned release writes `activated` on every change that it tested, and leaves it out of a change that didn't compile.
            let activated = match (mutant.get("activated"), status) {
                (Some(Value::Bool(activated)), _) => *activated,
                (None, Status::CompileError) => false,
                _ => return Err(lacks(format!("activated {place}"))),
            };
            mutants.push(Mutant {
                file: file.strip_prefix('/').unwrap_or(file).to_owned(),
                line,
                mutator: text("mutatorName")?.to_owned(),
                description: text("description")?.to_owned(),
                status,
                activated,
            });
        }
    }
    Ok(Report {
        version: version.to_owned(),
        mutants,
    })
}

/// Whether the tests failed or ran out of time before the changed code ran, which the integrity gate of the tool counts.
fn unactivated(mutant: &Mutant) -> bool {
    matches!(mutant.status, Status::Killed | Status::Timeout) && !mutant.activated
}

/// A line for each change that the tests missed, that reached the time limit, or that the tests killed before the changed code ran.
fn findings(report: &Report) -> Vec<String> {
    report
        .mutants
        .iter()
        .filter(|mutant| {
            matches!(
                mutant.status,
                Status::Survived | Status::NoCoverage | Status::Timeout
            ) || unactivated(mutant)
        })
        .map(|mutant| {
            format!(
                "{} {}:{} {}: {}{}",
                mutant.status.name(),
                mutant.file,
                mutant.line,
                mutant.mutator,
                mutant.description,
                if unactivated(mutant) {
                    ", before the changed code ran"
                } else {
                    ""
                }
            )
        })
        .collect()
}

/// The `PASS` line of a report whose changes the tests all detected, or the failure of the run.
/// A missed change fails the run, and a failed tool adds its own failure.
/// A timeout leaves the run inconclusive, and so does a `Killed` change whose changed code never ran.
/// The exit code 2 of the integrity gate adds no failure when such a change explains it.
fn verdict(pin: &str, report: &Report, exit: ExitStatus) -> Result<String> {
    ensure(report.version == pin, || {
        format!(
            "{TOOL} {} wrote the report, and {MISE} pins {pin}",
            report.version
        )
    })?;
    let count = |wanted: fn(&Mutant) -> bool| {
        report
            .mutants
            .iter()
            .filter(|mutant| wanted(mutant))
            .count()
    };
    let ended = (!exit.success()).then(|| Failure::new(format!("{TOOL} ended with {exit}")));
    let missed = count(|mutant| matches!(mutant.status, Status::Survived | Status::NoCoverage));
    if missed > 0 {
        let failure = Failure::new(format!("Changes that the package tests missed: {missed}"));
        return Err(match ended {
            Some(ended) => failure.followed_by(&ended),
            None => failure,
        });
    }
    let gated = count(unactivated) > 0 && exit.code() == Some(2);
    if let Some(ended) = ended
        && !gated
    {
        return Err(ended);
    }
    let timeouts = count(|mutant| mutant.status == Status::Timeout);
    let killed_early = count(|mutant| mutant.status == Status::Killed && !mutant.activated);
    let undecided = [
        (
            timeouts,
            "Changes that reached the time limit of the tool, so the package tests",
        ),
        (
            killed_early,
            "Changes that the package tests killed before the changed code ran, so the tests",
        ),
    ]
    .into_iter()
    .filter(|(changes, _)| *changes > 0)
    .map(|(changes, reason)| format!("{reason} neither detected nor missed them: {changes}"))
    .collect::<Vec<_>>();
    if !undecided.is_empty() {
        return Err(Failure::inconclusive(undecided.join("\n")));
    }
    let detected = count(|mutant| mutant.status == Status::Killed);
    ensure(detected > 0, || {
        "The package tests detected no change".to_owned()
    })?;
    Ok(format!(
        "PASS mutate: {detected} detected and {} unviable changes",
        count(|mutant| mutant.status == Status::CompileError)
    ))
}

/// Runs the tool over the package with `arguments`, prints each change that the tests miss, and fails on any.
/// The run removes the report of an earlier run first, so only a report that this run wrote counts.
pub fn mutate(host: &mut impl Host, root: &Path, arguments: &[String]) -> Result<()> {
    let mise = host
        .read(&root.join(MISE))
        .context(|| format!("Read {MISE}"))?;
    let pin =
        pinned(&mise).ok_or_else(|| Failure::new(format!("{MISE} pins no release of {TOOL}")))?;
    let directory = root.join(REPORTS);
    host.create_directories(&directory)
        .context(|| format!("Create {}", directory.display()))?;
    let written = directory.join(REPORT);
    if host.exists(&written) {
        host.remove_file(&written)
            .context(|| format!("Remove the report of an earlier run, {}", written.display()))?;
    }
    let invocation = Invocation::new(TOOL)
        .current_dir(root)
        .args([
            "run",
            ".",
            "--no-cache",
            "--max-integrity-warnings",
            "0",
            "--output",
        ])
        .arg(&written)
        .args(
            arguments
                .iter()
                .filter(|argument| *argument != "--no-cache"),
        );
    let exit = host
        .run(&invocation, Streams::Shown)
        .context(|| format!("Start {invocation}"))?
        .status;
    ensure(host.exists(&written), || {
        format!("{invocation} wrote no report and ended with {exit}")
    })?;
    let text = host
        .read(&written)
        .context(|| format!("Read {}", written.display()))?;
    let report = report(&text)?;
    for finding in findings(&report) {
        host.print_error(&finding);
    }
    let summary = verdict(&pin, &report, exit)?;
    host.print(&summary);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::host::fake::{FakeHost, Fault};
    use std::os::unix::process::ExitStatusExt;

    const MISE_TOML: &str = "[tools]\nrust = { version = \"1.99.1\" }\n\"github:ericodx/swift-mutation-testing\" = \"1.6.4\"\n";
    const RUN: &str = "show cd \"/repo\" && \"swift-mutation-testing\" \"run\" \".\" \"--no-cache\" \"--max-integrity-warnings\" \"0\" \"--output\" \"/repo/target/mutation/report.json\"";

    /// A report of `version` whose changes each lie in their file at their line with their status.
    /// Like the reports of the pinned release, a change carries `activated`, false without coverage and true otherwise, except a change that didn't compile, which carries none.
    /// A status that ends in ` unactivated` carries `activated` false.
    fn written(version: &str, mutants: &[(&str, u64, &str)]) -> String {
        let mut files: Vec<(&str, Vec<String>)> = Vec::new();
        for (index, (file, line, status)) in mutants.iter().enumerate() {
            let (status, activated) = match status.strip_suffix(" unactivated") {
                Some(status) => (status, ",\"activated\":false"),
                None => match *status {
                    "CompileError" => (*status, ""),
                    "NoCoverage" => (*status, ",\"activated\":false"),
                    _ => (*status, ",\"activated\":true"),
                },
            };
            let mutant = format!(
                "{{\"id\":\"swift-mutation-testing_{index}\",\"status\":\"{status}\"{activated},\"mutatorName\":\"Swap{index}\",\"description\":\"a \\u2192 b{index}\",\"location\":{{\"start\":{{\"line\":{line},\"column\":3}},\"end\":{{\"line\":{line},\"column\":9}}}}}}"
            );
            match files.iter_mut().find(|(known, _)| known == file) {
                Some((_, list)) => list.push(mutant),
                None => files.push((file, vec![mutant])),
            }
        }
        let files = files
            .iter()
            .map(|(file, list)| {
                format!(
                    "\"{file}\":{{\"language\":\"swift\",\"mutants\":[{}]}}",
                    list.join(",")
                )
            })
            .collect::<Vec<_>>()
            .join(",");
        format!(
            "{{\"schemaVersion\":\"1\",\"config\":{{\"toolVersion\":\"{version}\",\"planSha256\":\"00\"}},\"thresholds\":{{\"high\":80,\"low\":60}},\"projectRoot\":\"/repo\",\"files\":{{{files}}}}}"
        )
    }

    const DETECTED: [(&str, u64, &str); 3] = [
        ("/Sources/GymemoCopy/Copy.swift", 25, "Killed"),
        ("/Sources/GymemoCopy/Copy.swift", 46, "CompileError"),
        ("/Sources/GymemoCopy/CopyText.swift", 117, "Killed"),
    ];

    fn repository(report: &str) -> FakeHost {
        let mut host = FakeHost::new();
        host.file("/repo/mise.toml", MISE_TOML);
        host.writes(
            "\"swift-mutation-testing\"",
            "/repo/target/mutation/report.json",
            report,
        );
        host
    }

    fn texts(arguments: &[&str]) -> Vec<String> {
        arguments
            .iter()
            .map(|argument| (*argument).to_owned())
            .collect()
    }

    fn exited(code: i32) -> ExitStatus {
        ExitStatus::from_raw(code << 8)
    }

    #[test]
    fn the_command_owns_every_option_that_selects_part_of_the_plan() {
        for owned in [
            "--plan",
            "--plan=plan.json",
            "--shard",
            "--shard=0/2",
            "--exclude",
            "--exclude=**/Generated/**",
            "--operator",
            "--operator=RemoveSideEffects",
            "--operator-tier",
            "--operator-tier=conservative",
            "--disable-mutator",
            "--disable-mutator=SwapTernary",
        ] {
            assert_eq!(
                refused(&texts(&[
                    "--sources-path",
                    "Sources/GymemoCopy",
                    owned,
                    "x"
                ])),
                Some(owned),
                "{owned}"
            );
        }
        for allowed in [
            "--sources-path",
            "--plans",
            "--shards",
            "--excludes",
            "--operators",
            "--operator-tiers",
            "--disable-mutators",
            "--timeout",
            "--concurrency",
            "--quiet",
            "--target",
            "--keep-logs",
        ] {
            assert_eq!(refused(&texts(&[allowed, "1"])), None, "{allowed}");
        }
    }

    #[test]
    fn the_command_owns_its_output_and_its_integrity_gate() {
        assert_eq!(
            refused(&texts(&["--sources-path", "Sources/GymemoCopy"])),
            None
        );
        assert_eq!(
            refused(&texts(&["--max-integrity-warnings", "3"])),
            Some("--max-integrity-warnings")
        );
        assert_eq!(
            refused(&texts(&["--quiet", "--max-integrity-warnings=3"])),
            Some("--max-integrity-warnings=3")
        );
        assert_eq!(refused(&texts(&["--max-integrity-warning", "3"])), None);
        assert_eq!(refused(&texts(&["--max-new-survivors", "0"])), None);
        assert_eq!(
            refused(&texts(&["--html-output", "a.html", "--no-cache"])),
            None
        );
        assert_eq!(
            refused(&texts(&["--concurrency", "4", "--output", "a.json"])),
            Some("--output")
        );
        assert_eq!(
            refused(&texts(&["--output=a.json"])),
            Some("--output=a.json")
        );
        assert_eq!(refused(&texts(&["--outputs"])), None);
        assert_eq!(refused(&[]), None);
    }

    #[test]
    fn the_pin_reads_from_the_tools_of_mise() {
        assert_eq!(pinned(MISE_TOML).as_deref(), Some("1.6.4"));
        assert_eq!(
            pinned("[tools]\nswift-mutation-testing = \"2.0.0\"\n").as_deref(),
            Some("2.0.0")
        );
        assert_eq!(
            pinned("[tools]\n\"aqua:a/swift-mutation-testing\"=\"3.1\"").as_deref(),
            Some("3.1")
        );
        for refused in [
            "",
            "\"github:ericodx/swift-mutation-testing-extra\" = \"1.6.4\"",
            "\"github:ericodx/swift-mutation-testing\" = 1.6.4",
            "\"github:ericodx/swift-mutation-testing\" = \"\"",
            "# \"github:ericodx/swift-mutation-testing\"",
        ] {
            assert_eq!(pinned(refused), None, "{refused:?}");
        }
        for value in [
            "{ version = '1.6.4', os = ['macos'] }",
            "{ os = ['macos'], version = '1.6.4' }",
            "'1.6.4' # exact pin",
        ] {
            assert_eq!(
                pinned(&format!(
                    "[tools]\n'github:ericodx/swift-mutation-testing' = {value}\n"
                ))
                .as_deref(),
                Some("1.6.4")
            );
        }
        for value in [
            "true",
            "{}",
            "{ version = 1 }",
            "['1.6.4']",
            "{ version = '' }",
        ] {
            assert_eq!(
                pinned(&format!("[tools]\nswift-mutation-testing = {value}")),
                None
            );
        }
        assert_eq!(
            pinned(
                "[tools]\nswift-mutation-testing = '1.6.4'\n'github:ericodx/swift-mutation-testing' = '1.6.4'"
            ),
            None
        );
        assert_eq!(pinned("[tasks]\nswift-mutation-testing = '1.6.4'"), None);
    }

    #[test]
    fn the_repository_pins_the_mutation_tool_in_its_actual_mise_format() {
        assert!(pinned(include_str!("../../mise.toml")).is_some());
    }

    #[test]
    fn a_report_reads_as_its_changes() {
        assert_eq!(
            report(&written("1.6.4", &DETECTED[..2])),
            Ok(Report {
                version: "1.6.4".to_owned(),
                mutants: vec![
                    Mutant {
                        file: "Sources/GymemoCopy/Copy.swift".to_owned(),
                        line: 25,
                        mutator: "Swap0".to_owned(),
                        description: "a → b0".to_owned(),
                        status: Status::Killed,
                        activated: true,
                    },
                    Mutant {
                        file: "Sources/GymemoCopy/Copy.swift".to_owned(),
                        line: 46,
                        mutator: "Swap1".to_owned(),
                        description: "a → b1".to_owned(),
                        status: Status::CompileError,
                        activated: false,
                    },
                ],
            })
        );
        let activation = |mutants: &[(&str, u64, &str)]| {
            report(&written("1.6.4", mutants)).map(|report| {
                report
                    .mutants
                    .iter()
                    .map(|mutant| mutant.activated)
                    .collect::<Vec<_>>()
            })
        };
        assert_eq!(
            activation(&[
                ("/a.swift", 1, "Killed"),
                ("/a.swift", 2, "Killed unactivated"),
                ("/a.swift", 3, "Timeout unactivated"),
                ("/a.swift", 4, "NoCoverage"),
                ("/a.swift", 5, "CompileError unactivated"),
            ]),
            Ok(vec![true, false, false, false, false])
        );
        let statuses = [
            "Killed",
            "CompileError",
            "Survived",
            "NoCoverage",
            "Timeout",
        ]
        .map(|status| ("/a.swift", 1, status));
        assert_eq!(
            report(&written("1.6.4", &statuses)).map(|report| report
                .mutants
                .iter()
                .map(|mutant| mutant.status)
                .collect::<Vec<_>>()),
            Ok(vec![
                Status::Killed,
                Status::CompileError,
                Status::Survived,
                Status::NoCoverage,
                Status::Timeout
            ])
        );
        assert_eq!(
            report(&written("1.6.4", &[("/a.swift", 1, "Errored")])),
            Err(Failure::new(
                "The mutation report gives the change at index 0 of /a.swift the unknown status `Errored`"
            ))
        );
        assert_eq!(
            report("{\"files\":"),
            Err(Failure::new(
                "The mutation report isn't JSON: expected a value at byte 9"
            ))
        );
    }

    #[test]
    fn a_missing_field_of_the_report_fails_the_run() {
        let complete = written("1.6.4", &[("/a.swift", 7, "Killed")]);
        for (removed, replacement, field) in [
            (
                "\"toolVersion\":\"1.6.4\"",
                "\"tool\":\"1.6.4\"",
                "config.toolVersion",
            ),
            ("\"files\":{", "\"file\":{", "files"),
            ("\"mutants\":[", "\"mutant\":[", "mutants of /a.swift"),
            (
                "\"status\":\"Killed\"",
                "\"state\":\"Killed\"",
                "status of the change at index 0 of /a.swift",
            ),
            (
                "\"mutatorName\"",
                "\"mutator\"",
                "mutatorName of the change at index 0 of /a.swift",
            ),
            (
                "\"description\"",
                "\"text\"",
                "description of the change at index 0 of /a.swift",
            ),
            (
                "\"start\"",
                "\"begin\"",
                "location.start.line of the change at index 0 of /a.swift",
            ),
            (
                "\"line\":7,",
                "\"line\":-7,",
                "location.start.line of the change at index 0 of /a.swift",
            ),
            (
                "\"line\":7,",
                "\"line\":\"7\",",
                "location.start.line of the change at index 0 of /a.swift",
            ),
            (
                "\"location\"",
                "\"place\"",
                "location.start.line of the change at index 0 of /a.swift",
            ),
            (
                "\"status\":\"Killed\"",
                "\"status\":1",
                "status of the change at index 0 of /a.swift",
            ),
            ("\"files\":{", "\"files\":[{", "files"),
            (
                ",\"activated\":true",
                "",
                "activated of the change at index 0 of /a.swift",
            ),
            (
                "\"activated\":true",
                "\"activated\":\"true\"",
                "activated of the change at index 0 of /a.swift",
            ),
            (
                "\"activated\":true",
                "\"activated\":1",
                "activated of the change at index 0 of /a.swift",
            ),
        ] {
            let broken = complete.replacen(removed, replacement, 1);
            let broken = if replacement == "\"files\":[{" {
                format!("{}]}}", &broken[..broken.len() - 1])
            } else {
                broken
            };
            assert_ne!(broken, complete, "{removed}");
            assert_eq!(
                report(&broken),
                Err(Failure::new(format!("The mutation report lacks {field}"))),
                "{removed}"
            );
        }
        assert_eq!(
            report("{\"config\":{\"toolVersion\":\"1.6.4\"},\"files\":{\"/a.swift\":[]}}"),
            Err(Failure::new(
                "The mutation report lacks mutants of /a.swift"
            ))
        );
        assert_eq!(
            report(
                "{\"config\":{\"toolVersion\":\"1.6.4\"},\"files\":{\"/a.swift\":{\"mutants\":[[]]}}}"
            ),
            Err(Failure::new(
                "The mutation report lacks status of the change at index 0 of /a.swift"
            ))
        );
        assert_eq!(
            report("{\"config\":{\"toolVersion\":1},\"files\":{}}"),
            Err(Failure::new("The mutation report lacks config.toolVersion"))
        );
        for status in ["Killed", "Survived", "NoCoverage", "Timeout"] {
            let ran = written(
                "1.6.4",
                &[("/a.swift", 7, "CompileError"), ("/a.swift", 8, status)],
            );
            let without = ran
                .replace(",\"activated\":true", "")
                .replace(",\"activated\":false", "");
            assert_ne!(without, ran, "{status}");
            assert_eq!(
                report(&without),
                Err(Failure::new(
                    "The mutation report lacks activated of the change at index 1 of /a.swift"
                )),
                "{status}"
            );
        }
    }

    #[test]
    fn each_missed_change_each_timeout_and_each_kill_before_the_change_ran_is_printed_with_its_place()
     {
        let report = report(&written(
            "1.6.4",
            &[
                ("/Sources/A.swift", 3, "Killed"),
                ("/Sources/A.swift", 9, "Survived"),
                ("/Sources/B.swift", 12, "NoCoverage"),
                ("/Sources/B.swift", 14, "Timeout"),
                ("/Sources/B.swift", 15, "CompileError"),
                ("/Sources/B.swift", 16, "Killed unactivated"),
                ("/Sources/B.swift", 17, "Timeout unactivated"),
            ],
        ));
        assert_eq!(
            report.map(|report| findings(&report)),
            Ok(vec![
                "Survived Sources/A.swift:9 Swap1: a → b1".to_owned(),
                "NoCoverage Sources/B.swift:12 Swap2: a → b2".to_owned(),
                "Timeout Sources/B.swift:14 Swap3: a → b3".to_owned(),
                "Killed Sources/B.swift:16 Swap5: a → b5, before the changed code ran".to_owned(),
                "Timeout Sources/B.swift:17 Swap6: a → b6, before the changed code ran".to_owned(),
            ])
        );
    }

    #[test]
    fn the_verdict_needs_the_pinned_tool_every_change_detected_and_one_killed() {
        let verdict_of = |version: &str, mutants: &[(&str, u64, &str)], exit: ExitStatus| {
            report(&written(version, mutants)).and_then(|report| verdict("1.6.4", &report, exit))
        };
        assert_eq!(
            verdict_of("1.6.4", &DETECTED, exited(0)),
            Ok("PASS mutate: 2 detected and 1 unviable changes".to_owned())
        );
        assert_eq!(
            verdict_of("1.6.5", &DETECTED, exited(0)),
            Err(Failure::new(
                "swift-mutation-testing 1.6.5 wrote the report, and mise.toml pins 1.6.4"
            ))
        );
        assert_eq!(
            verdict_of(
                "1.6.4",
                &[
                    ("/a.swift", 1, "Survived"),
                    ("/a.swift", 2, "NoCoverage"),
                    ("/a.swift", 3, "Timeout"),
                    ("/a.swift", 4, "Killed")
                ],
                exited(0)
            ),
            Err(Failure::new("Changes that the package tests missed: 2"))
        );
        assert_eq!(
            verdict_of(
                "1.6.4",
                &[("/a.swift", 2, "NoCoverage"), ("/a.swift", 4, "Killed")],
                exited(2)
            ),
            Err(Failure::new(
                "Changes that the package tests missed: 1\nswift-mutation-testing ended with exit status: 2"
            ))
        );
        assert_eq!(
            verdict_of("1.6.4", &DETECTED, exited(2)),
            Err(Failure::new(
                "swift-mutation-testing ended with exit status: 2"
            ))
        );
        let timed_out = verdict_of(
            "1.6.4",
            &[
                ("/a.swift", 3, "Timeout"),
                ("/a.swift", 4, "Killed"),
                ("/a.swift", 5, "Timeout"),
            ],
            exited(0),
        );
        assert_eq!(
            timed_out,
            Err(Failure::inconclusive(
                "Changes that reached the time limit of the tool, so the package tests neither detected nor missed them: 2"
            ))
        );
        assert_eq!(
            verdict_of("1.6.4", &[("/a.swift", 3, "Timeout")], exited(0))
                .map_err(|failure| failure.code()),
            Err(75)
        );
        assert_eq!(
            verdict_of("1.6.4", &[("/a.swift", 3, "CompileError")], exited(0)),
            Err(Failure::new("The package tests detected no change"))
        );
        assert_eq!(
            verdict_of("1.6.4", &[], exited(0)),
            Err(Failure::new("The package tests detected no change"))
        );
    }

    #[test]
    fn a_kill_before_the_changed_code_ran_detects_nothing_and_leaves_the_run_inconclusive() {
        let verdict_of = |mutants: &[(&str, u64, &str)], exit: ExitStatus| {
            report(&written("1.6.4", mutants)).and_then(|report| verdict("1.6.4", &report, exit))
        };
        let unactivated = "Changes that the package tests killed before the changed code ran, so the tests neither detected nor missed them: 1";
        let timeouts = "Changes that reached the time limit of the tool, so the package tests neither detected nor missed them: 1";
        for exit in [0, 2] {
            assert_eq!(
                verdict_of(
                    &[
                        ("/a.swift", 1, "Killed"),
                        ("/a.swift", 2, "Killed unactivated")
                    ],
                    exited(exit)
                ),
                Err(Failure::inconclusive(unactivated)),
                "{exit}"
            );
            assert_eq!(
                verdict_of(&[("/a.swift", 2, "Killed unactivated")], exited(exit))
                    .map_err(|failure| failure.code()),
                Err(75),
                "{exit}"
            );
        }
        assert_eq!(
            verdict_of(
                &[
                    ("/a.swift", 1, "Killed"),
                    ("/a.swift", 2, "Timeout unactivated"),
                    ("/a.swift", 3, "Killed unactivated"),
                ],
                exited(2)
            ),
            Err(Failure::inconclusive(format!("{timeouts}\n{unactivated}")))
        );
        assert_eq!(
            verdict_of(
                &[
                    ("/a.swift", 1, "Survived"),
                    ("/a.swift", 2, "Killed unactivated")
                ],
                exited(2)
            ),
            Err(Failure::new(
                "Changes that the package tests missed: 1\nswift-mutation-testing ended with exit status: 2"
            ))
        );
        for (mutants, exit) in [
            (&[("/a.swift", 2, "Killed unactivated")][..], 1),
            (&[("/a.swift", 2, "Killed unactivated")][..], 3),
            (
                &[("/a.swift", 1, "Killed"), ("/a.swift", 2, "Timeout")][..],
                2,
            ),
        ] {
            assert_eq!(
                verdict_of(mutants, exited(exit)),
                Err(Failure::new(format!(
                    "swift-mutation-testing ended with exit status: {exit}"
                ))),
                "{mutants:?} {exit}"
            );
        }
    }

    #[test]
    fn a_run_with_a_kill_before_the_changed_code_ran_prints_it_and_stays_inconclusive() {
        let root = Path::new("/repo");
        let mut host = repository(&written(
            "1.6.4",
            &[
                ("/Sources/A.swift", 3, "Killed"),
                ("/Sources/A.swift", 4, "Killed unactivated"),
            ],
        ));
        host.fail("\"swift-mutation-testing\"", Fault::Exit(2, "gate"));
        let ended = mutate(&mut host, root, &[]);
        assert_eq!(ended.as_ref().map_err(Failure::code), Err(75), "{ended:?}");
        assert_eq!(
            host.errors,
            ["Killed Sources/A.swift:4 Swap1: a → b1, before the changed code ran"]
        );
        assert_eq!(host.output, Vec::<String>::new());
    }

    #[test]
    fn a_run_removes_the_earlier_report_runs_the_tool_and_reads_the_new_report() {
        let root = Path::new("/repo");
        let mut host = repository(&written("1.6.4", &DETECTED));
        host.file(
            "/repo/target/mutation/report.json",
            &written("1.6.4", &[("/old.swift", 1, "Survived")]),
        );
        let arguments = texts(&["--sources-path", "Sources/GymemoCopy", "--no-cache"]);
        assert_eq!(mutate(&mut host, root, &arguments), Ok(()));
        assert_eq!(
            host.transcript(),
            [
                "read /repo/mise.toml".to_owned(),
                "create /repo/target/mutation".to_owned(),
                "exists /repo/target/mutation/report.json".to_owned(),
                "remove /repo/target/mutation/report.json".to_owned(),
                format!("{RUN} \"--sources-path\" \"Sources/GymemoCopy\""),
                "exists /repo/target/mutation/report.json".to_owned(),
                "read /repo/target/mutation/report.json".to_owned(),
            ]
        );
        assert_eq!(
            host.output,
            ["PASS mutate: 2 detected and 1 unviable changes"]
        );
        assert_eq!(host.errors, Vec::<String>::new());
    }

    #[test]
    fn a_report_left_by_an_earlier_run_never_counts() {
        let root = Path::new("/repo");
        let mut host = FakeHost::new();
        host.file("/repo/mise.toml", MISE_TOML);
        host.file(
            "/repo/target/mutation/report.json",
            &written("1.6.4", &DETECTED),
        );
        host.fail("\"swift-mutation-testing\"", Fault::Exit(1, "build failed"));
        assert_eq!(
            mutate(&mut host, root, &[]),
            Err(Failure::new(format!(
                "{} wrote no report and ended with exit status: 1",
                &RUN["show ".len()..]
            )))
        );
        assert_eq!(host.output, Vec::<String>::new());
        let mut host = FakeHost::new();
        host.file("/repo/mise.toml", MISE_TOML);
        assert!(mutate(&mut host, root, &[]).is_err());
        assert_eq!(
            host.transcript()[2..4],
            ["exists /repo/target/mutation/report.json", RUN]
        );
    }

    #[test]
    fn a_failed_run_prints_its_findings_before_its_failure() {
        let root = Path::new("/repo");
        let mut host = repository(&written(
            "1.6.4",
            &[
                ("/Sources/A.swift", 9, "Survived"),
                ("/Sources/A.swift", 3, "Killed"),
                ("/Sources/A.swift", 4, "Timeout"),
            ],
        ));
        assert_eq!(
            mutate(&mut host, root, &[]),
            Err(Failure::new("Changes that the package tests missed: 1"))
        );
        assert_eq!(
            host.errors,
            [
                "Survived Sources/A.swift:9 Swap0: a → b0",
                "Timeout Sources/A.swift:4 Swap2: a → b2"
            ]
        );
        assert_eq!(host.output, Vec::<String>::new());

        let mut host = repository(&written("1.6.4", &DETECTED));
        host.fail("\"swift-mutation-testing\"", Fault::Exit(2, "gate"));
        assert_eq!(
            mutate(&mut host, root, &[]),
            Err(Failure::new(
                "swift-mutation-testing ended with exit status: 2"
            ))
        );
        let mut host = repository("{\"files\":");
        assert!(
            mutate(&mut host, root, &[])
                .is_err_and(|failure| failure.to_string().contains("byte 9"))
        );
    }

    #[test]
    fn a_missing_pin_or_a_failed_effect_stops_the_run() {
        let root = Path::new("/repo");
        let mut host = FakeHost::new();
        assert_eq!(
            mutate(&mut host, root, &[]),
            Err(Failure::new("Read mise.toml: no such file"))
        );
        let mut host = FakeHost::new();
        host.file("/repo/mise.toml", "[tools]\n");
        assert_eq!(
            mutate(&mut host, root, &[]),
            Err(Failure::new(
                "mise.toml pins no release of swift-mutation-testing"
            ))
        );
        let mut host = repository("{}");
        host.refuse_creating("/repo/target/mutation");
        assert_eq!(
            mutate(&mut host, root, &[]),
            Err(Failure::new("Create /repo/target/mutation: no permission"))
        );
        let mut host = repository("{}");
        host.fail("\"swift-mutation-testing\"", Fault::Missing);
        assert_eq!(
            mutate(&mut host, root, &[]),
            Err(Failure::new(format!(
                "Start {}: no such program",
                &RUN["show ".len()..]
            )))
        );
    }
}
