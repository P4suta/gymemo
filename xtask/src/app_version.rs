use crate::failure::{Context, Result, ensure};
use crate::host::Host;
use std::fmt;
use std::path::Path;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AppVersion(String);

impl AppVersion {
    pub fn parse(value: &str) -> Result<Self> {
        let parts = value.split('.').collect::<Vec<_>>();
        ensure(
            parts.len() == 3
                && parts.iter().all(|part| {
                    !part.is_empty()
                        && part.bytes().all(|byte| byte.is_ascii_digit())
                        && (part.len() == 1 || !part.starts_with('0'))
                        && part.parse::<u32>().is_ok()
                }),
            || "The app version requires three canonical numeric components".into(),
        )?;
        Ok(Self(value.to_owned()))
    }
}

impl fmt::Display for AppVersion {
    fn fmt(&self, output: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.0.fmt(output)
    }
}

pub fn read(host: &mut impl Host, root: &Path) -> Result<AppVersion> {
    let text = host
        .read(&root.join("Config/MarketingVersion.txt"))
        .context(|| "Read the canonical app version".into())?;
    AppVersion::parse(text.trim())
}

pub fn generate(host: &mut impl Host, root: &Path) -> Result<()> {
    let version = read(host, root)?;
    host.create_directories(&root.join("Config"))
        .context(|| "Create the generated build configuration directory".into())?;
    host.write(
        &root.join("Config/Version.xcconfig"),
        &format!("MARKETING_VERSION = {version}\n"),
    )
    .context(|| "Write the generated app version configuration".into())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::host::fake::FakeHost;

    #[test]
    fn accepts_canonical_store_versions() -> Result<()> {
        for value in ["0.1.0", "1.0.0", "2.12.345"] {
            assert_eq!(AppVersion::parse(value)?.0, value);
        }
        Ok(())
    }

    #[test]
    fn rejects_missing_extra_and_noncanonical_components() {
        for value in [
            "",
            "1",
            "1.0",
            "1.0.0.1",
            "v1.0.0",
            "01.0.0",
            "1.00.0",
            "1.0.01",
            "1..0",
            "1.a.0",
            "1.0.0-beta",
            "1.0.0+build",
            "1.0.0\n",
            " 1.0.0",
            "1.0.0 ",
            "１.0.0",
            "1.0.4294967296",
        ] {
            assert!(AppVersion::parse(value).is_err(), "{value:?}");
        }
    }

    #[test]
    fn generates_the_build_setting_from_the_canonical_version() -> Result<()> {
        let mut host = FakeHost::new();
        host.file("/repo/Config/MarketingVersion.txt", "1.2.3\n");
        generate(&mut host, Path::new("/repo"))?;
        assert_eq!(
            host.read(Path::new("/repo/Config/Version.xcconfig"))
                .unwrap(),
            "MARKETING_VERSION = 1.2.3\n"
        );
        assert_eq!(read(&mut host, Path::new("/repo"))?.to_string(), "1.2.3");
        assert!(
            host.transcript()
                .iter()
                .all(|line| !line.starts_with("show ") && !line.starts_with("capture "))
        );
        Ok(())
    }

    #[test]
    fn refuses_missing_or_invalid_versions_and_unwritable_configuration() {
        let mut host = FakeHost::new();
        assert!(generate(&mut host, Path::new("/repo")).is_err());
        for value in ["1.0\n", "1.0.0\n1.0.1\n", "1.0.0-beta\n"] {
            host.file("/repo/Config/MarketingVersion.txt", value);
            assert!(generate(&mut host, Path::new("/repo")).is_err());
        }
        assert!(
            host.transcript()
                .iter()
                .all(|line| !line.starts_with("write "))
        );
        host.file("/repo/Config/MarketingVersion.txt", "1.0.0\n");
        host.directory("/repo/Config/Version.xcconfig", &[]);
        assert!(generate(&mut host, Path::new("/repo")).is_err());
    }
}
