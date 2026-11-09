//! Gives each test a new temporary directory and removes the directory when the test ends.

use std::{
    env, fs, io,
    path::{Path, PathBuf},
    process,
};

/// A directory under the temporary directory, which its drop removes even after a failed assertion.
pub struct Scratch {
    path: PathBuf,
}

impl Scratch {
    /// A new empty directory, named after its test and this process so that parallel runs never share one.
    pub fn new(test: &str) -> io::Result<Self> {
        let path = env::temp_dir().join(format!("gymemo-xtask-{test}-{}", process::id()));
        if path.exists() {
            fs::remove_dir_all(&path)?;
        }
        fs::create_dir(&path)?;
        Ok(Self { path })
    }

    /// A small repository that passes every source check.
    pub fn repository(test: &str) -> io::Result<Self> {
        let repository = Self::new(test)?;
        repository.write("App/Screen.swift", "List { Text(copy[.title]) }\n")?;
        repository.write("Sources/GymemoCore/Rule.swift", "import Foundation\n")?;
        repository.write("Sources/GymemoKit/Store.swift", "import Foundation\n")?;
        repository.write("project.yml", "name: gymemo\n")?;
        repository.write("Config/App-Info.plist", "<plist/>\n")?;
        repository.write("Config/PrivacyInfo.xcprivacy", "<plist/>\n")?;
        Ok(repository)
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    /// Writes `text` to `file` under the directory, and creates the parent directories of the file.
    pub fn write(&self, file: &str, text: &str) -> io::Result<()> {
        let file = self.path.join(file);
        if let Some(parent) = file.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(file, text)
    }
}

impl Drop for Scratch {
    fn drop(&mut self) {
        // A directory that stays behind fails no test, and the next run with this name removes it.
        let _ = fs::remove_dir_all(&self.path);
    }
}
