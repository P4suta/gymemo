use super::{Activation, Identity, KeychainPort, Request, VerifiedInstaller, install};
use crate::{
    failure::{Context, Failure, Result, ensure},
    host::{Host, Invocation, Streams},
};
use base64::{Engine as _, engine::general_purpose::STANDARD};
use ring::digest::{SHA1_FOR_LEGACY_USE_ONLY, SHA256, digest};
use std::{
    env, fs, io,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
};

#[cfg(target_os = "macos")]
pub(super) mod security;

struct ImportedIdentity {
    der: Vec<u8>,
    subject: String,
    private_key: bool,
}

trait KeychainApi {
    type Keychain;

    fn create(&mut self, path: &Path, password: &str, prompt_user: bool) -> Result<Self::Keychain>;
    fn unlock(&mut self, keychain: &mut Self::Keychain, password: &str) -> Result<()>;
    fn import(
        &mut self,
        keychain: &Self::Keychain,
        data: &[u8],
        password: &str,
    ) -> Result<Vec<Option<ImportedIdentity>>>;
    fn settings(
        &mut self,
        keychain: &mut Self::Keychain,
        lock_on_sleep: bool,
        interval: u32,
    ) -> Result<()>;
}

struct Credentials {
    data: Vec<u8>,
    password: String,
}

impl Credentials {
    fn decode(encoded: &str, password: String) -> Result<Self> {
        ensure(!password.is_empty(), || {
            "The installer certificate password is empty".into()
        })?;
        let encoded = encoded
            .bytes()
            .filter(|byte| !byte.is_ascii_whitespace())
            .collect::<Vec<_>>();
        let data = STANDARD
            .decode(encoded)
            .map_err(|_| Failure::new("The installer certificate is not valid Base64"))?;
        ensure(!data.is_empty(), || {
            "The installer certificate is empty".into()
        })?;
        Ok(Self { data, password })
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct Preferences {
    default: PathBuf,
    search: Vec<PathBuf>,
}

struct Native<'a, H, A: KeychainApi, E> {
    host: &'a mut H,
    api: &'a mut A,
    read_variable: E,
    destination: PathBuf,
    credentials: Option<Credentials>,
    password: String,
    before: Option<Preferences>,
    keychain: Option<A::Keychain>,
}

fn variable(name: &str) -> Result<String> {
    env::var(name).map_err(|_| Failure::new(format!("{name} is missing or is not UTF-8")))
}

fn paths(bytes: &[u8]) -> Result<Vec<PathBuf>> {
    let text = std::str::from_utf8(bytes).context(|| "Read keychain paths as UTF-8".into())?;
    let tokens = shlex::split(text)
        .ok_or_else(|| Failure::new("The keychain path list has invalid quoting"))?;
    let paths = tokens.into_iter().map(PathBuf::from).collect::<Vec<_>>();
    ensure(
        paths
            .iter()
            .all(|path| path.is_absolute() && !path.to_string_lossy().contains(['\0', '\r', '\n'])),
        || "The keychain path list contains an invalid path".into(),
    )?;
    Ok(paths)
}

fn password_file(path: &Path) -> Result<String> {
    let metadata =
        fs::symlink_metadata(path).context(|| "Read the keychain password file metadata".into())?;
    ensure(
        metadata.is_file() && metadata.permissions().mode() & 0o077 == 0,
        || "The keychain password must be a regular file readable only by its owner".into(),
    )?;
    let value =
        fs::read_to_string(path).context(|| "Read the protected keychain password file".into())?;
    let password = value.trim_end_matches(['\r', '\n']);
    ensure(
        !password.is_empty()
            && password.trim() == password
            && !password.contains(['\0', '\r', '\n']),
        || {
            "The keychain password file must contain one nonempty line without surrounding whitespace".into()
        },
    )?;
    Ok(password.into())
}

fn hex(bytes: &[u8]) -> String {
    const DIGITS: &[u8; 16] = b"0123456789abcdef";
    bytes
        .iter()
        .flat_map(|byte| {
            [
                char::from(DIGITS[usize::from(byte >> 4)]),
                char::from(DIGITS[usize::from(byte & 15)]),
            ]
        })
        .collect()
}

fn valid_identities(bytes: &[u8]) -> Result<Vec<String>> {
    let text = std::str::from_utf8(bytes)
        .context(|| "Read the installer identity list as UTF-8".into())?;
    let mut identities = Vec::new();
    let mut count = None;
    for line in text.lines().map(str::trim).filter(|line| !line.is_empty()) {
        let fields = shlex::split(line)
            .ok_or_else(|| Failure::new("The installer identity list has invalid quoting"))?;
        if fields.len() == 4 && fields[1..] == ["valid", "identities", "found"] {
            ensure(count.is_none(), || {
                "The installer identity list repeats its count".into()
            })?;
            count = Some(
                fields[0]
                    .parse::<usize>()
                    .context(|| "Read the valid identity count".into())?,
            );
        } else {
            ensure(
                fields.len() == 3
                    && fields[0]
                        .strip_suffix(')')
                        .is_some_and(|number| number.parse::<usize>().is_ok())
                    && fields[1].len() == 40
                    && fields[1].bytes().all(|byte| byte.is_ascii_hexdigit()),
                || "The installer identity list contains an invalid record".into(),
            )?;
            identities.push(fields[1].to_ascii_lowercase());
        }
    }
    ensure(count == Some(identities.len()), || {
        "The installer identity count does not match its records".into()
    })?;
    Ok(identities)
}

impl<H: Host, A: KeychainApi, E> Native<'_, H, A, E> {
    fn command(&mut self, invocation: Invocation, operation: &str) -> Result<Vec<u8>> {
        let output = self
            .host
            .run(&invocation, Streams::Captured)
            .context(|| operation.into())?;
        ensure(output.status.success(), || {
            format!("{operation} failed with status {}", output.status)
        })?;
        Ok(output.stdout)
    }

    fn snapshot(&mut self) -> Result<Preferences> {
        let defaults = paths(&self.command(
            Invocation::new("security").args(["default-keychain", "-d", "user"]),
            "Read the default keychain",
        )?)?;
        ensure(defaults.len() == 1, || {
            "Installer import requires one existing default keychain".into()
        })?;
        let default = defaults
            .into_iter()
            .next()
            .ok_or_else(|| Failure::new("The default keychain is missing"))?;
        let search = paths(&self.command(
            Invocation::new("security").args(["list-keychains", "-d", "user"]),
            "Read the keychain search list",
        )?)?;
        Ok(Preferences { default, search })
    }
}

impl<H: Host, A: KeychainApi, E: Fn(&str) -> Result<String>> KeychainPort for Native<'_, H, A, E> {
    fn prepare(&mut self, request: &Request) -> Result<()> {
        ensure(
            (self.read_variable)("DOPPLER_PROJECT")? == "gymemo"
                && (self.read_variable)("DOPPLER_CONFIG")? == "ci_native_signing",
            || "Installer credentials must come from gymemo/ci_native_signing".into(),
        )?;
        let parent = request
            .keychain
            .parent()
            .ok_or_else(|| Failure::new("The installer keychain has no parent"))?;
        let name = request
            .keychain
            .file_name()
            .ok_or_else(|| Failure::new("The installer keychain has no filename"))?;
        self.destination = parent
            .canonicalize()
            .context(|| "Resolve the installer keychain directory".into())?
            .join(name);
        match fs::symlink_metadata(&self.destination) {
            Err(error) if error.kind() == io::ErrorKind::NotFound => {}
            Err(error) => {
                return Err(Failure::new(format!(
                    "Inspect the installer keychain destination: {error}"
                )));
            }
            Ok(_) => {
                return Err(Failure::new(
                    "The installer keychain destination already exists",
                ));
            }
        }
        self.password = password_file(&request.password_file)?;
        self.credentials = Some(Credentials::decode(
            &(self.read_variable)("APPLE_INSTALLER_CERTIFICATE_BASE64")?,
            (self.read_variable)("APPLE_INSTALLER_CERTIFICATE_PASSWORD")?,
        )?);
        let before = self.snapshot()?;
        ensure(
            before.default != self.destination && !before.search.contains(&self.destination),
            || "The installer keychain is already a keychain preference".into(),
        )?;
        self.before = Some(before);
        Ok(())
    }

    fn create(&mut self, _: &Request) -> Result<()> {
        self.keychain = Some(self.api.create(&self.destination, &self.password, false)?);
        Ok(())
    }

    fn identities(&mut self, _: &Request) -> Result<Vec<Identity>> {
        let keychain = self
            .keychain
            .as_mut()
            .ok_or_else(|| Failure::new("The installer keychain was not created"))?;
        self.api.unlock(keychain, &self.password)?;
        let credentials = self
            .credentials
            .as_ref()
            .ok_or_else(|| Failure::new("The installer credentials were not loaded"))?;
        let imported = self
            .api
            .import(keychain, &credentials.data, &credentials.password)?;
        let destination = self.destination.clone();
        let valid = valid_identities(
            &self.command(
                Invocation::new("security")
                    .args(["find-identity", "-p", "basic", "-v"])
                    .arg(destination),
                "Validate the installer identity in its dedicated keychain",
            )?,
        )?;
        imported
            .into_iter()
            .map(|item| {
                let Some(identity) = item else {
                    return Ok(Identity {
                        fingerprint: String::new(),
                        subject: String::new(),
                        private_key: false,
                        trusted: false,
                    });
                };
                let der = identity.der;
                super::purpose::verify(&der)?;
                let sha1 = hex(digest(&SHA1_FOR_LEGACY_USE_ONLY, &der).as_ref());
                Ok(Identity {
                    fingerprint: hex(digest(&SHA256, &der).as_ref()),
                    subject: identity.subject,
                    private_key: identity.private_key,
                    trusted: valid.len() == 1 && valid.contains(&sha1),
                })
            })
            .collect()
    }

    fn configure(&mut self, request: &Request, _: &VerifiedInstaller) -> Result<()> {
        let keychain = self
            .keychain
            .as_mut()
            .ok_or_else(|| Failure::new("The installer keychain was not created"))?;
        self.api.settings(keychain, true, 1_800)?;
        let destination = self.destination.clone();
        self.command(
            Invocation::new("asc")
                .args(["signing", "keychain", "set-partition-list", "--keychain"])
                .arg(destination)
                .arg("--keychain-password-file")
                .arg(&request.password_file)
                .args(["--partition", "apple-tool:,apple:"]),
            "Allow Apple tools to use the installer identity",
        )?;
        Ok(())
    }

    fn preferences(&mut self, _: &Request, activation: Activation) -> Result<()> {
        let before = self
            .before
            .clone()
            .ok_or_else(|| Failure::new("The original keychain preferences are missing"))?;
        let mut current = self.snapshot()?;
        if current.default == self.destination {
            self.command(
                Invocation::new("security")
                    .args(["default-keychain", "-d", "user", "-s"])
                    .arg(&before.default),
                "Restore the default keychain",
            )?;
            current.default = before.default.clone();
        }
        ensure(current.default == before.default, || {
            "The default keychain changed outside the installer import".into()
        })?;
        let without_owned = current
            .search
            .iter()
            .filter(|path| **path != self.destination)
            .cloned()
            .collect::<Vec<_>>();
        let unchanged = without_owned == before.search;
        let mut desired = without_owned;
        if activation == Activation::Add && unchanged {
            desired.push(self.destination.clone());
        }
        if desired != current.search {
            self.command(
                Invocation::new("security")
                    .args(["list-keychains", "-d", "user", "-s"])
                    .args(desired.iter()),
                "Set the installer keychain search policy",
            )?;
        }
        ensure(unchanged, || {
            "The keychain search list changed outside the installer import".into()
        })?;
        ensure(
            self.snapshot()?
                == Preferences {
                    default: before.default,
                    search: desired,
                },
            || "The installer keychain preferences did not match the selected policy".into(),
        )
    }

    fn delete(&mut self, _: &Request) -> Result<()> {
        drop(self.keychain.take());
        let destination = self.destination.clone();
        self.command(
            Invocation::new("security")
                .arg("delete-keychain")
                .arg(destination),
            "Delete the incomplete installer keychain",
        )?;
        Ok(())
    }
}

#[cfg(test)]
mod contracts;

fn execute<H: Host, A: KeychainApi, E: Fn(&str) -> Result<String>>(
    host: &mut H,
    request: &Request,
    api: &mut A,
    read_variable: E,
) -> Result<()> {
    let mut port = Native {
        host,
        api,
        read_variable,
        destination: PathBuf::new(),
        credentials: None,
        password: String::new(),
        before: None,
        keychain: None,
    };
    let identity = install(&mut port, request)?;
    port.host.print(&format!(
        "Verified Mac App Store installer identity {} ({})",
        identity.subject, identity.fingerprint
    ));
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::scratch::Scratch;
    use std::os::unix::fs::symlink;

    #[test]
    fn accepts_cli_base64_line_breaks_without_exposing_bad_inputs() -> Result<()> {
        assert_eq!(
            Credentials::decode(" AQ\nID\r\n", "test-password".into())?.data,
            [1, 2, 3]
        );
        for input in ["", "not-a-private-certificate", "${shared.config.VALUE}"] {
            let error = Credentials::decode(input, "test-password".into())
                .err()
                .ok_or_else(|| Failure::new("An invalid certificate was accepted"))?;
            assert!(!error.to_string().contains("test-password"));
            if !input.is_empty() {
                assert!(!error.to_string().contains(input));
            }
        }
        assert!(Credentials::decode("AQID", String::new()).is_err());
        Ok(())
    }

    #[test]
    fn parses_quoted_keychain_paths_and_valid_identity_counts() -> Result<()> {
        assert_eq!(
            paths(b"\"/tmp/first keychain\"\n\"/tmp/second\"\n")?,
            [
                PathBuf::from("/tmp/first keychain"),
                PathBuf::from("/tmp/second")
            ]
        );
        for text in ["relative", "\"/tmp/unterminated", "\"/tmp/bad\npath\""] {
            assert!(paths(text.as_bytes()).is_err());
        }
        let hash = "A".repeat(40);
        let listing = format!("1) {hash} \"Installer subject\"\n1 valid identities found\n");
        assert_eq!(
            valid_identities(listing.as_bytes())?,
            [hash.to_ascii_lowercase()]
        );
        assert_eq!(
            valid_identities(b"0 valid identities found")?,
            Vec::<String>::new()
        );
        for text in [
            "",
            "1 valid identities found",
            "1) bad \"subject\"\n1 valid identities found",
            "0 valid identities found\n0 valid identities found",
        ] {
            assert!(valid_identities(text.as_bytes()).is_err());
        }
        Ok(())
    }

    #[test]
    fn refuses_unprotected_empty_and_linked_password_files() -> Result<()> {
        let scratch = Scratch::new("installer-password")
            .context(|| "Create the password test directory".into())?;
        let path = scratch.path().join("password");
        fs::write(&path, "test-password\n").context(|| "Write the test password".into())?;
        fs::set_permissions(&path, fs::Permissions::from_mode(0o600))
            .context(|| "Protect the test password".into())?;
        assert_eq!(password_file(&path)?, "test-password");
        let link = scratch.path().join("linked");
        symlink(&path, &link).context(|| "Create the password test link".into())?;
        assert!(password_file(&link).is_err());
        for value in [
            "",
            "\n",
            " secret",
            "secret ",
            "first\nsecond",
            "bad\0password",
        ] {
            fs::write(&path, value).context(|| "Write a refused password".into())?;
            assert!(password_file(&path).is_err());
        }
        fs::write(&path, "test-password").context(|| "Restore the test password".into())?;
        fs::set_permissions(&path, fs::Permissions::from_mode(0o644))
            .context(|| "Expose the test password permissions".into())?;
        assert!(password_file(&path).is_err());
        assert!(password_file(scratch.path()).is_err());
        Ok(())
    }
}
