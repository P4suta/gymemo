//! Runs cargo-mutants over xtask in the Rust image, in shards that each stay well inside the time limit, and reads the outcome files that each shard wrote.
//!
//! Each run writes into a new directory `target/mutants/run-N`, so the files of an earlier run never count.

use crate::{
    bounded::{self, Image, Mount, Reading, Step, Toolset, WORK},
    failure::{Context, Failure, Result, ensure},
    host::Host,
};
use std::path::Path;

const PACKAGE: &str = "xtask";
/// The directory of the runs, relative to the repository.
const RUNS: &str = "target/mutants";
/// The most mutants of one shard.
/// The slowest file-restricted run in the container, over `xtask/src/swift_mutation.rs`, built its baseline in 4 seconds and tested 34 mutants in 70 seconds.
/// At 2.1 seconds for each mutant, a full shard takes about 214 seconds, under a quarter of the 900-second limit.
/// Even when one mutant in five reaches the 20-second test timeout of cargo-mutants, a shard takes about 572 seconds, under two thirds of the limit.
const MUTANTS_PER_SHARD: usize = 100;
/// The options that the command chooses itself, which a caller may not pass on.
/// Each shard tests its baseline first, so a failing test suite fails the run instead of catching every mutant.
/// Each shard runs one job, the default of cargo-mutants, since the shard size rests on one job and 2 GiB holds one build.
/// The run mutates xtask from the manifest of the repository, so a caller can't point it at another crate.
const OWNED: [&str; 10] = [
    "--shard",
    "--output",
    "--list",
    "--in-place",
    "--package",
    "--baseline",
    "--jobs",
    "--dir",
    "--manifest-path",
    "--gitignore",
];
/// The short forms of the owned options.
const OWNED_SHORT: [char; 4] = ['o', 'p', 'j', 'd'];
/// The other short options of cargo-mutants 27.1.0 that take a value, so the rest of their argument is the value.
const VALUED_SHORT: [char; 8] = ['L', 'C', 't', 'F', 'e', 'E', 'f', 'D'];
/// The exit codes of cargo-mutants after a run that wrote its outcomes: none missed, some missed, and some timed out.
const FINISHED: [i32; 3] = [0, 2, 3];

/// The outcome files of one shard, one mutant on each line.
#[derive(Debug, Default, PartialEq, Eq)]
struct Shard {
    caught: Vec<String>,
    missed: Vec<String>,
    timeout: Vec<String>,
    unviable: Vec<String>,
}

/// Whether `argument` is a cluster of short options that names an owned one before a value starts.
fn names_owned_short(argument: &str) -> bool {
    argument
        .strip_prefix('-')
        .filter(|letters| !letters.starts_with('-'))
        .is_some_and(|letters| {
            letters
                .chars()
                .take_while(|letter| !VALUED_SHORT.contains(letter))
                .any(|letter| OWNED_SHORT.contains(&letter))
        })
}

/// The first argument before `--` that names an owned option, alone or in a cluster of short options.
pub fn refused(arguments: &[String]) -> Option<&str> {
    arguments
        .iter()
        .map(String::as_str)
        .take_while(|argument| *argument != "--")
        .find(|argument| {
            OWNED.iter().any(|owned| {
                argument
                    .strip_prefix(owned)
                    .is_some_and(|rest| rest.is_empty() || rest.starts_with('='))
            }) || names_owned_short(argument)
        })
}

/// The number of the next run after the runs among `names`, or nothing after a run with the largest number.
fn next_run(names: &[String]) -> Option<u32> {
    names
        .iter()
        .filter_map(|name| name.strip_prefix("run-")?.parse::<u32>().ok())
        .max()
        .map_or(Some(1), |latest| latest.checked_add(1))
}

/// The number of shards that keep each shard at `MUTANTS_PER_SHARD` mutants or fewer.
fn shards(listed: usize) -> usize {
    listed.div_ceil(MUTANTS_PER_SHARD)
}

/// A line for each mutant that a shard missed or that reached the test timeout.
fn findings(shards: &[Shard]) -> Vec<String> {
    let missed = shards
        .iter()
        .flat_map(|shard| &shard.missed)
        .map(|mutant| format!("MISSED {mutant}"));
    let timeouts = shards
        .iter()
        .flat_map(|shard| &shard.timeout)
        .map(|mutant| format!("TIMEOUT {mutant}"));
    missed.chain(timeouts).collect()
}

/// The `PASS` line of a run whose shards caught every viable mutant, or the failure of the run.
/// A missed mutant fails the run first, then a shard that failed or stopped, and then a timeout leaves the run inconclusive.
fn verdict(listed: usize, shards: &[Shard], stop: Option<Failure>) -> Result<String> {
    let count = |outcome: fn(&Shard) -> &Vec<String>| {
        shards
            .iter()
            .map(|shard| outcome(shard).len())
            .sum::<usize>()
    };
    let missed = count(|shard| &shard.missed);
    if missed > 0 {
        let failure = Failure::new(format!(
            "Mutants of {PACKAGE} that the tests missed: {missed}"
        ));
        return Err(match stop {
            Some(stop) => failure.followed_by(&stop),
            None => failure,
        });
    }
    if let Some(stop) = stop {
        return Err(stop);
    }
    let timeouts = count(|shard| &shard.timeout);
    if timeouts > 0 {
        return Err(Failure::inconclusive(format!(
            "Mutants of {PACKAGE} that reached the test timeout, so the tests neither caught nor missed them: {timeouts}"
        )));
    }
    let caught = count(|shard| &shard.caught);
    let unviable = count(|shard| &shard.unviable);
    // The shards missed no mutant and saw no timeout here, so the caught and the unviable ones are every mutant that the shards tested.
    let tested = caught + unviable;
    ensure(tested == listed, || {
        format!("The shards tested {tested} mutants, and cargo mutants --list found {listed}")
    })?;
    ensure(caught > 0, || {
        format!("cargo-mutants caught no mutant of {PACKAGE}")
    })?;
    Ok(format!(
        "PASS mutate-xtask: {caught} caught and {unviable} unviable mutants of {listed} listed, in {} shard(s)",
        shards.len()
    ))
}

/// Runs `command` from the repository in the Rust image, and returns what the step reads.
fn run(
    host: &mut impl Host,
    root: &Path,
    image: &Image,
    command: Vec<String>,
    reading: Reading,
    accepted: &[i32],
) -> Result<String> {
    let step = Step {
        image,
        directory: WORK,
        command,
        reading,
        mount: Mount::Writable,
    };
    bounded::run(host, root, &step, accepted).map(|finished| finished.output)
}

/// The cargo-mutants command line with the options of the command before `arguments`.
fn cargo_mutants(options: &[&str], arguments: &[String]) -> Vec<String> {
    ["cargo", "mutants", "--gitignore=true"]
        .iter()
        .chain(options)
        .map(|word| (*word).to_owned())
        .chain(arguments.iter().cloned())
        .collect()
}

/// The outcome files that cargo-mutants wrote into `directory`.
fn outcomes(host: &mut impl Host, directory: &Path) -> Result<Shard> {
    let written = directory.join("mutants.out");
    let mut read = |name: &str| -> Result<Vec<String>> {
        let file = written.join(format!("{name}.txt"));
        let text = host
            .read(&file)
            .context(|| format!("Read {}", file.display()))?;
        Ok(text
            .lines()
            .filter(|line| !line.is_empty())
            .map(str::to_owned)
            .collect())
    };
    Ok(Shard {
        caught: read("caught")?,
        missed: read("missed")?,
        timeout: read("timeout")?,
        unviable: read("unviable")?,
    })
}

/// Runs cargo-mutants over xtask with `arguments`, one bounded shard after another, prints each missed mutant, and fails on any.
/// The run stops at the first shard that fails or stops at a limit, and it reports the mutants that the earlier shards missed before that stop.
pub fn mutate(host: &mut impl Host, root: &Path, arguments: &[String]) -> Result<()> {
    let image = bounded::build(host, root, Toolset::Rust)?;
    let listing = cargo_mutants(&["--list", "--package", PACKAGE], arguments);
    let shown = listing.join(" ");
    let printed = run(host, root, &image, listing, Reading::Captured, &[0])?;
    let listed = printed
        .lines()
        .filter(|line| !line.trim().is_empty())
        .count();
    ensure(listed > 0, || format!("`{shown}` found no mutant"))?;
    let count = shards(listed);
    let runs = root.join(RUNS);
    host.create_directories(&runs)
        .context(|| format!("Create {}", runs.display()))?;
    let names = host
        .list(&runs)
        .context(|| format!("Read {}", runs.display()))?;
    let next = next_run(&names).ok_or_else(|| {
        Failure::new(format!(
            "{} holds run-{}, the largest run number, so it has no number for a new run",
            runs.display(),
            u32::MAX
        ))
    })?;
    let run_name = format!("run-{next}");
    let mut finished = Vec::new();
    let mut stop = None;
    for index in 0..count {
        let shard = format!("{run_name}/shard-{index}");
        let directory = runs.join(&shard);
        let command = cargo_mutants(
            &[
                "--package",
                PACKAGE,
                "--shard",
                &format!("{index}/{count}"),
                "--output",
                &format!("{WORK}/{RUNS}/{shard}"),
            ],
            arguments,
        );
        let outcome = host
            .create_directories(&directory)
            .context(|| format!("Create {}", directory.display()))
            .and_then(|()| run(host, root, &image, command, Reading::Shown, &FINISHED))
            .and_then(|_| outcomes(host, &directory));
        match outcome {
            Ok(shard) => finished.push(shard),
            Err(failure) => {
                stop = Some(failure);
                break;
            }
        }
    }
    for finding in findings(&finished) {
        host.print_error(&finding);
    }
    let summary = verdict(listed, &finished, stop)?;
    host.print(&summary);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::host::fake::{Ending, FakeHost, Fault};

    fn texts(arguments: &[&str]) -> Vec<String> {
        arguments
            .iter()
            .map(|argument| (*argument).to_owned())
            .collect()
    }

    fn mutants(prefix: &str, count: usize) -> Vec<String> {
        (0..count)
            .map(|index| format!("xtask/src/{prefix}.rs:{index}:1: replace"))
            .collect()
    }

    fn shard(caught: usize, missed: usize, timeout: usize, unviable: usize) -> Shard {
        Shard {
            caught: mutants("caught", caught),
            missed: mutants("missed", missed),
            timeout: mutants("timeout", timeout),
            unviable: mutants("unviable", unviable),
        }
    }

    /// A host whose cargo-mutants lists `listed` mutants and whose shards of run `run` write their outcomes.
    fn planned(listed: usize, run: u32, outcomes: &[Shard]) -> FakeHost {
        let mut host = FakeHost::new();
        host.prints("\"--list\"", &mutants("listed", listed).join("\n"));
        let count = outcomes.len();
        for (index, shard) in outcomes.iter().enumerate() {
            let part = format!("\"--shard\" \"{index}/{count}\"");
            let directory = format!("/repo/target/mutants/run-{run}/shard-{index}/mutants.out");
            for (name, lines) in [
                ("caught", &shard.caught),
                ("missed", &shard.missed),
                ("timeout", &shard.timeout),
                ("unviable", &shard.unviable),
            ] {
                let text = lines
                    .iter()
                    .map(|line| format!("{line}\n"))
                    .collect::<String>();
                host.writes(&part, &format!("{directory}/{name}.txt"), &text);
            }
        }
        host
    }

    /// The command of each container that the run created, which follows the time limit on its command line.
    fn commands(host: &FakeHost) -> Vec<String> {
        host.transcript()
            .iter()
            .filter_map(|line| line.split_once("\"900s\" "))
            .map(|(_, command)| command.replace('"', ""))
            .collect()
    }

    #[test]
    fn the_command_owns_the_crate_that_it_mutates() {
        for owned in [
            "--dir",
            "--dir=../other",
            "-d",
            "-d../other",
            "--manifest-path",
            "--manifest-path=../other/Cargo.toml",
        ] {
            let arguments = texts(&["--file", "xtask/src/json.rs", owned, "x"]);
            assert_eq!(refused(&arguments), Some(owned), "{owned}");
        }
        assert_eq!(refused(&texts(&["--dir", "../other"])), Some("--dir"));
        assert_eq!(
            refused(&texts(&["--manifest-path", "../other/Cargo.toml"])),
            Some("--manifest-path")
        );
        for cluster in ["-vd", "-vdproject", "-hVd."] {
            assert_eq!(
                refused(&texts(&["--file", "a.rs", cluster])),
                Some(cluster),
                "{cluster}"
            );
        }
        for allowed in ["--dirs", "--directory", "--manifest-paths", "-fd", "-ed"] {
            assert_eq!(refused(&texts(&[allowed, "1"])), None, "{allowed}");
        }
        assert_eq!(refused(&texts(&["--", "--dir", "-d"])), None);
    }

    #[test]
    fn the_command_owns_the_shards_the_output_the_listing_the_copy_the_package_the_baseline_and_the_jobs()
     {
        for owned in [
            "--shard",
            "--shard=1/2",
            "--output",
            "--output=out",
            "-o",
            "-oout",
            "--list",
            "--list=true",
            "--in-place",
            "--gitignore",
            "--gitignore=false",
            "--package",
            "--package=xtask",
            "-p",
            "-pxtask",
            "--baseline",
            "--baseline=skip",
            "--jobs",
            "--jobs=4",
            "-j",
            "-j4",
        ] {
            let arguments = texts(&["--file", "xtask/src/json.rs", owned, "x"]);
            assert_eq!(refused(&arguments), Some(owned), "{owned}");
        }
        assert_eq!(
            refused(&texts(&["--baseline", "skip", "--file", "a.rs"])),
            Some("--baseline")
        );
        assert_eq!(refused(&texts(&["--jobs", "4"])), Some("--jobs"));
        for cluster in [
            "-vj4",
            "-Vj4",
            "-vo",
            "-vpxtask",
            "-hvVj",
            "-vVo/tmp/x",
            "-xj",
        ] {
            assert_eq!(
                refused(&texts(&["--file", "a.rs", cluster, "x"])),
                Some(cluster),
                "{cluster}"
            );
        }
        for value in [
            "-fxtask/src/json.rs",
            "-vfjson.rs",
            "-eopt",
            "-Ejson",
            "-Fjob",
            "-t20",
            "-L4",
            "-Cjobs",
            "-Dpatch.diff",
            "-vV",
            "-v",
        ] {
            assert_eq!(refused(&texts(&[value])), None, "{value}");
        }
        for allowed in [
            "--file",
            "-f",
            "--list-files",
            "--outputs",
            "--packages",
            "--shardx",
            "--baselines",
            "--jobserver",
            "-t",
            "--no-shuffle",
        ] {
            assert_eq!(refused(&texts(&[allowed, "1"])), None, "{allowed}");
        }
        assert_eq!(
            refused(&texts(&["--file", "a.rs", "--", "--output", "-p"])),
            None
        );
        assert_eq!(refused(&texts(&["--", "x", "--list"])), None);
        assert_eq!(refused(&[]), None);
    }

    #[test]
    fn a_run_takes_the_number_after_the_latest_run() {
        assert_eq!(next_run(&[]), Some(1));
        assert_eq!(
            next_run(&texts(&[
                "run-1", "run-10", "run-9", "notes", "run-x", "runs-40"
            ])),
            Some(11)
        );
        assert_eq!(next_run(&texts(&["shard-3"])), Some(1));
        assert_eq!(next_run(&texts(&["run-4294967294"])), Some(4_294_967_295));
        assert_eq!(next_run(&texts(&["run-1", "run-4294967295"])), None);
    }

    #[test]
    fn a_run_after_the_largest_run_number_refuses_before_any_shard() {
        let root = Path::new("/repo");
        let mut host = planned(1, 1, &[shard(1, 0, 0, 0)]);
        host.directory("/repo/target/mutants", &["run-4294967295"]);
        assert_eq!(
            mutate(&mut host, root, &[]),
            Err(Failure::new(
                "/repo/target/mutants holds run-4294967295, the largest run number, so it has no number for a new run"
            ))
        );
        assert_eq!(commands(&host).len(), 1);
    }

    #[test]
    fn each_shard_holds_at_most_its_share_of_mutants() {
        assert_eq!(MUTANTS_PER_SHARD, 100);
        assert_eq!(shards(1), 1);
        assert_eq!(shards(100), 1);
        assert_eq!(shards(101), 2);
        assert_eq!(shards(312), 4);
        assert_eq!(shards(400), 4);
    }

    #[test]
    fn each_missed_mutant_and_each_timeout_is_printed() {
        assert_eq!(
            findings(&[shard(2, 1, 0, 1), shard(0, 1, 1, 0)]),
            [
                "MISSED xtask/src/missed.rs:0:1: replace",
                "MISSED xtask/src/missed.rs:0:1: replace",
                "TIMEOUT xtask/src/timeout.rs:0:1: replace",
            ]
        );
        assert_eq!(findings(&[shard(3, 0, 0, 2)]), Vec::<String>::new());
    }

    #[test]
    fn the_verdict_needs_no_miss_no_stop_no_timeout_every_mutant_and_one_caught() {
        assert_eq!(
            verdict(7, &[shard(4, 0, 0, 3)], None),
            Ok(
                "PASS mutate-xtask: 4 caught and 3 unviable mutants of 7 listed, in 1 shard(s)"
                    .to_owned()
            )
        );
        assert_eq!(
            verdict(9, &[shard(4, 0, 0, 1), shard(2, 0, 0, 2)], None),
            Ok(
                "PASS mutate-xtask: 6 caught and 3 unviable mutants of 9 listed, in 2 shard(s)"
                    .to_owned()
            )
        );
        assert_eq!(
            verdict(9, &[shard(4, 1, 1, 1), shard(1, 1, 0, 0)], None),
            Err(Failure::new("Mutants of xtask that the tests missed: 2"))
        );
        let stopped = Failure::inconclusive("`cargo mutants` stopped at the time limit");
        assert_eq!(
            verdict(
                9,
                &[shard(4, 1, 0, 1)],
                Some(Failure::inconclusive(
                    "`cargo mutants` stopped at the time limit"
                ))
            ),
            Err(Failure::new("Mutants of xtask that the tests missed: 1").followed_by(&stopped))
        );
        assert_eq!(
            verdict(
                9,
                &[shard(4, 0, 0, 1)],
                Some(Failure::inconclusive(
                    "`cargo mutants` stopped at the time limit"
                ))
            ),
            Err(Failure::inconclusive(
                "`cargo mutants` stopped at the time limit"
            ))
        );
        assert_eq!(
            verdict(
                9,
                &[shard(4, 0, 2, 1)],
                Some(Failure::new("`cargo mutants` failed"))
            ),
            Err(Failure::new("`cargo mutants` failed"))
        );
        assert_eq!(
            verdict(9, &[shard(4, 0, 2, 1), shard(1, 0, 1, 0)], None),
            Err(Failure::inconclusive(
                "Mutants of xtask that reached the test timeout, so the tests neither caught nor missed them: 3"
            ))
        );
        assert_eq!(
            verdict(8, &[shard(4, 0, 0, 3)], None),
            Err(Failure::new(
                "The shards tested 7 mutants, and cargo mutants --list found 8"
            ))
        );
        assert_eq!(
            verdict(6, &[shard(4, 0, 0, 3)], None),
            Err(Failure::new(
                "The shards tested 7 mutants, and cargo mutants --list found 6"
            ))
        );
        assert_eq!(
            verdict(3, &[shard(0, 0, 0, 3)], None),
            Err(Failure::new("cargo-mutants caught no mutant of xtask"))
        );
    }

    #[test]
    fn a_run_lists_the_mutants_then_runs_each_shard_in_a_new_directory() {
        let root = Path::new("/repo");
        let mut host = planned(150, 3, &[shard(90, 0, 0, 10), shard(40, 0, 0, 10)]);
        host.directory("/repo/target/mutants", &["run-1", "run-2"]);
        let arguments = texts(&["--file", "xtask/src/json.rs", "--", "--test-threads", "1"]);
        assert_eq!(mutate(&mut host, root, &arguments), Ok(()));
        assert_eq!(
            commands(&host),
            [
                "cargo mutants --gitignore=true --list --package xtask --file xtask/src/json.rs -- --test-threads 1",
                "cargo mutants --gitignore=true --package xtask --shard 0/2 --output /work/target/mutants/run-3/shard-0 --file xtask/src/json.rs -- --test-threads 1",
                "cargo mutants --gitignore=true --package xtask --shard 1/2 --output /work/target/mutants/run-3/shard-1 --file xtask/src/json.rs -- --test-threads 1",
            ]
        );
        let lines = &host.transcript()[2..];
        assert_eq!(
            lines[0],
            "capture \"docker\" \"build\" \"--quiet\" \"--tag\" \"gymemo-rust:proofs\" \"/repo/xtask/proofs/rust\""
        );
        assert!(lines[1].contains(
            "\"--volume\" \"/repo:/work\" \"--volume\" \"/repo/target/verification-cargo/registry:/usr/local/cargo/registry:ro\" \"--workdir\" \"/work\" \"--env\" \"CARGO_TARGET_DIR=/tmp/gymemo-target\" \"--env\" \"CARGO_NET_OFFLINE=true\""
        ));
        assert!(lines[2].starts_with("capture \"docker\" \"start\""));
        assert_eq!(
            lines[5..7],
            ["create /repo/target/mutants", "list /repo/target/mutants"]
        );
        assert_eq!(lines[7], "create /repo/target/mutants/run-3/shard-0");
        assert!(lines[9].starts_with("show \"docker\" \"start\""));
        assert_eq!(
            lines[12..16],
            [
                "read /repo/target/mutants/run-3/shard-0/mutants.out/caught.txt",
                "read /repo/target/mutants/run-3/shard-0/mutants.out/missed.txt",
                "read /repo/target/mutants/run-3/shard-0/mutants.out/timeout.txt",
                "read /repo/target/mutants/run-3/shard-0/mutants.out/unviable.txt",
            ]
        );
        assert_eq!(lines[16], "create /repo/target/mutants/run-3/shard-1");
        assert_eq!(
            host.output,
            ["PASS mutate-xtask: 130 caught and 20 unviable mutants of 150 listed, in 2 shard(s)"]
        );
        assert_eq!(host.errors, Vec::<String>::new());
        assert_eq!(host.containers(), 0);
    }

    #[test]
    fn the_outcomes_of_an_earlier_run_never_count() {
        let root = Path::new("/repo");
        let mut host = planned(5, 2, &[shard(3, 0, 0, 2)]);
        host.directory("/repo/target/mutants", &["run-1"]);
        host.file(
            "/repo/target/mutants/run-1/shard-0/mutants.out/missed.txt",
            "xtask/src/old.rs:1:1: replace\n",
        );
        assert_eq!(mutate(&mut host, root, &[]), Ok(()));
        assert!(!host.transcript().iter().any(|line| line.contains("run-1/")));

        let mut host = FakeHost::new();
        host.prints("\"--list\"", "xtask/src/a.rs:1:1: replace\n");
        host.directory("/repo/target/mutants", &["run-1"]);
        for name in ["caught", "missed", "timeout", "unviable"] {
            host.file(
                &format!("/repo/target/mutants/run-2/shard-0/mutants.out/{name}.txt"),
                "",
            );
        }
        host.file(
            "/repo/target/mutants/run-1/shard-0/mutants.out/caught.txt",
            "xtask/src/a.rs:1:1: replace\n",
        );
        assert_eq!(
            mutate(&mut host, root, &[]),
            Err(Failure::new(
                "The shards tested 0 mutants, and cargo mutants --list found 1"
            ))
        );
    }

    #[test]
    fn a_missed_mutant_is_printed_and_fails_the_run_after_every_shard() {
        let root = Path::new("/repo");
        let mut host = planned(
            201,
            1,
            &[shard(99, 1, 0, 0), shard(100, 0, 0, 0), shard(0, 1, 0, 0)],
        );
        host.ends("\"0/3\"", Ending::Exit(2));
        host.ends("\"2/3\"", Ending::Exit(2));
        assert_eq!(
            mutate(&mut host, root, &[]),
            Err(Failure::new("Mutants of xtask that the tests missed: 2"))
        );
        assert_eq!(commands(&host).len(), 4);
        assert_eq!(
            host.errors,
            [
                "MISSED xtask/src/missed.rs:0:1: replace",
                "MISSED xtask/src/missed.rs:0:1: replace"
            ]
        );
        assert_eq!(host.output, Vec::<String>::new());
    }

    #[test]
    fn a_timeout_or_a_stopped_shard_leaves_the_run_inconclusive() {
        let root = Path::new("/repo");
        let mut host = planned(2, 1, &[shard(1, 0, 1, 0)]);
        host.ends("\"0/1\"", Ending::Exit(3));
        assert_eq!(
            mutate(&mut host, root, &[]),
            Err(Failure::inconclusive(
                "Mutants of xtask that reached the test timeout, so the tests neither caught nor missed them: 1"
            ))
        );
        assert_eq!(host.errors, ["TIMEOUT xtask/src/timeout.rs:0:1: replace"]);

        let mut host = planned(150, 1, &[shard(100, 0, 0, 0), shard(50, 0, 0, 0)]);
        host.ends("\"0/2\"", Ending::OutOfMemory(137));
        let stopped = mutate(&mut host, root, &[]);
        assert_eq!(
            stopped,
            Err(Failure::inconclusive(
                "`cargo mutants --gitignore=true --package xtask --shard 0/2 --output /work/target/mutants/run-1/shard-0` reached the memory limit of 2 GiB without swap"
            ))
        );
        assert_eq!(commands(&host).len(), 2);
        assert!(
            !host
                .transcript()
                .iter()
                .any(|line| line.starts_with("read "))
        );

        let mut host = planned(150, 1, &[shard(100, 0, 0, 0), shard(50, 0, 0, 0)]);
        host.ends("\"1/2\"", Ending::Exit(124));
        assert_eq!(
            mutate(&mut host, root, &[]).map_err(|failure| failure.code()),
            Err(75)
        );
    }

    #[test]
    fn a_failed_shard_or_a_missing_outcome_file_stops_the_run() {
        let root = Path::new("/repo");
        let mut host = planned(150, 1, &[shard(100, 0, 0, 0), shard(50, 0, 0, 0)]);
        host.ends("\"0/2\"", Ending::Exit(4));
        assert_eq!(
            mutate(&mut host, root, &[]),
            Err(Failure::new(
                "`cargo mutants --gitignore=true --package xtask --shard 0/2 --output /work/target/mutants/run-1/shard-0` failed with exit code 4 in its container"
            ))
        );
        assert_eq!(commands(&host).len(), 2);

        let mut host = FakeHost::new();
        host.prints("\"--list\"", "a\nb\n");
        assert_eq!(
            mutate(&mut host, root, &[]),
            Err(Failure::new(
                "Read /repo/target/mutants/run-1/shard-0/mutants.out/caught.txt: no such file"
            ))
        );
        let mut host = FakeHost::new();
        host.prints("\"--list\"", "\n");
        assert_eq!(
            mutate(&mut host, root, &texts(&["--file", "xtask/src/none.rs"])),
            Err(Failure::new(
                "`cargo mutants --gitignore=true --list --package xtask --file xtask/src/none.rs` found no mutant"
            ))
        );
        let mut host = FakeHost::new();
        host.ends("\"--list\"", Ending::Exit(1));
        assert!(mutate(&mut host, root, &[]).is_err_and(|failure| {
            failure.to_string().starts_with(
                "`cargo mutants --gitignore=true --list --package xtask` failed with exit code 1",
            )
        }));
        let mut host = planned(1, 1, &[shard(1, 0, 0, 0)]);
        host.refuse_listing("/repo/target/mutants");
        assert_eq!(
            mutate(&mut host, root, &[]),
            Err(Failure::new("Read /repo/target/mutants: no permission"))
        );
        let mut host = planned(1, 1, &[shard(1, 0, 0, 0)]);
        host.refuse_creating("/repo/target/mutants/run-1/shard-0");
        assert_eq!(
            mutate(&mut host, root, &[]),
            Err(Failure::new(
                "Create /repo/target/mutants/run-1/shard-0: no permission"
            ))
        );
        let mut host = planned(1, 1, &[shard(1, 0, 0, 0)]);
        host.fail("\"build\"", Fault::Exit(1, "no daemon"));
        assert!(mutate(&mut host, root, &[]).is_err());
        assert_eq!(host.transcript().len(), 3);
    }
}
