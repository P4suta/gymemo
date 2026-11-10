//! A recording fake of the host.
//!
//! It keeps every program and directory call in one transcript, and it stands in for the simulator, the build, and the files of a run.
//! It keeps the messages for the standard output and the standard error in two lists of their own.
//! A setting of its simulator changes only when the command for that setting succeeds, so a test reads which settings a run left behind.

use super::{Host, Invocation, Streams};
use std::{
    collections::{BTreeMap, BTreeSet},
    io, iter,
    os::unix::process::ExitStatusExt,
    path::{Path, PathBuf},
    process::{ExitStatus, Output},
};

/// The identifier of the dedicated simulator in the listing that the fake prints.
pub const DEVICE: &str = "AAAAAAAA-0000-4000-8000-0123456789AB";
/// The identifier that the fake's `simctl create` prints.
pub const CREATED: &str = "BBBBBBBB-1111-4111-8111-0123456789AB";

const LISTING: &str = "== Devices ==\n-- iOS 27.0 --\n    gymemo checks (AAAAAAAA-0000-4000-8000-0123456789AB) (Shutdown) \n-- iOS 27.1 --\n    gymemo checks (9B2E7D10-AAAA-4BBB-8CCC-0123456789AB) (Booted) \n";

/// The image identifier that the fake's `docker build --quiet` prints.
pub const IMAGE: &str = "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

/// How the command of a container ends.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Ending {
    /// The command exits with this code.
    Exit(i32),
    /// The kernel stops a process of the container at the memory limit, and the container then exits with this code.
    OutOfMemory(i32),
}

/// A container that `docker create` made and that no `docker rm` removed yet.
struct Container {
    /// The command line of `docker create`, which holds the command of the container.
    line: String,
    /// The exit code, and whether the memory limit stopped a process, once the container ran.
    ended: Option<(i32, bool)>,
}

/// The way one program goes wrong.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Fault {
    /// The program ends with this exit code after it wrote this text to its standard error.
    Exit(i32, &'static str),
    /// This signal ends the program.
    Signal(i32),
    /// The program doesn't start.
    Missing,
    /// The program succeeds and prints bytes that aren't text.
    Garbled,
}

impl Fault {
    fn outcome(self) -> io::Result<Output> {
        match self {
            Fault::Exit(code, error) => Ok(ended(code << 8, "", error)),
            Fault::Signal(signal) => Ok(ended(signal, "", "")),
            Fault::Missing => Err(io::Error::new(io::ErrorKind::NotFound, "no such program")),
            Fault::Garbled => Ok(Output {
                stdout: vec![0xff],
                ..ended(0, "", "")
            }),
        }
    }
}

/// The output of a program whose wait status is `status`.
fn ended(status: i32, output: &str, error: &str) -> Output {
    Output {
        status: ExitStatus::from_raw(status),
        stdout: output.as_bytes().to_vec(),
        stderr: error.as_bytes().to_vec(),
    }
}

fn refused() -> io::Error {
    io::Error::new(io::ErrorKind::PermissionDenied, "no permission")
}

fn missing_file() -> io::Error {
    io::Error::new(io::ErrorKind::NotFound, "no such file")
}

pub struct FakeHost {
    transcript: Vec<String>,
    started: usize,
    faults: BTreeMap<usize, Fault>,
    rules: Vec<(&'static str, Fault)>,
    directories: BTreeMap<PathBuf, BTreeSet<String>>,
    uncreatable: BTreeSet<PathBuf>,
    unlistable: BTreeSet<PathBuf>,
    unremovable: BTreeSet<PathBuf>,
    files: BTreeMap<PathBuf, String>,
    printed: Vec<(String, String)>,
    written: Vec<(String, PathBuf, String)>,
    endings: Vec<(String, Ending)>,
    containers: BTreeMap<String, Container>,
    made: usize,
    /// What `simctl list devices` prints.
    pub listing: String,
    /// What `simctl create` prints.
    pub created: String,
    /// The interface style that the simulator shows, which no run has set at the start.
    pub appearance: String,
    /// The Increase Contrast setting of the simulator, which no run has set at the start.
    pub contrast: String,
    /// The display settings and the test selection of each `xcodebuild test`, in the order of the runs.
    pub passes: Vec<String>,
    /// The applications that `open` finds, by the name or the bundle identifier that `open` receives.
    pub applications: Vec<&'static str>,
    /// The files that an export writes, by the name of the result bundle.
    pub attachments: BTreeMap<&'static str, Vec<&'static str>>,
    /// The messages written to the standard output, in their order.
    pub output: Vec<String>,
    /// The messages written to the standard error, in their order.
    pub errors: Vec<String>,
}

impl FakeHost {
    /// A host whose simulator exists, whose programs all succeed, and whose directories are all missing.
    pub fn new() -> Self {
        Self {
            transcript: Vec::new(),
            started: 0,
            faults: BTreeMap::new(),
            rules: Vec::new(),
            directories: BTreeMap::new(),
            uncreatable: BTreeSet::new(),
            unlistable: BTreeSet::new(),
            unremovable: BTreeSet::new(),
            files: BTreeMap::new(),
            printed: Vec::new(),
            written: Vec::new(),
            endings: Vec::new(),
            containers: BTreeMap::new(),
            made: 0,
            listing: LISTING.to_owned(),
            created: format!("{CREATED}\n"),
            appearance: "unset".to_owned(),
            contrast: "unset".to_owned(),
            passes: Vec::new(),
            applications: vec!["Simulator", "com.apple.dt.Devices"],
            attachments: BTreeMap::new(),
            output: Vec::new(),
            errors: Vec::new(),
        }
    }

    /// Makes the program at this position among the started programs go wrong, where the first program has position 0.
    pub fn fail_at(&mut self, position: usize, fault: Fault) {
        self.faults.insert(position, fault);
    }

    /// Makes each program whose command line holds `part` go wrong.
    pub fn fail(&mut self, part: &'static str, fault: Fault) {
        self.rules.push((part, fault));
    }

    /// Adds a directory that holds `names`.
    pub fn directory(&mut self, path: &str, names: &[&str]) {
        self.directories.insert(
            PathBuf::from(path),
            names.iter().map(|name| (*name).to_owned()).collect(),
        );
    }

    /// Adds a file that holds `text`.
    pub fn file(&mut self, path: &str, text: &str) {
        self.files.insert(PathBuf::from(path), text.to_owned());
    }

    /// Makes each program, or the command of each container, whose command line holds `part` print `text` to its standard output.
    /// Of the rules that match a command line, the one added last decides, so a test can replace a rule of a prepared host.
    pub fn prints(&mut self, part: &str, text: &str) {
        self.printed.push((part.to_owned(), text.to_owned()));
    }

    /// Makes each program, or the command of each container, whose command line holds `part` write `text` to `path`.
    /// A program writes even when it fails, as long as it starts.
    pub fn writes(&mut self, part: &str, path: &str, text: &str) {
        self.written
            .push((part.to_owned(), PathBuf::from(path), text.to_owned()));
    }

    /// Makes the command of each container whose command line holds `part` end this way, where every other command exits with 0.
    /// Of the rules that match a command line, the one added last decides.
    pub fn ends(&mut self, part: &str, ending: Ending) {
        self.endings.push((part.to_owned(), ending));
    }

    /// The number of containers that exist.
    pub fn containers(&self) -> usize {
        self.containers.len()
    }

    pub fn refuse_creating(&mut self, path: &str) {
        self.uncreatable.insert(PathBuf::from(path));
    }

    pub fn refuse_listing(&mut self, path: &str) {
        self.unlistable.insert(PathBuf::from(path));
    }

    pub fn refuse_removing(&mut self, path: &str) {
        self.unremovable.insert(PathBuf::from(path));
    }

    /// Every call so far, one line for each.
    pub fn transcript(&self) -> &[String] {
        &self.transcript
    }

    /// Keeps the result bundle that `xcodebuild test` leaves once it starts, even when its tests fail.
    fn leave_bundle(&mut self, words: &[&str]) {
        let ["xcodebuild", "test", options @ ..] = words else {
            return;
        };
        let bundle = options
            .iter()
            .skip_while(|option| **option != "-resultBundlePath")
            .nth(1)
            .map(Path::new);
        if let Some((directory, name)) =
            bundle.and_then(|bundle| bundle.parent().zip(bundle.file_name()))
        {
            self.directories
                .entry(directory.to_owned())
                .or_default()
                .insert(name.to_string_lossy().into_owned());
        }
    }

    /// What a program without a fault does and prints, where `line` is its command line.
    fn succeed(&mut self, words: &[&str], line: &str) -> Output {
        match words {
            ["xcrun", "simctl", "list", "devices"] => ended(0, &self.listing, ""),
            ["xcrun", "simctl", "create", ..] => ended(0, &self.created, ""),
            ["xcrun", "simctl", "ui", _, "appearance", style] => {
                self.appearance = (*style).to_owned();
                ended(0, "", "")
            }
            ["xcrun", "simctl", "ui", _, "increase_contrast", contrast] => {
                self.contrast = (*contrast).to_owned();
                ended(0, "", "")
            }
            ["xcodebuild", "test", options @ ..] => {
                let selection = options
                    .iter()
                    .filter(|option| option.contains("-testing:"))
                    .copied()
                    .collect::<Vec<_>>();
                self.passes.push(format!(
                    "{} {}: {}",
                    self.appearance,
                    self.contrast,
                    selection.join(" ")
                ));
                ended(0, "", "")
            }
            [
                "xcrun",
                "xcresulttool",
                "export",
                "attachments",
                "--path",
                bundle,
                "--output-path",
                directory,
                ..,
            ] => {
                let written = Path::new(bundle)
                    .file_name()
                    .and_then(|name| self.attachments.get(&*name.to_string_lossy()))
                    .cloned()
                    .unwrap_or_default();
                self.directories
                    .entry(PathBuf::from(directory))
                    .or_default()
                    .extend(written.into_iter().map(str::to_owned));
                ended(0, "", "")
            }
            ["open", _, application] if !self.applications.contains(application) => {
                ended(1 << 8, "", "Unable to find application\n")
            }
            ["docker", "build", ..] => {
                let image = self.output_of(line).unwrap_or(IMAGE).to_owned();
                ended(0, &format!("{image}\n"), "")
            }
            ["docker", "create", ..] => {
                self.made += 1;
                let id = format!("{:064x}", self.made);
                self.containers.insert(
                    id.clone(),
                    Container {
                        line: line.to_owned(),
                        ended: None,
                    },
                );
                ended(0, &format!("{id}\n"), "")
            }
            ["docker", "start", "--attach", id] => self.start(id),
            ["docker", "inspect", "--format", _, id] => match self.containers.get(*id) {
                Some(Container {
                    ended: Some((code, out_of_memory)),
                    ..
                }) => ended(0, &format!("exited {out_of_memory} {code}\n"), ""),
                Some(_) => ended(0, "created false 0\n", ""),
                None => no_such_container(),
            },
            ["docker", "logs", id] => match self.containers.get(*id) {
                Some(container) => ended(0, self.output_of(&container.line).unwrap_or(""), ""),
                None => no_such_container(),
            },
            ["docker", "rm", "--force", id] => match self.containers.remove(*id) {
                Some(_) => ended(0, &format!("{id}\n"), ""),
                None => no_such_container(),
            },
            _ => ended(0, self.output_of(line).unwrap_or(""), ""),
        }
    }

    /// What a program prints by the rule added last among the rules whose part `line` holds.
    fn output_of(&self, line: &str) -> Option<&str> {
        self.printed
            .iter()
            .rev()
            .find(|(part, _)| line.contains(part))
            .map(|(_, text)| text.as_str())
    }

    /// Writes the file of every rule whose part `line` holds.
    fn write_files(&mut self, line: &str) {
        for (part, path, text) in &self.written {
            if line.contains(part) {
                self.files.insert(path.clone(), text.clone());
            }
        }
    }

    /// Runs the command of the container `id`, which ends as its rule says, and keeps that end for `docker inspect`.
    fn start(&mut self, id: &str) -> Output {
        let Some(line) = self
            .containers
            .get(id)
            .map(|container| container.line.clone())
        else {
            return no_such_container();
        };
        let ending = self
            .endings
            .iter()
            .rev()
            .find(|(part, _)| line.contains(part))
            .map_or(Ending::Exit(0), |(_, ending)| *ending);
        let (code, out_of_memory) = match ending {
            Ending::Exit(code) => (code, false),
            Ending::OutOfMemory(code) => (code, true),
        };
        if let Some(container) = self.containers.get_mut(id) {
            container.ended = Some((code, out_of_memory));
        }
        self.write_files(&line);
        ended(code << 8, self.output_of(&line).unwrap_or(""), "")
    }
}

/// What Docker answers about a container that doesn't exist.
fn no_such_container() -> Output {
    ended(1 << 8, "", "Error: No such container\n")
}

impl Host for FakeHost {
    fn run(&mut self, invocation: &Invocation, streams: Streams) -> io::Result<Output> {
        let line = invocation.to_string();
        let verb = match streams {
            Streams::Captured => "capture",
            Streams::Shown => "show",
            Streams::ShownWithoutErrors => "show-without-errors",
        };
        self.transcript.push(format!("{verb} {line}"));
        let position = self.started;
        self.started += 1;
        let words = iter::once(invocation.program.to_owned())
            .chain(
                invocation
                    .arguments
                    .iter()
                    .map(|argument| argument.to_string_lossy().into_owned()),
            )
            .collect::<Vec<_>>();
        let words = words.iter().map(String::as_str).collect::<Vec<_>>();
        let fault = self.faults.get(&position).copied().or_else(|| {
            self.rules
                .iter()
                .find(|(part, _)| line.contains(part))
                .map(|(_, fault)| *fault)
        });
        if fault != Some(Fault::Missing) {
            self.leave_bundle(&words);
            // A container writes its files when it starts, so a Docker command line writes nothing here.
            if words.first() != Some(&"docker") {
                self.write_files(&line);
            }
        }
        let result = match fault {
            Some(fault) => fault.outcome()?,
            None => self.succeed(&words, &line),
        };
        // Only a captured program hands its output to the caller.
        Ok(match streams {
            Streams::Captured => result,
            Streams::Shown | Streams::ShownWithoutErrors => Output {
                status: result.status,
                stdout: Vec::new(),
                stderr: Vec::new(),
            },
        })
    }

    fn create_directories(&mut self, directory: &Path) -> io::Result<()> {
        self.transcript
            .push(format!("create {}", directory.display()));
        if self.uncreatable.contains(directory) {
            return Err(refused());
        }
        self.directories.entry(directory.to_owned()).or_default();
        Ok(())
    }

    fn list(&mut self, directory: &Path) -> io::Result<Vec<String>> {
        self.transcript
            .push(format!("list {}", directory.display()));
        if self.unlistable.contains(directory) {
            return Err(refused());
        }
        self.directories
            .get(directory)
            .map(|names| names.iter().cloned().collect())
            .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "no such directory"))
    }

    fn exists(&mut self, path: &Path) -> bool {
        self.transcript.push(format!("exists {}", path.display()));
        self.directories.contains_key(path)
            || self.files.contains_key(path)
            || path
                .parent()
                .zip(path.file_name())
                .is_some_and(|(directory, name)| {
                    self.directories
                        .get(directory)
                        .is_some_and(|names| names.contains(name.to_string_lossy().as_ref()))
                })
    }

    fn read(&mut self, file: &Path) -> io::Result<String> {
        self.transcript.push(format!("read {}", file.display()));
        self.files.get(file).cloned().ok_or_else(missing_file)
    }

    fn files(&mut self, directory: &Path) -> io::Result<Vec<PathBuf>> {
        self.transcript
            .push(format!("files {}", directory.display()));
        let found = self
            .files
            .keys()
            .filter(|file| file.starts_with(directory))
            .cloned()
            .collect::<Vec<_>>();
        if found.is_empty() && !self.directories.contains_key(directory) {
            return Err(io::Error::new(io::ErrorKind::NotFound, "no such directory"));
        }
        Ok(found)
    }

    fn remove_file(&mut self, file: &Path) -> io::Result<()> {
        self.transcript.push(format!("remove {}", file.display()));
        if self.unremovable.contains(file) {
            return Err(refused());
        }
        self.files.remove(file).map(|_| ()).ok_or_else(missing_file)
    }

    fn print(&mut self, message: &str) {
        self.output.push(message.to_owned());
    }

    fn print_error(&mut self, message: &str) {
        self.errors.push(message.to_owned());
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::host::Local;

    fn shell(script: &'static str) -> Invocation {
        Invocation::new("sh").args(["-c", script])
    }

    #[test]
    fn each_fault_ends_a_program_as_the_real_host_reports_that_end() -> io::Result<()> {
        let exited = Local.run(&shell("printf gone >&2; exit 3"), Streams::Captured)?;
        assert_eq!(Fault::Exit(3, "gone").outcome()?, exited);
        let killed = Local.run(&shell("kill -9 $$"), Streams::Captured)?;
        assert_eq!(Fault::Signal(9).outcome()?, killed);
        let missing = Local.run(
            &Invocation::new("gymemo-no-such-program"),
            Streams::Captured,
        );
        assert_eq!(
            Fault::Missing.outcome().map_err(|error| error.kind()).err(),
            missing.map_err(|error| error.kind()).err()
        );
        let garbled = Local.run(&shell("printf '\\377'"), Streams::Captured)?;
        assert_eq!(Fault::Garbled.outcome()?, garbled);
        Ok(())
    }

    fn docker(arguments: &[&str]) -> Invocation {
        Invocation::new("docker").args(arguments)
    }

    fn text(result: &Output) -> (Option<i32>, String) {
        (
            result.status.code(),
            String::from_utf8_lossy(&result.stdout).into_owned(),
        )
    }

    /// The fake container follows a probe of Docker 29.8.
    /// There `start --attach` exits with the code of the container, and `inspect` reports `created` before the start.
    /// The memory limit sets `OOMKilled` there whatever the exit code.
    #[test]
    fn a_container_runs_once_reports_its_end_and_leaves_with_its_removal() -> io::Result<()> {
        let mut host = FakeHost::new();
        host.ends("\"lake\" \"build\"", Ending::Exit(3));
        host.ends("\"dd\"", Ending::OutOfMemory(1));
        host.prints("\"lake\" \"build\"", "built\n");
        host.writes("\"lake\" \"build\"", "/repo/out.txt", "written");
        let image = host.run(
            &docker(&["build", "--quiet", "/repo/lean"]),
            Streams::Captured,
        )?;
        assert_eq!(text(&image), (Some(0), format!("{IMAGE}\n")));
        let created = host.run(
            &docker(&["create", "--network", "none", IMAGE, "lake", "build"]),
            Streams::Captured,
        )?;
        let first = format!("{:064x}", 1);
        assert_eq!(text(&created), (Some(0), format!("{first}\n")));
        assert_eq!(host.containers(), 1);
        let state = |host: &mut FakeHost, id: &str| {
            host.run(
                &docker(&["inspect", "--format", "{{.State}}", id]),
                Streams::Captured,
            )
            .map(|result| text(&result))
        };
        assert_eq!(
            state(&mut host, &first)?,
            (Some(0), "created false 0\n".to_owned())
        );
        assert!(!host.exists(Path::new("/repo/out.txt")));
        let started = host.run(&docker(&["start", "--attach", &first]), Streams::Captured)?;
        assert_eq!(text(&started), (Some(3), "built\n".to_owned()));
        assert_eq!(host.read(Path::new("/repo/out.txt"))?, "written");
        assert_eq!(
            state(&mut host, &first)?,
            (Some(0), "exited false 3\n".to_owned())
        );
        let logs = host.run(&docker(&["logs", &first]), Streams::Captured)?;
        assert_eq!(text(&logs), (Some(0), "built\n".to_owned()));
        let shown = host.run(&docker(&["start", "--attach", &first]), Streams::Shown)?;
        assert_eq!(text(&shown), (Some(3), String::new()));

        let second = format!("{:064x}", 2);
        host.run(
            &docker(&["create", IMAGE, "dd", "bs=3G"]),
            Streams::Captured,
        )?;
        host.run(&docker(&["start", "--attach", &second]), Streams::Shown)?;
        assert_eq!(
            state(&mut host, &second)?,
            (Some(0), "exited true 1\n".to_owned())
        );
        assert_eq!(host.containers(), 2);
        for id in [&first, &second] {
            let removed = host.run(&docker(&["rm", "--force", id]), Streams::Captured)?;
            assert_eq!(removed.status.code(), Some(0));
        }
        assert_eq!(host.containers(), 0);
        for gone in [
            docker(&["rm", "--force", &first]),
            docker(&["start", "--attach", &first]),
            docker(&["logs", &first]),
            docker(&["inspect", "--format", "{{.State}}", &first]),
        ] {
            let result = host.run(&gone, Streams::Captured)?;
            assert_eq!(
                (
                    result.status.code(),
                    String::from_utf8_lossy(&result.stderr).into_owned()
                ),
                (Some(1), "Error: No such container\n".to_owned()),
                "{gone}"
            );
        }
        Ok(())
    }

    #[test]
    fn a_program_prints_and_writes_by_its_rules_and_a_fault_still_writes() -> io::Result<()> {
        let mut host = FakeHost::new();
        host.prints("\"run\"", "report written\n");
        host.writes("\"run\"", "/repo/report.json", "{}");
        let tool = Invocation::new("swift-mutation-testing").arg("run");
        let result = host.run(&tool, Streams::Captured)?;
        assert_eq!(text(&result), (Some(0), "report written\n".to_owned()));
        assert_eq!(host.read(Path::new("/repo/report.json"))?, "{}");
        host.remove_file(Path::new("/repo/report.json"))?;
        assert!(!host.exists(Path::new("/repo/report.json")));
        host.fail("\"run\"", Fault::Exit(2, "gate"));
        assert_eq!(host.run(&tool, Streams::Captured)?.status.code(), Some(2));
        assert!(host.exists(Path::new("/repo/report.json")));
        host.remove_file(Path::new("/repo/report.json"))?;
        host.fail_at(2, Fault::Missing);
        assert!(host.run(&tool, Streams::Captured).is_err());
        assert!(!host.exists(Path::new("/repo/report.json")));
        Ok(())
    }

    #[test]
    fn files_are_read_found_under_their_directories_and_removed() -> io::Result<()> {
        let mut host = FakeHost::new();
        host.file("/repo/src/main.rs", "fn main() {}");
        host.file("/repo/src/host/fake.rs", "");
        host.file("/repo/srcs/other.rs", "");
        host.directory("/repo/empty", &[]);
        assert_eq!(
            host.files(Path::new("/repo/src"))?,
            ["/repo/src/host/fake.rs", "/repo/src/main.rs"].map(PathBuf::from)
        );
        assert_eq!(host.files(Path::new("/repo/empty"))?, Vec::<PathBuf>::new());
        let kind = |result: io::Result<Vec<PathBuf>>| result.map_err(|error| error.kind());
        assert_eq!(
            kind(host.files(Path::new("/repo/missing"))),
            Err(io::ErrorKind::NotFound)
        );
        assert_eq!(host.read(Path::new("/repo/src/main.rs"))?, "fn main() {}");
        assert!(host.exists(Path::new("/repo/src/main.rs")));
        host.remove_file(Path::new("/repo/src/main.rs"))?;
        assert!(!host.exists(Path::new("/repo/src/main.rs")));
        assert_eq!(
            host.read(Path::new("/repo/src/main.rs"))
                .map_err(|error| error.kind()),
            Err(io::ErrorKind::NotFound)
        );
        assert_eq!(
            host.remove_file(Path::new("/repo/src/main.rs"))
                .map_err(|error| error.kind()),
            Err(io::ErrorKind::NotFound)
        );
        assert_eq!(
            host.transcript(),
            [
                "files /repo/src",
                "files /repo/empty",
                "files /repo/missing",
                "read /repo/src/main.rs",
                "exists /repo/src/main.rs",
                "remove /repo/src/main.rs",
                "exists /repo/src/main.rs",
                "read /repo/src/main.rs",
                "remove /repo/src/main.rs"
            ]
        );
        Ok(())
    }

    #[test]
    fn a_refused_removal_keeps_the_file() -> io::Result<()> {
        let mut host = FakeHost::new();
        host.file("/repo/kept.json", "{}");
        host.file("/repo/gone.json", "{}");
        host.refuse_removing("/repo/kept.json");
        assert_eq!(
            host.remove_file(Path::new("/repo/kept.json"))
                .map_err(|error| error.kind()),
            Err(io::ErrorKind::PermissionDenied)
        );
        assert_eq!(host.read(Path::new("/repo/kept.json"))?, "{}");
        host.remove_file(Path::new("/repo/gone.json"))?;
        assert!(!host.exists(Path::new("/repo/gone.json")));
        Ok(())
    }

    #[test]
    fn the_fake_hands_over_output_only_when_the_caller_captures_it() -> io::Result<()> {
        let listing = Invocation::new("xcrun").args(["simctl", "list", "devices"]);
        let mut host = FakeHost::new();
        let captured = host.run(&listing, Streams::Captured)?;
        assert_eq!(String::from_utf8_lossy(&captured.stdout), LISTING);
        let shown = host.run(&listing, Streams::Shown)?;
        assert!(shown.status.success());
        assert_eq!((shown.stdout, shown.stderr), (Vec::new(), Vec::new()));
        Ok(())
    }
}
