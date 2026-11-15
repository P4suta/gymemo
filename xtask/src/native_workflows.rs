use crate::{
    failure::{Failure, Result, ensure},
    host::Host,
};
use serde::Deserialize;
use std::{collections::BTreeMap, collections::BTreeSet, path::Path};
use yaml_rust2::{Yaml, YamlLoader};

#[derive(Clone, Copy, Debug, Deserialize, Eq, Ord, PartialEq, PartialOrd)]
#[serde(rename_all = "kebab-case")]
enum Job {
    Admission,
    InstallerTool,
    Signing,
    Inspect,
    Upload,
    Complete,
}

impl Job {
    fn id(self) -> &'static str {
        match self {
            Self::Admission => "admission",
            Self::InstallerTool => "installer-tool",
            Self::Signing => "signing",
            Self::Inspect => "inspect",
            Self::Upload => "upload",
            Self::Complete => "complete",
        }
    }
}

struct Guard {
    job: Job,
    needs: &'static [Job],
    condition: &'static str,
}

const DELIVERY: &[Guard] = &[
    Guard {
        job: Job::Inspect,
        needs: &[Job::Admission, Job::Signing],
        condition: "!cancelled() && needs.admission.result == 'success' && needs.signing.result == 'success'",
    },
    Guard {
        job: Job::Upload,
        needs: &[Job::Admission, Job::Inspect],
        condition: "!cancelled() && inputs.upload && needs.admission.result == 'success' && needs.inspect.result == 'success'",
    },
    Guard {
        job: Job::Signing,
        needs: &[Job::Admission, Job::InstallerTool],
        condition: "!cancelled() && github.ref == 'refs/heads/main' && github.repository_id == '1453033797' && needs.admission.result == 'success' && (inputs.platform != 'macOS' || github.run_attempt > 1 || needs.installer-tool.result == 'success')",
    },
    Guard {
        job: Job::InstallerTool,
        needs: &[Job::Admission],
        condition: "!cancelled() && needs.admission.result == 'success' && inputs.platform == 'macOS' && github.run_attempt == 1",
    },
    Guard {
        job: Job::Complete,
        needs: &[Job::Admission, Job::Signing, Job::Inspect, Job::Upload],
        condition: "!cancelled()",
    },
];

const UPLOAD: &[Guard] = &[
    Guard {
        job: Job::Admission,
        needs: &[],
        condition: "!cancelled() && github.ref == 'refs/heads/main' && github.repository_id == '1453033797'",
    },
    Guard {
        job: Job::Upload,
        needs: &[Job::Admission],
        condition: "!cancelled() && needs.admission.result == 'success'",
    },
    Guard {
        job: Job::Complete,
        needs: &[Job::Admission, Job::Upload],
        condition: "!cancelled()",
    },
];

const UPLOAD_SECRET_NAMES: &[&str] = &[
    "DOPPLER_PROJECT",
    "DOPPLER_CONFIG",
    "APP_STORE_CONNECT_KEY_ID",
    "APP_STORE_CONNECT_ISSUER_ID",
    "APP_STORE_CONNECT_PRIVATE_KEY_BASE64",
];

fn prerequisites(value: &Yaml) -> Result<BTreeSet<&str>> {
    let mut result = BTreeSet::new();
    let values = match value {
        Yaml::BadValue => return Ok(result),
        Yaml::String(value) => {
            result.insert(value.as_str());
            return Ok(result);
        }
        Yaml::Array(values) => values,
        _ => return Err(Failure::new("Native prerequisites require job identifiers")),
    };
    for value in values {
        let name = value
            .as_str()
            .ok_or_else(|| Failure::new("Native prerequisites require string identifiers"))?;
        ensure(result.insert(name), || {
            "Native prerequisites must not repeat a job".into()
        })?;
    }
    Ok(result)
}

fn workflow(source: &str, guards: &[Guard]) -> Result<Yaml> {
    let documents = YamlLoader::load_from_str(source)
        .map_err(|error| Failure::new(format!("Parse the native workflow: {error}")))?;
    ensure(documents.len() == 1, || {
        "Native workflows require one YAML document".into()
    })?;
    let document = documents
        .into_iter()
        .next()
        .ok_or_else(|| Failure::new("The native workflow is empty"))?;
    for guard in guards {
        let job = &document["jobs"][guard.job.id()];
        let condition = job["if"].as_str().ok_or_else(|| {
            Failure::new(format!(
                "Native job {} requires its cancellation-aware success condition",
                guard.job.id()
            ))
        })?;
        let condition = condition.trim();
        let condition = condition
            .strip_prefix("${{")
            .and_then(|text| text.strip_suffix("}}"))
            .unwrap_or(condition)
            .trim();
        ensure(condition == guard.condition, || {
            format!(
                "Native job {} requires its canonical cancellation and prerequisite condition",
                guard.job.id()
            )
        })?;
        let expected = guard.needs.iter().map(|job| job.id()).collect();
        ensure(prerequisites(&job["needs"])? == expected, || {
            format!("Native job {} has different prerequisites", guard.job.id())
        })?;
    }
    Ok(document)
}

pub fn check(host: &mut impl Host, root: &Path) -> Result<()> {
    let mut source = |path: &str| {
        host.read(&root.join(path))
            .map_err(|error| Failure::new(format!("Read {path}: {error}")))
    };
    let delivery = workflow(&source(".github/workflows/native-delivery.yml")?, DELIVERY)?;
    let ios_export = delivery["jobs"]["signing"]["steps"]
        .as_vec()
        .and_then(|steps| {
            steps.iter().find(|step| {
                step["name"].as_str() == Some("Export a signed iOS package without uploading")
            })
        })
        .and_then(|step| step["run"].as_str());
    ensure(
        ios_export.is_some_and(|run| {
            run.lines().any(|line| {
                let command: Vec<_> = line.split_whitespace().collect();
                command.starts_with(&["mise", "x", "--", "asc", "xcode", "export"])
                    && command.windows(2).any(|arguments| {
                        arguments
                            == [
                                "--export-options",
                                r#""$RUNNER_TEMP/gymemo-signing/ios-options.plist""#,
                            ]
                    })
            })
        }),
        || "Unsigned iOS export requires explicit provisioning options".into(),
    )?;
    ensure(
        delivery["jobs"]["upload"]["uses"].as_str()
            == Some("./.github/workflows/native-upload.yml"),
        || "Native delivery must use the shared upload boundary".into(),
    )?;
    let upload = workflow(&source(".github/workflows/native-upload.yml")?, UPLOAD)?;
    let forwarded = &delivery["jobs"]["upload"]["secrets"];
    let declared = &upload["on"]["workflow_call"]["secrets"];
    ensure(
        forwarded.as_hash().map(|values| values.len()) == Some(UPLOAD_SECRET_NAMES.len())
            && declared.as_hash().map(|values| values.len()) == Some(UPLOAD_SECRET_NAMES.len()),
        || "Native upload requires exactly its five named secrets".into(),
    )?;
    for &name in UPLOAD_SECRET_NAMES {
        let reference = format!("${{{{ secrets.{name} }}}}");
        ensure(forwarded[name].as_str() == Some(reference.as_str()), || {
            format!("Native upload must forward {name} by name")
        })?;
        ensure(declared[name]["required"].as_bool() == Some(true), || {
            format!("Native upload must require {name}")
        })?;
    }
    ensure(
        upload["jobs"]["upload"]["environment"].as_str() == Some("native-upload"),
        || "Native upload requires its protected environment".into(),
    )?;
    ensure(
        upload["run-name"].as_str() == Some("Upload signed run ${{ inputs.signing_run }}"),
        || "Native upload history requires its signing-run identity".into(),
    )?;
    let pins: toml::Value = toml::from_str(&source("mise.toml")?)
        .map_err(|error| Failure::new(format!("Read the workflow tool pins: {error}")))?;
    ensure(
        pins.get("tools")
            .and_then(|tools| tools.get("actionlint"))
            .and_then(toml::Value::as_str)
            == Some("1.7.12"),
        || "Review the local workflow compatibility exception when actionlint changes".into(),
    )?;
    host.print(
        "PASS native workflows: cancellation, prerequisites, iOS export, and upload boundary",
    );
    Ok(())
}

#[derive(Clone, Copy, Deserialize, Eq, PartialEq)]
#[serde(rename_all = "lowercase")]
enum Outcome {
    Success,
    Failure,
    Cancelled,
    Skipped,
}

#[derive(Deserialize)]
struct Observed {
    result: Outcome,
}

fn admit_outcome(kind: &str, requested: bool, source: &str) -> Result<()> {
    let jobs: &[Job] = match kind {
        "delivery" => &[Job::Admission, Job::Signing, Job::Inspect, Job::Upload],
        "upload" if requested => &[Job::Admission, Job::Upload],
        _ => {
            return Err(Failure::new(
                "Native outcome requires delivery or requested upload",
            ));
        }
    };
    let observed: BTreeMap<Job, Observed> = serde_json::from_str(source)
        .map_err(|error| Failure::new(format!("Read native job outcomes: {error}")))?;
    ensure(
        observed.keys().copied().collect::<BTreeSet<_>>() == jobs.iter().copied().collect(),
        || "Native outcome requires every declared operation exactly once".into(),
    )?;
    for job in jobs {
        let expected = if *job == Job::Upload && !requested {
            Outcome::Skipped
        } else {
            Outcome::Success
        };
        ensure(
            observed
                .get(job)
                .is_some_and(|value| value.result == expected),
            || {
                format!(
                    "Native operation {} did not reach its required outcome",
                    job.id()
                )
            },
        )?;
    }
    Ok(())
}

pub fn outcome(host: &mut impl Host, arguments: &[String]) -> Result<()> {
    let [kind, requested, source] = arguments else {
        return Err(Failure::new(
            "check-native-outcome requires delivery|upload true|false RESULTS_JSON",
        ));
    };
    let requested = match requested.as_str() {
        "true" => true,
        "false" => false,
        _ => {
            return Err(Failure::new(
                "Native upload selection requires true or false",
            ));
        }
    };
    admit_outcome(kind, requested, source)?;
    host.print("PASS native outcome: every requested operation completed");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::host::fake::FakeHost;
    use serde_json::json;
    use yaml_rust2::YamlEmitter;

    fn node<'a>(value: &'a mut Yaml, path: &[&str]) -> Result<&'a mut Yaml> {
        let Some((key, remaining)) = path.split_first() else {
            return Ok(value);
        };
        let Yaml::Hash(values) = value else {
            return Err(Failure::new("The workflow fixture requires a mapping"));
        };
        let child = values
            .get_mut(&Yaml::String((*key).to_owned()))
            .ok_or_else(|| Failure::new("The workflow fixture lacks its target"))?;
        node(child, remaining)
    }

    fn render(value: &Yaml) -> Result<String> {
        let mut output = String::new();
        YamlEmitter::new(&mut output)
            .dump(value)
            .map_err(|error| Failure::new(format!("Render the workflow fixture: {error}")))?;
        Ok(output)
    }

    fn source_host(delivery: &str, upload: &str, pins: &str) -> FakeHost {
        let mut host = FakeHost::new();
        host.file("/repo/.github/workflows/native-delivery.yml", delivery);
        host.file("/repo/.github/workflows/native-upload.yml", upload);
        host.file("/repo/mise.toml", pins);
        host
    }

    #[test]
    fn every_native_guard_rejects_omission_weakening_and_missing_dependencies() -> Result<()> {
        for (source, guards) in [
            (
                include_str!("../../.github/workflows/native-delivery.yml"),
                DELIVERY,
            ),
            (
                include_str!("../../.github/workflows/native-upload.yml"),
                UPLOAD,
            ),
        ] {
            let original = workflow(source, guards)?;
            for guard in guards {
                for condition in [
                    Yaml::Null,
                    Yaml::Boolean(false),
                    Yaml::String("always()".into()),
                    Yaml::String("success()".into()),
                ] {
                    let mut changed = original.clone();
                    *node(&mut changed, &["jobs", guard.job.id(), "if"])? = condition;
                    assert!(
                        workflow(&render(&changed)?, guards).is_err(),
                        "{}",
                        guard.job.id()
                    );
                }
                let mut changed = original.clone();
                if !guard.needs.is_empty() {
                    *node(&mut changed, &["jobs", guard.job.id(), "needs"])? =
                        Yaml::Array(Vec::new());
                    assert!(
                        workflow(&render(&changed)?, guards).is_err(),
                        "{}",
                        guard.job.id()
                    );
                }
            }
            assert!(workflow(&format!("{source}\n---\n{{}}\n"), guards).is_err());
        }
        Ok(())
    }

    #[test]
    fn actual_gate_refuses_changed_upload_boundaries_and_stale_compatibility() -> Result<()> {
        let delivery = include_str!("../../.github/workflows/native-delivery.yml");
        let upload = include_str!("../../.github/workflows/native-upload.yml");
        let pins = include_str!("../../mise.toml");
        check(&mut source_host(delivery, upload, pins), Path::new("/repo"))?;
        let document = workflow(delivery, DELIVERY)?;
        let mut changed = document.clone();
        *node(&mut changed, &["jobs", "upload", "uses"])? =
            Yaml::String("other/repo/workflow.yml@main".into());
        assert!(
            check(
                &mut source_host(&render(&changed)?, upload, pins),
                Path::new("/repo")
            )
            .is_err()
        );
        let document = workflow(upload, UPLOAD)?;
        for (path, value) in [
            (vec!["jobs", "upload", "environment"], "other"),
            (vec!["run-name"], "Unbound upload"),
        ] {
            let mut changed = document.clone();
            *node(&mut changed, &path)? = Yaml::String(value.into());
            assert!(
                check(
                    &mut source_host(delivery, &render(&changed)?, pins),
                    Path::new("/repo")
                )
                .is_err()
            );
        }
        let changed = pins.replace("actionlint = \"1.7.12\"", "actionlint = \"1.7.13\"");
        assert_ne!(changed, pins);
        assert!(
            check(
                &mut source_host(delivery, upload, &changed),
                Path::new("/repo")
            )
            .is_err()
        );
        Ok(())
    }

    #[test]
    fn actual_gate_refuses_unforwarded_upload_secrets() -> Result<()> {
        let delivery = include_str!("../../.github/workflows/native-delivery.yml");
        let upload = include_str!("../../.github/workflows/native-upload.yml");
        let pins = include_str!("../../mise.toml");
        let mut changed = workflow(delivery, DELIVERY)?;
        let Yaml::Hash(job) = node(&mut changed, &["jobs", "upload"])? else {
            return Err(Failure::new("The upload fixture requires a mapping"));
        };
        job.remove(&Yaml::String("secrets".into()));
        assert!(
            check(
                &mut source_host(&render(&changed)?, upload, pins),
                Path::new("/repo")
            )
            .is_err()
        );
        Ok(())
    }

    #[test]
    fn actual_gate_checks_each_upload_secret_and_its_declaration() -> Result<()> {
        let delivery = include_str!("../../.github/workflows/native-delivery.yml");
        let upload = include_str!("../../.github/workflows/native-upload.yml");
        let pins = include_str!("../../mise.toml");
        let delivery_document = workflow(delivery, DELIVERY)?;
        let upload_document = workflow(upload, UPLOAD)?;
        for name in [
            "DOPPLER_PROJECT",
            "DOPPLER_CONFIG",
            "APP_STORE_CONNECT_KEY_ID",
            "APP_STORE_CONNECT_ISSUER_ID",
            "APP_STORE_CONNECT_PRIVATE_KEY_BASE64",
        ] {
            let mut changed = delivery_document.clone();
            *node(&mut changed, &["jobs", "upload", "secrets", name])? =
                Yaml::String("other".into());
            assert!(
                check(
                    &mut source_host(&render(&changed)?, upload, pins),
                    Path::new("/repo")
                )
                .is_err(),
                "{name}"
            );
            let mut changed = upload_document.clone();
            *node(
                &mut changed,
                &["on", "workflow_call", "secrets", name, "required"],
            )? = Yaml::Boolean(false);
            assert!(
                check(
                    &mut source_host(delivery, &render(&changed)?, pins),
                    Path::new("/repo")
                )
                .is_err(),
                "{name}"
            );
        }
        for caller in [false, true] {
            let mut changed = if caller {
                delivery_document.clone()
            } else {
                upload_document.clone()
            };
            let path: &[&str] = if caller {
                &["jobs", "upload", "secrets"]
            } else {
                &["on", "workflow_call", "secrets"]
            };
            let Yaml::Hash(secrets) = node(&mut changed, path)? else {
                return Err(Failure::new("The secret fixture requires a mapping"));
            };
            secrets.insert(Yaml::String("EXTRA".into()), Yaml::String("other".into()));
            let rendered = render(&changed)?;
            let mut host = if caller {
                source_host(&rendered, upload, pins)
            } else {
                source_host(delivery, &rendered, pins)
            };
            assert!(check(&mut host, Path::new("/repo")).is_err());
        }
        Ok(())
    }

    #[test]
    fn actual_gate_rejects_implicit_ios_export_options() -> Result<()> {
        let delivery = include_str!("../../.github/workflows/native-delivery.yml");
        let upload = include_str!("../../.github/workflows/native-upload.yml");
        let pins = include_str!("../../mise.toml");
        let original = workflow(delivery, DELIVERY)?;
        for run in [
            r#"mise x -- asc xcode export --archive-path candidate/gymemo.xcarchive --ipa-path signed/gymemo.ipa --method app-store-connect --signing-style manual --team-id "$APPLE_TEAM_ID" --timeout 20m"#,
            r#"echo --export-options "$RUNNER_TEMP/gymemo-signing/ios-options.plist""#,
            "mise x -- asc xcode export --export-options other.plist",
            "mise x -- asc xcode export --export-options",
            "",
        ] {
            let mut changed = original.clone();
            let Yaml::Array(steps) = node(&mut changed, &["jobs", "signing", "steps"])? else {
                return Err(Failure::new("The signing fixture requires steps"));
            };
            let step = steps
                .iter_mut()
                .find(|step| {
                    step["name"].as_str() == Some("Export a signed iOS package without uploading")
                })
                .ok_or_else(|| Failure::new("The fixture lacks the iOS export"))?;
            *node(step, &["run"])? = Yaml::String(run.into());
            assert!(
                check(
                    &mut source_host(&render(&changed)?, upload, pins),
                    Path::new("/repo")
                )
                .is_err(),
                "{run}"
            );
        }
        Ok(())
    }

    #[test]
    fn delivery_source_does_not_inherit_optional_skips() -> Result<()> {
        workflow(
            include_str!("../../.github/workflows/native-delivery.yml"),
            DELIVERY,
        )?;
        Ok(())
    }

    #[test]
    fn refuses_the_observed_successful_signature_with_skipped_upload() {
        let observed = json!({
            "admission": {"result": "success"},
            "signing": {"result": "success"},
            "inspect": {"result": "skipped"},
            "upload": {"result": "skipped"},
        });
        assert!(admit_outcome("delivery", true, &observed.to_string()).is_err());
    }

    #[test]
    fn refuses_every_unsuccessful_requested_operation() -> Result<()> {
        let good = json!({
            "admission": {"result": "success"},
            "signing": {"result": "success"},
            "inspect": {"result": "success"},
            "upload": {"result": "success"},
        });
        admit_outcome("delivery", true, &good.to_string())?;
        for job in ["admission", "signing", "inspect", "upload"] {
            for result in ["failure", "cancelled", "skipped", "neutral"] {
                let mut changed = good.clone();
                changed[job]["result"] = json!(result);
                assert!(admit_outcome("delivery", true, &changed.to_string()).is_err());
            }
            let mut changed = good.clone();
            let removed = changed
                .as_object_mut()
                .and_then(|values| values.remove(job));
            assert!(removed.is_some());
            assert!(admit_outcome("delivery", true, &changed.to_string()).is_err());
        }
        let mut sign_only = good;
        sign_only["upload"]["result"] = json!("skipped");
        admit_outcome("delivery", false, &sign_only.to_string())?;
        sign_only["upload"]["result"] = json!("success");
        assert!(admit_outcome("delivery", false, &sign_only.to_string()).is_err());
        Ok(())
    }

    #[test]
    fn upload_outcome_rejects_missing_or_unrequested_work() -> Result<()> {
        let good = json!({
            "admission": {"result": "success"},
            "upload": {"result": "success"},
        });
        admit_outcome("upload", true, &good.to_string())?;
        assert!(admit_outcome("upload", false, &good.to_string()).is_err());
        let mut skipped = good.clone();
        skipped["upload"]["result"] = json!("skipped");
        assert!(admit_outcome("upload", false, &skipped.to_string()).is_err());
        assert!(admit_outcome("upload", true, "{}").is_err());
        assert!(admit_outcome("unknown", true, &good.to_string()).is_err());
        Ok(())
    }
}
