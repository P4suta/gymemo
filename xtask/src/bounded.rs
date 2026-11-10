//! Runs one verification tool in a new container under the owner's resource policy, and separates a finished run from a stop at a limit.
//!
//! The policy holds lean, lake, cargo-kani, and cargo-mutants to 2 CPUs, 2 GiB of memory without swap, 256 processes, and 900 seconds.
//! A stop at the time or the memory limit is inconclusive: it never passes and it never fails a proof or a mutant.
//! A step that only reads the repository gets it without write access.
//! Each image keeps one fixed name, so a rebuild leaves no image without a name behind.

use crate::{
    failure::{Context, Failure, Result},
    host::{Host, Invocation, Streams},
};
use std::path::Path;

/// The processors of one container.
pub const CPUS: u32 = 2;
/// The memory of one container, which is also its memory plus swap, so the container has no swap.
pub const MEMORY_BYTES: u64 = 2 << 30;
/// The processes and threads of one container.
pub const PIDS: u32 = 256;
/// The time of one container's command, which `timeout` ends in the container.
pub const SECONDS: u32 = 900;
/// The directory of the container where the repository lies.
pub const WORK: &str = "/work";

/// The image that one Dockerfile under `xtask/proofs` describes.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Toolset {
    /// Lean with lake and leanchecker.
    Lean,
    /// Rust with cargo-kani and cargo-mutants.
    Rust,
}

/// An image that `docker build` made for a toolset.
#[derive(Debug, PartialEq, Eq)]
pub struct Image {
    id: String,
    toolset: Toolset,
}

/// Where the output of a step goes and what the step hands back.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Reading {
    /// The terminal shows the output while the step runs, and the step hands back nothing.
    Shown,
    /// The step hands back its standard output, and the terminal shows nothing.
    Captured,
    /// The terminal shows the output while the step runs, and the step then hands back its standard output from the container's log.
    ShownThenRead,
}

/// Whether a step may write into the repository at `/work`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Mount {
    /// The step writes its build, its listing, or its outcomes into the repository.
    Writable,
    /// The step only reads the repository, so it can't rewrite what a later step reads.
    ReadOnly,
}

/// One command in one container.
#[derive(Debug)]
pub struct Step<'a> {
    pub image: &'a Image,
    /// The working directory in the container, under `/work`.
    pub directory: &'a str,
    /// The program and its arguments.
    pub command: Vec<String>,
    pub reading: Reading,
    pub mount: Mount,
}

/// A step whose command ran to its end in time and within its memory.
#[derive(Debug, PartialEq, Eq)]
pub struct Finished {
    pub code: i32,
    /// The standard output, when the step reads it.
    pub output: String,
}

/// What `docker inspect` reports of a container: its status, whether the kernel stopped a process at the memory limit, and the exit code.
const STATE: &str = "{{.State.Status}} {{.State.OOMKilled}} {{.State.ExitCode}}";
/// The time that `timeout` gives a command after its signal at the time limit before it kills the command.
const GRACE_SECONDS: u32 = 1;
/// The exit code of `timeout` when the time limit ends the command.
const TIMED_OUT: i32 = 124;
/// The exit code of a command that `SIGKILL` ended, which `timeout` reports when the command outlives the grace.
const KILLED: i32 = 137;

impl Toolset {
    /// The directory of the Dockerfile, relative to the repository.
    fn context(self) -> &'static str {
        match self {
            Toolset::Lean => "xtask/proofs/lean",
            Toolset::Rust => "xtask/proofs/rust",
        }
    }

    /// The fixed name of the image, which a rebuild moves to its new image, so the earlier image leaves no record without a name behind.
    fn tag(self) -> &'static str {
        match self {
            Toolset::Lean => "gymemo-lean:proofs",
            Toolset::Rust => "gymemo-rust:proofs",
        }
    }

    /// The variables of every container, where a Rust build keeps its artifacts apart from the native builds.
    fn environment(self) -> &'static [&'static str] {
        match self {
            Toolset::Lean => &[],
            Toolset::Rust => &["CARGO_TARGET_DIR=/work/target/container"],
        }
    }
}

fn docker() -> Invocation {
    Invocation::new("docker")
}

fn is_digest(text: &str) -> bool {
    text.len() == 64
        && text
            .bytes()
            .all(|byte| matches!(byte, b'0'..=b'9' | b'a'..=b'f'))
}

/// Runs `invocation` with its output captured, and returns its standard output, or the failure with its standard error.
fn captured(host: &mut impl Host, invocation: &Invocation) -> Result<String> {
    let result = host
        .run(invocation, Streams::Captured)
        .context(|| format!("Start {invocation}"))?;
    if !result.status.success() {
        return Err(Failure::new(format!(
            "{invocation} failed with {}:\n{}",
            result.status,
            String::from_utf8_lossy(&result.stderr).trim_end()
        )));
    }
    String::from_utf8(result.stdout).context(|| format!("Read the output of {invocation}"))
}

/// Builds the image of `toolset` under its fixed name and returns its identifier.
pub fn build(host: &mut impl Host, root: &Path, toolset: Toolset) -> Result<Image> {
    let context = root.join(toolset.context());
    let printed = captured(
        host,
        &docker()
            .args(["build", "--quiet", "--tag", toolset.tag()])
            .arg(&context),
    )?;
    let id = printed.trim();
    if !id.strip_prefix("sha256:").is_some_and(is_digest) {
        return Err(Failure::new(format!(
            "docker build printed no image identifier for {}: {id}",
            context.display()
        )));
    }
    Ok(Image {
        id: id.to_owned(),
        toolset,
    })
}

/// The command line that creates the container of `step` with the repository at `/work`, without a network, and under the limits.
/// A step that only reads gets the repository without write access.
fn create(root: &Path, step: &Step) -> Invocation {
    let mut volume = root.as_os_str().to_owned();
    volume.push(format!(":{WORK}"));
    if step.mount == Mount::ReadOnly {
        volume.push(":ro");
    }
    let memory = MEMORY_BYTES.to_string();
    docker()
        .args(["create", "--cpus", &CPUS.to_string()])
        .args(["--memory", &memory, "--memory-swap", &memory])
        .args(["--pids-limit", &PIDS.to_string()])
        .args(["--network", "none", "--volume"])
        .arg(volume)
        .args(["--workdir", step.directory])
        .args(
            step.image
                .toolset
                .environment()
                .iter()
                .flat_map(|variable| ["--env", variable]),
        )
        .arg(&step.image.id)
        .arg("timeout")
        .arg(format!("--kill-after={GRACE_SECONDS}s"))
        .arg(format!("{SECONDS}s"))
        .args(&step.command)
}

/// Runs `step` in a new container, which goes away after every outcome.
/// An exit code outside `accepted` fails the step, and a stop at a limit leaves the step inconclusive.
/// A failed removal of the container fails the step, after the failure of the step when there is one.
pub fn run(host: &mut impl Host, root: &Path, step: &Step, accepted: &[i32]) -> Result<Finished> {
    let printed = captured(host, &create(root, step))?;
    let id = printed.trim();
    if !is_digest(id) {
        return Err(Failure::new(format!(
            "docker create printed no container identifier: {id}"
        )));
    }
    let finished = attend(host, id, step, accepted);
    let removed = captured(host, &docker().args(["rm", "--force", id]));
    match (finished, removed) {
        (Ok(finished), Ok(_)) => Ok(finished),
        (Err(failure), Ok(_)) | (Ok(_), Err(failure)) => Err(failure),
        (Err(first), Err(later)) => Err(first.followed_by(&later)),
    }
}

/// Starts the created container `id`, waits for its end, and reads how it ended.
fn attend(host: &mut impl Host, id: &str, step: &Step, accepted: &[i32]) -> Result<Finished> {
    let streams = match step.reading {
        Reading::Captured => Streams::Captured,
        Reading::Shown | Reading::ShownThenRead => Streams::Shown,
    };
    let start = docker().args(["start", "--attach", id]);
    let started = host
        .run(&start, streams)
        .context(|| format!("Start {start}"))?;
    let state = captured(host, &docker().args(["inspect", "--format", STATE, id]))?;
    let command = step.command.join(" ");
    match ending(&state) {
        None => Err(Failure::new(format!(
            "The container {id} of `{command}` ended in the state `{}`",
            state.trim()
        ))),
        Some(Ending::TimeLimit(code)) => Err(Failure::inconclusive(format!(
            "`{command}` stopped at the time limit of {SECONDS} seconds with exit code {code}"
        ))),
        Some(Ending::MemoryLimit) => Err(Failure::inconclusive(format!(
            "`{command}` reached the memory limit of {} GiB without swap",
            MEMORY_BYTES >> 30
        ))),
        Some(Ending::Exit(code)) if !accepted.contains(&code) => {
            let written = [started.stdout, started.stderr].concat();
            let written = String::from_utf8_lossy(&written);
            let failed = format!("`{command}` failed with exit code {code} in its container");
            Err(Failure::new(match written.trim_end() {
                "" => failed,
                text => format!("{failed}:\n{text}"),
            }))
        }
        Some(Ending::Exit(code)) => {
            let output = match step.reading {
                Reading::Shown => String::new(),
                Reading::Captured => String::from_utf8(started.stdout)
                    .context(|| format!("Read the output of {start}"))?,
                Reading::ShownThenRead => captured(host, &docker().args(["logs", id]))?,
            };
            Ok(Finished { code, output })
        }
    }
}

/// How the command of a container ended.
#[derive(Debug, PartialEq, Eq)]
enum Ending {
    Exit(i32),
    /// The exit code is the one of `timeout` at the time limit, or the one of `SIGKILL`.
    TimeLimit(i32),
    MemoryLimit,
}

/// The ending that `docker inspect` reports as `STATUS OOM_KILLED EXIT_CODE`, or nothing for another state.
/// Docker 29.8 sets `OOMKilled` whenever the kernel stops any process of the container at the memory limit, whatever the exit code of the container.
/// A command that exits with 124 or 137 by itself reads as a stop at the time limit, which leaves its step inconclusive and never passes it.
fn ending(state: &str) -> Option<Ending> {
    let [status, out_of_memory, code] = state.split_whitespace().collect::<Vec<_>>()[..] else {
        return None;
    };
    let code = code.parse().ok()?;
    match (status, out_of_memory) {
        ("exited", "true") => Some(Ending::MemoryLimit),
        ("exited", "false") if matches!(code, TIMED_OUT | KILLED) => Some(Ending::TimeLimit(code)),
        ("exited", "false") => Some(Ending::Exit(code)),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::host::fake::{Ending as Ends, FakeHost, Fault, IMAGE};

    const ROOT: &str = "/repo";

    /// The calls of a step in the Lean image that shows its output, with `{id}` for the container.
    const SHOWN: &str = r#"
capture "docker" "build" "--quiet" "--tag" "gymemo-lean:proofs" "/repo/xtask/proofs/lean"
capture "docker" "create" "--cpus" "2" "--memory" "2147483648" "--memory-swap" "2147483648" "--pids-limit" "256" "--network" "none" "--volume" "/repo:/work" "--workdir" "/work/specs/lean" "{image}" "timeout" "--kill-after=1s" "900s" "lake" "build" "--wfail"
show "docker" "start" "--attach" "{id}"
capture "docker" "inspect" "--format" "{{.State.Status}} {{.State.OOMKilled}} {{.State.ExitCode}}" "{id}"
capture "docker" "rm" "--force" "{id}"
"#;

    fn lines(transcript: &str) -> Vec<String> {
        transcript
            .lines()
            .filter(|line| !line.is_empty())
            .map(|line| {
                line.replace("{image}", IMAGE)
                    .replace("{id}", &format!("{:064x}", 1))
            })
            .collect()
    }

    fn words(command: &str) -> Vec<String> {
        command.split(' ').map(str::to_owned).collect()
    }

    /// Runs `command` in the image of `toolset` from `/work/specs/lean`.
    fn step(
        host: &mut FakeHost,
        toolset: Toolset,
        command: &str,
        reading: Reading,
        accepted: &[i32],
    ) -> Result<Finished> {
        let root = Path::new(ROOT);
        let image = build(host, root, toolset)?;
        let step = Step {
            image: &image,
            directory: "/work/specs/lean",
            command: words(command),
            reading,
            mount: Mount::Writable,
        };
        run(host, root, &step, accepted)
    }

    fn lake(host: &mut FakeHost) -> Result<Finished> {
        step(
            host,
            Toolset::Lean,
            "lake build --wfail",
            Reading::Shown,
            &[0],
        )
    }

    #[test]
    fn the_limits_are_the_ones_of_the_policy() {
        assert_eq!(
            (CPUS, MEMORY_BYTES, PIDS, SECONDS),
            (2, 2 * 1024 * 1024 * 1024, 256, 900)
        );
    }

    #[test]
    fn a_step_runs_in_a_new_container_under_the_limits_and_leaves_no_container() {
        let mut host = FakeHost::new();
        assert_eq!(
            lake(&mut host),
            Ok(Finished {
                code: 0,
                output: String::new()
            })
        );
        assert_eq!(host.transcript(), lines(SHOWN));
        assert_eq!(host.containers(), 0);
        assert_eq!(host.output, Vec::<String>::new());
    }

    #[test]
    fn a_reading_step_mounts_the_repository_read_only() {
        let mut host = FakeHost::new();
        let root = Path::new(ROOT);
        let finished = build(&mut host, root, Toolset::Lean).and_then(|image| {
            let step = Step {
                image: &image,
                directory: "/work/specs/lean",
                command: words("lake env lean Axioms.lean"),
                reading: Reading::Captured,
                mount: Mount::ReadOnly,
            };
            run(&mut host, root, &step, &[0])
        });
        assert_eq!(finished.map(|finished| finished.code), Ok(0));
        assert_eq!(
            host.transcript()[1],
            format!(
                "capture \"docker\" \"create\" \"--cpus\" \"2\" \"--memory\" \"2147483648\" \"--memory-swap\" \"2147483648\" \"--pids-limit\" \"256\" \"--network\" \"none\" \"--volume\" \"/repo:/work:ro\" \"--workdir\" \"/work/specs/lean\" \"{IMAGE}\" \"timeout\" \"--kill-after=1s\" \"900s\" \"lake\" \"env\" \"lean\" \"Axioms.lean\""
            )
        );
        assert_eq!(host.containers(), 0);
    }

    #[test]
    fn a_rust_step_builds_into_a_target_directory_of_its_own() {
        let mut host = FakeHost::new();
        let finished = step(
            &mut host,
            Toolset::Rust,
            "cargo kani --package xtask",
            Reading::Shown,
            &[0],
        );
        assert_eq!(finished.map(|finished| finished.code), Ok(0));
        assert_eq!(
            host.transcript()[..2],
            [
                "capture \"docker\" \"build\" \"--quiet\" \"--tag\" \"gymemo-rust:proofs\" \"/repo/xtask/proofs/rust\"".to_owned(),
                format!(
                    "capture \"docker\" \"create\" \"--cpus\" \"2\" \"--memory\" \"2147483648\" \"--memory-swap\" \"2147483648\" \"--pids-limit\" \"256\" \"--network\" \"none\" \"--volume\" \"/repo:/work\" \"--workdir\" \"/work/specs/lean\" \"--env\" \"CARGO_TARGET_DIR=/work/target/container\" \"{IMAGE}\" \"timeout\" \"--kill-after=1s\" \"900s\" \"cargo\" \"kani\" \"--package\" \"xtask\""
                )
            ]
        );
    }

    #[test]
    fn a_captured_step_and_a_read_step_hand_back_the_standard_output() {
        let mut host = FakeHost::new();
        host.prints("\"Axioms.lean\"", "theorems 0\n");
        let captured = step(
            &mut host,
            Toolset::Lean,
            "lake env lean Axioms.lean",
            Reading::Captured,
            &[0],
        );
        assert_eq!(
            captured,
            Ok(Finished {
                code: 0,
                output: "theorems 0\n".to_owned()
            })
        );
        let id = format!("{:064x}", 1);
        assert_eq!(
            host.transcript()[2],
            format!("capture \"docker\" \"start\" \"--attach\" \"{id}\"")
        );
        let mut host = FakeHost::new();
        host.prints(
            "\"kani\"",
            "Complete - 1 successfully verified harnesses, 0 failures, 1 total.\n",
        );
        let read = step(
            &mut host,
            Toolset::Rust,
            "cargo kani",
            Reading::ShownThenRead,
            &[0],
        );
        assert_eq!(
            read.map(|finished| finished.output),
            Ok("Complete - 1 successfully verified harnesses, 0 failures, 1 total.\n".to_owned())
        );
        assert_eq!(
            host.transcript()[2..],
            [
                format!("show \"docker\" \"start\" \"--attach\" \"{id}\""),
                format!(
                    "capture \"docker\" \"inspect\" \"--format\" \"{{{{.State.Status}}}} {{{{.State.OOMKilled}}}} {{{{.State.ExitCode}}}}\" \"{id}\""
                ),
                format!("capture \"docker\" \"logs\" \"{id}\""),
                format!("capture \"docker\" \"rm\" \"--force\" \"{id}\""),
            ]
        );
        assert_eq!(host.containers(), 0);
    }

    #[test]
    fn an_exit_code_outside_the_accepted_ones_fails_the_step_and_the_container_still_goes() {
        let mut host = FakeHost::new();
        host.ends("\"lake\"", Ends::Exit(1));
        assert_eq!(
            lake(&mut host),
            Err(Failure::new(
                "`lake build --wfail` failed with exit code 1 in its container"
            ))
        );
        assert_eq!(host.transcript(), lines(SHOWN));
        assert_eq!(host.containers(), 0);

        let mut host = FakeHost::new();
        host.ends("\"Axioms.lean\"", Ends::Exit(1));
        host.prints("\"Axioms.lean\"", "error: unknown identifier\n");
        assert_eq!(
            step(
                &mut host,
                Toolset::Lean,
                "lake env lean Axioms.lean",
                Reading::Captured,
                &[0]
            ),
            Err(Failure::new(
                "`lake env lean Axioms.lean` failed with exit code 1 in its container:\nerror: unknown identifier"
            ))
        );

        for code in [0, 2, 3] {
            let mut host = FakeHost::new();
            host.ends("\"mutants\"", Ends::Exit(code));
            let finished = step(
                &mut host,
                Toolset::Rust,
                "cargo mutants",
                Reading::Shown,
                &[0, 2, 3],
            );
            assert_eq!(finished.map(|finished| finished.code), Ok(code));
        }
        let mut host = FakeHost::new();
        host.ends("\"mutants\"", Ends::Exit(4));
        assert_eq!(
            step(
                &mut host,
                Toolset::Rust,
                "cargo mutants",
                Reading::ShownThenRead,
                &[0, 2, 3]
            ),
            Err(Failure::new(
                "`cargo mutants` failed with exit code 4 in its container"
            ))
        );
        assert!(
            !host
                .transcript()
                .iter()
                .any(|line| line.contains("\"logs\""))
        );
        assert_eq!(host.containers(), 0);
    }

    #[test]
    fn a_stop_at_a_limit_is_inconclusive_and_the_container_still_goes() {
        let time = "`lake build --wfail` stopped at the time limit of 900 seconds with exit code";
        let memory = "`lake build --wfail` reached the memory limit of 2 GiB without swap";
        for (ending, message) in [
            (Ends::Exit(124), format!("{time} 124")),
            (Ends::Exit(137), format!("{time} 137")),
            (Ends::OutOfMemory(137), memory.to_owned()),
            (Ends::OutOfMemory(1), memory.to_owned()),
            (Ends::OutOfMemory(0), memory.to_owned()),
        ] {
            let mut host = FakeHost::new();
            host.ends("\"lake\"", ending);
            let stopped = lake(&mut host);
            assert_eq!(stopped, Err(Failure::inconclusive(message)), "{ending:?}");
            assert!(
                stopped.is_err_and(|failure| failure.code() == 75
                    && failure.to_string().starts_with("INCONCLUSIVE: ")),
                "{ending:?}"
            );
            assert_eq!(host.transcript(), lines(SHOWN), "{ending:?}");
            assert_eq!(host.containers(), 0, "{ending:?}");
        }
    }

    #[test]
    fn a_failed_removal_fails_a_finished_step_and_follows_the_failure_of_a_stopped_one() {
        let removal = format!(
            "\"docker\" \"rm\" \"--force\" \"{:064x}\" failed with exit status: 1:\nError: busy",
            1
        );
        let mut host = FakeHost::new();
        host.fail("\"rm\"", Fault::Exit(1, "Error: busy\n"));
        assert_eq!(lake(&mut host), Err(Failure::new(removal.clone())));
        let mut host = FakeHost::new();
        host.fail("\"rm\"", Fault::Exit(1, "Error: busy\n"));
        host.ends("\"lake\"", Ends::Exit(124));
        assert_eq!(
            lake(&mut host),
            Err(Failure::inconclusive(format!(
                "`lake build --wfail` stopped at the time limit of 900 seconds with exit code 124\n{removal}"
            )))
        );
        let mut host = FakeHost::new();
        host.fail("\"rm\"", Fault::Exit(1, "Error: busy\n"));
        host.ends("\"lake\"", Ends::Exit(1));
        assert_eq!(
            lake(&mut host),
            Err(Failure::new(format!(
                "`lake build --wfail` failed with exit code 1 in its container\n{removal}"
            )))
        );
    }

    #[test]
    fn a_container_that_never_ran_or_never_reported_fails_the_step_and_still_goes() {
        let id = format!("{:064x}", 1);
        let mut host = FakeHost::new();
        host.fail(
            "\"start\"",
            Fault::Exit(125, "Error response from daemon\n"),
        );
        assert_eq!(
            lake(&mut host),
            Err(Failure::new(format!(
                "The container {id} of `lake build --wfail` ended in the state `created false 0`"
            )))
        );
        assert_eq!(host.transcript(), lines(SHOWN));
        assert_eq!(host.containers(), 0);

        let mut host = FakeHost::new();
        host.fail("\"start\"", Fault::Missing);
        assert_eq!(
            lake(&mut host),
            Err(Failure::new(format!(
                "Start \"docker\" \"start\" \"--attach\" \"{id}\": no such program"
            )))
        );
        assert_eq!(host.transcript().len(), 4);
        assert_eq!(host.containers(), 0);

        let mut host = FakeHost::new();
        host.fail("\"inspect\"", Fault::Exit(1, "Error: gone\n"));
        assert_eq!(
            lake(&mut host),
            Err(Failure::new(format!(
                "\"docker\" \"inspect\" \"--format\" \"{{{{.State.Status}}}} {{{{.State.OOMKilled}}}} {{{{.State.ExitCode}}}}\" \"{id}\" failed with exit status: 1:\nError: gone"
            )))
        );
        assert_eq!(host.containers(), 0);

        let mut host = FakeHost::new();
        host.fail("\"logs\"", Fault::Garbled);
        let read = step(
            &mut host,
            Toolset::Rust,
            "cargo kani",
            Reading::ShownThenRead,
            &[0],
        );
        assert!(
            read.as_ref()
                .is_err_and(|failure| failure.to_string().starts_with(&format!(
                    "Read the output of \"docker\" \"logs\" \"{id}\": "
                ))),
            "{read:?}"
        );
        assert_eq!(host.containers(), 0);
    }

    #[test]
    fn a_failure_before_a_container_exists_removes_nothing() {
        let mut host = FakeHost::new();
        host.fail("\"create\"", Fault::Exit(125, "Error: no such image\n"));
        let refused = lake(&mut host);
        assert!(
            refused.as_ref().is_err_and(|failure| failure
                .to_string()
                .ends_with("\"lake\" \"build\" \"--wfail\" failed with exit status: 125:\nError: no such image")),
            "{refused:?}"
        );
        assert_eq!(host.transcript().len(), 2);
        let mut host = FakeHost::new();
        host.fail("\"create\"", Fault::Garbled);
        assert!(lake(&mut host).is_err());
        assert_eq!(host.transcript().len(), 2);
        let mut host = FakeHost::new();
        host.fail("\"create\"", Fault::Missing);
        assert!(lake(&mut host).is_err_and(|failure| {
            failure
                .to_string()
                .starts_with("Start \"docker\" \"create\"")
        }));
    }

    #[test]
    fn an_image_is_built_from_its_dockerfile_directory_and_named_by_its_identifier() {
        let mut host = FakeHost::new();
        let root = Path::new(ROOT);
        assert_eq!(
            build(&mut host, root, Toolset::Lean),
            Ok(Image {
                id: IMAGE.to_owned(),
                toolset: Toolset::Lean
            })
        );
        assert_eq!(
            host.transcript(),
            [
                "capture \"docker\" \"build\" \"--quiet\" \"--tag\" \"gymemo-lean:proofs\" \"/repo/xtask/proofs/lean\""
            ]
        );
        for printed in [
            "Successfully built 0123456789ab",
            "sha256:0123",
            "sha256:0123456789ABCDEF0123456789abcdef0123456789abcdef0123456789abcdef",
            "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdeg",
            "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0",
            "",
        ] {
            let mut host = FakeHost::new();
            host.prints("\"build\"", printed);
            assert_eq!(
                build(&mut host, root, Toolset::Rust),
                Err(Failure::new(format!(
                    "docker build printed no image identifier for /repo/xtask/proofs/rust: {printed}"
                ))),
                "{printed}"
            );
        }
        let mut host = FakeHost::new();
        host.fail("\"build\"", Fault::Exit(1, "ERROR: failed to solve\n"));
        assert_eq!(
            build(&mut host, root, Toolset::Rust),
            Err(Failure::new(
                "\"docker\" \"build\" \"--quiet\" \"--tag\" \"gymemo-rust:proofs\" \"/repo/xtask/proofs/rust\" failed with exit status: 1:\nERROR: failed to solve"
            ))
        );
    }

    #[test]
    fn the_state_of_a_container_reads_as_its_ending() {
        for (state, expected) in [
            ("exited false 0", Some(Ending::Exit(0))),
            ("exited false 0\n", Some(Ending::Exit(0))),
            ("exited false 1", Some(Ending::Exit(1))),
            ("exited false 2", Some(Ending::Exit(2))),
            ("exited false 123", Some(Ending::Exit(123))),
            ("exited false 125", Some(Ending::Exit(125))),
            ("exited false 136", Some(Ending::Exit(136))),
            ("exited false 138", Some(Ending::Exit(138))),
            ("exited false 124", Some(Ending::TimeLimit(124))),
            ("exited false 137", Some(Ending::TimeLimit(137))),
            ("exited true 137", Some(Ending::MemoryLimit)),
            ("exited true 1", Some(Ending::MemoryLimit)),
            ("exited true 0", Some(Ending::MemoryLimit)),
            ("created false 0", None),
            ("running false 0", None),
            ("exited maybe 0", None),
            ("exited false", None),
            ("exited false 0 0", None),
            ("exited false zero", None),
            ("", None),
        ] {
            assert_eq!(ending(state), expected, "{state:?}");
        }
    }
}
