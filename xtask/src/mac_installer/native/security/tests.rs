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
use std::{fs, os::unix::fs::PermissionsExt, path::PathBuf};

fn fixture_environment(name: &str) -> Result<String> {
    match name {
        "DOPPLER_PROJECT" => Ok("gymemo".into()),
        "DOPPLER_CONFIG" => Ok("ci_native_signing".into()),
        "APPLE_INSTALLER_CERTIFICATE_BASE64" => Ok("AQID".into()),
        "APPLE_INSTALLER_CERTIFICATE_PASSWORD" => Ok("fixture-p12-password".into()),
        _ => Err(Failure::new("Unexpected fixture variable")),
    }
}

#[test]
fn creates_unlocks_checks_and_removes_only_the_fixture_keychain() -> Result<()> {
    let _interaction = SecKeychain::disable_user_interaction()
        .context(|| "Disable interaction for the fixture keychain".into())?;
    let scratch = Scratch::new("security-framework-keychain")
        .context(|| "Create the native keychain fixture".into())?;
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
    let mut api = Framework;
    let mut port = Native {
        host: &mut host,
        api: &mut api,
        read_variable: fixture_environment,
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
    let checked: Result<()> = (|| {
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
                .import(keychain, &[1, 2, 3], "fixture-p12-password")
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
    })();
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
