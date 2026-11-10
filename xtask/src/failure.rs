//! The error that every check and step reports.

use std::fmt;

/// One refused check or failed step, with the text shown to the developer and the process exit code.
#[derive(Debug, PartialEq, Eq)]
pub struct Failure {
    message: String,
    code: u8,
}

pub type Result<T> = std::result::Result<T, Failure>;

/// The exit code of a run that neither passed nor failed, which `sysexits.h` calls `EX_TEMPFAIL`.
pub const INCONCLUSIVE: u8 = 75;

impl Failure {
    pub fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
            code: 1,
        }
    }

    /// A failure that carries a child process's own exit code.
    pub fn exit(message: impl Into<String>, code: u8) -> Self {
        Self {
            message: message.into(),
            code,
        }
    }

    /// A run that stopped at a resource limit, which counts neither as a pass nor as a failure.
    pub fn inconclusive(message: impl Into<String>) -> Self {
        Self {
            message: format!("INCONCLUSIVE: {}", message.into()),
            code: INCONCLUSIVE,
        }
    }

    pub fn code(&self) -> u8 {
        self.code
    }

    /// This failure with `later` reported after it, under the exit code of this failure.
    /// A cleanup that fails after a step failed reports both this way, and the step stays the first line.
    pub fn followed_by(self, later: &Failure) -> Self {
        Self {
            message: format!("{}\n{}", self.message, later.message),
            code: self.code,
        }
    }
}

impl fmt::Display for Failure {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.message)
    }
}

impl std::error::Error for Failure {}

/// Names the operation that produced a lower-level error.
pub trait Context<T> {
    fn context(self, operation: impl FnOnce() -> String) -> Result<T>;
}

impl<T, E: fmt::Display> Context<T> for std::result::Result<T, E> {
    fn context(self, operation: impl FnOnce() -> String) -> Result<T> {
        self.map_err(|error| Failure::new(format!("{}: {error}", operation())))
    }
}

/// Refuses with `message` unless `condition` holds.
pub fn ensure(condition: bool, message: impl FnOnce() -> String) -> Result<()> {
    if condition {
        Ok(())
    } else {
        Err(Failure::new(message()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_failure_shows_its_message_and_exits_with_1_unless_it_carries_another_code() {
        let refused = Failure::new("The check refused");
        assert_eq!(refused.to_string(), "The check refused");
        assert_eq!(refused.code(), 1);
        let child = Failure::exit(String::from("xcodebuild failed"), 65);
        assert_eq!(child.to_string(), "xcodebuild failed");
        assert_eq!(child.code(), 65);
        assert_eq!(Failure::exit("stopped", 0).code(), 0);
    }

    #[test]
    fn an_inconclusive_run_says_so_first_and_exits_with_its_own_code() {
        let stopped = Failure::inconclusive("lake build stopped at the time limit");
        assert_eq!(
            stopped,
            Failure::exit("INCONCLUSIVE: lake build stopped at the time limit", 75)
        );
        assert_eq!(INCONCLUSIVE, 75);
        assert_eq!(
            stopped.followed_by(&Failure::new("The cleanup failed")),
            Failure::exit(
                "INCONCLUSIVE: lake build stopped at the time limit\nThe cleanup failed",
                75
            )
        );
    }

    #[test]
    fn two_failures_are_equal_only_with_the_same_message_and_the_same_code() {
        assert_eq!(Failure::new("a"), Failure::exit("a", 1));
        assert_ne!(Failure::new("a"), Failure::new("b"));
        assert_ne!(Failure::new("a"), Failure::exit("a", 2));
    }

    #[test]
    fn a_later_failure_follows_the_first_one_under_the_first_exit_code() {
        let tests = Failure::exit("The tests failed", 65);
        let cleanup = Failure::exit("The cleanup failed", 2);
        assert_eq!(
            tests.followed_by(&cleanup),
            Failure::exit("The tests failed\nThe cleanup failed", 65)
        );
        assert_eq!(
            cleanup.followed_by(&Failure::new("x")),
            Failure::exit("The cleanup failed\nx", 2)
        );
    }

    #[test]
    fn context_names_the_operation_before_the_cause_and_leaves_success_alone() {
        let failed: std::result::Result<u8, &str> = Err("no permission");
        assert_eq!(
            failed.context(|| "Read the file".to_owned()),
            Err(Failure::new("Read the file: no permission"))
        );
        let read: std::result::Result<u8, &str> = Ok(7);
        assert_eq!(
            read.context(|| unreachable!("success names no operation")),
            Ok(7)
        );
    }

    #[test]
    fn ensure_refuses_with_its_message_only_when_the_condition_fails() {
        assert_eq!(
            ensure(false, || "The list is empty".to_owned()),
            Err(Failure::new("The list is empty"))
        );
        assert_eq!(
            ensure(true, || unreachable!("a held condition writes no message")),
            Ok(())
        );
    }
}
