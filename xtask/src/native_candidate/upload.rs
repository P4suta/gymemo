use super::{
    CandidateIdentity, FileDigest, Platform, Selection, capture, digest, hex, metadata, run_number,
    selected_identity, verify_candidate,
};
use crate::{
    failure::{Context, Failure, Result, ensure},
    host::{Host, Invocation},
    sbom::admit_native,
};
use serde::Serialize;
use serde_json::Value;
use std::{collections::BTreeMap, collections::BTreeSet, num::NonZeroU64, path::Path};

#[derive(Debug, Eq, PartialEq)]
enum Route {
    Delivery,
    Recovery,
}

#[derive(Debug)]
struct Origin {
    source: String,
    route: Route,
}

fn origin(value: &Value, signing: NonZeroU64, current: NonZeroU64) -> Result<Origin> {
    let source = value["head_sha"]
        .as_str()
        .filter(|value| hex(value, 40))
        .ok_or_else(|| Failure::new("The signing workflow requires a full source commit"))?;
    let attempt = value["run_attempt"]
        .as_u64()
        .filter(|value| *value > 0)
        .ok_or_else(|| Failure::new("The signing workflow attempt is missing"))?;
    ensure(
        value["id"].as_u64() == Some(signing.get())
            && value["head_branch"] == "main"
            && value["event"] == "workflow_dispatch"
            && value["path"] == ".github/workflows/native-delivery.yml"
            && value["repository"]["id"] == 1453033797_u64
            && value["head_repository"]["id"] == 1453033797_u64,
        || "The signed package requires the selected protected native delivery run".into(),
    )?;
    let route = if signing == current {
        ensure(attempt == 1 && value["status"] == "in_progress", || {
            "A repeated delivery upload requires provider reconciliation".into()
        })?;
        Route::Delivery
    } else {
        ensure(
            value["status"] == "completed" && value["conclusion"].as_str().is_some(),
            || "Recovery requires a completed original signing workflow".into(),
        )?;
        Route::Recovery
    };
    Ok(Origin {
        source: source.to_owned(),
        route,
    })
}

fn records<'a>(pages: &'a Value, field: &str) -> Result<Vec<&'a Value>> {
    let pages = pages
        .as_array()
        .filter(|pages| !pages.is_empty())
        .ok_or_else(|| Failure::new("Native history requires every response page"))?;
    let total = pages
        .first()
        .and_then(|page| page["total_count"].as_u64())
        .ok_or_else(|| Failure::new("Native history is missing its total count"))?;
    let mut records = Vec::new();
    let mut identities = BTreeSet::new();
    for page in pages {
        ensure(page["total_count"].as_u64() == Some(total), || {
            "Native history changed during pagination".into()
        })?;
        let entries = page[field]
            .as_array()
            .ok_or_else(|| Failure::new("Native history is missing its records"))?;
        for entry in entries {
            let id = entry["id"]
                .as_u64()
                .filter(|id| *id > 0)
                .ok_or_else(|| Failure::new("Native history has an invalid identity"))?;
            ensure(identities.insert(id), || {
                "Native history repeats an identity".into()
            })?;
            records.push(entry);
        }
    }
    ensure(u64::try_from(records.len()).ok() == Some(total), || {
        "Native history is incomplete".into()
    })?;
    Ok(records)
}

fn named(job: &Value, name: &str) -> bool {
    job["name"]
        .as_str()
        .and_then(|name| name.rsplit(" / ").next())
        == Some(name)
}

fn skipped_uploads(jobs: &[&Value]) -> Result<()> {
    let uploads = jobs
        .iter()
        .filter(|job| named(job, "Upload the preserved native package"))
        .collect::<Vec<_>>();
    ensure(!uploads.is_empty(), || {
        "The original upload history is missing".into()
    })?;
    ensure(
        uploads
            .iter()
            .all(|job| job["status"] == "completed" && job["conclusion"] == "skipped"),
        || "An attempted or unresolved upload requires provider reconciliation".into(),
    )
}

fn history(pages: &Value, route: &Route) -> Result<()> {
    let jobs = records(pages, "jobs")?;
    let signatures = jobs
        .iter()
        .filter(|job| {
            named(job, "Sign the preserved native candidate")
                && job["run_attempt"].as_u64() == Some(1)
        })
        .collect::<Vec<_>>();
    ensure(
        signatures.len() == 1
            && signatures
                .iter()
                .all(|job| job["status"] == "completed" && job["conclusion"] == "success"),
        || "The original signed bytes require successful first-attempt signing".into(),
    )?;
    match route {
        Route::Delivery => Ok(()),
        Route::Recovery => skipped_uploads(&jobs),
    }
}

struct Checksums {
    package: FileDigest,
    sbom: FileDigest,
}

fn package(platform: &Platform) -> &'static str {
    match platform {
        Platform::Macos => "signed/gymemo.pkg",
        Platform::Ios | Platform::Visionos => "signed/gymemo.ipa",
    }
}

fn checksums(text: &str, platform: &Platform) -> Result<Checksums> {
    let package = package(platform);
    let sbom = "signed/native-sbom.cdx.json";
    let mut entries = BTreeMap::new();
    for line in text.lines() {
        let fields = line.split_whitespace().collect::<Vec<_>>();
        let [digest, name] = fields.as_slice() else {
            return Err(Failure::new(
                "The signed checksum index has an invalid record",
            ));
        };
        ensure(hex(digest, 64) && [package, sbom].contains(name), || {
            "The signed checksum index contains an invalid digest or path".into()
        })?;
        ensure(entries.insert(*name, *digest).is_none(), || {
            "The signed checksum index repeats a file".into()
        })?;
    }
    ensure(entries.len() == 2, || {
        "The signed checksum index must cover the package and its SBOM".into()
    })?;
    let file = |name: &str| {
        entries
            .get(name)
            .map(|digest| FileDigest {
                name: name.to_owned(),
                sha256: (*digest).to_owned(),
            })
            .ok_or_else(|| Failure::new("The signed checksum index lacks a required file"))
    };
    Ok(Checksums {
        package: file(package)?,
        sbom: file(sbom)?,
    })
}

fn pages(host: &mut impl Host, root: &Path, endpoint: String) -> Result<Value> {
    metadata(
        host,
        root,
        Invocation::new("gh")
            .args(["api", "--paginate", "--slurp"])
            .arg(endpoint),
    )
}

fn previous_recoveries(
    host: &mut impl Host,
    root: &Path,
    signing: NonZeroU64,
    current: NonZeroU64,
) -> Result<()> {
    let listing = pages(
        host,
        root,
        "repos/P4suta/gymemo/actions/workflows/native-upload.yml/runs?event=workflow_dispatch&branch=main&per_page=100".into(),
    )?;
    for run in records(&listing, "workflow_runs")? {
        let id = run["id"]
            .as_u64()
            .and_then(NonZeroU64::new)
            .ok_or_else(|| Failure::new("Recovery history requires a run identity"))?;
        if id == current {
            continue;
        }
        let title = run["display_title"]
            .as_str()
            .ok_or_else(|| Failure::new("Recovery history lacks its signing-run identity"))?;
        let selected = title
            .strip_prefix("Upload signed run ")
            .map(run_number)
            .transpose()?;
        if selected.is_some_and(|selected| selected != signing) {
            continue;
        }
        ensure(
            run["head_branch"] == "main"
                && run["event"] == "workflow_dispatch"
                && run["path"] == ".github/workflows/native-upload.yml"
                && run["status"] == "completed",
            || "A prior recovery has an unresolved scope or outcome".into(),
        )?;
        let jobs = pages(
            host,
            root,
            format!("repos/P4suta/gymemo/actions/runs/{id}/jobs?filter=all&per_page=100"),
        )?;
        skipped_uploads(&records(&jobs, "jobs")?)?;
    }
    Ok(())
}

fn archive_paths(listing: &str, platform: &Platform) -> Result<()> {
    let files = BTreeSet::from([
        "candidate/native-candidate.tar",
        "candidate/native-candidate.json",
        package(platform),
        "signed/native-sbom.cdx.json",
        "signed/SHA256SUMS",
    ]);
    let mut seen = BTreeSet::new();
    for path in listing.lines() {
        ensure(
            (files.contains(path) || ["candidate/", "signed/"].contains(&path))
                && seen.insert(path),
            || "The signed archive contains an unexpected or repeated path".into(),
        )?;
    }
    ensure(files.is_subset(&seen), || {
        "The signed archive lacks required package files".into()
    })
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct UploadManifest {
    schema: u8,
    identity: CandidateIdentity,
    signing_run: NonZeroU64,
    signing_source: String,
    archive: FileDigest,
    package: FileDigest,
    sbom: FileDigest,
}

pub(super) fn run(host: &mut impl Host, root: &Path, arguments: &[String]) -> Result<()> {
    let [platform, source, candidate, signing, current, output] = arguments else {
        return Err(Failure::new(
            "prepare-native-upload requires PLATFORM SHA CANDIDATE_RUN SIGNING_RUN CURRENT_RUN OUTPUT_FILE",
        ));
    };
    let selection = Selection::parse(&[platform.clone(), source.clone(), candidate.clone()])?;
    let signing = run_number(signing)?;
    let current = run_number(current)?;
    let identity = selected_identity(host, root, selection)?;
    let run = metadata(
        host,
        root,
        Invocation::new("gh").args([
            "api",
            &format!("repos/P4suta/gymemo/actions/runs/{signing}"),
        ]),
    )?;
    let origin = origin(&run, signing, current)?;
    capture(
        host,
        root,
        Invocation::new("git").args(["merge-base", "--is-ancestor", &origin.source, "origin/main"]),
    )?;
    let jobs = pages(
        host,
        root,
        format!("repos/P4suta/gymemo/actions/runs/{signing}/jobs?filter=all&per_page=100"),
    )?;
    history(&jobs, &origin.route)?;
    if origin.route == Route::Recovery {
        previous_recoveries(host, root, signing, current)?;
    }
    let directory = root.join("target/native-upload");
    ensure(!host.exists(&directory), || {
        "Preserved upload inputs must not be overwritten".into()
    })?;
    host.create_directories(&directory)
        .context(|| "Create the native upload directory".into())?;
    capture(
        host,
        root,
        Invocation::new("gh")
            .args([
                "run",
                "download",
                &signing.to_string(),
                "--repo",
                "P4suta/gymemo",
                "--name",
                "native-signed-attempt-1",
                "--dir",
            ])
            .arg(&directory),
    )?;
    let archive = directory.join("native-signed.tar");
    capture(
        host,
        root,
        Invocation::new("gh")
            .args(["attestation", "verify"])
            .arg(&archive)
            .args([
                "--repo",
                "P4suta/gymemo",
                "--signer-workflow",
                "P4suta/gymemo/.github/workflows/native-delivery.yml",
                "--source-ref",
                "refs/heads/main",
                "--source-digest",
                &origin.source,
                "--signer-digest",
                &origin.source,
            ]),
    )?;
    let archive_sha = digest(host, root, &archive)?;
    let listing = capture(
        host,
        root,
        Invocation::new("tar")
            .args(["--list", "--file"])
            .arg(&archive),
    )?;
    archive_paths(&listing, &identity.platform)?;
    capture(
        host,
        root,
        Invocation::new("tar")
            .args(["--extract", "--file"])
            .arg(&archive)
            .arg("--directory")
            .arg(&directory),
    )?;
    let admitted = verify_candidate(host, &directory.join("candidate"), &identity)?;
    let index = host
        .read(&directory.join("signed/SHA256SUMS"))
        .context(|| "Read the signed package checksums".into())?;
    let sums = checksums(&index, &identity.platform)?;
    for file in [&sums.package, &sums.sbom] {
        ensure(
            digest(host, root, &directory.join(&file.name))? == file.sha256,
            || "The signed package or SBOM differs from its checksum".into(),
        )?;
    }
    let sbom = host
        .read(&directory.join(&sums.sbom.name))
        .context(|| "Read the final signed dependency inventory".into())?;
    admit_native(&sbom, &identity.version)?;
    let manifest = UploadManifest {
        schema: 1,
        identity: admitted.identity,
        signing_run: signing,
        signing_source: origin.source,
        archive: FileDigest {
            name: "native-signed.tar".into(),
            sha256: archive_sha,
        },
        package: sums.package,
        sbom: sums.sbom,
    };
    let json = serde_json::to_string_pretty(&manifest)
        .context(|| "Encode the admitted native upload".into())?;
    host.write(&directory.join("native-upload.json"), &format!("{json}\n"))
        .context(|| "Preserve the admitted native upload".into())?;
    let output = Path::new(output);
    if host.exists(output) {
        ensure(
            host.read(output)
                .context(|| "Read the native upload output file".into())?
                .is_empty(),
            || "Native upload outputs must not replace existing values".into(),
        )?;
    }
    let outputs = format!(
        "version={}\nplatform={}\nsigning_source={}\nsource={}\ncandidate_run={}\nsigning_run={}\narchive_sha256={}\npackage_sha256={}\n",
        manifest.identity.version,
        platform,
        manifest.signing_source,
        manifest.identity.source,
        manifest.identity.run_id,
        signing,
        manifest.archive.sha256,
        manifest.package.sha256,
    );
    host.write(output, &outputs)
        .context(|| "Write native upload outputs".into())?;
    host.print(&format!(
        "PASS native upload: {} build {} from signed run {signing}",
        manifest.identity.version, manifest.identity.run_id
    ));
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::host::fake::{FakeHost, Fault};
    use crate::native_candidate::tests::{
        arguments as candidate_arguments, prepare_verification, sbom,
    };
    use serde_json::json;

    const STAGING: &str = "/repo/target/native-upload";
    const OUTPUT: &str = "/repo/outputs";

    fn arguments(recovery: bool) -> Vec<String> {
        let mut values = candidate_arguments();
        values.extend(["11", if recovery { "12" } else { "11" }, OUTPUT].map(str::to_owned));
        values
    }

    fn listing(platform: &Platform) -> String {
        format!(
            "candidate/\ncandidate/native-candidate.tar\ncandidate/native-candidate.json\nsigned/\n{}\nsigned/native-sbom.cdx.json\nsigned/SHA256SUMS\n",
            package(platform)
        )
    }

    fn prepared(recovery: bool) -> Result<FakeHost> {
        let mut host = prepare_verification();
        let mut origin = metadata();
        if !recovery {
            origin["status"] = json!("in_progress");
            origin["conclusion"] = Value::Null;
        }
        host.prints("actions/runs/11\"", &origin.to_string());
        host.prints("runs/11/jobs?", &jobs("skipped").to_string());
        host.prints(
            "native-upload.yml/runs?",
            r#"[{"total_count":0,"workflow_runs":[]}]"#,
        );
        host.prints(
            "\"--list\" \"--file\" \"/repo/target/native-upload/native-signed.tar\"",
            &listing(&Platform::Ios),
        );
        let manifest = host.read(Path::new("/repo/native-candidate.json")).unwrap();
        host.writes(
            "\"--extract\" \"--file\"",
            &format!("{STAGING}/candidate/native-candidate.json"),
            &manifest,
        );
        host.writes(
            "\"--extract\" \"--file\"",
            &format!("{STAGING}/signed/SHA256SUMS"),
            &format!(
                "{}  signed/gymemo.ipa\n{}  signed/native-sbom.cdx.json\n",
                "a".repeat(64),
                "a".repeat(64)
            ),
        );
        host.writes(
            "\"--extract\" \"--file\"",
            &format!("{STAGING}/signed/native-sbom.cdx.json"),
            &sbom(),
        );
        Ok(host)
    }

    #[test]
    fn admits_the_same_signed_bytes_through_delivery_and_recovery() -> Result<()> {
        for recovery in [false, true] {
            let mut host = prepared(recovery)?;
            run(&mut host, Path::new("/repo"), &arguments(recovery))?;
            let manifest: Value = serde_json::from_str(
                &host
                    .read(Path::new(&format!("{STAGING}/native-upload.json")))
                    .unwrap(),
            )
            .unwrap();
            assert_eq!(manifest["identity"]["source"], candidate_arguments()[1]);
            assert_eq!(manifest["signingSource"], "a".repeat(40));
            assert_eq!(manifest["signingRun"], 11);
            assert_eq!(manifest["archive"]["sha256"], "a".repeat(64));
            assert_eq!(manifest["package"]["name"], "signed/gymemo.ipa");
            assert_eq!(
                host.read(Path::new(OUTPUT)).unwrap(),
                format!(
                    "version=1.0.0\nplatform=iOS\nsigning_source={}\nsource={}\ncandidate_run=1234\nsigning_run=11\narchive_sha256={}\npackage_sha256={}\n",
                    "a".repeat(40),
                    candidate_arguments()[1],
                    "a".repeat(64),
                    "a".repeat(64)
                )
            );
            let transcript = host.transcript();
            let position = |needle: &str| {
                transcript
                    .iter()
                    .position(|line| line.contains(needle))
                    .ok_or_else(|| {
                        Failure::new("The admission protocol omitted a required operation")
                    })
            };
            assert!(position("native-delivery.yml\"")? < position("\"--extract\" \"--file\"")?);
            assert!(position("native-candidate.yml\"")? < position("write /repo/outputs")?);
            assert_eq!(
                transcript
                    .iter()
                    .any(|line| line.contains("native-upload.yml/runs?")),
                recovery
            );
            assert!(!transcript.iter().any(|line| {
                ["xcodebuild", "codesign", "doppler", "--method", "\"POST\""]
                    .iter()
                    .any(|part| line.contains(part))
            }));
        }
        Ok(())
    }

    #[test]
    fn every_failed_external_admission_operation_withholds_outputs() -> Result<()> {
        let mut baseline = prepared(true)?;
        run(&mut baseline, Path::new("/repo"), &arguments(true))?;
        let count = baseline
            .transcript()
            .iter()
            .filter(|line| line.starts_with("capture "))
            .count();
        for position in 0..count {
            for fault in [
                Fault::Missing,
                Fault::Exit(1, "unavailable"),
                Fault::Signal(9),
                Fault::Garbled,
            ] {
                let mut host = prepared(true)?;
                host.fail_at(position, fault);
                assert!(
                    run(&mut host, Path::new("/repo"), &arguments(true)).is_err(),
                    "{position}: {fault:?}"
                );
                assert!(!host.exists(Path::new(OUTPUT)), "{position}: {fault:?}");
                assert!(
                    !host
                        .output
                        .iter()
                        .any(|line| line.starts_with("PASS native upload"))
                );
            }
        }
        Ok(())
    }

    #[test]
    fn refuses_changed_package_inventory_and_outputs_without_overwriting_inputs() -> Result<()> {
        for (path, value) in [
            (
                "signed/SHA256SUMS",
                format!(
                    "{}  signed/gymemo.ipa\n{}  signed/native-sbom.cdx.json\n",
                    "b".repeat(64),
                    "a".repeat(64)
                ),
            ),
            (
                "signed/SHA256SUMS",
                format!(
                    "{}  signed/gymemo.ipa\n{}  signed/native-sbom.cdx.json\n",
                    "a".repeat(64),
                    "b".repeat(64)
                ),
            ),
            ("signed/native-sbom.cdx.json", "{}".into()),
            ("candidate/native-candidate.json", "{}".into()),
        ] {
            let mut host = prepared(true)?;
            host.writes(
                "\"--extract\" \"--file\"",
                &format!("{STAGING}/{path}"),
                &value,
            );
            assert!(
                run(&mut host, Path::new("/repo"), &arguments(true)).is_err(),
                "{path}"
            );
            assert!(!host.exists(Path::new(OUTPUT)));
        }
        for directory in [STAGING, "/repo/target/native-upload/candidate/target"] {
            let mut host = prepared(true)?;
            host.refuse_creating(directory);
            assert!(run(&mut host, Path::new("/repo"), &arguments(true)).is_err());
            assert!(!host.exists(Path::new(OUTPUT)));
        }
        let mut host = prepared(true)?;
        host.directory(STAGING, &[]);
        assert!(run(&mut host, Path::new("/repo"), &arguments(true)).is_err());
        assert!(
            !host
                .transcript()
                .iter()
                .any(|line| line.contains("\"download\""))
        );
        let mut host = prepared(true)?;
        host.file(OUTPUT, "preserve\n");
        assert!(run(&mut host, Path::new("/repo"), &arguments(true)).is_err());
        assert_eq!(host.read(Path::new(OUTPUT)).unwrap(), "preserve\n");
        Ok(())
    }

    #[test]
    fn recovery_requires_complete_prior_history_without_any_upload_attempt() -> Result<()> {
        for title in ["Upload signed run 11", "Unidentified recovery"] {
            for outcome in ["skipped", "success", "failure", "cancelled"] {
                let mut host = prepared(true)?;
                host.prints("native-upload.yml/runs?", &json!([{"total_count":2,"workflow_runs":[
                    {"id":12},
                    {"id":10,"display_title":title,"head_branch":"main","event":"workflow_dispatch","path":".github/workflows/native-upload.yml","status":"completed"}
                ]}]).to_string());
                host.prints("runs/10/jobs?", &jobs(outcome).to_string());
                let result = run(&mut host, Path::new("/repo"), &arguments(true));
                assert_eq!(result.is_ok(), outcome == "skipped", "{title}: {outcome}");
                if outcome != "skipped" {
                    assert!(!host.exists(Path::new(OUTPUT)));
                }
            }
        }
        Ok(())
    }

    #[test]
    fn rejects_invalid_arguments_and_incomplete_or_unsafe_archives() -> Result<()> {
        for index in 0..5 {
            for invalid in ["", "0", "../value", "value\nvalue"] {
                let mut arguments = arguments(true);
                arguments[index] = invalid.into();
                let mut host = FakeHost::new();
                assert!(run(&mut host, Path::new("/repo"), &arguments).is_err());
                assert!(host.transcript().is_empty());
            }
        }
        for platform in [Platform::Ios, Platform::Macos, Platform::Visionos] {
            let valid = listing(&platform);
            archive_paths(&valid, &platform)?;
            for invalid in [
                String::new(),
                format!("{valid}../escape\n"),
                format!("{valid}signed/SHA256SUMS\n"),
                valid.replace("candidate/native-candidate.json\n", ""),
                valid.replace("signed/SHA256SUMS", "/signed/SHA256SUMS"),
            ] {
                assert!(archive_paths(&invalid, &platform).is_err());
            }
        }
        for invalid in [
            json!([]),
            json!([{}]),
            json!([{"total_count":1,"jobs":[]}]),
            json!([{"total_count":2,"jobs":[{"id":1},{"id":1}]}]),
            json!([{"total_count":1,"jobs":[{"id":0}]}]),
            json!([{"total_count":2,"jobs":[{"id":1}]},{"total_count":1,"jobs":[{"id":2}]}]),
        ] {
            assert!(records(&invalid, "jobs").is_err());
        }
        assert_eq!(
            records(
                &json!([{"total_count":2,"jobs":[{"id":1}]},{"total_count":2,"jobs":[{"id":2}]}]),
                "jobs"
            )?
            .len(),
            2
        );
        Ok(())
    }

    fn number(value: u64) -> Result<NonZeroU64> {
        NonZeroU64::new(value).ok_or_else(|| Failure::new("The fixture run must be positive"))
    }

    fn metadata() -> Value {
        json!({
            "id": 11, "head_sha": "a".repeat(40), "head_branch": "main",
            "event": "workflow_dispatch", "path": ".github/workflows/native-delivery.yml",
            "repository": {"id": 1453033797_u64},
            "head_repository": {"id": 1453033797_u64},
            "run_attempt": 1, "status": "completed", "conclusion": "success",
        })
    }

    fn jobs(upload: &str) -> Value {
        json!([{"total_count": 2, "jobs": [
            {"id": 101, "name": "Sign the preserved native candidate", "status": "completed", "conclusion": "success", "run_attempt": 1},
            {"id": 102, "name": "Upload the preserved native package", "status": "completed", "conclusion": upload, "run_attempt": 1},
        ]}])
    }

    #[test]
    fn admits_only_bound_completed_signing_origins() -> Result<()> {
        let admitted = origin(&metadata(), number(11)?, number(12)?)?;
        assert_eq!(admitted.source, "a".repeat(40));
        assert_eq!(admitted.route, Route::Recovery);
        for (key, value) in [
            ("id", json!(12)),
            ("head_sha", json!("not-a-commit")),
            ("head_branch", json!("other")),
            ("event", json!("pull_request")),
            ("path", json!(".github/workflows/other.yml")),
            ("status", json!("in_progress")),
            ("run_attempt", json!(0)),
            ("repository", json!({"id": 1})),
            ("head_repository", json!({"id": 1})),
        ] {
            let mut changed = metadata();
            changed[key] = value;
            assert!(origin(&changed, number(11)?, number(12)?).is_err(), "{key}");
        }
        let mut live = metadata();
        live["status"] = json!("in_progress");
        live["conclusion"] = Value::Null;
        assert_eq!(
            origin(&live, number(11)?, number(11)?)?.route,
            Route::Delivery
        );
        live["run_attempt"] = json!(2);
        assert!(origin(&live, number(11)?, number(11)?).is_err());
        Ok(())
    }

    #[test]
    fn refuses_every_attempted_or_unresolved_upload() -> Result<()> {
        history(&jobs("skipped"), &Route::Recovery)?;
        for result in [
            "success",
            "failure",
            "cancelled",
            "timed_out",
            "neutral",
            "",
        ] {
            assert!(
                history(&jobs(result), &Route::Recovery).is_err(),
                "{result}"
            );
        }
        let mut incomplete = jobs("skipped");
        incomplete[0]["total_count"] = json!(3);
        assert!(history(&incomplete, &Route::Recovery).is_err());
        assert!(history(&json!([]), &Route::Recovery).is_err());
        let mut failed_signing = jobs("skipped");
        failed_signing[0]["jobs"][0]["conclusion"] = json!("failure");
        assert!(history(&failed_signing, &Route::Recovery).is_err());
        let mut second_attempt = jobs("skipped");
        second_attempt[0]["jobs"][0]["run_attempt"] = json!(2);
        assert!(history(&second_attempt, &Route::Recovery).is_err());
        Ok(())
    }

    #[test]
    fn requires_complete_unique_package_checksums() -> Result<()> {
        let package = "a".repeat(64);
        let sbom = "b".repeat(64);
        let valid = format!("{package}  signed/gymemo.ipa\n{sbom}  signed/native-sbom.cdx.json\n");
        let admitted = checksums(&valid, &Platform::Visionos)?;
        assert_eq!(admitted.package.sha256, package);
        assert_eq!(admitted.sbom.sha256, sbom);
        assert!(checksums(&valid, &Platform::Macos).is_err());
        for invalid in [
            valid.replace("signed/gymemo.ipa", "../gymemo.ipa"),
            valid.replace("signed/gymemo.ipa", "/gymemo.ipa"),
            valid.replace("signed/gymemo.ipa", "signed/native-sbom.cdx.json"),
            valid.replace(&package, "not-a-digest"),
            format!("{valid}{valid}"),
            format!("{package}  signed/gymemo.ipa\n"),
        ] {
            assert!(checksums(&invalid, &Platform::Visionos).is_err());
        }
        assert!(hex(&package, 64));
        Ok(())
    }
}
