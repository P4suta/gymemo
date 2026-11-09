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

pub struct FakeHost {
    transcript: Vec<String>,
    started: usize,
    faults: BTreeMap<usize, Fault>,
    rules: Vec<(&'static str, Fault)>,
    directories: BTreeMap<PathBuf, BTreeSet<String>>,
    uncreatable: BTreeSet<PathBuf>,
    unlistable: BTreeSet<PathBuf>,
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

    pub fn refuse_creating(&mut self, path: &str) {
        self.uncreatable.insert(PathBuf::from(path));
    }

    pub fn refuse_listing(&mut self, path: &str) {
        self.unlistable.insert(PathBuf::from(path));
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

    /// What a program without a fault does and prints.
    fn succeed(&mut self, words: &[&str]) -> Output {
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
            _ => ended(0, "", ""),
        }
    }
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
        }
        let result = match fault {
            Some(fault) => fault.outcome()?,
            None => self.succeed(&words),
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
            || path
                .parent()
                .zip(path.file_name())
                .is_some_and(|(directory, name)| {
                    self.directories
                        .get(directory)
                        .is_some_and(|names| names.contains(name.to_string_lossy().as_ref()))
                })
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
