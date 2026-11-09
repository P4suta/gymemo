//! The error that every check and step reports.

use std::fmt;

/// One refused check or failed step, with the text shown to the developer and the process exit code.
#[derive(Debug, PartialEq, Eq)]
pub struct Failure {
    message: String,
    code: u8,
}

pub type Result<T> = std::result::Result<T, Failure>;

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

    pub fn code(&self) -> u8 {
        self.code
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
