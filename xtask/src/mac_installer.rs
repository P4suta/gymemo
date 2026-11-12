use crate::{
    failure::{Failure, Result, ensure},
    host::Host,
};
use std::path::{Component, PathBuf};

#[cfg(any(target_os = "macos", test))]
mod native;

#[cfg(any(target_os = "macos", test))]
mod purpose;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Activation {
    Preserve,
    Add,
}

#[derive(Debug, PartialEq, Eq)]
struct Request {
    keychain: PathBuf,
    password_file: PathBuf,
    fingerprint: String,
    activation: Activation,
}

#[derive(Debug, PartialEq, Eq)]
enum Operation {
    Plan(Request),
    Install(Request),
}

impl Operation {
    fn parse(arguments: &[String]) -> Result<Self> {
        ensure(arguments.len() >= 3, || {
            "install-mac-installer requires KEYCHAIN PASSWORD_FILE CERT_SHA256".into()
        })?;
        let keychain = PathBuf::from(&arguments[0]);
        let password_file = PathBuf::from(&arguments[1]);
        for path in [&keychain, &password_file] {
            ensure(
                path.is_absolute()
                    && !path.components().any(|part| part == Component::ParentDir)
                    && !path
                        .as_os_str()
                        .to_string_lossy()
                        .contains(['\0', '\r', '\n']),
                || {
                    "Installer import paths must be absolute and contain no parent traversal or control characters".into()
                },
            )?;
        }
        ensure(
            keychain
                .file_name()
                .and_then(|name| name.to_str())
                .is_some_and(|name| name.starts_with("gymemo-") && name.ends_with(".keychain-db")),
            || "The new installer keychain must be named gymemo-*.keychain-db".into(),
        )?;
        ensure(
            arguments[2].len() == 64 && arguments[2].bytes().all(|byte| byte.is_ascii_hexdigit()),
            || {
                "The expected installer certificate fingerprint must contain 64 hexadecimal digits"
                    .into()
            },
        )?;
        let mut confirm = false;
        let mut activation = Activation::Preserve;
        for argument in &arguments[3..] {
            match argument.as_str() {
                "--confirm" if !confirm => confirm = true,
                "--add-to-search-list" if activation == Activation::Preserve => {
                    activation = Activation::Add
                }
                _ => {
                    return Err(Failure::new(
                        "Installer import received an unknown or repeated option",
                    ));
                }
            }
        }
        let request = Request {
            keychain,
            password_file,
            fingerprint: arguments[2].to_ascii_lowercase(),
            activation,
        };
        Ok(if confirm {
            Self::Install(request)
        } else {
            Self::Plan(request)
        })
    }
}

#[cfg(any(target_os = "macos", test))]
#[derive(Clone, Debug)]
struct Identity {
    fingerprint: String,
    subject: String,
    private_key: bool,
    trusted: bool,
}

#[cfg(any(target_os = "macos", test))]
#[derive(Debug)]
struct VerifiedInstaller {
    fingerprint: String,
    subject: String,
}

#[cfg(any(target_os = "macos", test))]
trait KeychainPort {
    fn prepare(&mut self, request: &Request) -> Result<()>;
    fn create(&mut self, request: &Request) -> Result<()>;
    fn identities(&mut self, request: &Request) -> Result<Vec<Identity>>;
    fn configure(&mut self, request: &Request, identity: &VerifiedInstaller) -> Result<()>;
    fn preferences(&mut self, request: &Request, activation: Activation) -> Result<()>;
    fn delete(&mut self, request: &Request) -> Result<()>;
}

#[cfg(any(target_os = "macos", test))]
fn install(port: &mut impl KeychainPort, request: &Request) -> Result<VerifiedInstaller> {
    port.prepare(request)?;
    port.create(request)?;
    let result: Result<VerifiedInstaller> = (|| {
        let mut identities = port.identities(request)?;
        ensure(identities.len() == 1, || {
            "The installer input must contain exactly one identity".into()
        })?;
        let identity = identities
            .pop()
            .ok_or_else(|| Failure::new("The installer identity is missing"))?;
        ensure(identity.fingerprint == request.fingerprint, || {
            "The installer certificate fingerprint does not match".into()
        })?;
        ensure(
            identity
                .subject
                .strip_prefix("3rd Party Mac Developer Installer: ")
                .is_some_and(|name| !name.trim().is_empty()),
            || "The certificate is not a Mac App Store installer certificate".into(),
        )?;
        ensure(identity.private_key, || {
            "The installer identity has no private key".into()
        })?;
        ensure(identity.trusted, || {
            "The installer identity is not trusted in its dedicated keychain".into()
        })?;
        let verified = VerifiedInstaller {
            fingerprint: identity.fingerprint,
            subject: identity.subject,
        };
        port.configure(request, &verified)?;
        port.preferences(request, request.activation)?;
        Ok(verified)
    })();
    match result {
        Ok(identity) => Ok(identity),
        Err(mut failure) => {
            if let Err(cleanup) = port.preferences(request, Activation::Preserve) {
                failure = failure.followed_by(&cleanup);
            }
            if let Err(cleanup) = port.delete(request) {
                failure = failure.followed_by(&cleanup);
            }
            Err(failure)
        }
    }
}

pub fn run(host: &mut impl Host, arguments: &[String]) -> Result<()> {
    match Operation::parse(arguments)? {
        Operation::Plan(request) => {
            host.print(&format!(
                "Import the expected Mac App Store installer identity into {}",
                request.keychain.display()
            ));
            Ok(())
        }
        Operation::Install(request) => {
            #[cfg(target_os = "macos")]
            {
                native::security::run(host, &request)
            }
            #[cfg(not(target_os = "macos"))]
            {
                let _ = request;
                Err(Failure::new("Installer import requires macOS"))
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::host::fake::FakeHost;

    fn request() -> Request {
        Request {
            keychain: PathBuf::from("/tmp/gymemo-installer.keychain-db"),
            password_file: PathBuf::from("/tmp/keychain-password"),
            fingerprint: "a".repeat(64),
            activation: Activation::Preserve,
        }
    }

    fn arguments() -> Vec<String> {
        vec![
            "/tmp/gymemo-installer.keychain-db".into(),
            "/tmp/keychain-password".into(),
            "A".repeat(64),
        ]
    }

    fn identity() -> Identity {
        Identity {
            fingerprint: "a".repeat(64),
            subject: "3rd Party Mac Developer Installer: Example (EXAMPLE123)".into(),
            private_key: true,
            trusted: true,
        }
    }

    #[derive(Clone, Copy, Debug, PartialEq, Eq)]
    enum Step {
        Prepare,
        Create,
        Import,
        Configure,
        Preserve,
        Add,
        Delete,
    }

    struct Fake {
        steps: Vec<Step>,
        faults: Vec<Step>,
        identities: Vec<Identity>,
    }

    impl Fake {
        fn new() -> Self {
            Self {
                steps: Vec::new(),
                faults: Vec::new(),
                identities: vec![identity()],
            }
        }

        fn step(&mut self, step: Step) -> Result<()> {
            self.steps.push(step);
            if self.faults.contains(&step) {
                Err(Failure::new(format!("{step:?} failed")))
            } else {
                Ok(())
            }
        }
    }

    impl KeychainPort for Fake {
        fn prepare(&mut self, _: &Request) -> Result<()> {
            self.step(Step::Prepare)
        }
        fn create(&mut self, _: &Request) -> Result<()> {
            self.step(Step::Create)
        }
        fn identities(&mut self, _: &Request) -> Result<Vec<Identity>> {
            self.step(Step::Import)?;
            Ok(self.identities.clone())
        }
        fn configure(&mut self, _: &Request, _: &VerifiedInstaller) -> Result<()> {
            self.step(Step::Configure)
        }
        fn preferences(&mut self, _: &Request, activation: Activation) -> Result<()> {
            self.step(match activation {
                Activation::Preserve => Step::Preserve,
                Activation::Add => Step::Add,
            })
        }
        fn delete(&mut self, _: &Request) -> Result<()> {
            self.step(Step::Delete)
        }
    }

    #[test]
    fn plans_without_credentials_or_effects_and_requires_confirmation_to_import() -> Result<()> {
        assert_eq!(Operation::parse(&arguments())?, Operation::Plan(request()));
        let mut apply = arguments();
        apply.extend(["--confirm".into(), "--add-to-search-list".into()]);
        let mut expected = request();
        expected.activation = Activation::Add;
        assert_eq!(Operation::parse(&apply)?, Operation::Install(expected));
        let mut host = FakeHost::new();
        run(&mut host, &arguments())?;
        assert!(host.transcript().is_empty());
        assert_eq!(host.output.len(), 1);
        Ok(())
    }

    #[test]
    fn rejects_ambiguous_paths_fingerprints_and_options() {
        let mut cases = vec![Vec::new(), vec!["--confirm".into()], arguments()];
        cases[2][0] = "/tmp/login.keychain-db".into();
        for (index, invalid) in [
            (0, "relative.keychain-db"),
            (0, "/tmp/gymemo-bad\n.keychain-db"),
            (1, "relative-password"),
            (2, ""),
            (2, "abc"),
            (2, &"g".repeat(64)),
        ] {
            let mut args = arguments();
            args[index] = invalid.into();
            cases.push(args);
        }
        for suffix in [
            vec!["--unknown"],
            vec!["--confirm", "--confirm"],
            vec!["--add-to-search-list", "--add-to-search-list"],
        ] {
            let mut args = arguments();
            args.extend(suffix.into_iter().map(String::from));
            cases.push(args);
        }
        for args in cases {
            assert!(Operation::parse(&args).is_err(), "{args:?}");
        }
    }

    #[test]
    fn configures_only_one_trusted_installer_with_its_private_key_and_expected_fingerprint()
    -> Result<()> {
        for activation in [Activation::Preserve, Activation::Add] {
            let mut port = Fake::new();
            let mut request = request();
            request.activation = activation;
            let verified = install(&mut port, &request)?;
            assert_eq!(verified.fingerprint, request.fingerprint);
            assert_eq!(verified.subject, identity().subject);
            assert_eq!(
                port.steps,
                [
                    Step::Prepare,
                    Step::Create,
                    Step::Import,
                    Step::Configure,
                    if activation == Activation::Add {
                        Step::Add
                    } else {
                        Step::Preserve
                    }
                ]
            );
        }
        Ok(())
    }

    #[test]
    fn removes_the_owned_keychain_for_an_invalid_identity() {
        let mut wrong_hash = identity();
        wrong_hash.fingerprint = "b".repeat(64);
        let mut application = identity();
        application.subject = "Apple Distribution: Example".into();
        let mut developer_id = identity();
        developer_id.subject = "Developer ID Installer: Example".into();
        let mut no_key = identity();
        no_key.private_key = false;
        let mut untrusted = identity();
        untrusted.trusted = false;
        for identities in [
            vec![],
            vec![identity(), identity()],
            vec![wrong_hash],
            vec![application],
            vec![developer_id],
            vec![no_key],
            vec![untrusted],
        ] {
            let mut port = Fake::new();
            port.identities = identities;
            assert!(install(&mut port, &request()).is_err());
            assert_eq!(
                port.steps,
                [
                    Step::Prepare,
                    Step::Create,
                    Step::Import,
                    Step::Preserve,
                    Step::Delete
                ]
            );
        }
    }

    #[test]
    fn cleans_up_only_after_creation_and_keeps_every_failure() {
        for fault in [Step::Prepare, Step::Create] {
            let mut port = Fake::new();
            port.faults.push(fault);
            assert!(install(&mut port, &request()).is_err());
            assert!(!port.steps.contains(&Step::Delete));
        }
        for fault in [Step::Import, Step::Configure, Step::Add] {
            let mut port = Fake::new();
            port.faults.extend([fault, Step::Preserve, Step::Delete]);
            let mut request = request();
            request.activation = Activation::Add;
            let message = install(&mut port, &request).unwrap_err().to_string();
            assert!(message.starts_with(&format!("{fault:?} failed")));
            assert!(message.contains("Preserve failed"));
            assert!(message.contains("Delete failed"));
            assert!(port.steps.ends_with(&[Step::Preserve, Step::Delete]));
        }
    }
}
