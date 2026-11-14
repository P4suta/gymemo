//! Runs the local release checks for one source commit.

use crate::{
    failure::{Context, Failure, Result, ensure},
    host::{Host, Invocation, Streams},
};
use serde_json::Value;
use std::{fmt, path::Path};

const CONTEXT: &str = "Local qualification";
const REPOSITORY: &str = "repos/P4suta/gymemo";

pub(crate) struct Commit(String);

impl Commit {
    pub(crate) fn parse(value: &str) -> Result<Self> {
        ensure(
            value.len() == 40 && value.bytes().all(|byte| byte.is_ascii_hexdigit()),
            || "Qualification requires a full source commit identifier".into(),
        )?;
        Ok(Self(value.to_ascii_lowercase()))
    }
}

impl fmt::Display for Commit {
    fn fmt(&self, output: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.0.fmt(output)
    }
}

#[derive(Clone, Copy)]
enum Verdict {
    Pending,
    Success,
    Failure,
    Inconclusive,
}

impl Verdict {
    fn state(self) -> &'static str {
        match self {
            Self::Pending => "pending",
            Self::Success => "success",
            Self::Failure => "failure",
            Self::Inconclusive => "error",
        }
    }
}

struct Plan {
    source: Commit,
    devices: [String; 5],
    execute: bool,
}

fn is_device(value: &str) -> bool {
    value.len() == 36
        && value.bytes().enumerate().all(|(position, byte)| {
            if [8, 13, 18, 23].contains(&position) {
                byte == b'-'
            } else {
                byte.is_ascii_hexdigit()
            }
        })
}

impl Plan {
    fn parse(arguments: &[String]) -> Result<Self> {
        ensure(arguments.len() == 6 || arguments.len() == 7, || {
            "qualify requires SHA FLOOR IPAD DUO WATCH VISION and optional --run".into()
        })?;
        let source = Commit::parse(&arguments[0])?;
        let devices: [String; 5] = std::array::from_fn(|position| arguments[position + 1].clone());
        for (position, device) in devices.iter().enumerate() {
            ensure(
                is_device(device)
                    && !devices[..position]
                        .iter()
                        .any(|earlier| earlier.eq_ignore_ascii_case(device)),
                || "Qualification requires five distinct simulator identifiers".into(),
            )?;
        }
        let execute = match arguments.get(6).map(String::as_str) {
            None => false,
            Some("--run") => true,
            Some(_) => {
                return Err(Failure::new(
                    "qualify accepts only --run after the destinations",
                ));
            }
        };
        Ok(Self {
            source,
            devices,
            execute,
        })
    }

    fn commands(&self, root: &Path) -> Vec<Invocation> {
        let just = |arguments: &[&str]| {
            Invocation::new("mise")
                .current_dir(root)
                .args(["x", "--", "just"])
                .args(arguments.iter().copied())
        };
        let native = |platform: &str, identifier: &str| {
            just(&[
                "native-test",
                "-destination",
                &format!("platform={platform},id={identifier}"),
            ])
        };
        vec![
            just(&["require-mac-ui", &self.source.to_string()]),
            just(&["check"]),
            just(&["ui-test"]),
            just(&["ui-test-on", &self.devices[0]]),
            native("iOS Simulator", &self.devices[1]),
            native("iOS Simulator", &self.devices[2]),
            native("visionOS Simulator", &self.devices[4]),
            just(&[
                "watch-test",
                "-destination",
                &format!("platform=watchOS Simulator,id={}", self.devices[3]),
            ]),
            just(&["sanitize"]),
            just(&["mutate", "--concurrency", "2"]),
            just(&["mutate-xtask"]),
            just(&["proofs"]),
        ]
    }

    fn admit_devices(&self, metadata: &Value) -> Result<()> {
        let runtimes = metadata["devices"]
            .as_object()
            .ok_or_else(|| Failure::new("simctl omitted the device metadata"))?;
        let requirements = [
            ("FLOOR", "iOS-26-", "iPhone-"),
            ("IPAD", "iOS-27-", "iPad-"),
            ("DUO", "iOS-27-", "iPhone-Duo"),
            ("WATCH", "watchOS-27-", "Apple-Watch-"),
            ("VISION", "xrOS-27-", "Apple-Vision-Pro"),
        ];
        for (selected, (role, runtime, device_type)) in self.devices.iter().zip(requirements) {
            let mut found = Vec::new();
            for (name, devices) in runtimes {
                let devices = devices
                    .as_array()
                    .ok_or_else(|| Failure::new("simctl returned an invalid device list"))?;
                for device in devices {
                    if device["udid"]
                        .as_str()
                        .is_some_and(|value| value.eq_ignore_ascii_case(selected))
                    {
                        found.push((name, device));
                    }
                }
            }
            let [(name, device)] = found.as_slice() else {
                return Err(Failure::new(format!(
                    "{role} must identify exactly one available simulator"
                )));
            };
            ensure(
                name.starts_with(&format!("com.apple.CoreSimulator.SimRuntime.{runtime}"))
                    && device["isAvailable"].as_bool() == Some(true)
                    && device["deviceTypeIdentifier"]
                        .as_str()
                        .is_some_and(|value| {
                            value.starts_with(&format!(
                                "com.apple.CoreSimulator.SimDeviceType.{device_type}"
                            ))
                        }),
                || format!("{role} has the wrong runtime, device type, or availability"),
            )?;
        }
        Ok(())
    }
}

fn captured(host: &mut impl Host, root: &Path, command: Invocation) -> Result<String> {
    let output = host
        .run(&command.current_dir(root), Streams::Captured)
        .context(|| "Start qualification metadata lookup".into())?;
    ensure(output.status.success(), || {
        "Qualification metadata lookup failed; inspect the provider or Git state".into()
    })?;
    String::from_utf8(output.stdout).context(|| "Read qualification metadata".into())
}

fn metadata(host: &mut impl Host, root: &Path, command: Invocation) -> Result<Value> {
    serde_json::from_str(&captured(host, root, command)?)
        .map_err(|_| Failure::new("Qualification metadata isn't valid JSON"))
}

fn source_is_unchanged(host: &mut impl Host, root: &Path, source: &Commit) -> Result<()> {
    let head = captured(
        host,
        root,
        Invocation::new("git").args(["rev-parse", "--verify", "HEAD"]),
    )?;
    let state = captured(
        host,
        root,
        Invocation::new("git").args(["status", "--porcelain=v1", "--untracked-files=normal"]),
    )?;
    ensure(head.trim() == source.0 && state.trim().is_empty(), || {
        "Qualification requires the selected HEAD with no staged, unstaged, or untracked changes"
            .into()
    })
}

fn status(host: &mut impl Host, root: &Path, source: &Commit, verdict: Verdict) -> Result<()> {
    let state = verdict.state();
    let response = metadata(
        host,
        root,
        Invocation::new("gh").args([
            "api",
            "--method",
            "POST",
            &format!("{REPOSITORY}/statuses/{source}"),
            "--raw-field",
            &format!("state={state}"),
            "--raw-field",
            &format!("context={CONTEXT}"),
            "--raw-field",
            "description=Local native, simulator, sanitizer, mutation, and proof checks",
            "--raw-field",
            &format!("target_url=https://github.com/P4suta/gymemo/blob/{source}/docs/verification.md#local-release-qualification"),
        ]),
    )?;
    ensure(
        response["state"].as_str() == Some(state)
            && response["context"].as_str() == Some(CONTEXT)
            && response["creator"]["id"].as_u64() == Some(42_543_015),
        || "GitHub didn't acknowledge the qualification status from the repository owner".into(),
    )
}

fn admit_remote_source(host: &mut impl Host, root: &Path, source: &Commit) -> Result<()> {
    let repository = metadata(host, root, Invocation::new("gh").args(["api", REPOSITORY]))?;
    ensure(
        repository["id"].as_u64() == Some(1_453_033_797)
            && repository["owner"]["id"].as_u64() == Some(42_543_015)
            && repository["default_branch"].as_str() == Some("main")
            && repository["private"].as_bool() == Some(false),
        || "Qualification requires the public P4suta/gymemo repository and main branch".into(),
    )?;
    let comparison = metadata(
        host,
        root,
        Invocation::new("gh").args(["api", &format!("{REPOSITORY}/compare/main...{source}")]),
    )?;
    ensure(
        matches!(comparison["status"].as_str(), Some("identical" | "behind"))
            && comparison["ahead_by"].as_u64() == Some(0)
            && comparison["merge_base_commit"]["sha"].as_str() == Some(&source.0),
        || "The source must already belong to the repository's main branch".into(),
    )?;
    Ok(())
}

pub fn require(host: &mut impl Host, root: &Path, source: &str) -> Result<()> {
    let source = Commit::parse(source)?;
    admit_remote_source(host, root, &source)?;
    for page in 1..=10 {
        let response = metadata(
            host,
            root,
            Invocation::new("gh").args([
                "api",
                &format!("{REPOSITORY}/commits/{source}/statuses?per_page=100&page={page}"),
            ]),
        )?;
        let statuses = response
            .as_array()
            .ok_or_else(|| Failure::new("GitHub omitted the status list"))?;
        if let Some(status) = statuses.iter().find(|status| {
            status["context"]
                .as_str()
                .is_some_and(|context| context.eq_ignore_ascii_case(CONTEXT))
        }) {
            ensure(
                status["state"].as_str() == Some("success")
                    && status["creator"]["id"].as_u64() == Some(42_543_015)
                    && status["url"].as_str()
                        == Some(&format!(
                            "https://api.github.com/{REPOSITORY}/statuses/{source}"
                        )),
                || {
                    "The latest local qualification must pass for the selected source and repository owner".into()
                },
            )?;
            host.print(&format!("PASS qualification: GitHub reports the owner's successful local checks for {source}"));
            return Ok(());
        }
        if statuses.len() < 100 {
            break;
        }
    }
    Err(Failure::new(
        "GitHub reports no local qualification within the checked status pages",
    ))
}

pub fn run(host: &mut impl Host, root: &Path, arguments: &[String]) -> Result<()> {
    let plan = Plan::parse(arguments)?;
    let commands = plan.commands(root);
    host.print(&format!("Local qualification for {}", plan.source));
    for command in &commands {
        host.print(&format!("CHECK {command}"));
    }
    if !plan.execute {
        return Ok(());
    }
    source_is_unchanged(host, root, &plan.source)?;
    let devices = metadata(
        host,
        root,
        Invocation::new("xcrun").args(["simctl", "list", "devices", "available", "--json"]),
    )?;
    plan.admit_devices(&devices)?;
    admit_remote_source(host, root, &plan.source)?;
    status(host, root, &plan.source, Verdict::Pending)?;
    for command in commands {
        host.print(&format!("RUN {command}"));
        let result = host
            .run(&command, Streams::Shown)
            .map_err(|error| Failure::inconclusive(format!("Start {command}: {error}")))
            .and_then(|output| {
                if output.status.success() {
                    return Ok(());
                }
                match output.status.code() {
                    Some(75) | None => Err(Failure::inconclusive(format!(
                        "{command} didn't establish a result"
                    ))),
                    Some(code) => Err(Failure::exit(
                        format!("{command} failed with {code}"),
                        u8::try_from(code).unwrap_or(1),
                    )),
                }
            })
            .and_then(|()| {
                source_is_unchanged(host, root, &plan.source)
                    .map_err(|error| Failure::inconclusive(error.to_string()))
            });
        if let Err(failure) = result {
            let state = if failure.code() == 75 {
                Verdict::Inconclusive
            } else {
                Verdict::Failure
            };
            return match status(host, root, &plan.source, state) {
                Ok(()) => Err(failure),
                Err(later) => Err(failure.followed_by(&later)),
            };
        }
    }
    status(host, root, &plan.source, Verdict::Success)?;
    host.print(
        "PASS qualification: every local release check passed for the selected clean source commit",
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::host::fake::{FakeHost, Fault};
    use serde_json::json;

    const SOURCE: &str = "0123456789abcdef0123456789abcdef01234567";
    const DEVICES: [&str; 5] = [
        "AAAAAAAA-0000-4000-8000-0123456789AB",
        "BBBBBBBB-0000-4000-8000-0123456789AB",
        "CCCCCCCC-0000-4000-8000-0123456789AB",
        "DDDDDDDD-0000-4000-8000-0123456789AB",
        "EEEEEEEE-0000-4000-8000-0123456789AB",
    ];

    fn arguments(execute: bool) -> Vec<String> {
        let mut values = std::iter::once(SOURCE)
            .chain(DEVICES)
            .map(str::to_owned)
            .collect::<Vec<_>>();
        if execute {
            values.push("--run".into());
        }
        values
    }

    fn prepared() -> FakeHost {
        let mut host = FakeHost::new();
        host.prints("\"repos/P4suta/gymemo\"", &json!({"id":1453033797,"owner":{"id":42543015},"default_branch":"main","private":false}).to_string());
        host.prints("\"rev-parse\"", &format!("{SOURCE}\n"));
        host.prints("\"status\" \"--porcelain=v1\"", "");
        host.prints("\"simctl\" \"list\" \"devices\"", &json!({"devices":{
            "com.apple.CoreSimulator.SimRuntime.iOS-26-4":[{"udid":DEVICES[0],"isAvailable":true,"deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-Air"}],
            "com.apple.CoreSimulator.SimRuntime.iOS-27-2":[
                {"udid":DEVICES[1],"isAvailable":true,"deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB"},
                {"udid":DEVICES[2],"isAvailable":true,"deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-Duo"}
            ],
            "com.apple.CoreSimulator.SimRuntime.watchOS-27-2":[{"udid":DEVICES[3],"isAvailable":true,"deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.Apple-Watch-SE-3-40mm"}],
            "com.apple.CoreSimulator.SimRuntime.xrOS-27-2":[{"udid":DEVICES[4],"isAvailable":true,"deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.Apple-Vision-Pro"}]
        }}).to_string());
        host.prints(
            "\"compare/main...",
            &json!({"status":"identical","ahead_by":0,"merge_base_commit":{"sha":SOURCE}})
                .to_string(),
        );
        host.prints(
            "repos/P4suta/gymemo/compare/",
            &json!({"status":"identical","ahead_by":0,"merge_base_commit":{"sha":SOURCE}})
                .to_string(),
        );
        for state in ["pending", "success", "failure", "error"] {
            host.prints(
                &format!("state={state}"),
                &json!({"state":state,"context":"Local qualification","creator":{"id":42543015}})
                    .to_string(),
            );
        }
        host
    }

    #[test]
    fn the_plan_names_every_local_check_without_starting_a_program() -> Result<()> {
        let mut host = FakeHost::new();
        run(&mut host, Path::new("/repo"), &arguments(false))?;
        assert!(host.transcript().is_empty());
        let printed = host.output.join("\n");
        for required in [
            SOURCE,
            "check",
            "ui-test",
            "native-test",
            "watch-test",
            "sanitize",
            "mutate",
            "mutate-xtask",
            "proofs",
        ] {
            assert!(printed.contains(required), "{required}");
        }
        Ok(())
    }

    #[test]
    fn malformed_sources_destinations_and_options_never_start_a_program() {
        for position in 0..6 {
            for invalid in ["", "--run", "../source", "bad\nvalue"] {
                let mut values = arguments(true);
                values[position] = invalid.into();
                let mut host = FakeHost::new();
                assert!(run(&mut host, Path::new("/repo"), &values).is_err());
                assert!(host.transcript().is_empty());
            }
        }
        for values in [
            vec![],
            vec![SOURCE.into()],
            {
                let mut values = arguments(true);
                values.push("--skip".into());
                values
            },
            {
                let mut values = arguments(false);
                values.push("--skip".into());
                values
            },
            {
                let mut values = arguments(false);
                values[2] = values[1].clone();
                values
            },
        ] {
            let mut host = FakeHost::new();
            assert!(run(&mut host, Path::new("/repo"), &values).is_err());
            assert!(host.transcript().is_empty());
        }
    }

    #[test]
    fn dirty_or_different_sources_and_unavailable_devices_never_start_checks() {
        for (command, value) in [
            ("\"rev-parse\"", "another\n"),
            ("\"status\" \"--porcelain=v1\"", " M App/GymemoApp.swift\n"),
            ("\"simctl\" \"list\" \"devices\"", "{\"devices\":{}}"),
            (
                "repos/P4suta/gymemo/compare/",
                "{\"status\":\"ahead\",\"ahead_by\":1}",
            ),
        ] {
            let mut host = prepared();
            host.prints(command, value);
            assert!(run(&mut host, Path::new("/repo"), &arguments(true)).is_err());
            assert!(
                host.transcript()
                    .iter()
                    .all(|line| !line.starts_with("show "))
            );
            assert!(
                host.transcript()
                    .iter()
                    .all(|line| !line.contains("state=success"))
            );
        }
    }

    #[test]
    fn every_destination_requires_its_runtime_type_and_availability() -> Result<()> {
        let plan = Plan::parse(&arguments(false))?;
        let mut host = prepared();
        let valid = metadata(
            &mut host,
            Path::new("/repo"),
            Invocation::new("xcrun").args(["simctl", "list", "devices", "available", "--json"]),
        )?;
        plan.admit_devices(&valid)?;
        for selected in DEVICES {
            for field in ["runtime", "deviceTypeIdentifier", "isAvailable"] {
                let mut invalid = valid.clone();
                let runtimes = invalid["devices"].as_object_mut().unwrap();
                let (runtime, position) = runtimes
                    .iter()
                    .find_map(|(name, devices)| {
                        devices
                            .as_array()
                            .unwrap()
                            .iter()
                            .position(|device| device["udid"].as_str() == Some(selected))
                            .map(|position| (name.clone(), position))
                    })
                    .unwrap();
                if field == "runtime" {
                    let device = runtimes
                        .get_mut(&runtime)
                        .unwrap()
                        .as_array_mut()
                        .unwrap()
                        .remove(position);
                    runtimes.insert(
                        "com.apple.CoreSimulator.SimRuntime.unsupported".into(),
                        json!([device]),
                    );
                } else {
                    runtimes[&runtime][position][field] = if field == "isAvailable" {
                        json!(false)
                    } else {
                        json!("com.apple.CoreSimulator.SimDeviceType.unsupported")
                    };
                }
                let failure = plan
                    .admit_devices(&invalid)
                    .expect_err("one invalid destination property");
                assert!(
                    failure
                        .to_string()
                        .contains("wrong runtime, device type, or availability"),
                    "{selected}: {field}"
                );
            }
        }
        Ok(())
    }

    #[test]
    fn a_status_acknowledgement_requires_state_context_and_owner() {
        let valid = json!({"state":"success","context":CONTEXT,"creator":{"id":42543015}});
        for (pointer, replacement) in [
            ("/state", json!("pending")),
            ("/context", json!("Another check")),
            ("/creator/id", json!(1)),
        ] {
            let mut invalid = valid.clone();
            *invalid.pointer_mut(pointer).unwrap() = replacement;
            let mut host = prepared();
            host.prints("state=success", &invalid.to_string());
            let failure = status(
                &mut host,
                Path::new("/repo"),
                &Commit::parse(SOURCE).unwrap(),
                Verdict::Success,
            )
            .expect_err("an unrelated acknowledgement");
            assert!(
                failure.to_string().contains("didn't acknowledge"),
                "{pointer}"
            );
            assert_eq!(host.transcript().len(), 1);
            assert!(host.transcript()[0].contains("state=success"));
        }
    }

    #[test]
    fn source_admission_checks_each_repository_and_ancestry_property() {
        let source = Commit::parse(SOURCE).unwrap();
        let valid = json!({"id":1453033797,"owner":{"id":42543015},"default_branch":"main","private":false});
        for (pointer, replacement) in [
            ("/id", json!(1)),
            ("/owner/id", json!(1)),
            ("/default_branch", json!("another")),
            ("/private", json!(true)),
        ] {
            let mut invalid = valid.clone();
            *invalid.pointer_mut(pointer).unwrap() = replacement;
            let mut host = prepared();
            host.prints("\"repos/P4suta/gymemo\"", &invalid.to_string());
            let failure = admit_remote_source(&mut host, Path::new("/repo"), &source)
                .expect_err("a different repository property");
            assert!(
                failure
                    .to_string()
                    .contains("requires the public P4suta/gymemo"),
                "{pointer}"
            );
            assert_eq!(host.transcript().len(), 1);
        }
        let valid = json!({"status":"identical","ahead_by":0,"merge_base_commit":{"sha":SOURCE}});
        for (pointer, replacement) in [
            ("/status", json!("ahead")),
            ("/ahead_by", json!(1)),
            ("/merge_base_commit/sha", json!("another")),
        ] {
            let mut invalid = valid.clone();
            *invalid.pointer_mut(pointer).unwrap() = replacement;
            let mut host = prepared();
            host.prints("compare/main...", &invalid.to_string());
            let failure = admit_remote_source(&mut host, Path::new("/repo"), &source)
                .expect_err("an unrelated source commit");
            assert!(
                failure.to_string().contains("must already belong"),
                "{pointer}"
            );
            assert_eq!(host.transcript().len(), 2);
        }
    }

    #[test]
    fn success_requires_every_check_and_rechecks_the_source_between_them() -> Result<()> {
        let mut host = prepared();
        run(&mut host, Path::new("/repo"), &arguments(true))?;
        let lines = host.transcript();
        let commands = lines
            .iter()
            .filter(|line| line.starts_with("show "))
            .collect::<Vec<_>>();
        assert_eq!(commands.len(), 12);
        assert!(commands[0].contains("\"require-mac-ui\""));
        assert!(commands[0].contains(SOURCE));
        assert!(commands.iter().all(|line| !line.contains("platform=macOS")));
        for recipe in [
            "\"check\"",
            "\"ui-test\"",
            "\"sanitize\"",
            "\"mutate\"",
            "\"mutate-xtask\"",
            "\"proofs\"",
        ] {
            assert!(
                commands.iter().any(|line| line.contains(recipe)),
                "{recipe}"
            );
        }
        assert_eq!(
            lines
                .iter()
                .filter(|line| line.contains("\"rev-parse\""))
                .count(),
            13
        );
        assert_eq!(
            lines
                .iter()
                .filter(|line| line.contains("state=success"))
                .count(),
            1
        );
        assert!(
            lines
                .last()
                .expect("final status")
                .contains("state=success")
        );
        Ok(())
    }

    #[test]
    fn missing_hosted_mac_checks_stop_before_any_local_suite() {
        let mut host = prepared();
        host.fail(
            "\"require-mac-ui\"",
            Fault::Exit(1, "no hosted Mac UI result"),
        );
        assert!(run(&mut host, Path::new("/repo"), &arguments(true)).is_err());
        let lines = host.transcript();
        assert_eq!(
            lines
                .iter()
                .filter(|line| line.starts_with("show "))
                .count(),
            1
        );
        assert!(lines.iter().all(|line| !line.contains("state=success")));
        assert!(
            lines
                .last()
                .expect("failure status")
                .contains("state=failure")
        );
    }

    #[test]
    fn failed_or_inconclusive_checks_stop_without_a_success_status() {
        for code in [1, 75] {
            let mut host = prepared();
            host.fail("\"sanitize\"", Fault::Exit(code, "fixture failure"));
            let result = run(&mut host, Path::new("/repo"), &arguments(true));
            assert!(result.is_err());
            let lines = host.transcript();
            assert!(lines.iter().all(|line| !line.contains("state=success")));
            assert!(lines.iter().all(|line| !line.contains("\"mutate\"")));
            let expected = if code == 75 {
                "state=error"
            } else {
                "state=failure"
            };
            assert!(lines.last().expect("failure status").contains(expected));
        }
    }

    #[test]
    fn qualification_requires_the_current_status_of_the_exact_source_and_owner() -> Result<()> {
        let mut host = prepared();
        host.prints(
            "/statuses?per_page=100&page=1",
            &json!([{
                "url":"https://api.github.com/repos/P4suta/gymemo/statuses/0123456789abcdef0123456789abcdef01234567",
                "context":"local QUALIFICATION","state":"success","creator":{"id":42543015}
            }])
            .to_string(),
        );
        require(&mut host, Path::new("/repo"), SOURCE)?;
        assert!(
            host.transcript()
                .iter()
                .all(|line| !line.contains("\"POST\"") && !line.starts_with("show "))
        );
        Ok(())
    }

    #[test]
    fn stale_failed_missing_and_other_creators_statuses_are_refused() {
        let valid = json!([{
            "url":"https://api.github.com/repos/P4suta/gymemo/statuses/0123456789abcdef0123456789abcdef01234567",
            "context":"Local qualification","state":"success","creator":{"id":42543015}
        }]);
        for (path, value) in [
            (
                "/0/url",
                json!("https://api.github.com/repos/P4suta/gymemo/statuses/another"),
            ),
            ("/0/context", json!("Another check")),
            ("/0/state", json!("failure")),
            ("/0/state", json!("error")),
            ("/0/state", json!("pending")),
            ("/0/creator/id", json!(1)),
            ("/0/creator", Value::Null),
        ] {
            let mut changed = valid.clone();
            *changed.pointer_mut(path).expect("fixture field") = value;
            let mut host = prepared();
            host.prints("/statuses?per_page=100&page=1", &changed.to_string());
            assert!(
                require(&mut host, Path::new("/repo"), SOURCE).is_err(),
                "{path}"
            );
            assert!(
                host.transcript()
                    .iter()
                    .all(|line| !line.contains("\"POST\""))
            );
        }
        let mut host = FakeHost::new();
        assert!(require(&mut host, Path::new("/repo"), "main").is_err());
        assert!(host.transcript().is_empty());
    }

    #[test]
    fn the_newest_context_wins_and_status_pagination_is_bounded() -> Result<()> {
        let passed = json!({
            "url":"https://api.github.com/repos/P4suta/gymemo/statuses/0123456789abcdef0123456789abcdef01234567",
            "context":"Local qualification","state":"success","creator":{"id":42543015}
        });
        let mut failed = passed.clone();
        failed["state"] = json!("failure");
        for (statuses, succeeds) in [
            (json!([failed, passed]), false),
            (json!([passed, failed]), true),
        ] {
            let mut host = prepared();
            host.prints("/statuses?per_page=100&page=1", &statuses.to_string());
            assert_eq!(
                require(&mut host, Path::new("/repo"), SOURCE).is_ok(),
                succeeds
            );
        }
        let mut host = prepared();
        let page = json!(vec![json!({"context":"another"}); 100]);
        host.prints("/statuses?per_page=100&page=", &page.to_string());
        host.prints(
            "/statuses?per_page=100&page=2",
            &json!([passed]).to_string(),
        );
        require(&mut host, Path::new("/repo"), SOURCE)?;
        assert_eq!(
            host.transcript()
                .iter()
                .filter(|line| line.contains("/statuses?"))
                .count(),
            2
        );
        let mut host = prepared();
        host.prints("/statuses?per_page=100&page=", &page.to_string());
        assert!(require(&mut host, Path::new("/repo"), SOURCE).is_err());
        assert_eq!(
            host.transcript()
                .iter()
                .filter(|line| line.contains("/statuses?"))
                .count(),
            10
        );
        for invalid in [Value::Null, json!([]), json!({})] {
            let mut host = prepared();
            host.prints("/statuses?per_page=100&page=1", &invalid.to_string());
            assert!(require(&mut host, Path::new("/repo"), SOURCE).is_err());
        }
        for length in [0, 1, 99] {
            let mut host = prepared();
            host.prints(
                "/statuses?per_page=100&page=1",
                &json!(vec![json!({"context":"another"}); length]).to_string(),
            );
            assert!(require(&mut host, Path::new("/repo"), SOURCE).is_err());
            assert_eq!(
                host.transcript()
                    .iter()
                    .filter(|line| line.contains("/statuses?"))
                    .count(),
                1
            );
        }
        Ok(())
    }

    #[test]
    fn lost_source_access_after_a_check_invalidates_the_run() {
        let mut host = prepared();
        host.fail_at(7, Fault::Missing);
        let result = run(&mut host, Path::new("/repo"), &arguments(true));
        assert!(result.is_err_and(|failure| failure.code() == 75));
        let lines = host.transcript();
        assert_eq!(
            lines
                .iter()
                .filter(|line| line.starts_with("show "))
                .count(),
            1
        );
        assert!(lines.last().expect("error status").contains("state=error"));
        assert!(lines.iter().all(|line| !line.contains("state=success")));
    }
}
