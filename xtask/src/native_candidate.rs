use crate::sbom::admit_native as admit_sbom;
use crate::{
    app_version::AppVersion,
    failure::{Context, Failure, Result, ensure},
    host::{Host, Invocation, Streams},
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::BTreeSet;
use std::num::NonZeroU64;
use std::path::Path;

const BUILDER: &str = "P4suta/gymemo/.github/workflows/native-candidate.yml@refs/heads/main";

pub fn run(host: &mut impl Host, root: &Path, arguments: &[String], seal: bool) -> Result<()> {
    let selection = Selection::parse(arguments)?;
    crate::qualification::require(host, root, &selection.source)?;
    let version = capture(
        host,
        root,
        Invocation::new("git").args([
            "show",
            &format!("{}:Config/MarketingVersion.txt", selection.source),
        ]),
    )?;
    let version = AppVersion::parse(version.trim())?;
    let identity = CandidateIdentity {
        source: selection.source,
        version: version.to_string(),
        platform: selection.platform,
        run_id: selection.run_id,
        build_number: selection.run_id,
        attempt: 1,
    };
    if seal {
        seal_candidate(host, root, &identity, &version)?;
    } else {
        verify_candidate(host, root, &identity)?;
    }
    host.print(&format!(
        "PASS native candidate: {} build {} for {}",
        identity.version, identity.build_number, identity.source
    ));
    Ok(())
}

struct Selection {
    platform: Platform,
    source: String,
    run_id: NonZeroU64,
}

impl Selection {
    fn parse(arguments: &[String]) -> Result<Self> {
        ensure(arguments.len() == 3, || {
            "Native candidate commands require PLATFORM SOURCE_SHA RUN_ID".into()
        })?;
        let platform = Platform::parse(&arguments[0])?;
        ensure(hex(&arguments[1], 40), || {
            "Native candidates require a full lowercase source commit identifier".into()
        })?;
        let number = |value: &str| -> Result<NonZeroU64> {
            ensure(
                !value.starts_with('0') && value.bytes().all(|b| b.is_ascii_digit()),
                || "Native build and run identifiers require canonical positive integers".into(),
            )?;
            value
                .parse::<NonZeroU64>()
                .context(|| "Read the native build or run identifier".into())
        };
        Ok(Self {
            platform,
            source: arguments[1].clone(),
            run_id: number(&arguments[2])?,
        })
    }
}

fn capture(host: &mut impl Host, root: &Path, invocation: Invocation) -> Result<String> {
    let invocation = invocation.current_dir(root);
    let output = host
        .run(&invocation, Streams::Captured)
        .context(|| format!("Start {invocation}"))?;
    ensure(output.status.success(), || {
        format!(
            "{invocation} failed: {}",
            String::from_utf8_lossy(&output.stderr)
        )
    })?;
    String::from_utf8(output.stdout).context(|| format!("Read text from {invocation}"))
}

fn metadata(host: &mut impl Host, root: &Path, invocation: Invocation) -> Result<Value> {
    serde_json::from_str(&capture(host, root, invocation)?)
        .context(|| "Read native candidate metadata".into())
}

fn digest(host: &mut impl Host, root: &Path, path: &Path) -> Result<String> {
    let output = capture(
        host,
        root,
        Invocation::new("shasum").args(["-a", "256"]).arg(path),
    )?;
    let digest = output.split_whitespace().next().unwrap_or("");
    ensure(hex(digest, 64), || {
        "The native artifact checksum is missing or malformed".into()
    })?;
    Ok(digest.into())
}

fn archive_inventory(
    host: &mut impl Host,
    root: &Path,
    identity: &CandidateIdentity,
    version: &AppVersion,
) -> Result<Vec<InventoryEntry>> {
    let archive = root.join("target/gymemo.xcarchive");
    let files = host
        .files(&archive)
        .context(|| "List the preserved native archive".into())?;
    ensure(
        files.iter().all(|path| {
            !path.components().any(|part| {
                part.as_os_str()
                    .to_str()
                    .is_some_and(|name| name.ends_with(".framework") || name.ends_with(".dylib"))
            })
        }),
        || "Embedded native dependencies require an explicit SBOM and dependency policy".into(),
    )?;
    let dependencies = metadata(
        host,
        root,
        Invocation::new("swift").args(["package", "show-dependencies", "--format", "json"]),
    )?;
    ensure(
        dependencies["dependencies"]
            .as_array()
            .is_some_and(Vec::is_empty),
        || {
            "External Swift dependencies require an explicit license and vulnerability policy"
                .into()
        },
    )?;
    let properties = metadata(
        host,
        root,
        Invocation::new("plutil")
            .args(["-extract", "ApplicationProperties", "json", "-o", "-"])
            .arg(archive.join("Info.plist")),
    )?;
    ensure(
        properties["ApplicationPath"] == "Applications/gymemo.app"
            && properties["CFBundleIdentifier"] == "com.p4suta.gymemo"
            && properties["CFBundleShortVersionString"] == identity.version
            && properties["CFBundleVersion"] == identity.build_number.to_string(),
        || "The Xcode archive properties differ from the native candidate".into(),
    )?;
    let mut bundles = Vec::new();
    let mut info_paths = BTreeSet::new();
    for role in identity.platform.roles() {
        let base = archive.join(if matches!(role, BundleRole::Watch) {
            "Products/Applications/gymemo.app/Watch/gymemoWatch.app"
        } else {
            "Products/Applications/gymemo.app"
        });
        let mac = matches!(role, BundleRole::Macos);
        let info = base.join(if mac {
            "Contents/Info.plist"
        } else {
            "Info.plist"
        });
        info_paths.insert(info.clone());
        let executable = base.join(if mac {
            "Contents/MacOS/gymemo"
        } else if matches!(role, BundleRole::Watch) {
            "gymemoWatch"
        } else {
            "gymemo"
        });
        let privacy = base.join(if mac {
            "Contents/Resources/PrivacyInfo.xcprivacy"
        } else {
            "PrivacyInfo.xcprivacy"
        });
        let plist = |path: &Path| {
            Invocation::new("plutil")
                .args(["-convert", "json", "-o", "-"])
                .arg(path)
        };
        let information = metadata(host, root, plist(&info))?;
        let privacy_information = metadata(host, root, plist(&privacy))?;
        let architectures = capture(
            host,
            root,
            Invocation::new("xcrun")
                .args(["lipo", "-archs"])
                .arg(&executable),
        )?
        .split_whitespace()
        .map(str::to_owned)
        .collect();
        let bundle = admit_bundle(
            role,
            version,
            &identity.build_number.to_string(),
            ObservedBundle {
                info: information,
                privacy: privacy_information,
                architectures,
            },
        )?;
        bundles.push(InventoryEntry {
            bundle,
            executable_sha256: digest(host, root, &executable)?,
            privacy_sha256: digest(host, root, &privacy)?,
        });
    }
    let observed = files
        .into_iter()
        .filter(|path| {
            path.to_string_lossy().ends_with(".app/Info.plist")
                || path.to_string_lossy().ends_with(".app/Contents/Info.plist")
        })
        .collect::<BTreeSet<_>>();
    ensure(observed == info_paths, || {
        "The native archive contains an undeclared app bundle or lacks a required bundle".into()
    })?;
    Ok(bundles)
}

fn seal_candidate(
    host: &mut impl Host,
    root: &Path,
    identity: &CandidateIdentity,
    version: &AppVersion,
) -> Result<()> {
    let head = capture(
        host,
        root,
        Invocation::new("git").args(["rev-parse", "--verify", "HEAD"]),
    )?;
    let state = capture(
        host,
        root,
        Invocation::new("git").args(["status", "--porcelain=v1", "--untracked-files=normal"]),
    )?;
    ensure(
        head.trim() == identity.source && state.trim().is_empty(),
        || "Native candidates require the selected clean source checkout".into(),
    )?;
    ensure(
        !host.exists(&root.join("native-candidate.tar"))
            && !host.exists(&root.join("native-candidate.json")),
        || "A preserved native candidate must not be overwritten".into(),
    )?;
    let bundles = archive_inventory(host, root, identity, version)?;
    let sbom_path = root.join("target/native-sbom.cdx.json");
    capture(
        host,
        root,
        Invocation::new("syft").args([
            "scan",
            "dir:target/gymemo.xcarchive",
            "--source-name",
            "gymemo",
            "--source-version",
            &identity.version,
            "--parallelism",
            "2",
            "--output",
            "cyclonedx-json=target/native-sbom.cdx.json",
        ]),
    )?;
    let sbom = host
        .read(&sbom_path)
        .context(|| "Read the archived dependency inventory".into())?;
    admit_sbom(&sbom, &identity.version)?;
    let sbom_digest = digest(host, root, &sbom_path)?;
    capture(
        host,
        root,
        Invocation::new("tar").args([
            "--create",
            "--file",
            "native-candidate.tar",
            "--directory",
            "target",
            "gymemo.xcarchive",
            "native-sbom.cdx.json",
        ]),
    )?;
    let artifact_digest = digest(host, root, &root.join("native-candidate.tar"))?;
    let candidate = CandidateManifest {
        schema: 1,
        repository: "P4suta/gymemo".into(),
        repository_id: 1453033797,
        builder: BUILDER.into(),
        identity: identity.clone(),
        artifact: FileDigest {
            name: "native-candidate.tar".into(),
            sha256: artifact_digest.clone(),
        },
        sbom: FileDigest {
            name: "native-sbom.cdx.json".into(),
            sha256: sbom_digest,
        },
        bundles,
        checks: vec![CheckOutcome {
            context: "Local qualification".into(),
            state: "success".into(),
            creator_id: 42543015,
        }],
    };
    let text = serde_json::to_string_pretty(&candidate)
        .context(|| "Encode the native candidate manifest".into())?;
    admit_manifest(&text, identity, &artifact_digest)?;
    host.write(&root.join("native-candidate.json"), &format!("{text}\n"))
        .context(|| "Preserve the native candidate manifest".into())
}

fn verify_candidate(host: &mut impl Host, root: &Path, identity: &CandidateIdentity) -> Result<()> {
    for artifact in ["native-candidate.tar", "native-candidate.json"] {
        capture(
            host,
            root,
            Invocation::new("gh").args([
                "attestation",
                "verify",
                artifact,
                "--repo",
                "P4suta/gymemo",
                "--signer-workflow",
                "P4suta/gymemo/.github/workflows/native-candidate.yml",
                "--source-ref",
                "refs/heads/main",
                "--source-digest",
                &identity.source,
                "--signer-digest",
                &identity.source,
            ]),
        )?;
    }
    let run = metadata(
        host,
        root,
        Invocation::new("gh").args([
            "api",
            &format!("repos/P4suta/gymemo/actions/runs/{}", identity.run_id),
        ]),
    )?;
    ensure(
        run["id"].as_u64() == Some(identity.run_id.get())
            && run["head_sha"] == identity.source
            && run["head_branch"] == "main"
            && run["event"] == "workflow_dispatch"
            && run["path"] == ".github/workflows/native-candidate.yml"
            && run["conclusion"] == "success"
            && run["head_repository"]["id"] == 1453033797_u64,
        || {
            "The native artifact does not belong to the selected successful protected candidate run"
                .into()
        },
    )?;
    let text = host
        .read(&root.join("native-candidate.json"))
        .context(|| "Read the preserved native manifest".into())?;
    let sha256 = digest(host, root, &root.join("native-candidate.tar"))?;
    let manifest = admit_manifest(&text, identity, &sha256)?;
    let listing = capture(
        host,
        root,
        Invocation::new("tar").args(["--list", "--file", "native-candidate.tar"]),
    )?;
    let entries = listing.lines().collect::<Vec<_>>();
    ensure(
        entries
            .iter()
            .filter(|path| **path == "native-sbom.cdx.json")
            .count()
            == 1
            && entries.contains(&"gymemo.xcarchive/Info.plist")
            && entries.iter().all(|path| {
                (*path == "native-sbom.cdx.json" || path.starts_with("gymemo.xcarchive/"))
                    && path.split('/').all(|part| part != ".." && part != ".")
            }),
        || "The native archive contains an unsafe or unexpected path".into(),
    )?;
    let sbom = capture(
        host,
        root,
        Invocation::new("tar").args([
            "--extract",
            "--to-stdout",
            "--file",
            "native-candidate.tar",
            "native-sbom.cdx.json",
        ]),
    )?;
    admit_sbom(&sbom, &identity.version)?;
    host.create_directories(&root.join("target"))
        .context(|| "Create the native inventory check directory".into())?;
    let path = root.join("target/native-sbom.cdx.json");
    host.write(&path, &sbom)
        .context(|| "Read back the preserved native SBOM bytes".into())?;
    ensure(digest(host, root, &path)? == manifest.sbom.sha256, || {
        "The preserved SBOM differs from the native manifest".into()
    })
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
struct CandidateIdentity {
    source: String,
    version: String,
    platform: Platform,
    run_id: NonZeroU64,
    build_number: NonZeroU64,
    attempt: u32,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
struct WireIdentity {
    source: String,
    version: String,
    platform: Platform,
    run_id: NonZeroU64,
    build_number: NonZeroU64,
    attempt: u32,
}

#[derive(Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
struct FileDigest {
    name: String,
    sha256: String,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
struct WireBundle {
    identifier: String,
    platform: String,
    architectures: BTreeSet<String>,
    executable_sha256: String,
    privacy_sha256: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct InventoryEntry {
    #[serde(flatten)]
    bundle: Bundle,
    executable_sha256: String,
    privacy_sha256: String,
}

#[derive(Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
struct CheckOutcome {
    context: String,
    state: String,
    creator_id: u64,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields, rename_all = "camelCase")]
struct WireManifest {
    schema: u32,
    repository: String,
    repository_id: u64,
    builder: String,
    identity: WireIdentity,
    artifact: FileDigest,
    sbom: FileDigest,
    bundles: Vec<WireBundle>,
    checks: Vec<CheckOutcome>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct CandidateManifest {
    schema: u32,
    repository: String,
    repository_id: u64,
    builder: String,
    identity: CandidateIdentity,
    artifact: FileDigest,
    sbom: FileDigest,
    bundles: Vec<InventoryEntry>,
    checks: Vec<CheckOutcome>,
}

fn admit_manifest(
    text: &str,
    expected: &CandidateIdentity,
    sha256: &str,
) -> Result<CandidateManifest> {
    let wire: WireManifest =
        serde_json::from_str(text).context(|| "Read the native candidate manifest".into())?;
    let identity = CandidateIdentity {
        source: wire.identity.source,
        version: wire.identity.version,
        platform: wire.identity.platform,
        run_id: wire.identity.run_id,
        build_number: wire.identity.build_number,
        attempt: wire.identity.attempt,
    };
    ensure(
        wire.schema == 1
            && wire.repository == "P4suta/gymemo"
            && wire.repository_id == 1453033797
            && wire.builder == BUILDER
            && identity == *expected
            && identity.attempt == 1,
        || "The native candidate differs from the selected protected build".into(),
    )?;
    ensure(
        wire.artifact.name == "native-candidate.tar"
            && hex(&wire.artifact.sha256, 64)
            && wire.artifact.sha256 == sha256
            && wire.sbom.name == "native-sbom.cdx.json"
            && hex(&wire.sbom.sha256, 64),
        || "The native candidate artifact or SBOM digest differs".into(),
    )?;
    let roles = expected.platform.roles();
    ensure(wire.bundles.len() == roles.len(), || {
        "The native candidate bundle inventory is incomplete".into()
    })?;
    let mut bundles = Vec::new();
    for (bundle, role) in wire.bundles.into_iter().zip(roles) {
        let (identifier, _, platform, _, architectures) = role.contract();
        ensure(
            bundle.identifier == identifier
                && bundle.platform == platform
                && bundle.architectures == architectures.into_iter().map(str::to_owned).collect()
                && hex(&bundle.executable_sha256, 64)
                && hex(&bundle.privacy_sha256, 64),
            || "The native candidate bundle inventory differs".into(),
        )?;
        bundles.push(InventoryEntry {
            bundle: Bundle {
                identifier: bundle.identifier,
                platform: bundle.platform,
                architectures: bundle.architectures,
            },
            executable_sha256: bundle.executable_sha256,
            privacy_sha256: bundle.privacy_sha256,
        });
    }
    ensure(
        wire.checks.len() == 1
            && wire.checks[0].context == "Local qualification"
            && wire.checks[0].state == "success"
            && wire.checks[0].creator_id == 42543015,
        || "The native candidate lacks the owner's successful local qualification".into(),
    )?;
    Ok(CandidateManifest {
        schema: wire.schema,
        repository: wire.repository,
        repository_id: wire.repository_id,
        builder: wire.builder,
        identity,
        artifact: wire.artifact,
        sbom: wire.sbom,
        bundles,
        checks: wire.checks,
    })
}

fn hex(value: &str, length: usize) -> bool {
    value.len() == length
        && value
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

#[derive(Clone, Debug, Deserialize, PartialEq, Eq, Serialize)]
pub enum Platform {
    #[serde(rename = "iOS")]
    Ios,
    #[serde(rename = "macOS")]
    Macos,
    #[serde(rename = "visionOS")]
    Visionos,
}

impl Platform {
    fn parse(value: &str) -> Result<Self> {
        match value {
            "iOS" => Ok(Self::Ios),
            "macOS" => Ok(Self::Macos),
            "visionOS" => Ok(Self::Visionos),
            _ => Err(Failure::new(
                "The native platform must be iOS, macOS, or visionOS",
            )),
        }
    }

    fn roles(&self) -> Vec<BundleRole> {
        match self {
            Self::Ios => vec![BundleRole::Ios, BundleRole::Watch],
            Self::Macos => vec![BundleRole::Macos],
            Self::Visionos => vec![BundleRole::Visionos],
        }
    }
}

#[derive(Clone, Copy)]
enum BundleRole {
    Ios,
    Macos,
    Visionos,
    Watch,
}

impl BundleRole {
    fn contract(
        self,
    ) -> (
        &'static str,
        &'static str,
        &'static str,
        &'static str,
        Vec<&'static str>,
    ) {
        match self {
            Self::Ios => (
                "com.p4suta.gymemo",
                "gymemo",
                "iPhoneOS",
                "MinimumOSVersion",
                vec!["arm64"],
            ),
            Self::Macos => (
                "com.p4suta.gymemo",
                "gymemo",
                "MacOSX",
                "LSMinimumSystemVersion",
                vec!["arm64", "x86_64"],
            ),
            Self::Visionos => (
                "com.p4suta.gymemo",
                "gymemo",
                "XROS",
                "MinimumOSVersion",
                vec!["arm64"],
            ),
            Self::Watch => (
                "com.p4suta.gymemo.watchkitapp",
                "gymemoWatch",
                "WatchOS",
                "MinimumOSVersion",
                vec!["arm64", "arm64_32"],
            ),
        }
    }
}

struct ObservedBundle {
    info: Value,
    privacy: Value,
    architectures: BTreeSet<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct Bundle {
    identifier: String,
    platform: String,
    architectures: BTreeSet<String>,
}

fn admit_bundle(
    role: BundleRole,
    version: &AppVersion,
    build: &str,
    observed: ObservedBundle,
) -> Result<Bundle> {
    let (identifier, executable, platform, minimum, architectures) = role.contract();
    let expected_version = version.to_string();
    ensure(
        observed.info["CFBundleIdentifier"].as_str() == Some(identifier)
            && observed.info["CFBundleExecutable"].as_str() == Some(executable)
            && observed.info["CFBundleSupportedPlatforms"] == serde_json::json!([platform])
            && observed.info["CFBundleShortVersionString"].as_str() == Some(&expected_version)
            && observed.info["CFBundleVersion"].as_str() == Some(build)
            && observed.info[minimum].as_str() == Some("26.0"),
        || {
            "The native bundle differs from its declared identity, version, platform, or deployment floor".into()
        },
    )?;
    let expected = architectures
        .into_iter()
        .map(str::to_owned)
        .collect::<BTreeSet<_>>();
    ensure(observed.architectures == expected, || {
        "The native bundle lacks a required architecture or contains an unexpected architecture"
            .into()
    })?;
    ensure(
        observed.privacy["NSPrivacyTracking"].as_bool() == Some(false)
            && observed.privacy["NSPrivacyCollectedDataTypes"]
                .as_array()
                .is_some_and(Vec::is_empty),
        || "The native bundle must declare no tracking and no collected data".into(),
    )?;
    if matches!(role, BundleRole::Watch) {
        ensure(
            observed.info["WKCompanionAppBundleIdentifier"].as_str() == Some("com.p4suta.gymemo")
                && observed.info["WKRunsIndependentlyOfCompanionApp"].as_bool() == Some(false),
            || "The Watch bundle must use its declared paired iPhone companion".into(),
        )?;
    }
    Ok(Bundle {
        identifier: identifier.into(),
        platform: platform.into(),
        architectures: observed.architectures,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::host::fake::{FakeHost, Fault};
    use serde_json::json;

    fn arguments() -> Vec<String> {
        ["iOS", "0123456789abcdef0123456789abcdef01234567", "1234"]
            .map(str::to_owned)
            .to_vec()
    }

    fn sbom() -> String {
        json!({"bomFormat":"CycloneDX","specVersion":"1.7","metadata":{"component":{"name":"gymemo","version":"1.0.0"}},"components":[{"type":"library","name":"gymemo","version":"1.0.0"}]}).to_string()
    }

    #[test]
    fn the_sbom_names_the_candidate_and_refuses_uncovered_libraries() -> Result<()> {
        admit_sbom(&sbom(), "1.0.0")?;
        for (pointer, replacement) in [
            ("/bomFormat", json!("another")),
            ("/specVersion", json!("unknown")),
            ("/metadata/component/name", json!("another")),
            ("/metadata/component/version", json!("1.0.1")),
            ("/components/0/name", json!("third-party-library")),
            ("/components/0/version", json!("1.0.1")),
            ("/components/0/type", json!("framework")),
        ] {
            let mut invalid: Value = serde_json::from_str(&sbom()).unwrap();
            *invalid.pointer_mut(pointer).unwrap() = replacement;
            assert!(
                admit_sbom(&invalid.to_string(), "1.0.0").is_err(),
                "{pointer}"
            );
        }
        assert!(admit_sbom("{}", "1.0.0").is_err());
        Ok(())
    }

    fn prepare_verification() -> FakeHost {
        let mut host = FakeHost::new();
        let source = &arguments()[1];
        host.prints("\"repos/P4suta/gymemo\"",&json!({"id":1453033797,"owner":{"id":42543015},"default_branch":"main","private":false}).to_string());
        host.prints(
            "repos/P4suta/gymemo/compare/",
            &json!({"status":"identical","ahead_by":0,"merge_base_commit":{"sha":source}})
                .to_string(),
        );
        host.prints("/statuses?",&json!([{"context":"Local qualification","state":"success","creator":{"id":42543015},"url":format!("https://api.github.com/repos/P4suta/gymemo/statuses/{source}")}]).to_string());
        host.prints("\"show\"", "1.0.0\n");
        host.prints("actions/runs/1234", &json!({"id":1234,"run_number":17,"head_sha":source,"head_branch":"main","event":"workflow_dispatch","path":".github/workflows/native-candidate.yml","conclusion":"success","head_repository":{"id":1453033797}}).to_string());
        host.file("/repo/native-candidate.json", &manifest().to_string());
        host.prints("\"shasum\"", &format!("{}  file\n", "a".repeat(64)));
        host.prints(
            "\"--list\"",
            "gymemo.xcarchive/Info.plist\nnative-sbom.cdx.json\n",
        );
        host.prints("\"--to-stdout\"", &sbom());
        let mut value = manifest();
        value["sbom"]["sha256"] = json!("a".repeat(64));
        host.file("/repo/native-candidate.json", &value.to_string());
        host
    }

    #[test]
    fn verifies_preserved_bytes_and_current_owner_qualification_before_admission() -> Result<()> {
        let mut host = prepare_verification();
        run(&mut host, Path::new("/repo"), &arguments(), false)?;
        assert!(
            host.output
                .iter()
                .any(|message| message.contains("PASS native candidate"))
        );
        assert!(
            !host
                .transcript()
                .iter()
                .any(|line| line.contains("\"syft\"") || line.contains("xcodebuild"))
        );
        Ok(())
    }

    #[test]
    fn refuses_bad_arguments_before_any_external_program() {
        for position in 0..3 {
            for invalid in ["", "../value", "bad\nvalue", "0"] {
                let mut values = arguments();
                values[position] = invalid.into();
                let mut host = FakeHost::new();
                assert!(run(&mut host, Path::new("/repo"), &values, false).is_err());
                assert!(host.transcript().is_empty());
            }
        }
    }

    fn prepare_sealing() -> FakeHost {
        let mut host = prepare_verification();
        host.remove_file(Path::new("/repo/native-candidate.json"))
            .unwrap();
        host.prints("\"rev-parse\"", &arguments()[1]);
        host.prints("\"status\" \"--porcelain=v1\"", "");
        host.prints("\"show-dependencies\"", "{\"dependencies\":[]}");
        host.prints("\"-extract\" \"ApplicationProperties\"",&json!({"ApplicationPath":"Applications/gymemo.app","CFBundleIdentifier":"com.p4suta.gymemo","CFBundleShortVersionString":"1.0.0","CFBundleVersion":"1234"}).to_string());
        for (role, directory, executable) in [
            (
                BundleRole::Ios,
                "Products/Applications/gymemo.app",
                "gymemo",
            ),
            (
                BundleRole::Watch,
                "Products/Applications/gymemo.app/Watch/gymemoWatch.app",
                "gymemoWatch",
            ),
        ] {
            let base = format!("/repo/target/gymemo.xcarchive/{directory}");
            let mut observed = observed(role);
            observed.info["CFBundleVersion"] = json!("1234");
            for (file, value) in [
                ("Info.plist", observed.info),
                ("PrivacyInfo.xcprivacy", observed.privacy),
            ] {
                let path = format!("{base}/{file}");
                host.file(&path, "plist");
                host.prints(
                    &format!("\"plutil\" \"-convert\" \"json\" \"-o\" \"-\" \"{path}\""),
                    &value.to_string(),
                );
            }
            host.prints(
                &format!("\"lipo\" \"-archs\" \"{base}/{executable}\""),
                if matches!(role, BundleRole::Watch) {
                    "arm64 arm64_32\n"
                } else {
                    "arm64\n"
                },
            );
        }
        host.writes("\"syft\"", "/repo/target/native-sbom.cdx.json", &sbom());
        host.writes("\"--create\"", "/repo/native-candidate.tar", "archive");
        host
    }

    #[test]
    fn sealing_reads_the_archive_and_sbom_before_preserving_the_manifest() -> Result<()> {
        let mut host = prepare_sealing();
        run(&mut host, Path::new("/repo"), &arguments(), true)?;
        let text = host.read(Path::new("/repo/native-candidate.json")).unwrap();
        let manifest = admit_manifest(&text, &identity(), &"a".repeat(64))?;
        assert_eq!(manifest.bundles.len(), 2);
        assert_eq!(manifest.sbom.sha256, "a".repeat(64));
        assert!(run(&mut host, Path::new("/repo"), &arguments(), true).is_err());
        Ok(())
    }

    #[test]
    fn a_failed_sealing_program_never_preserves_a_candidate_manifest() -> Result<()> {
        let mut clean = prepare_sealing();
        run(&mut clean, Path::new("/repo"), &arguments(), true)?;
        let programs = clean
            .transcript()
            .iter()
            .filter(|line| line.starts_with("capture "))
            .count();
        assert!(programs > 10);
        for position in 0..programs {
            let mut host = prepare_sealing();
            host.fail_at(position, Fault::Exit(1, "boundary failed"));
            assert!(
                run(&mut host, Path::new("/repo"), &arguments(), true).is_err(),
                "{position}"
            );
            assert!(
                !host.exists(Path::new("/repo/native-candidate.json")),
                "{position}"
            );
        }
        Ok(())
    }

    #[test]
    fn verification_refuses_changed_run_metadata_paths_sbom_and_origin() {
        let mut base = prepare_verification();
        let run_json = metadata(
            &mut base,
            Path::new("/repo"),
            Invocation::new("gh").args(["api", "repos/P4suta/gymemo/actions/runs/1234"]),
        )
        .unwrap();
        for (pointer, replacement) in [
            ("/id", json!(1235)),
            ("/head_sha", json!("f".repeat(40))),
            ("/head_branch", json!("feature")),
            ("/event", json!("pull_request")),
            ("/path", json!("another.yml")),
            ("/conclusion", json!("failure")),
            ("/head_repository/id", json!(1)),
        ] {
            let mut invalid = run_json.clone();
            *invalid.pointer_mut(pointer).unwrap() = replacement;
            let mut host = prepare_verification();
            host.prints("actions/runs/1234", &invalid.to_string());
            assert!(
                run(&mut host, Path::new("/repo"), &arguments(), false).is_err(),
                "{pointer}"
            );
        }
        for listing in [
            "gymemo.xcarchive/../private\nnative-sbom.cdx.json\n",
            "/private\n",
            "native-sbom.cdx.json\nnative-sbom.cdx.json\ngymemo.xcarchive/Info.plist\n",
        ] {
            let mut host = prepare_verification();
            host.prints("\"--list\"", listing);
            assert!(run(&mut host, Path::new("/repo"), &arguments(), false).is_err());
        }
        for (part, output) in [("\"--to-stdout\"", "{}"), ("\"shasum\"", "not-a-digest")] {
            let mut host = prepare_verification();
            host.prints(part, output);
            assert!(run(&mut host, Path::new("/repo"), &arguments(), false).is_err());
        }
        for part in ["\"attestation\"", "actions/runs/1234", "\"--to-stdout\""] {
            let mut host = prepare_verification();
            host.fail(part, Fault::Exit(1, "refused"));
            assert!(run(&mut host, Path::new("/repo"), &arguments(), false).is_err());
        }
    }

    fn identity() -> CandidateIdentity {
        CandidateIdentity {
            source: "0123456789abcdef0123456789abcdef01234567".into(),
            version: "1.0.0".into(),
            platform: Platform::Ios,
            run_id: NonZeroU64::new(1234).unwrap(),
            build_number: NonZeroU64::new(1234).unwrap(),
            attempt: 1,
        }
    }

    fn manifest() -> Value {
        let bundle = |identifier, platform, architectures: Vec<&str>| json!({"identifier":identifier,"platform":platform,"architectures":architectures,"executableSha256":"c".repeat(64),"privacySha256":"d".repeat(64)});
        json!({"schema":1,"repository":"P4suta/gymemo","repositoryId":1453033797_u64,"builder":BUILDER,"identity":identity(),"artifact":{"name":"native-candidate.tar","sha256":"a".repeat(64)},"sbom":{"name":"native-sbom.cdx.json","sha256":"b".repeat(64)},"bundles":[bundle("com.p4suta.gymemo","iPhoneOS",vec!["arm64"]),bundle("com.p4suta.gymemo.watchkitapp","WatchOS",vec!["arm64","arm64_32"])],"checks":[{"context":"Local qualification","state":"success","creatorId":42543015}]})
    }

    #[test]
    fn a_manifest_binds_the_expected_source_run_target_version_and_bytes() -> Result<()> {
        let accepted = admit_manifest(&manifest().to_string(), &identity(), &"a".repeat(64))?;
        assert_eq!(accepted.identity, identity());
        assert_eq!(accepted.bundles.len(), 2);
        Ok(())
    }

    #[test]
    fn each_changed_identity_digest_inventory_or_outcome_is_refused() {
        for (pointer, replacement) in [
            ("/schema", json!(2)),
            ("/repository", json!("another/gymemo")),
            ("/repositoryId", json!(1)),
            ("/builder", json!("another.yml@refs/heads/main")),
            ("/identity/source", json!("f".repeat(40))),
            ("/identity/version", json!("1.0.1")),
            ("/identity/platform", json!("macOS")),
            ("/identity/runId", json!(1235)),
            ("/identity/runId", json!(0)),
            ("/identity/buildNumber", json!(18)),
            ("/identity/attempt", json!(2)),
            ("/artifact/name", json!("../native-candidate.tar")),
            ("/artifact/sha256", json!("f".repeat(64))),
            ("/sbom/name", json!("another.json")),
            ("/sbom/sha256", json!("not-a-digest")),
            ("/bundles", json!([])),
            ("/bundles/0/identifier", json!("another")),
            ("/bundles/0/platform", json!("iPhoneSimulator")),
            ("/bundles/0/architectures", json!(["arm64", "x86_64"])),
            ("/bundles/1/architectures", json!(["arm64"])),
            ("/bundles/0/executableSha256", json!("bad")),
            ("/bundles/0/privacySha256", json!("bad")),
            ("/checks", json!([])),
            ("/checks/0/context", json!("another")),
            ("/checks/0/state", json!("pending")),
            ("/checks/0/creatorId", json!(1)),
        ] {
            let mut invalid = manifest();
            *invalid.pointer_mut(pointer).unwrap() = replacement;
            assert!(
                admit_manifest(&invalid.to_string(), &identity(), &"a".repeat(64)).is_err(),
                "{pointer}"
            );
        }
        assert!(admit_manifest(&manifest().to_string(), &identity(), &"e".repeat(64)).is_err());
        let mut invalid = manifest();
        invalid["unexpected"] = json!(true);
        assert!(admit_manifest(&invalid.to_string(), &identity(), &"a".repeat(64)).is_err());
    }

    fn observed(role: BundleRole) -> ObservedBundle {
        let (identifier, executable, platform, minimum, architectures) = match role {
            BundleRole::Ios => (
                "com.p4suta.gymemo",
                "gymemo",
                "iPhoneOS",
                "MinimumOSVersion",
                vec!["arm64"],
            ),
            BundleRole::Macos => (
                "com.p4suta.gymemo",
                "gymemo",
                "MacOSX",
                "LSMinimumSystemVersion",
                vec!["arm64", "x86_64"],
            ),
            BundleRole::Visionos => (
                "com.p4suta.gymemo",
                "gymemo",
                "XROS",
                "MinimumOSVersion",
                vec!["arm64"],
            ),
            BundleRole::Watch => (
                "com.p4suta.gymemo.watchkitapp",
                "gymemoWatch",
                "WatchOS",
                "MinimumOSVersion",
                vec!["arm64", "arm64_32"],
            ),
        };
        let mut info = json!({"CFBundleIdentifier":identifier,"CFBundleExecutable":executable,"CFBundleSupportedPlatforms":[platform],"CFBundleShortVersionString":"1.0.0","CFBundleVersion":"17"});
        info[minimum] = json!("26.0");
        if matches!(role, BundleRole::Watch) {
            info["WKCompanionAppBundleIdentifier"] = json!("com.p4suta.gymemo");
            info["WKRunsIndependentlyOfCompanionApp"] = json!(false);
        }
        ObservedBundle {
            info,
            privacy: json!({"NSPrivacyTracking":false,"NSPrivacyCollectedDataTypes":[]}),
            architectures: architectures.into_iter().map(str::to_owned).collect(),
        }
    }

    #[test]
    fn admits_each_declared_native_bundle_and_both_mac_architectures() -> Result<()> {
        let version = AppVersion::parse("1.0.0")?;
        for role in [
            BundleRole::Ios,
            BundleRole::Macos,
            BundleRole::Visionos,
            BundleRole::Watch,
        ] {
            let bundle = admit_bundle(role, &version, "17", observed(role))?;
            assert_eq!(
                bundle.identifier,
                if matches!(role, BundleRole::Watch) {
                    "com.p4suta.gymemo.watchkitapp"
                } else {
                    "com.p4suta.gymemo"
                }
            );
            assert_eq!(
                bundle.architectures.len(),
                if matches!(role, BundleRole::Macos | BundleRole::Watch) {
                    2
                } else {
                    1
                }
            );
        }
        Ok(())
    }

    #[test]
    fn rejects_each_mismatched_bundle_property() -> Result<()> {
        let version = AppVersion::parse("1.0.0")?;
        for role in [
            BundleRole::Ios,
            BundleRole::Macos,
            BundleRole::Visionos,
            BundleRole::Watch,
        ] {
            for (field, replacement) in [
                ("CFBundleIdentifier", json!("com.p4suta.another")),
                ("CFBundleExecutable", json!("another")),
                ("CFBundleSupportedPlatforms", json!(["iPhoneSimulator"])),
                ("CFBundleShortVersionString", json!("1.0.1")),
                ("CFBundleVersion", json!("18")),
                ("CFBundleVersion", json!(17)),
            ] {
                let mut invalid = observed(role);
                invalid.info[field] = replacement;
                assert!(
                    admit_bundle(role, &version, "17", invalid).is_err(),
                    "{field}"
                );
            }
            let minimum = if matches!(role, BundleRole::Macos) {
                "LSMinimumSystemVersion"
            } else {
                "MinimumOSVersion"
            };
            let mut invalid = observed(role);
            invalid.info[minimum] = json!("27.0");
            assert!(admit_bundle(role, &version, "17", invalid).is_err());
            let mut invalid = observed(role);
            invalid.architectures.remove("arm64");
            assert!(admit_bundle(role, &version, "17", invalid).is_err());
            let mut invalid = observed(role);
            invalid.architectures.insert("armv7".into());
            assert!(admit_bundle(role, &version, "17", invalid).is_err());
            if matches!(role, BundleRole::Macos | BundleRole::Watch) {
                let mut invalid = observed(role);
                invalid
                    .architectures
                    .remove(if matches!(role, BundleRole::Macos) {
                        "x86_64"
                    } else {
                        "arm64_32"
                    });
                assert!(admit_bundle(role, &version, "17", invalid).is_err());
            }
        }
        Ok(())
    }

    #[test]
    fn rejects_tracking_collection_and_a_different_watch_companion() -> Result<()> {
        let version = AppVersion::parse("1.0.0")?;
        for privacy in [
            Value::Null,
            json!({"NSPrivacyTracking":true,"NSPrivacyCollectedDataTypes":[]}),
            json!({"NSPrivacyTracking":false,"NSPrivacyCollectedDataTypes":[{}]}),
        ] {
            let mut invalid = observed(BundleRole::Ios);
            invalid.privacy = privacy;
            assert!(admit_bundle(BundleRole::Ios, &version, "17", invalid).is_err());
        }
        for (field, replacement) in [
            ("WKCompanionAppBundleIdentifier", json!("another")),
            ("WKRunsIndependentlyOfCompanionApp", json!(true)),
        ] {
            let mut invalid = observed(BundleRole::Watch);
            invalid.info[field] = replacement;
            assert!(admit_bundle(BundleRole::Watch, &version, "17", invalid).is_err());
        }
        Ok(())
    }
}
