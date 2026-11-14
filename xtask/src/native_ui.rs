//! Admission of the complete hosted Mac UI suite for one source commit.

use crate::{
    failure::{Context, Result, ensure},
    host::{Host, Invocation, Streams},
    qualification::Commit,
};
use serde::{Deserialize, de::DeserializeOwned};
use std::path::Path;

const REPOSITORY: &str = "repos/P4suta/gymemo";
const JOBS: [&str; 3] = [
    "Build Mac UI products",
    "Sign Mac UI products",
    "Mac UI tests",
];

fn metadata<T: DeserializeOwned>(
    host: &mut impl Host,
    root: &Path,
    command: Invocation,
) -> Result<T> {
    let output = host
        .run(&command.current_dir(root), Streams::Captured)
        .context(|| "Start Mac UI metadata lookup".into())?;
    ensure(output.status.success(), || {
        "Mac UI metadata lookup failed".into()
    })?;
    serde_json::from_slice(&output.stdout).context(|| "Read Mac UI metadata".into())
}

#[derive(Deserialize)]
struct Repository {
    id: u64,
}

#[derive(Deserialize)]
struct WorkflowRun {
    id: u64,
    run_attempt: u32,
    head_sha: String,
    head_branch: String,
    path: String,
    event: String,
    status: String,
    conclusion: Option<String>,
    html_url: String,
    repository: Repository,
    head_repository: Repository,
}

#[derive(Deserialize)]
struct Runs {
    workflow_runs: Vec<WorkflowRun>,
}

#[derive(Deserialize)]
struct Job {
    name: String,
    run_id: u64,
    run_attempt: u32,
    head_sha: String,
    status: String,
    conclusion: Option<String>,
}

#[derive(Deserialize)]
struct Jobs {
    jobs: Vec<Job>,
}

pub fn require(host: &mut impl Host, root: &Path, source: &str) -> Result<()> {
    let source = Commit::parse(source)?.to_string();
    let runs: Runs = metadata(host, root, Invocation::new("gh").args([
        "api", &format!("{REPOSITORY}/actions/workflows/native-ui.yml/runs?event=workflow_dispatch&head_sha={source}&per_page=1")
    ]))?;
    ensure(runs.workflow_runs.len() == 1, || {
        "No hosted Mac UI run exists for this source".into()
    })?;
    let run = &runs.workflow_runs[0];
    ensure(
        run.id > 0
            && run.run_attempt > 0
            && run.head_sha == source
            && run.head_branch == "main"
            && run.path == ".github/workflows/native-ui.yml"
            && run.event == "workflow_dispatch"
            && run.status == "completed"
            && run.conclusion.as_deref() == Some("success")
            && run.repository.id == 1_453_033_797
            && run.head_repository.id == 1_453_033_797
            && run.html_url == format!("https://github.com/P4suta/gymemo/actions/runs/{}", run.id),
        || "The latest Mac UI run must succeed on the exact main source in this repository".into(),
    )?;
    let jobs: Jobs = metadata(
        host,
        root,
        Invocation::new("gh").args([
            "api",
            &format!(
                "{REPOSITORY}/actions/runs/{}/jobs?filter=latest&per_page=100",
                run.id
            ),
        ]),
    )?;
    ensure(
        jobs.jobs.len() == JOBS.len()
            && JOBS.iter().all(|name| {
                jobs.jobs.iter().any(|job| {
                    job.name == *name
                        && job.run_id == run.id
                        && job.run_attempt == run.run_attempt
                        && job.head_sha == source
                        && job.status == "completed"
                        && job.conclusion.as_deref() == Some("success")
                })
            }),
        || "Every Mac UI build, signing, and test job must succeed in the latest attempt".into(),
    )?;
    host.print(&format!(
        "PASS Mac UI: all hosted jobs passed for {source} ({})",
        run.html_url
    ));
    Ok(())
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Counts {
    passed_tests: u32,
    failed_tests: u32,
    skipped_tests: u32,
    expected_failures: u32,
}

impl Counts {
    fn complete(&self) -> bool {
        self.passed_tests == 16
            && self.failed_tests == 0
            && self.skipped_tests == 0
            && self.expected_failures == 0
    }
}

#[derive(Deserialize)]
struct Device {
    platform: String,
}

#[derive(Deserialize)]
struct DeviceResult {
    device: Device,
    #[serde(flatten)]
    counts: Counts,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Summary {
    result: String,
    total_test_count: u32,
    #[serde(flatten)]
    counts: Counts,
    devices_and_configurations: Vec<DeviceResult>,
}

pub fn check_result(host: &mut impl Host, root: &Path, bundle: &str) -> Result<()> {
    let summary: Summary = metadata(
        host,
        root,
        Invocation::new("xcrun").args([
            "xcresulttool",
            "get",
            "test-results",
            "summary",
            "--path",
            bundle,
            "--compact",
        ]),
    )?;
    ensure(
        summary.result == "Passed"
            && summary.total_test_count == 16
            && summary.counts.complete()
            && summary.devices_and_configurations.len() == 1
            && summary.devices_and_configurations[0].device.platform == "macOS"
            && summary.devices_and_configurations[0].counts.complete(),
        || {
            "Mac UI qualification requires all 16 tests to pass without skips or expected failures"
                .into()
        },
    )?;
    host.print("PASS Mac UI result: all 16 tests passed without skips or expected failures");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::host::fake::{FakeHost, Fault};
    use serde_json::{Value, json};

    const SOURCE: &str = "0123456789abcdef0123456789abcdef01234567";
    fn root() -> &'static Path {
        Path::new("/repo")
    }

    fn run() -> Value {
        json!({"workflow_runs":[{
            "id":123,"run_attempt":1,"head_sha":SOURCE,"head_branch":"main",
            "path":".github/workflows/native-ui.yml","event":"workflow_dispatch",
            "status":"completed","conclusion":"success",
            "html_url":"https://github.com/P4suta/gymemo/actions/runs/123",
            "repository":{"id":1453033797},"head_repository":{"id":1453033797}
        }]})
    }

    fn jobs() -> Value {
        let jobs = [
            "Build Mac UI products",
            "Sign Mac UI products",
            "Mac UI tests",
        ]
        .map(|name| {
            json!({
                "name":name,"run_id":123,"run_attempt":1,"head_sha":SOURCE,
                "status":"completed","conclusion":"success"
            })
        });
        json!({"jobs":jobs})
    }

    fn prepared() -> FakeHost {
        let mut host = FakeHost::new();
        host.prints("/actions/workflows/native-ui.yml/runs?", &run().to_string());
        host.prints("/actions/runs/123/jobs?", &jobs().to_string());
        host
    }

    #[test]
    fn requires_the_latest_exact_source_main_run_and_all_three_jobs() -> Result<()> {
        let mut host = prepared();
        require(&mut host, root(), SOURCE)?;
        assert_eq!(host.transcript().len(), 2);
        let lookup = &host.transcript()[0];
        assert!(lookup.contains(&format!("head_sha={SOURCE}")));
        assert!(lookup.contains("event=workflow_dispatch"));
        assert!(lookup.contains("per_page=1"));
        assert!(!lookup.contains("status=completed"));
        assert!(host.transcript()[1].contains("filter=latest"));
        Ok(())
    }

    #[test]
    fn refuses_missing_running_failed_or_misbound_runs_before_reading_jobs() {
        let valid = run();
        let duplicate = valid["workflow_runs"][0].clone();
        for (pointer, invalid) in [
            ("/workflow_runs", json!([])),
            ("/workflow_runs", json!([duplicate.clone(), duplicate])),
            ("/workflow_runs/0/id", json!(0)),
            ("/workflow_runs/0/run_attempt", json!(0)),
            ("/workflow_runs/0/head_sha", json!("another")),
            ("/workflow_runs/0/head_branch", json!("topic")),
            (
                "/workflow_runs/0/path",
                json!(".github/workflows/checks.yml"),
            ),
            ("/workflow_runs/0/event", json!("pull_request")),
            ("/workflow_runs/0/status", json!("in_progress")),
            ("/workflow_runs/0/conclusion", json!("failure")),
            ("/workflow_runs/0/conclusion", Value::Null),
            ("/workflow_runs/0/repository/id", json!(7)),
            ("/workflow_runs/0/head_repository/id", json!(7)),
            (
                "/workflow_runs/0/html_url",
                json!("https://example.invalid/123"),
            ),
        ] {
            let mut metadata = valid.clone();
            *metadata.pointer_mut(pointer).expect("fixture field") = invalid;
            let mut host = prepared();
            host.prints(
                "/actions/workflows/native-ui.yml/runs?",
                &metadata.to_string(),
            );
            assert!(require(&mut host, root(), SOURCE).is_err(), "{pointer}");
            assert_eq!(host.transcript().len(), 1);
        }
    }

    #[test]
    fn refuses_missing_skipped_failed_or_different_attempt_jobs() {
        let mut extra = jobs()["jobs"].as_array().expect("fixture jobs").clone();
        extra.push(extra[0].clone());
        for (pointer, invalid) in [
            ("/jobs", json!([])),
            ("/jobs", json!(extra)),
            ("/jobs/2/name", json!("Another suite")),
            ("/jobs/2/conclusion", json!("skipped")),
            ("/jobs/2/conclusion", json!("failure")),
            ("/jobs/2/status", json!("queued")),
            ("/jobs/2/run_id", json!(456)),
            ("/jobs/2/run_attempt", json!(2)),
            ("/jobs/2/head_sha", json!("another")),
        ] {
            let mut metadata = jobs();
            *metadata.pointer_mut(pointer).expect("fixture field") = invalid;
            let mut host = prepared();
            host.prints("/actions/runs/123/jobs?", &metadata.to_string());
            assert!(require(&mut host, root(), SOURCE).is_err(), "{pointer}");
        }
    }

    #[test]
    fn rejects_a_zero_run_even_when_its_url_is_consistent() {
        let mut metadata = run();
        metadata["workflow_runs"][0]["id"] = json!(0);
        metadata["workflow_runs"][0]["html_url"] =
            json!("https://github.com/P4suta/gymemo/actions/runs/0");
        let mut host = prepared();
        host.prints(
            "/actions/workflows/native-ui.yml/runs?",
            &metadata.to_string(),
        );
        assert!(require(&mut host, root(), SOURCE).is_err());
        assert_eq!(host.transcript().len(), 1);
    }

    fn summary() -> Value {
        json!({"result":"Passed","totalTestCount":16,"passedTests":16,
            "failedTests":0,"skippedTests":0,"expectedFailures":0,
            "devicesAndConfigurations":[{"device":{"platform":"macOS"},
                "passedTests":16,"failedTests":0,"skippedTests":0,"expectedFailures":0}]})
    }

    #[test]
    fn requires_the_complete_unskipped_mac_result() -> Result<()> {
        let mut host = FakeHost::new();
        host.prints("\"xcresulttool\"", &summary().to_string());
        check_result(&mut host, root(), "target/mac-ui.xcresult")?;
        assert!(host.transcript()[0].contains("\"summary\" \"--path\" \"target/mac-ui.xcresult\""));
        let device = summary()["devicesAndConfigurations"][0].clone();
        for (pointer, invalid) in [
            ("/result", json!("Failed")),
            ("/totalTestCount", json!(15)),
            ("/passedTests", json!(15)),
            ("/failedTests", json!(1)),
            ("/skippedTests", json!(1)),
            ("/expectedFailures", json!(1)),
            ("/devicesAndConfigurations", json!([])),
            ("/devicesAndConfigurations", json!([device.clone(), device])),
            ("/devicesAndConfigurations/0/device/platform", json!("iOS")),
            ("/devicesAndConfigurations/0/passedTests", json!(15)),
            ("/devicesAndConfigurations/0/failedTests", json!(1)),
            ("/devicesAndConfigurations/0/skippedTests", json!(1)),
            ("/devicesAndConfigurations/0/expectedFailures", json!(1)),
        ] {
            let mut metadata = summary();
            *metadata.pointer_mut(pointer).expect("fixture field") = invalid;
            host.prints("\"xcresulttool\"", &metadata.to_string());
            assert!(
                check_result(&mut host, root(), "target/mac-ui.xcresult").is_err(),
                "{pointer}"
            );
        }
        Ok(())
    }

    #[test]
    fn malformed_sources_and_unreadable_metadata_fail_closed() {
        for source in ["", "main", "../source", "--help"] {
            let mut host = prepared();
            assert!(require(&mut host, root(), source).is_err());
            assert!(host.transcript().is_empty());
        }
        for fault in [
            Fault::Exit(1, "fixture failure"),
            Fault::Missing,
            Fault::Garbled,
        ] {
            let mut host = prepared();
            host.fail("/actions/", fault);
            assert!(require(&mut host, root(), SOURCE).is_err());
            let mut host = FakeHost::new();
            host.fail("\"xcresulttool\"", fault);
            assert!(check_result(&mut host, root(), "target/mac-ui.xcresult").is_err());
        }
        for invalid in ["not JSON", "{}", "null"] {
            let mut host = prepared();
            host.prints("/actions/workflows/native-ui.yml/runs?", invalid);
            assert!(require(&mut host, root(), SOURCE).is_err());
            let mut host = FakeHost::new();
            host.prints("\"xcresulttool\"", invalid);
            assert!(check_result(&mut host, root(), "target/mac-ui.xcresult").is_err());
        }
    }
}
