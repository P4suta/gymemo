use super::*;
use crate::{
    failure::{Failure, ensure},
    host::{Invocation, Local, Streams},
    mac_installer::{
        Activation,
        native::{Native, Preferences},
    },
    scratch::Scratch,
};
use std::{fs, os::unix::fs::PermissionsExt, path::PathBuf, sync::Mutex};

static KEYCHAIN_FIXTURE: Mutex<()> = Mutex::new(());

fn fixture_environment(name: &str) -> Result<String> {
    match name {
        "DOPPLER_PROJECT" => Ok("gymemo".into()),
        "DOPPLER_CONFIG" => Ok("ci_native_signing".into()),
        "APPLE_INSTALLER_CERTIFICATE_BASE64" => Ok("AQID".into()),
        "APPLE_INSTALLER_CERTIFICATE_PASSWORD" => Ok("fixture-p12-password".into()),
        _ => Err(Failure::new("Unexpected fixture variable")),
    }
}

type FixturePort<'a> = Native<'a, Local, Framework, fn(&str) -> Result<String>>;

fn with_keychain(
    name: &str,
    check: impl FnOnce(&mut FixturePort<'_>, &Path) -> Result<()>,
) -> Result<()> {
    let _serial = KEYCHAIN_FIXTURE
        .lock()
        .map_err(|_| Failure::new("The native keychain fixture lock is poisoned"))?;
    let _interaction = SecKeychain::disable_user_interaction()
        .context(|| "Disable interaction for the fixture keychain".into())?;
    let scratch = Scratch::new(name).context(|| "Create the native keychain fixture".into())?;
    let password_file = scratch.path().join("password");
    fs::write(&password_file, "fixture-keychain-password")
        .context(|| "Write the fixture keychain password".into())?;
    fs::set_permissions(&password_file, fs::Permissions::from_mode(0o600))
        .context(|| "Protect the fixture keychain password".into())?;
    let request = Request {
        keychain: scratch.path().join("gymemo-fixture.keychain-db"),
        password_file,
        fingerprint: "a".repeat(64),
        activation: Activation::Preserve,
    };
    let mut host = Local;
    let importer = scratch.path().join("installer-import");
    let compiled = host
        .run(
            &Invocation::new("xcrun")
                .args([
                    "swiftc",
                    "-swift-version",
                    "6",
                    "-parse-as-library",
                    "-warnings-as-errors",
                    "-O",
                ])
                .arg(Path::new(env!("CARGO_MANIFEST_DIR")).join("native/InstallerImport.swift"))
                .arg("-o")
                .arg(&importer),
            Streams::Captured,
        )
        .context(|| "Compile the native installer fixture".into())?;
    ensure(compiled.status.success(), || {
        "The native installer fixture didn't compile".into()
    })?;
    let mut api = Framework { importer };
    let mut port = Native {
        host: &mut host,
        api: &mut api,
        read_variable: fixture_environment as fn(&str) -> Result<String>,
        destination: PathBuf::new(),
        credentials: None,
        password: String::new(),
        before: None,
        keychain: None,
    };
    use crate::mac_installer::KeychainPort as _;
    port.prepare(&request)?;
    let before: Preferences = port
        .before
        .clone()
        .ok_or_else(|| Failure::new("Missing original preferences"))?;
    port.create(&request)?;
    let checked = check(&mut port, scratch.path());
    let restored = port.preferences(&request, Activation::Preserve);
    let removed = port.delete(&request);
    checked?;
    restored?;
    removed?;
    ensure(
        port.snapshot()? == before && !port.destination.exists(),
        || "The fixture keychain or its preferences remain".into(),
    )
}

#[test]
fn creates_unlocks_checks_and_removes_only_the_fixture_keychain() -> Result<()> {
    with_keychain("security-framework-keychain", |port, _| {
        let locked = port
            .host
            .run(
                &Invocation::new("security")
                    .arg("lock-keychain")
                    .arg(&port.destination),
                Streams::Captured,
            )
            .context(|| "Lock the fixture keychain".into())?;
        ensure(locked.status.success(), || {
            "The fixture keychain did not lock".into()
        })?;
        let keychain = port
            .keychain
            .as_mut()
            .ok_or_else(|| Failure::new("Missing fixture keychain"))?;
        ensure(
            port.api.unlock(keychain, "wrong-fixture-password").is_err(),
            || "The native API accepted the wrong fixture password".into(),
        )?;
        port.api.unlock(keychain, &port.password)?;
        ensure(
            port.api
                .import(
                    keychain,
                    &[1, 2, 3],
                    "fixture-p12-password",
                    Path::new("/usr/bin/productbuild"),
                )
                .is_err(),
            || "The native API accepted invalid PKCS#12 bytes".into(),
        )?;
        port.api.settings(keychain, true, 1_800)?;
        let output = port
            .host
            .run(
                &Invocation::new("security")
                    .arg("show-keychain-info")
                    .arg(&port.destination),
                Streams::Captured,
            )
            .context(|| "Read the native keychain lock settings".into())?;
        let settings = format!(
            "{}{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
        ensure(
            output.status.success()
                && settings.contains("lock-on-sleep")
                && settings.contains("timeout=1800s"),
            || "The native keychain lock settings differ from the requested policy".into(),
        )
    })
}

#[test]
fn imports_a_disposable_identity_with_productbuild_access() -> Result<()> {
    with_keychain("installer-tool-access", |port, root| {
        let certificate = root.join("certificate.pem");
        let key = root.join("key.pem");
        let identity_file = root.join("identity.p12");
        let der = root.join("certificate.der");
        port.command(
            Invocation::new("openssl")
                .args([
                    "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
                ])
                .args(["-subj", "/CN=Gymemo Installer Fixture", "-keyout"])
                .arg(&key)
                .arg("-out")
                .arg(&certificate),
            "Generate the disposable installer identity",
        )?;
        port.command(
            Invocation::new("openssl")
                .args(["pkcs12", "-export", "-inkey"])
                .arg(&key)
                .arg("-in")
                .arg(&certificate)
                .arg("-out")
                .arg(&identity_file)
                .arg("-passout")
                .arg(format!("file:{}", root.join("password").display())),
            "Protect the disposable installer identity",
        )?;
        port.command(
            Invocation::new("openssl")
                .args(["x509", "-in"])
                .arg(&certificate)
                .args(["-outform", "DER", "-out"])
                .arg(&der),
            "Read the disposable public certificate",
        )?;
        let keychain = port
            .keychain
            .as_mut()
            .ok_or_else(|| Failure::new("Missing fixture keychain"))?;
        port.api.unlock(keychain, &port.password)?;
        let data =
            fs::read(&identity_file).context(|| "Read the disposable PKCS#12 identity".into())?;
        ensure(
            port.api
                .import(
                    keychain,
                    &data,
                    "wrong-fixture-password",
                    Path::new("/usr/bin/productbuild"),
                )
                .is_err(),
            || "The native importer accepted the wrong PKCS#12 password".into(),
        )?;
        let identities = port.api.import(
            keychain,
            &data,
            &port.password,
            Path::new("/usr/bin/productbuild"),
        )?;
        let [Some(identity)] = identities.as_slice() else {
            return Err(Failure::new("The disposable import requires one identity"));
        };
        ensure(
            identity.der == fs::read(&der).context(|| "Read the public fixture DER".into())?
                && identity.subject == "Gymemo Installer Fixture"
                && identity.private_key,
            || "The native importer returned different public metadata".into(),
        )?;
        let access = port.command(
            Invocation::new("security")
                .args(["dump-keychain", "-a"])
                .arg(&port.destination),
            "Read access metadata from the disposable keychain",
        )?;
        ensure(
            String::from_utf8_lossy(&access).contains("productbuild"),
            || "The imported fixture key doesn't trust productbuild".into(),
        )
    })
}
