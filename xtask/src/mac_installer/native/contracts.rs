use super::*;
use crate::{
    host::fake::{FakeHost, Fault},
    scratch::Scratch,
};
use std::os::unix::fs::symlink;

const LOGIN: &str = "/tmp/login.keychain-db";
const OTHER: &str = "/tmp/other.keychain-db";

struct Api {
    steps: Vec<&'static str>,
    fault: Option<&'static str>,
    imported: Vec<Option<ImportedIdentity>>,
}

fn certificate() -> Vec<u8> {
    let pem = include_str!("../fixtures/installer.pem");
    STANDARD
        .decode(
            pem.lines()
                .filter(|line| !line.starts_with("-----"))
                .collect::<String>(),
        )
        .unwrap()
}

fn imported() -> ImportedIdentity {
    ImportedIdentity {
        der: certificate(),
        subject: "3rd Party Mac Developer Installer: Example (EXAMPLE123)".into(),
        private_key: true,
    }
}

impl Api {
    fn new() -> Self {
        Self {
            steps: Vec::new(),
            fault: None,
            imported: vec![Some(imported())],
        }
    }

    fn step(&mut self, name: &'static str) -> Result<()> {
        self.steps.push(name);
        if self.fault == Some(name) {
            Err(Failure::new(format!("{name} failed")))
        } else {
            Ok(())
        }
    }
}

impl KeychainApi for Api {
    type Keychain = PathBuf;

    fn create(&mut self, path: &Path, password: &str, prompt_user: bool) -> Result<PathBuf> {
        self.step("create")?;
        assert_eq!(password, "keychain-test-password");
        assert!(!prompt_user);
        Ok(path.into())
    }

    fn unlock(&mut self, _: &mut PathBuf, password: &str) -> Result<()> {
        self.step("unlock")?;
        assert_eq!(password, "keychain-test-password");
        Ok(())
    }

    fn import(
        &mut self,
        _: &PathBuf,
        data: &[u8],
        password: &str,
    ) -> Result<Vec<Option<ImportedIdentity>>> {
        self.step("import")?;
        assert_eq!(data, [1, 2, 3]);
        assert_eq!(password, "p12-test-password");
        Ok(std::mem::take(&mut self.imported))
    }

    fn settings(&mut self, _: &mut PathBuf, lock_on_sleep: bool, interval: u32) -> Result<()> {
        self.step("settings")?;
        assert!(lock_on_sleep);
        assert_eq!(interval, 1_800);
        Ok(())
    }
}

fn environment(name: &str) -> Result<String> {
    match name {
        "DOPPLER_PROJECT" => Ok("gymemo".into()),
        "DOPPLER_CONFIG" => Ok("ci_native_signing".into()),
        "APPLE_INSTALLER_CERTIFICATE_BASE64" => Ok("AQID".into()),
        "APPLE_INSTALLER_CERTIFICATE_PASSWORD" => Ok("p12-test-password".into()),
        _ => Err(Failure::new("Unexpected environment lookup")),
    }
}

fn fixture(name: &str) -> Result<(Scratch, Request)> {
    let scratch = Scratch::new(name).context(|| "Create the installer fixture".into())?;
    let password_file = scratch.path().join("password");
    fs::write(&password_file, "keychain-test-password\n")
        .context(|| "Write the fixture password".into())?;
    fs::set_permissions(&password_file, fs::Permissions::from_mode(0o600))
        .context(|| "Protect the fixture password".into())?;
    let request = Request {
        keychain: scratch.path().join("gymemo-installer.keychain-db"),
        password_file,
        fingerprint: hex(digest(&SHA256, &certificate()).as_ref()),
        activation: Activation::Preserve,
    };
    Ok((scratch, request))
}

fn prepared_host() -> FakeHost {
    let mut host = FakeHost::new();
    host.prints("\"default-keychain\"", &format!("\"{LOGIN}\"\n"));
    host.prints("\"list-keychains\"", &format!("\"{LOGIN}\"\n\"{OTHER}\"\n"));
    let hash = hex(digest(&SHA1_FOR_LEGACY_USE_ONLY, &certificate()).as_ref());
    host.prints(
        "\"find-identity\"",
        &format!("1) {hash} \"Installer\"\n1 valid identities found\n"),
    );
    host
}

fn test_port<'a, E>(
    host: &'a mut FakeHost,
    api: &'a mut Api,
    read_variable: E,
) -> Native<'a, FakeHost, Api, E> {
    Native {
        host,
        api,
        read_variable,
        destination: PathBuf::new(),
        credentials: None,
        password: String::new(),
        before: None,
        keychain: None,
    }
}

#[test]
fn reads_environment_values_and_rejects_a_missing_variable() -> Result<()> {
    let (name, expected) = env::vars()
        .find(|(_, value)| !value.is_empty())
        .ok_or_else(|| Failure::new("The test environment is empty"))?;
    assert_eq!(variable(&name)?, expected);
    let missing = format!("GYMEMO_MISSING_INSTALLER_VARIABLE_{}", std::process::id());
    assert!(env::var(&missing).is_err());
    assert!(variable(&missing).is_err());
    Ok(())
}

#[test]
fn encodes_every_byte_and_rejects_each_invalid_path_and_identity_field() -> Result<()> {
    let bytes = (0..=255).collect::<Vec<u8>>();
    assert_eq!(
        hex(&bytes),
        bytes
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect::<String>()
    );
    assert_eq!(hex(&[]), "");
    for invalid in [b"\xff".as_slice(), b"\"/tmp/a\0b\"", b"\"/tmp/a\rb\""] {
        assert!(paths(invalid).is_err());
    }
    let hash = "a".repeat(40);
    for invalid in [
        format!("one) {hash} subject\n1 valid identities found"),
        format!("1 {hash} subject\n1 valid identities found"),
        format!("1) {} subject\n1 valid identities found", "g".repeat(40)),
        format!("1) {hash}\n1 valid identities found"),
        format!("1) {hash} subject extra\n1 valid identities found"),
        "no valid identities found".into(),
        "0 invalid identities found".into(),
        format!("1) {hash} subject\n2 valid identities found"),
    ] {
        assert!(valid_identities(invalid.as_bytes()).is_err(), "{invalid:?}");
    }
    assert!(valid_identities(&[0xff]).is_err());
    assert_eq!(
        valid_identities(
            format!("\n 1) {hash} subject \n\n1 valid identities found\n").as_bytes()
        )?,
        [hash]
    );
    Ok(())
}

#[test]
fn prepares_only_the_selected_secret_configuration_and_new_destination() -> Result<()> {
    let (scratch, request) = fixture("installer-prepare")?;
    for (name, wrong) in [
        ("DOPPLER_PROJECT", "another-project"),
        ("DOPPLER_CONFIG", "dev"),
    ] {
        let mut host = prepared_host();
        let mut api = Api::new();
        let mut port = test_port(&mut host, &mut api, |key: &str| {
            if key == name {
                Ok(wrong.into())
            } else {
                environment(key)
            }
        });
        assert!(port.prepare(&request).is_err());
        assert!(port.host.transcript().is_empty());
        assert!(port.api.steps.is_empty());
    }
    for missing in [
        "DOPPLER_PROJECT",
        "DOPPLER_CONFIG",
        "APPLE_INSTALLER_CERTIFICATE_BASE64",
        "APPLE_INSTALLER_CERTIFICATE_PASSWORD",
    ] {
        let mut host = prepared_host();
        let mut api = Api::new();
        assert!(
            test_port(&mut host, &mut api, |key: &str| if key == missing {
                Err(Failure::new("Missing fixture variable"))
            } else {
                environment(key)
            })
            .prepare(&request)
            .is_err()
        );
    }
    let mut host = prepared_host();
    let mut api = Api::new();
    let mut port = test_port(&mut host, &mut api, environment);
    port.prepare(&request)?;
    assert_eq!(
        port.destination,
        scratch
            .path()
            .canonicalize()
            .unwrap()
            .join("gymemo-installer.keychain-db")
    );
    assert_eq!(port.password, "keychain-test-password");
    assert_eq!(port.credentials.as_ref().unwrap().data, [1, 2, 3]);
    assert_eq!(
        port.before,
        Some(Preferences {
            default: LOGIN.into(),
            search: vec![LOGIN.into(), OTHER.into()]
        })
    );
    assert!(!request.keychain.exists());
    Ok(())
}

#[test]
fn refuses_existing_destinations_missing_parents_and_metadata_errors() -> Result<()> {
    let (scratch, mut request) = fixture("installer-destinations")?;
    let file = scratch.path().join("existing-file");
    fs::write(&file, "existing").unwrap();
    let directory = scratch.path().join("existing-directory");
    fs::create_dir(&directory).unwrap();
    let link = scratch.path().join("dangling-link");
    symlink(scratch.path().join("missing"), &link).unwrap();
    for destination in [
        file.clone(),
        directory,
        link,
        scratch.path().join("missing/child"),
        file.join("child"),
        PathBuf::from("/"),
    ] {
        request.keychain = destination;
        let mut host = prepared_host();
        let mut api = Api::new();
        assert!(
            test_port(&mut host, &mut api, environment)
                .prepare(&request)
                .is_err()
        );
        assert!(host.transcript().is_empty());
        assert!(api.steps.is_empty());
    }
    Ok(())
}

#[test]
fn refuses_preexisting_default_or_search_preferences_independently() -> Result<()> {
    let (_scratch, request) = fixture("installer-owned-preferences")?;
    let destination = request
        .keychain
        .parent()
        .unwrap()
        .canonicalize()
        .unwrap()
        .join(request.keychain.file_name().unwrap());
    for default in [true, false] {
        let mut host = prepared_host();
        let mut api = Api::new();
        host.prints(
            if default {
                "\"default-keychain\""
            } else {
                "\"list-keychains\""
            },
            &format!("\"{}\"\n", destination.display()),
        );
        assert!(
            test_port(&mut host, &mut api, environment)
                .prepare(&request)
                .is_err()
        );
        assert!(api.steps.is_empty());
    }
    Ok(())
}

#[test]
fn propagates_command_failures_and_requires_one_default_keychain() -> Result<()> {
    for fault in [Fault::Missing, Fault::Exit(1, "refused"), Fault::Garbled] {
        for position in [0, 1] {
            let mut host = prepared_host();
            host.fail_at(position, fault);
            let mut api = Api::new();
            assert!(
                test_port(&mut host, &mut api, environment)
                    .snapshot()
                    .is_err()
            );
        }
    }
    for output in ["", "\"/tmp/one\" \"/tmp/two\""] {
        let mut host = prepared_host();
        host.prints("\"default-keychain\"", output);
        let mut api = Api::new();
        assert!(
            test_port(&mut host, &mut api, environment)
                .snapshot()
                .is_err()
        );
    }
    let mut host = prepared_host();
    host.prints("\"probe\"", "distinct output");
    let mut api = Api::new();
    assert_eq!(
        test_port(&mut host, &mut api, environment).command(
            Invocation::new("security").arg("probe"),
            "Probe the keychain"
        )?,
        b"distinct output"
    );
    Ok(())
}

#[test]
fn imports_validates_configures_and_reports_the_expected_identity() -> Result<()> {
    let (_scratch, request) = fixture("installer-complete")?;
    let mut host = prepared_host();
    let mut api = Api::new();
    execute(&mut host, &request, &mut api, environment)?;
    assert_eq!(api.steps, ["create", "unlock", "import", "settings"]);
    assert_eq!(
        host.output,
        [format!(
            "Verified Mac App Store installer identity {} ({})",
            imported().subject,
            request.fingerprint
        )]
    );
    let transcript = host.transcript().join("\n");
    assert!(transcript.contains("\"asc\" \"signing\" \"keychain\" \"set-partition-list\""));
    assert!(!transcript.contains("test-password"));
    assert!(!transcript.contains("delete-keychain"));
    assert!(!transcript.contains("\"-s\""));
    Ok(())
}

#[test]
fn rejects_untrusted_missing_malformed_and_multiple_imported_identities() -> Result<()> {
    let (_scratch, request) = fixture("installer-identities")?;
    for listing in [
        "0 valid identities found".into(),
        format!("1) {} subject\n1 valid identities found", "b".repeat(40)),
        format!(
            "1) {} subject\n2) {} subject\n2 valid identities found",
            hex(digest(&SHA1_FOR_LEGACY_USE_ONLY, &certificate()).as_ref()),
            "b".repeat(40)
        ),
    ] {
        let mut host = prepared_host();
        host.prints("\"find-identity\"", &listing);
        let mut api = Api::new();
        assert!(execute(&mut host, &request, &mut api, environment).is_err());
        assert!(!api.steps.contains(&"settings"));
        assert!(
            host.transcript()
                .last()
                .unwrap()
                .contains("\"delete-keychain\"")
        );
    }
    let mut malformed = imported();
    malformed.der = vec![0xff];
    let mut missing_key = imported();
    missing_key.private_key = false;
    let mut wrong_subject = imported();
    wrong_subject.subject = "Apple Distribution: Example".into();
    for identities in [
        vec![],
        vec![None],
        vec![Some(imported()), Some(imported())],
        vec![Some(malformed)],
        vec![Some(missing_key)],
        vec![Some(wrong_subject)],
    ] {
        let mut host = prepared_host();
        let mut api = Api::new();
        api.imported = identities;
        assert!(execute(&mut host, &request, &mut api, environment).is_err());
        assert!(!api.steps.contains(&"settings"));
        assert!(
            host.transcript()
                .last()
                .unwrap()
                .contains("\"delete-keychain\"")
        );
    }
    Ok(())
}

#[test]
fn keeps_api_failures_and_cleans_up_only_an_owned_keychain() -> Result<()> {
    let (_scratch, request) = fixture("installer-api-failures")?;
    for fault in ["create", "unlock", "import", "settings"] {
        let mut host = prepared_host();
        let mut api = Api::new();
        api.fault = Some(fault);
        let error = execute(&mut host, &request, &mut api, environment)
            .unwrap_err()
            .to_string();
        assert!(error.starts_with(&format!("{fault} failed")));
        assert_eq!(
            host.transcript()
                .iter()
                .any(|line| line.contains("delete-keychain")),
            fault != "create"
        );
        assert!(host.output.is_empty());
    }
    let mut host = prepared_host();
    host.fail("\"set-partition-list\"", Fault::Exit(1, "refused"));
    host.fail("\"delete-keychain\"", Fault::Missing);
    let mut api = Api::new();
    let error = execute(&mut host, &request, &mut api, environment)
        .unwrap_err()
        .to_string();
    assert!(error.contains("Allow Apple tools"));
    assert!(error.contains("Delete the incomplete"));
    Ok(())
}

#[test]
fn restores_owned_preferences_and_adds_only_when_requested() -> Result<()> {
    let (_scratch, request) = fixture("installer-restore-preferences")?;
    for activation in [Activation::Preserve, Activation::Add] {
        let mut host = prepared_host();
        let mut api = Api::new();
        let mut port = test_port(&mut host, &mut api, environment);
        port.destination = request.keychain.clone();
        port.before = Some(Preferences {
            default: LOGIN.into(),
            search: vec![LOGIN.into(), OTHER.into()],
        });
        let before = format!("\"{LOGIN}\" \"{OTHER}\"");
        let owned = format!("{before} \"{}\"", request.keychain.display());
        port.host
            .prints_at(0, &format!("\"{}\"", request.keychain.display()));
        port.host.prints_at(1, &owned);
        port.host.prints_at(
            if activation == Activation::Add { 4 } else { 5 },
            if activation == Activation::Add {
                &owned
            } else {
                &before
            },
        );
        port.preferences(&request, activation)?;
        let transcript = port.host.transcript().join("\n");
        assert!(transcript.contains(&format!(
            "\"default-keychain\" \"-d\" \"user\" \"-s\" \"{LOGIN}\""
        )));
        assert_eq!(
            transcript.contains("\"list-keychains\" \"-d\" \"user\" \"-s\""),
            activation == Activation::Preserve
        );
    }
    Ok(())
}

#[test]
fn preserves_external_changes_and_refuses_a_different_postcondition() -> Result<()> {
    let (_scratch, request) = fixture("installer-concurrent-preferences")?;
    let mut host = prepared_host();
    let mut api = Api::new();
    let mut port = test_port(&mut host, &mut api, environment);
    port.destination = request.keychain.clone();
    port.before = Some(Preferences {
        default: LOGIN.into(),
        search: vec![LOGIN.into(), OTHER.into()],
    });
    port.host.prints_at(
        1,
        &format!(
            "\"{LOGIN}\" \"{OTHER}\" \"/tmp/concurrent\" \"{}\"",
            request.keychain.display()
        ),
    );
    assert!(port.preferences(&request, Activation::Add).is_err());
    assert_eq!(
        port.host.transcript().last().unwrap(),
        "capture \"security\" \"list-keychains\" \"-d\" \"user\" \"-s\" \"/tmp/login.keychain-db\" \"/tmp/other.keychain-db\" \"/tmp/concurrent\""
    );
    let mut host = prepared_host();
    let mut api = Api::new();
    let mut port = test_port(&mut host, &mut api, environment);
    port.destination = request.keychain.clone();
    port.before = Some(Preferences {
        default: LOGIN.into(),
        search: vec![LOGIN.into(), OTHER.into()],
    });
    port.host.prints_at(0, "\"/tmp/concurrent\"");
    assert!(port.preferences(&request, Activation::Preserve).is_err());
    assert!(
        !port
            .host
            .transcript()
            .iter()
            .any(|line| line.contains("\"-s\""))
    );
    for position in [2, 3] {
        let mut host = prepared_host();
        let mut api = Api::new();
        let mut port = test_port(&mut host, &mut api, environment);
        port.destination = request.keychain.clone();
        port.before = Some(Preferences {
            default: LOGIN.into(),
            search: vec![LOGIN.into(), OTHER.into()],
        });
        port.host.prints_at(position, "\"/tmp/concurrent\"");
        assert!(port.preferences(&request, Activation::Preserve).is_err());
    }
    Ok(())
}

#[test]
fn refuses_unprepared_operations_and_drops_the_owned_handle_before_deletion() -> Result<()> {
    let (_scratch, request) = fixture("installer-unprepared")?;
    let mut host = prepared_host();
    let mut api = Api::new();
    let mut port = test_port(&mut host, &mut api, environment);
    let verified = VerifiedInstaller {
        fingerprint: request.fingerprint.clone(),
        subject: imported().subject,
    };
    assert!(port.identities(&request).is_err());
    assert!(port.configure(&request, &verified).is_err());
    assert!(port.preferences(&request, Activation::Preserve).is_err());
    port.keychain = Some(request.keychain.clone());
    port.password = "keychain-test-password".into();
    assert!(port.identities(&request).is_err());
    port.destination = request.keychain.clone();
    port.delete(&request)?;
    assert!(port.keychain.is_none());
    assert!(
        port.host
            .transcript()
            .last()
            .unwrap()
            .ends_with(&format!("\"{}\"", request.keychain.display()))
    );
    Ok(())
}

#[derive(Default)]
struct PolicyBranches {
    found: bool,
}

impl<'ast> syn::visit::Visit<'ast> for PolicyBranches {
    fn visit_macro(&mut self, _: &'ast syn::Macro) {
        self.found = true;
    }

    fn visit_expr(&mut self, expression: &'ast syn::Expr) {
        self.found |= matches!(
            expression,
            syn::Expr::If(_)
                | syn::Expr::Match(_)
                | syn::Expr::Binary(_)
                | syn::Expr::Loop(_)
                | syn::Expr::ForLoop(_)
                | syn::Expr::While(_)
                | syn::Expr::Macro(_)
        );
        if let syn::Expr::MethodCall(call) = expression {
            self.found |= matches!(
                call.method.to_string().as_str(),
                "any"
                    | "all"
                    | "find"
                    | "find_map"
                    | "filter"
                    | "filter_map"
                    | "take_while"
                    | "skip_while"
                    | "position"
                    | "rposition"
                    | "map_or"
                    | "map_or_else"
                    | "unwrap_or"
                    | "unwrap_or_else"
                    | "or"
                    | "or_else"
                    | "and"
                    | "and_then"
                    | "is_some_and"
                    | "is_none_or"
                    | "starts_with"
                    | "ends_with"
                    | "contains"
            );
        }
        syn::visit::visit_expr(self, expression);
    }
}

fn has_policy(source: &str) -> bool {
    use syn::visit::Visit as _;
    let mut policy = PolicyBranches::default();
    policy.visit_file(&syn::parse_file(source).unwrap());
    policy.found
}

#[test]
fn keeps_policy_out_of_the_platform_api_translation() {
    assert!(!has_policy(include_str!("security.rs")));
    for source in [
        "fn adapter() { if valid { import(); } }",
        "fn adapter() { match result { Some(value) => value, None => fallback } }",
        "fn adapter() { valid && trusted; }",
        "fn adapter() { expected == actual; }",
        "fn adapter() { loop { retry(); } }",
        "fn adapter() { for item in inputs { import(item); } }",
        "fn adapter() { while pending { retry(); } }",
        "fn adapter() { ensure!(trusted); }",
        "fn adapter() { identities.any(valid); }",
        "fn adapter() { value.unwrap_or(fallback); }",
        "fn adapter() { subject.starts_with(prefix); }",
    ] {
        assert!(has_policy(source), "{source}");
    }
}
