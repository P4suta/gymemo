//! The programs, directories, and output streams that a command reaches, behind one port.
//!
//! A command decides which programs start, in which order, what follows a failure, and what it writes for the developer.
//! A test hands it a recording fake, and `main` hands it the adapter over the standard library.

use std::{
    ffi::OsString,
    fmt, fs, io,
    path::{Path, PathBuf},
    process::{Command, Output, Stdio},
};

#[cfg(test)]
pub mod fake;

/// Where the output of a program goes while the program runs.
#[derive(Clone, Copy, Debug)]
pub enum Streams {
    /// The caller receives the standard output and the standard error.
    Captured,
    /// The terminal shows the standard output and the standard error.
    Shown,
    /// The terminal shows the standard output, and the standard error goes nowhere.
    ShownWithoutErrors,
}

/// One program with its arguments and its working directory.
/// Its methods carry the names of `std::process::Command`, so a command line reads here as it reads there.
#[derive(Debug)]
pub struct Invocation {
    program: &'static str,
    arguments: Vec<OsString>,
    directory: Option<PathBuf>,
}

impl Invocation {
    pub fn new(program: &'static str) -> Self {
        Self {
            program,
            arguments: Vec::new(),
            directory: None,
        }
    }

    pub fn arg(mut self, argument: impl Into<OsString>) -> Self {
        self.arguments.push(argument.into());
        self
    }

    pub fn args<A: Into<OsString>>(mut self, arguments: impl IntoIterator<Item = A>) -> Self {
        self.arguments.extend(arguments.into_iter().map(Into::into));
        self
    }

    pub fn current_dir(mut self, directory: &Path) -> Self {
        self.directory = Some(directory.to_owned());
        self
    }

    /// The command of the standard library that starts this program.
    fn command(&self) -> Command {
        let mut command = Command::new(self.program);
        command.args(&self.arguments);
        if let Some(directory) = &self.directory {
            command.current_dir(directory);
        }
        command
    }
}

/// Writes the command line as `std::process::Command` describes itself, which is the text that a failed step reports.
impl fmt::Display for Invocation {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "{:?}", self.command())
    }
}

/// What a command needs from outside the process.
pub trait Host {
    /// Runs the program, waits for its end, and returns its exit status with the output that `streams` captured.
    fn run(&mut self, invocation: &Invocation, streams: Streams) -> io::Result<Output>;

    /// Creates `directory` and each missing parent directory.
    fn create_directories(&mut self, directory: &Path) -> io::Result<()>;

    /// The names in `directory`.
    fn list(&mut self, directory: &Path) -> io::Result<Vec<String>>;

    /// Whether a file or a directory stands at `path`.
    fn exists(&mut self, path: &Path) -> bool;

    /// The text of `file`, which must be UTF-8.
    fn read(&mut self, file: &Path) -> io::Result<String>;

    /// Every file under `directory` at any depth, in path order, without the directories.
    fn files(&mut self, directory: &Path) -> io::Result<Vec<PathBuf>>;

    /// Removes `file`, which must exist and must not be a directory.
    fn remove_file(&mut self, file: &Path) -> io::Result<()>;

    /// Writes `message` and a line break to the standard output.
    fn print(&mut self, message: &str);

    /// Writes `message` and a line break to the standard error.
    fn print_error(&mut self, message: &str);
}

/// Adds every file under `directory` to `found`, descending into each directory below it.
fn walk(directory: &Path, found: &mut Vec<PathBuf>) -> io::Result<()> {
    for entry in fs::read_dir(directory)? {
        let path = entry?.path();
        if path.is_dir() {
            walk(&path, found)?;
        } else {
            found.push(path);
        }
    }
    Ok(())
}

/// The machine that runs this command, reached through the standard library.
pub struct Local;

impl Host for Local {
    fn run(&mut self, invocation: &Invocation, streams: Streams) -> io::Result<Output> {
        let mut command = invocation.command();
        let shown = |status| Output {
            status,
            stdout: Vec::new(),
            stderr: Vec::new(),
        };
        match streams {
            Streams::Captured => command.output(),
            Streams::Shown => command.status().map(shown),
            Streams::ShownWithoutErrors => command.stderr(Stdio::null()).status().map(shown),
        }
    }

    fn create_directories(&mut self, directory: &Path) -> io::Result<()> {
        fs::create_dir_all(directory)
    }

    fn list(&mut self, directory: &Path) -> io::Result<Vec<String>> {
        fs::read_dir(directory)?
            .map(|entry| Ok(entry?.file_name().to_string_lossy().into_owned()))
            .collect()
    }

    fn exists(&mut self, path: &Path) -> bool {
        path.exists()
    }

    fn read(&mut self, file: &Path) -> io::Result<String> {
        fs::read_to_string(file)
    }

    fn files(&mut self, directory: &Path) -> io::Result<Vec<PathBuf>> {
        let mut found = Vec::new();
        walk(directory, &mut found)?;
        found.sort();
        Ok(found)
    }

    fn remove_file(&mut self, file: &Path) -> io::Result<()> {
        fs::remove_file(file)
    }

    fn print(&mut self, message: &str) {
        println!("{message}");
    }

    fn print_error(&mut self, message: &str) {
        eprintln!("{message}");
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::scratch::Scratch;
    use std::{env, os::unix::fs::MetadataExt};

    const EVERY_STREAMS: [Streams; 3] = [
        Streams::Captured,
        Streams::Shown,
        Streams::ShownWithoutErrors,
    ];

    fn shell(script: &'static str) -> Invocation {
        Invocation::new("sh").args(["-c", script])
    }

    fn text(bytes: &[u8]) -> String {
        String::from_utf8_lossy(bytes).into_owned()
    }

    /// Whether two paths name one file.
    fn same_file(first: &str, second: &str) -> io::Result<bool> {
        let (first, second) = (fs::metadata(first)?, fs::metadata(second)?);
        Ok(first.dev() == second.dev() && first.ino() == second.ino())
    }

    #[test]
    fn a_command_line_reads_as_the_standard_library_writes_it() {
        assert_eq!(
            Invocation::new("xcrun")
                .args(["simctl", "list", "devices"])
                .to_string(),
            r#""xcrun" "simctl" "list" "devices""#
        );
        assert_eq!(
            Invocation::new("xcodebuild")
                .current_dir(Path::new("/repo"))
                .arg("build")
                .arg(Path::new("/repo/a b.app"))
                .args(vec!["-quiet".to_owned()])
                .to_string(),
            r#"cd "/repo" && "xcodebuild" "build" "/repo/a b.app" "-quiet""#
        );
    }

    #[test]
    fn the_exit_status_is_the_one_of_the_program() -> io::Result<()> {
        for streams in EVERY_STREAMS {
            assert!(
                Local
                    .run(&Invocation::new("true"), streams)?
                    .status
                    .success()
            );
            let failed = Local.run(&Invocation::new("false"), streams)?.status;
            assert_eq!((failed.success(), failed.code()), (false, Some(1)));
            assert_eq!(Local.run(&shell("exit 3"), streams)?.status.code(), Some(3));
        }
        Ok(())
    }

    #[test]
    fn captured_output_keeps_the_two_streams_apart() -> io::Result<()> {
        let result = Local.run(
            &shell("printf out; printf err >&2; exit 4"),
            Streams::Captured,
        )?;
        assert_eq!(result.status.code(), Some(4));
        assert_eq!(
            (text(&result.stdout), text(&result.stderr)),
            ("out".to_owned(), "err".to_owned())
        );
        Ok(())
    }

    #[test]
    fn each_argument_arrives_whole_and_in_order() -> io::Result<()> {
        let listed = Invocation::new("printf").args(["%s|", "a b", "", "é", "*.png"]);
        let result = Local.run(&listed, Streams::Captured)?;
        assert_eq!(text(&result.stdout), "a b||é|*.png|");
        Ok(())
    }

    #[test]
    fn a_program_runs_in_its_directory_or_in_the_one_of_the_caller() -> io::Result<()> {
        let scratch = Scratch::new("host-directory")?;
        let printed = |invocation: &Invocation| {
            Local
                .run(invocation, Streams::Captured)
                .map(|result| text(&result.stdout).trim_end().to_owned())
        };
        assert_eq!(
            printed(&shell("pwd -P").current_dir(scratch.path()))?,
            fs::canonicalize(scratch.path())?.display().to_string()
        );
        assert_eq!(
            printed(&shell("pwd -P"))?,
            fs::canonicalize(env::current_dir()?)?.display().to_string()
        );
        Ok(())
    }

    #[test]
    fn a_missing_program_fails_to_start() {
        for streams in EVERY_STREAMS {
            let started = Local.run(&Invocation::new("gymemo-no-such-program"), streams);
            assert_eq!(
                started.map_err(|error| error.kind()).err(),
                Some(io::ErrorKind::NotFound)
            );
        }
    }

    /// The program writes to both streams, and only a captured run hands that text back.
    /// The shown runs write it to the streams of this process, so a test run shows two short lines there.
    #[test]
    fn a_shown_program_hands_back_nothing_of_what_it_writes() -> io::Result<()> {
        let writer = shell("printf 'shown\\n'; printf 'error\\n' >&2");
        let captured = Local.run(&writer, Streams::Captured)?;
        assert_eq!(
            (text(&captured.stdout), text(&captured.stderr)),
            ("shown\n".to_owned(), "error\n".to_owned())
        );
        for streams in [Streams::Shown, Streams::ShownWithoutErrors] {
            let shown = Local.run(&writer, streams)?;
            assert!(shown.status.success(), "{streams:?}");
            assert_eq!(
                (shown.stdout, shown.stderr),
                (Vec::new(), Vec::new()),
                "{streams:?}"
            );
        }
        Ok(())
    }

    /// The standard error of a program shown without errors goes to `/dev/null` wherever this process writes.
    /// The other checks compare each shown stream with the stream of this process, and they tell the two apart only when this process writes to `/dev/null`.
    #[test]
    fn a_shown_program_writes_to_the_streams_of_the_caller_except_a_hidden_standard_error()
    -> io::Result<()> {
        let error_goes_nowhere = shell("test /dev/stderr -ef /dev/null");
        let output_goes_nowhere = shell("test /dev/stdout -ef /dev/null");
        // A caller whose own stream already goes nowhere hands that stream on, so the expectation follows the caller.
        let caller_error = same_file("/dev/stderr", "/dev/null")?;
        let caller_output = same_file("/dev/stdout", "/dev/null")?;
        let shown = Local.run(&error_goes_nowhere, Streams::Shown)?;
        assert_eq!(shown.status.success(), caller_error);
        assert_eq!(
            Local
                .run(&output_goes_nowhere, Streams::Shown)?
                .status
                .success(),
            caller_output
        );
        assert!(
            Local
                .run(&error_goes_nowhere, Streams::ShownWithoutErrors)?
                .status
                .success()
        );
        assert_eq!(
            Local
                .run(&output_goes_nowhere, Streams::ShownWithoutErrors)?
                .status
                .success(),
            caller_output
        );
        Ok(())
    }

    #[test]
    fn directories_are_created_with_their_parents_and_listed_by_name() -> io::Result<()> {
        let scratch = Scratch::new("host-directories")?;
        let nested = scratch.path().join("target/ui-test");
        assert!(!Local.exists(&nested));
        Local.create_directories(&nested)?;
        assert!(Local.exists(&nested));
        assert!(nested.is_dir());
        assert_eq!(Local.list(&nested)?, Vec::<String>::new());
        scratch.write("target/ui-test/run-2-dark.xcresult/Info.plist", "")?;
        scratch.write("target/ui-test/notes.txt", "")?;
        Local.create_directories(&nested)?;
        let mut names = Local.list(&nested)?;
        names.sort();
        assert_eq!(names, ["notes.txt", "run-2-dark.xcresult"]);
        assert!(Local.exists(&nested.join("notes.txt")));
        assert!(!Local.exists(&nested.join("run-3-dark.xcresult")));
        Ok(())
    }

    #[test]
    fn a_file_is_read_as_text_and_removed() -> io::Result<()> {
        let scratch = Scratch::new("host-files")?;
        scratch.write("target/mutation/report.json", "{\"é\": 1}\n")?;
        let report = scratch.path().join("target/mutation/report.json");
        assert_eq!(Local.read(&report)?, "{\"é\": 1}\n");
        Local.remove_file(&report)?;
        assert!(!report.exists());
        assert!(scratch.path().join("target/mutation").is_dir());
        let kinds = |result: io::Result<()>| result.map_err(|error| error.kind());
        assert_eq!(
            kinds(Local.remove_file(&report)),
            Err(io::ErrorKind::NotFound)
        );
        assert_eq!(
            kinds(Local.read(&report).map(|_| ())),
            Err(io::ErrorKind::NotFound)
        );
        fs::write(&report, [b'{', 0xff, b'}'])?;
        assert_eq!(
            kinds(Local.read(&report).map(|_| ())),
            Err(io::ErrorKind::InvalidData)
        );
        assert!(Local.remove_file(&scratch.path().join("target")).is_err());
        assert!(scratch.path().join("target/mutation").is_dir());
        Ok(())
    }

    #[test]
    fn the_files_under_a_directory_are_found_at_every_depth_in_path_order() -> io::Result<()> {
        let scratch = Scratch::new("host-walk")?;
        for file in [
            "src/main.rs",
            "src/host/fake.rs",
            "src/b.rs",
            "src/a/z/deep.rs",
        ] {
            scratch.write(file, "")?;
        }
        fs::create_dir_all(scratch.path().join("src/empty"))?;
        let found = Local.files(&scratch.path().join("src"))?;
        let relative = found
            .iter()
            .map(|file| file.strip_prefix(scratch.path()).map(Path::to_owned))
            .collect::<std::result::Result<Vec<_>, _>>()
            .map_err(io::Error::other)?;
        assert_eq!(
            relative,
            [
                "src/a/z/deep.rs",
                "src/b.rs",
                "src/host/fake.rs",
                "src/main.rs"
            ]
            .map(PathBuf::from)
        );
        assert_eq!(
            Local
                .files(&scratch.path().join("missing"))
                .map_err(|error| error.kind()),
            Err(io::ErrorKind::NotFound)
        );
        assert!(Local.files(&scratch.path().join("src/main.rs")).is_err());
        Ok(())
    }

    #[test]
    fn a_missing_directory_is_not_listed_and_a_file_holds_no_directory() -> io::Result<()> {
        let scratch = Scratch::new("host-refusals")?;
        let listed = Local.list(&scratch.path().join("missing"));
        assert_eq!(
            listed.map_err(|error| error.kind()),
            Err(io::ErrorKind::NotFound)
        );
        scratch.write("file", "")?;
        assert!(
            Local
                .create_directories(&scratch.path().join("file/below"))
                .is_err()
        );
        Ok(())
    }
}
