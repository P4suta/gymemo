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

fn mac_sandbox(delivery: &Yaml) -> Result<()> {
    let steps = delivery["jobs"]["signing"]["steps"]
        .as_vec()
        .ok_or_else(|| Failure::new("Native signing requires steps"))?;
    let step = |name| {
        steps
            .iter()
            .find(|step| step["name"].as_str() == Some(name))
            .ok_or_else(|| Failure::new(format!("Native signing requires {name}")))
    };
    let source = step("Read the qualified Mac sandbox configuration")?;
    ensure(
        source["with"]["ref"].as_str() == Some("${{ inputs.source_sha }}")
            && source["with"]["path"].as_str() == Some("qualified-source")
            && source["with"]["sparse-checkout"].as_str() == Some("Config/Mac.entitlements")
            && source["with"]["persist-credentials"].as_bool() == Some(false),
        || "Mac sandbox permissions must come from the qualified source".into(),
    )?;
    let phases = [
        "Sign the preserved Mac app",
        "Create the signed Mac package",
    ];
    ensure(
        steps
            .iter()
            .filter_map(|step| step["name"].as_str())
            .filter(|name| phases.contains(name))
            .eq(phases),
        || "Mac app signing must precede one separate packaging step".into(),
    )?;
    for (name, other) in [
        (phases[0], "productbuild --sign"),
        (phases[1], "codesign --force"),
    ] {
        let selected = step(name)?;
        ensure(
            selected["env"]["MAC_APP"].as_str()
                == Some("candidate/gymemo.xcarchive/Products/Applications/gymemo.app")
                && selected["timeout-minutes"].as_i64() == Some(5)
                && selected["run"]
                    .as_str()
                    .is_some_and(|run| !run.contains(other)),
            || {
                "Mac signing phases require the preserved app and separate five-minute limits"
                    .into()
            },
        )?;
    }
    let contracts: [(&str, &[&str]); 4] = [
        (
            "Install the macOS profile and installer identity",
            &[
                r#"mise x -- installer-tool/xtask install-mac-installer "$RUNNER_TEMP/gymemo-installer.keychain-db" "$RUNNER_TEMP/gymemo-signing/keychain-password" "$INSTALLER_SHA256" --add-to-search-list --confirm > "$RUNNER_TEMP/gymemo-signing/installer-identity.json""#,
            ],
        ),
        (
            "Sign the preserved Mac app",
            &[
                "set -o pipefail",
                r#"test "$(plutil -extract 'TeamIdentifier.0' raw -o - "$RUNNER_TEMP/gymemo-signing/mac-profile.plist")" = "$APPLE_TEAM_ID""#,
                r#"test "$(plutil -extract 'Entitlements.com\.apple\.application-identifier' raw -o - "$RUNNER_TEMP/gymemo-signing/mac-profile.plist")" = "$APPLE_TEAM_ID.com.p4suta.gymemo""#,
                r#"cp qualified-source/Config/Mac.entitlements "$RUNNER_TEMP/gymemo-signing/mac-entitlements.plist""#,
                r#"plutil -insert 'com\.apple\.application-identifier' -string "$APPLE_TEAM_ID.com.p4suta.gymemo" "$RUNNER_TEMP/gymemo-signing/mac-entitlements.plist""#,
                r#"plutil -insert 'com\.apple\.developer\.team-identifier' -string "$APPLE_TEAM_ID" "$RUNNER_TEMP/gymemo-signing/mac-entitlements.plist""#,
                r#"cp "$RUNNER_TEMP/gymemo-signing/mac.provisionprofile" "$MAC_APP/Contents/embedded.provisionprofile""#,
                r#"codesign --force --sign 'Apple Distribution' --keychain "$RUNNER_TEMP/gymemo-application.keychain-db" --entitlements "$RUNNER_TEMP/gymemo-signing/mac-entitlements.plist" "$MAC_APP""#,
                r#"codesign --verify --deep --strict "$MAC_APP""#,
            ],
        ),
        (
            "Create the signed Mac package",
            &[
                "set -o pipefail",
                r#"installer_identity="$(jq -er '.subject' "$RUNNER_TEMP/gymemo-signing/installer-identity.json")""#,
                r#"productbuild --sign "$installer_identity" --keychain "$RUNNER_TEMP/gymemo-installer.keychain-db" --component "$MAC_APP" /Applications signed/gymemo.pkg"#,
                "pkgutil --check-signature signed/gymemo.pkg",
                "shasum -a 256 signed/gymemo.pkg > signed/SHA256SUMS",
            ],
        ),
        (
            "Verify the signed Mac sandbox",
            &[
                r#"codesign --verify --deep --strict "$exported_app""#,
                r#"codesign -d --entitlements - --xml "$exported_app" > "$RUNNER_TEMP/gymemo-signing/mac-entitlements.plist""#,
                r#"test "$(plutil -extract 'com\.apple\.security\.app-sandbox' raw -o - "$RUNNER_TEMP/gymemo-signing/mac-entitlements.plist")" = true"#,
                r#"test "$(plutil -extract 'com\.apple\.security\.files\.user-selected\.read-write' raw -o - "$RUNNER_TEMP/gymemo-signing/mac-entitlements.plist")" = true"#,
            ],
        ),
    ];
    for (name, required) in contracts {
        let selected = step(name)?;
        ensure(
            selected["if"].as_str()
                == Some("github.run_attempt == 1 && inputs.platform == 'macOS'")
                && selected["run"].as_str().is_some_and(|run| {
                    required
                        .iter()
                        .all(|command| run.lines().any(|line| line.trim() == *command))
                }),
            || format!("Mac signing requires sandbox preparation and verification in {name}"),
        )?;
    }
    Ok(())
}

#[derive(Clone, Copy)]
enum ExpressionRegion {
    Text,
    Code,
    Property,
    SingleQuoted,
}

fn expression_uses_secrets(value: &str) -> bool {
    let mut characters = value.chars().peekable();
    let mut region = ExpressionRegion::Text;
    while let Some(character) = characters.next() {
        match region {
            ExpressionRegion::Text => {
                if character == '$'
                    && characters.next_if_eq(&'{').is_some()
                    && characters.next_if_eq(&'{').is_some()
                {
                    region = ExpressionRegion::Code;
                }
            }
            ExpressionRegion::Code | ExpressionRegion::Property => {
                if character == '}' && characters.next_if_eq(&'}').is_some() {
                    region = ExpressionRegion::Text;
                } else if character == '\'' {
                    region = ExpressionRegion::SingleQuoted;
                } else if character.is_ascii_alphabetic() || character == '_' {
                    let mut identifier = character.to_string();
                    while let Some(character) = characters.next_if(|character| {
                        character.is_ascii_alphanumeric() || matches!(character, '_' | '-')
                    }) {
                        identifier.push(character);
                    }
                    if matches!(region, ExpressionRegion::Code)
                        && identifier.eq_ignore_ascii_case("secrets")
                    {
                        return true;
                    }
                    region = ExpressionRegion::Code;
                } else if !character.is_ascii_whitespace() {
                    region = if character == '.' {
                        ExpressionRegion::Property
                    } else {
                        ExpressionRegion::Code
                    };
                }
            }
            ExpressionRegion::SingleQuoted => {
                if character == '\'' && characters.next_if_eq(&'\'').is_none() {
                    region = ExpressionRegion::Code;
                }
            }
        }
    }
    false
}

fn yaml_uses_secrets(value: &Yaml) -> bool {
    match value {
        Yaml::String(value) => expression_uses_secrets(value),
        Yaml::Array(values) => values.iter().any(yaml_uses_secrets),
        Yaml::Hash(values) => values
            .iter()
            .any(|(key, value)| yaml_uses_secrets(key) || yaml_uses_secrets(value)),
        _ => false,
    }
}

fn installer_tools(
    document: &Yaml,
    workflow_name: &str,
    consumer: &str,
    verification: &str,
    private_steps: &[&str],
    condition: Option<&str>,
) -> Result<()> {
    let builder = &document["jobs"]["installer-tool"];
    ensure(
        builder["environment"] == Yaml::BadValue
            && !yaml_uses_secrets(builder)
            && !yaml_uses_secrets(&document["env"]),
        || "Installer tools must be built without private credentials".into(),
    )?;
    let steps = builder["steps"]
        .as_vec()
        .ok_or_else(|| Failure::new("The installer tool build requires steps"))?;
    ensure(
        steps.iter().any(|step| {
            step["run"].as_str() == Some("mise x -- just build-installer-tool")
                && step["if"] == Yaml::BadValue
        }),
        || "The installer controller and native bridge must be built together".into(),
    )?;
    for binary in ["xtask", "installer-import"] {
        let path = format!("target/debug/{binary}");
        ensure(
            steps
                .iter()
                .filter(|step| {
                    step["with"]["subject-path"].as_str() == Some(path.as_str())
                        && step["if"] == Yaml::BadValue
                        && step["uses"].as_str().is_some_and(|action| {
                            action.starts_with("actions/attest-build-provenance@")
                        })
                })
                .count()
                == 1,
            || format!("Installer provenance requires exactly one attestation for {binary}"),
        )?;
    }
    ensure(
        steps.iter().any(|step| {
            step["id"].as_str() == Some("artifact")
                && step["with"]["path"].as_str().is_some_and(|path| {
                    path.lines()
                        .eq(["target/debug/xtask", "target/debug/installer-import"])
                })
                && step["if"] == Yaml::BadValue
        }),
        || "The installer artifact must contain both executables".into(),
    )?;
    let job = &document["jobs"][consumer];
    ensure(
        prerequisites(&job["needs"])?.contains("installer-tool"),
        || "Installer credentials must depend on the tool build".into(),
    )?;
    let steps = job["steps"]
        .as_vec()
        .ok_or_else(|| Failure::new("Installer verification requires steps"))?;
    let position = |name| {
        steps
            .iter()
            .position(|step| step["name"].as_str() == Some(name))
            .ok_or_else(|| Failure::new(format!("The installer workflow requires {name}")))
    };
    let verified = position(verification)?;
    ensure(!private_steps.is_empty(), || {
        "Installer verification requires private-input boundaries".into()
    })?;
    for private in private_steps {
        ensure(verified < position(private)?, || {
            "Verify both installer executables before private inputs".into()
        })?;
    }
    let selected = &steps[verified];
    ensure(
        match condition {
            Some(expected) => selected["if"].as_str() == Some(expected),
            None => selected["if"] == Yaml::BadValue,
        },
        || "Installer provenance verification must remain reachable".into(),
    )?;
    let run = selected["run"]
        .as_str()
        .ok_or_else(|| Failure::new("Installer provenance verification requires commands"))?;
    for binary in ["xtask", "installer-import"] {
        let command = format!(
            r#"gh attestation verify installer-tool/{binary} --repo "$GITHUB_REPOSITORY" --signer-workflow "$GITHUB_REPOSITORY/.github/workflows/{workflow_name}" --source-ref refs/heads/main --source-digest "$GITHUB_SHA" --signer-digest "$GITHUB_SHA""#
        );
        ensure(run.lines().any(|line| line.trim() == command), || {
            format!("Verify installer provenance for {binary}")
        })?;
    }
    ensure(
        run.lines().any(|line| {
            line.trim() == "chmod 700 installer-tool/xtask installer-tool/installer-import"
        }),
        || "Protect both verified installer executables before use".into(),
    )?;
    ensure(
        steps.iter().all(|step| {
            step["run"].as_str().is_none_or(|run| {
                !["cargo build", "swiftc", "just build-installer-tool"]
                    .iter()
                    .any(|command| run.contains(command))
            })
        }),
        || "Build installer tools before the protected credential job".into(),
    )?;
    Ok(())
}

pub fn check(host: &mut impl Host, root: &Path) -> Result<()> {
    let mut source = |path: &str| {
        host.read(&root.join(path))
            .map_err(|error| Failure::new(format!("Read {path}: {error}")))
    };
    let delivery = workflow(&source(".github/workflows/native-delivery.yml")?, DELIVERY)?;
    let credentials = workflow(&source(".github/workflows/native-credentials.yml")?, &[])?;
    for (document, name, consumer, verification, import, condition) in [
        (
            &delivery,
            "native-delivery.yml",
            "signing",
            "Verify the installer importer source",
            &[
                "Install the expected application signing identity",
                "Install the macOS profile and installer identity",
            ][..],
            Some("github.run_attempt == 1 && inputs.platform == 'macOS'"),
        ),
        (
            &credentials,
            "native-credentials.yml",
            "installer",
            "Verify the importer source",
            &["Verify the selected Mac App Store installer identity"][..],
            None,
        ),
    ] {
        installer_tools(document, name, consumer, verification, import, condition)?;
    }
    ensure(source("justfile")?.contains("build-installer-tool:\n    cargo build --locked -p xtask\n    xcrun swiftc -swift-version 6 -parse-as-library -warnings-as-errors -O xtask/native/InstallerImport.swift -o target/debug/installer-import"), || "The installer tool recipe requires a checked native bridge build".into())?;
    mac_sandbox(&delivery)?;
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
        "PASS native workflows: cancellation, prerequisites, explicit export, sandbox, and upload boundary",
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
        host.file(
            "/repo/.github/workflows/native-credentials.yml",
            include_str!("../../.github/workflows/native-credentials.yml"),
        );
        host.file("/repo/justfile", include_str!("../../justfile"));
        host
    }

    fn signing_step<'a>(document: &'a mut Yaml, name: &str) -> Result<&'a mut Yaml> {
        let Yaml::Array(steps) = node(document, &["jobs", "signing", "steps"])? else {
            return Err(Failure::new("The signing fixture requires steps"));
        };
        steps
            .iter_mut()
            .find(|step| step["name"].as_str() == Some(name))
            .ok_or_else(|| Failure::new(format!("The fixture lacks {name}")))
    }

    type InstallerCase = (
        &'static str,
        &'static str,
        &'static str,
        &'static str,
        &'static [&'static str],
        Option<&'static str>,
    );

    const INSTALLER_CASES: [InstallerCase; 2] = [
        (
            include_str!("../../.github/workflows/native-delivery.yml"),
            "native-delivery.yml",
            "signing",
            "Verify the installer importer source",
            &[
                "Install the expected application signing identity",
                "Install the macOS profile and installer identity",
            ],
            Some("github.run_attempt == 1 && inputs.platform == 'macOS'"),
        ),
        (
            include_str!("../../.github/workflows/native-credentials.yml"),
            "native-credentials.yml",
            "installer",
            "Verify the importer source",
            &["Verify the selected Mac App Store installer identity"],
            None,
        ),
    ];

    #[test]
    fn installer_boundaries_reject_missing_builds_artifacts_and_provenance() -> Result<()> {
        for (source, name, consumer, verification, import, condition) in INSTALLER_CASES {
            installer_tools(
                &workflow(source, &[])?,
                name,
                consumer,
                verification,
                import,
                condition,
            )?;
            for (before, after) in [
                (
                    "mise x -- just build-installer-tool",
                    "mise x -- cargo build --locked -p xtask",
                ),
                (
                    "subject-path: target/debug/installer-import",
                    "subject-path: target/debug/missing",
                ),
                (
                    "subject-path: target/debug/xtask",
                    "subject-path: target/debug/missing",
                ),
                (
                    "            target/debug/installer-import",
                    "            target/debug/missing",
                ),
                (
                    "gh attestation verify installer-tool/installer-import",
                    "false --",
                ),
                ("gh attestation verify installer-tool/xtask", "false --"),
                (
                    "chmod 700 installer-tool/xtask installer-tool/installer-import",
                    "true",
                ),
                (
                    "chmod 700 installer-tool/xtask installer-tool/installer-import",
                    "cargo build --locked -p xtask",
                ),
                ("actions/attest-build-provenance@", "unrelated/action@"),
                (
                    "- run: mise x -- just build-installer-tool",
                    "- if: false\n        run: mise x -- just build-installer-tool",
                ),
                (
                    "- uses: actions/attest-build-provenance@",
                    "- if: false\n        uses: actions/attest-build-provenance@",
                ),
            ] {
                assert!(source.contains(before), "{name}: {before}");
                let changed = workflow(&source.replace(before, after), &[])?;
                assert!(
                    installer_tools(&changed, name, consumer, verification, import, condition)
                        .is_err(),
                    "{name}: {before}"
                );
            }
        }
        Ok(())
    }

    #[test]
    fn installer_builds_reject_credential_scope_and_repeated_attestations() -> Result<()> {
        for (source, name, consumer, verification, import, condition) in INSTALLER_CASES {
            let original = workflow(source, &[])?;
            let mut extended = original.clone();
            let Yaml::Array(steps) = node(&mut extended, &["jobs", "installer-tool", "steps"])?
            else {
                return Err(Failure::new("The installer fixture requires build steps"));
            };
            let mut metadata = steps
                .iter()
                .find(|step| step["with"]["subject-path"].as_str() == Some("target/debug/xtask"))
                .ok_or_else(|| Failure::new("The installer fixture lacks provenance"))?
                .clone();
            *node(&mut metadata, &["with", "subject-path"])? = Yaml::String("Cargo.lock".into());
            steps.push(metadata);
            installer_tools(&extended, name, consumer, verification, import, condition)?;
            let private_environment = workflow("PRIVATE: ${{ secrets.PRIVATE }}", &[])?;
            for (path, field, value) in [
                (
                    vec!["jobs", "installer-tool"],
                    "environment",
                    Yaml::String("native-signing".into()),
                ),
                (
                    vec!["jobs", "installer-tool"],
                    "env",
                    private_environment.clone(),
                ),
                (vec![], "env", private_environment),
                (
                    vec!["jobs", consumer],
                    "needs",
                    Yaml::String("admission".into()),
                ),
            ] {
                let mut changed = original.clone();
                let Yaml::Hash(fields) = node(&mut changed, &path)? else {
                    return Err(Failure::new("The installer fixture requires a mapping"));
                };
                fields.insert(Yaml::String(field.into()), value);
                assert!(
                    installer_tools(&changed, name, consumer, verification, import, condition)
                        .is_err(),
                    "{name}: {field}"
                );
            }
            for binary in ["xtask", "installer-import"] {
                let mut changed = original.clone();
                let Yaml::Array(steps) = node(&mut changed, &["jobs", "installer-tool", "steps"])?
                else {
                    return Err(Failure::new("The installer fixture requires build steps"));
                };
                let path = format!("target/debug/{binary}");
                let repeated = steps
                    .iter()
                    .find(|step| step["with"]["subject-path"].as_str() == Some(path.as_str()))
                    .ok_or_else(|| Failure::new("The installer fixture lacks an attestation"))?
                    .clone();
                steps.push(repeated);
                assert!(
                    installer_tools(&changed, name, consumer, verification, import, condition)
                        .is_err(),
                    "{name}: {binary}"
                );
            }
        }
        Ok(())
    }

    #[test]
    fn installer_verification_must_precede_private_inputs_without_skips() -> Result<()> {
        for (source, name, consumer, verification, import, condition) in INSTALLER_CASES {
            let original = workflow(source, &[])?;
            assert!(
                installer_tools(
                    &original,
                    name,
                    consumer,
                    verification,
                    &[verification],
                    condition
                )
                .is_err(),
                "{name}: shared verification and import step"
            );
            assert!(
                installer_tools(&original, name, consumer, verification, &[], condition).is_err()
            );
            for (import_step, reordered) in
                import.iter().flat_map(|step| [(step, false), (step, true)])
            {
                let mut changed = original.clone();
                let Yaml::Array(steps) = node(&mut changed, &["jobs", consumer, "steps"])? else {
                    return Err(Failure::new(
                        "The installer fixture requires credential steps",
                    ));
                };
                let position = |name| {
                    steps
                        .iter()
                        .position(|step| step["name"].as_str() == Some(name))
                        .ok_or_else(|| {
                            Failure::new("The installer fixture lacks a credential step")
                        })
                };
                let verify = position(verification)?;
                let private = position(import_step)?;
                if reordered {
                    steps.swap(verify, private);
                } else {
                    let Yaml::Hash(fields) = &mut steps[verify] else {
                        return Err(Failure::new(
                            "The installer fixture requires a verification step",
                        ));
                    };
                    fields.insert(Yaml::String("if".into()), Yaml::Boolean(false));
                }
                assert!(
                    installer_tools(&changed, name, consumer, verification, import, condition)
                        .is_err(),
                    "{name}: {reordered}"
                );
            }
        }
        Ok(())
    }

    #[test]
    fn installer_builds_refuse_indexed_and_whole_secret_contexts() -> Result<()> {
        for (source, name, consumer, verification, import, condition) in INSTALLER_CASES {
            for expression in ["${{ secrets['PRIVATE'] }}", "${{ toJSON(secrets) }}"] {
                for path in [vec!["jobs", "installer-tool"], vec![]] {
                    let mut changed = workflow(source, &[])?;
                    let environment = workflow(&format!("PRIVATE: {expression}"), &[])?;
                    let Yaml::Hash(fields) = node(&mut changed, &path)? else {
                        return Err(Failure::new("The installer fixture requires a mapping"));
                    };
                    fields.insert(Yaml::String("env".into()), environment);
                    assert!(
                        installer_tools(&changed, name, consumer, verification, import, condition)
                            .is_err(),
                        "{name}: {expression}"
                    );
                }
            }
        }
        Ok(())
    }

    #[test]
    fn installer_verification_precedes_private_app_inputs() -> Result<()> {
        let mut changed = workflow(
            include_str!("../../.github/workflows/native-delivery.yml"),
            DELIVERY,
        )?;
        let Yaml::Array(steps) = node(&mut changed, &["jobs", "signing", "steps"])? else {
            return Err(Failure::new("The delivery fixture requires signing steps"));
        };
        let verification = steps
            .iter()
            .position(|step| step["name"].as_str() == Some("Verify the installer importer source"))
            .ok_or_else(|| Failure::new("The delivery fixture lacks verification"))?;
        let private = steps
            .iter()
            .position(|step| {
                step["name"].as_str() == Some("Install the expected application signing identity")
            })
            .ok_or_else(|| Failure::new("The delivery fixture lacks private app inputs"))?;
        steps.swap(verification, private);
        assert!(
            installer_tools(
                &changed,
                "native-delivery.yml",
                "signing",
                "Verify the installer importer source",
                &[
                    "Install the expected application signing identity",
                    "Install the macOS profile and installer identity"
                ],
                Some("github.run_attempt == 1 && inputs.platform == 'macOS'")
            )
            .is_err()
        );
        Ok(())
    }

    #[test]
    fn detects_secret_contexts_without_matching_properties_or_literals() {
        for expression in [
            "${{ secrets.PRIVATE }}",
            "${{ secrets['PRIVATE'] }}",
            "${{ SECRETS . PRIVATE }}",
            "${{ toJSON(secrets) }}",
            "prefix ${{ join(fromJSON(toJSON(secrets)), ',') }} suffix",
            "${{ format('}} it''s text', secrets.PRIVATE) }}",
            "${{ inputs.value }} ${{ secrets.PRIVATE }}",
        ] {
            assert!(expression_uses_secrets(expression), "{expression}");
        }
        for expression in [
            "",
            "${{",
            "${{ inputs",
            "${{ 'unfinished",
            "Build without secrets.PRIVATE",
            "${{ 'secrets' }}",
            "${{ 'it''s secrets.PRIVATE' }}",
            "${{ inputs.secrets }}",
            "${{ inputs . secrets }}",
            "${{ inputs['secrets'] }}",
            "${{ secrets_extra }}",
            "${{ _secrets }}",
            "${{ secrets-name }}",
            "secrets.PRIVATE ${{ inputs.value }}",
        ] {
            assert!(!expression_uses_secrets(expression), "{expression}");
        }
    }

    #[test]
    fn nested_yaml_secrets_refuse_mixed_collections_and_expression_keys() -> Result<()> {
        for (source, expected) in [
            (
                "root:\n  - true\n  - nested: ${{ secrets.PRIVATE }}\n  - 12",
                true,
            ),
            ("'${{ secrets.PRIVATE }}': public", true),
            ("${{ toJSON(secrets) }}", true),
            ("root:\n  - true\n  - 12\n  - plain", false),
        ] {
            assert_eq!(
                yaml_uses_secrets(&workflow(source, &[])?),
                expected,
                "{source}"
            );
        }
        Ok(())
    }

    #[test]
    fn installer_recipe_requires_the_native_bridge() -> Result<()> {
        let mut host = source_host(
            include_str!("../../.github/workflows/native-delivery.yml"),
            include_str!("../../.github/workflows/native-upload.yml"),
            include_str!("../../mise.toml"),
        );
        host.file(
            "/repo/justfile",
            "build-installer-tool:\n    cargo build --locked -p xtask\n",
        );
        assert!(check(&mut host, Path::new("/repo")).is_err());
        Ok(())
    }

    #[test]
    fn refuses_an_unattested_installer_bridge() -> Result<()> {
        let delivery = include_str!("../../.github/workflows/native-delivery.yml");
        let upload = include_str!("../../.github/workflows/native-upload.yml");
        let pins = include_str!("../../mise.toml");
        let mut changed = workflow(delivery, DELIVERY)?;
        let Yaml::Array(steps) = node(&mut changed, &["jobs", "installer-tool", "steps"])? else {
            return Err(Failure::new("The importer fixture requires steps"));
        };
        let selected = steps
            .iter_mut()
            .find(|step| {
                step["with"]["subject-path"].as_str() == Some("target/debug/installer-import")
            })
            .ok_or_else(|| Failure::new("The importer fixture lacks bridge provenance"))?;
        *node(selected, &["with", "subject-path"])? = Yaml::Null;
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
    fn actual_gate_rejects_mac_export_without_sandbox_preparation() -> Result<()> {
        let delivery = include_str!("../../.github/workflows/native-delivery.yml");
        let upload = include_str!("../../.github/workflows/native-upload.yml");
        let pins = include_str!("../../mise.toml");
        let mut changed = workflow(delivery, DELIVERY)?;
        let step = signing_step(&mut changed, "Sign the preserved Mac app")?;
        *node(step, &["run"])? = Yaml::String(
            r#"mise x -- asc xcode export --archive-path candidate/gymemo.xcarchive --pkg-path signed/gymemo.pkg --method app-store-connect --signing-style manual --team-id "$APPLE_TEAM_ID" --timeout 20m"#.into(),
        );
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
    fn mac_signing_and_packaging_have_independent_limits() -> Result<()> {
        let delivery = include_str!("../../.github/workflows/native-delivery.yml");
        let mut document = workflow(delivery, DELIVERY)?;
        for (name, expected, other) in [
            (
                "Sign the preserved Mac app",
                "codesign --force",
                "productbuild --sign",
            ),
            (
                "Create the signed Mac package",
                "productbuild --sign",
                "codesign --force",
            ),
        ] {
            let stage = signing_step(&mut document, name)?;
            assert_eq!(stage["timeout-minutes"].as_i64(), Some(5), "{name}");
            let run = stage["run"]
                .as_str()
                .ok_or_else(|| Failure::new("The Mac stage requires commands"))?;
            assert!(run.contains(expected), "{name}");
            assert!(!run.contains(other), "{name}");
        }
        Ok(())
    }

    #[test]
    fn mac_signing_rejects_combined_reordered_or_repeated_phases() -> Result<()> {
        let delivery = include_str!("../../.github/workflows/native-delivery.yml");
        let original = workflow(delivery, DELIVERY)?;
        for (name, other) in [
            ("Sign the preserved Mac app", "productbuild --sign"),
            ("Create the signed Mac package", "codesign --force"),
        ] {
            let mut changed = original.clone();
            let stage = signing_step(&mut changed, name)?;
            let run = stage["run"]
                .as_str()
                .ok_or_else(|| Failure::new("The Mac stage requires commands"))?;
            let combined = format!("{run}\n{other} ignored");
            *node(stage, &["run"])? = Yaml::String(combined);
            assert!(mac_sandbox(&changed).is_err(), "{name}");

            let mut changed = original.clone();
            let repeated = signing_step(&mut changed, name)?.clone();
            let Yaml::Array(steps) = node(&mut changed, &["jobs", "signing", "steps"])? else {
                return Err(Failure::new("The signing fixture requires steps"));
            };
            steps.push(repeated);
            assert!(mac_sandbox(&changed).is_err(), "{name}");
        }
        let mut changed = original;
        let Yaml::Array(steps) = node(&mut changed, &["jobs", "signing", "steps"])? else {
            return Err(Failure::new("The signing fixture requires steps"));
        };
        let index = |name| {
            steps
                .iter()
                .position(|step| step["name"].as_str() == Some(name))
                .ok_or_else(|| Failure::new(format!("The signing fixture lacks {name}")))
        };
        let signing = index("Sign the preserved Mac app")?;
        let packaging = index("Create the signed Mac package")?;
        steps.swap(signing, packaging);
        assert!(mac_sandbox(&changed).is_err());
        Ok(())
    }

    #[test]
    fn mac_export_requires_native_packaging() -> Result<()> {
        let delivery = include_str!("../../.github/workflows/native-delivery.yml");
        let mut changed = workflow(delivery, DELIVERY)?;
        let step = signing_step(&mut changed, "Create the signed Mac package")?;
        let run = step["run"]
            .as_str()
            .ok_or_else(|| Failure::new("The export fixture requires commands"))?;
        let missing = run
            .lines()
            .filter(|line| !line.contains("productbuild --sign"))
            .collect::<Vec<_>>()
            .join("\n");
        *node(step, &["run"])? = Yaml::String(missing);
        assert!(mac_sandbox(&changed).is_err());
        Ok(())
    }

    #[test]
    fn mac_export_rejects_an_implicit_installer_identity() -> Result<()> {
        let delivery = include_str!("../../.github/workflows/native-delivery.yml");
        let mut changed = workflow(delivery, DELIVERY)?;
        let step = signing_step(&mut changed, "Create the signed Mac package")?;
        let run = step["run"]
            .as_str()
            .ok_or_else(|| Failure::new("The export fixture requires commands"))?;
        let implicit = run
            .lines()
            .filter(|line| !line.contains("installer_identity"))
            .collect::<Vec<_>>()
            .join("\n");
        *node(step, &["run"])? = Yaml::String(implicit);
        assert!(mac_sandbox(&changed).is_err());
        Ok(())
    }

    #[test]
    fn mac_sandbox_requires_the_qualified_source_and_preserved_app() -> Result<()> {
        let delivery = include_str!("../../.github/workflows/native-delivery.yml");
        let original = workflow(delivery, DELIVERY)?;
        mac_sandbox(&original)?;
        for (name, path, value) in [
            (
                "Read the qualified Mac sandbox configuration",
                vec!["with", "ref"],
                Yaml::String("main".into()),
            ),
            (
                "Read the qualified Mac sandbox configuration",
                vec!["with", "path"],
                Yaml::String("other".into()),
            ),
            (
                "Read the qualified Mac sandbox configuration",
                vec!["with", "sparse-checkout"],
                Yaml::String("Config/Other.entitlements".into()),
            ),
            (
                "Read the qualified Mac sandbox configuration",
                vec!["with", "persist-credentials"],
                Yaml::Boolean(true),
            ),
            (
                "Sign the preserved Mac app",
                vec!["env", "MAC_APP"],
                Yaml::String("other.app".into()),
            ),
            (
                "Sign the preserved Mac app",
                vec!["timeout-minutes"],
                Yaml::Integer(6),
            ),
            (
                "Sign the preserved Mac app",
                vec!["timeout-minutes"],
                Yaml::Null,
            ),
            (
                "Create the signed Mac package",
                vec!["env", "MAC_APP"],
                Yaml::String("other.app".into()),
            ),
            (
                "Create the signed Mac package",
                vec!["timeout-minutes"],
                Yaml::Integer(6),
            ),
            (
                "Create the signed Mac package",
                vec!["timeout-minutes"],
                Yaml::Null,
            ),
        ] {
            let mut changed = original.clone();
            *node(signing_step(&mut changed, name)?, &path)? = value;
            assert!(mac_sandbox(&changed).is_err(), "{name}: {path:?}");
        }
        Ok(())
    }

    #[test]
    fn mac_sandbox_rejects_each_missing_preparation_or_verification() -> Result<()> {
        let delivery = include_str!("../../.github/workflows/native-delivery.yml");
        let original = workflow(delivery, DELIVERY)?;
        for (name, fragment) in [
            ("Sign the preserved Mac app", "set -o pipefail"),
            (
                "Install the macOS profile and installer identity",
                "installer-tool/xtask",
            ),
            ("Sign the preserved Mac app", "TeamIdentifier.0"),
            (
                "Sign the preserved Mac app",
                "Entitlements.com\\.apple\\.application-identifier",
            ),
            (
                "Sign the preserved Mac app",
                "cp qualified-source/Config/Mac.entitlements",
            ),
            (
                "Sign the preserved Mac app",
                "plutil -insert 'com\\.apple\\.application-identifier'",
            ),
            (
                "Sign the preserved Mac app",
                "plutil -insert 'com\\.apple\\.developer\\.team-identifier'",
            ),
            ("Sign the preserved Mac app", "embedded.provisionprofile"),
            ("Create the signed Mac package", "jq -er '.subject'"),
            ("Sign the preserved Mac app", "codesign --force"),
            ("Create the signed Mac package", "productbuild --sign"),
            ("Create the signed Mac package", "set -o pipefail"),
            ("Create the signed Mac package", "pkgutil --check-signature"),
            ("Create the signed Mac package", "shasum -a 256"),
            ("Sign the preserved Mac app", "codesign --verify"),
            ("Verify the signed Mac sandbox", "codesign --verify"),
            ("Verify the signed Mac sandbox", "codesign -d"),
            ("Verify the signed Mac sandbox", "security\\.app-sandbox"),
            (
                "Verify the signed Mac sandbox",
                "user-selected\\.read-write",
            ),
        ] {
            let mut changed = original.clone();
            let step = signing_step(&mut changed, name)?;
            let run = step["run"]
                .as_str()
                .ok_or_else(|| Failure::new("The signing fixture requires commands"))?;
            let weakened = run
                .lines()
                .filter(|line| !line.contains(fragment))
                .collect::<Vec<_>>()
                .join("\n");
            assert_ne!(weakened.lines().count(), run.lines().count(), "{fragment}");
            *node(step, &["run"])? = Yaml::String(weakened);
            assert!(mac_sandbox(&changed).is_err(), "{fragment}");
        }
        for name in [
            "Read the qualified Mac sandbox configuration",
            "Install the macOS profile and installer identity",
            "Sign the preserved Mac app",
            "Create the signed Mac package",
            "Verify the signed Mac sandbox",
        ] {
            let mut changed = original.clone();
            *node(signing_step(&mut changed, name)?, &["name"])? = Yaml::Null;
            assert!(mac_sandbox(&changed).is_err(), "{name}");
        }
        for name in [
            "Install the macOS profile and installer identity",
            "Sign the preserved Mac app",
            "Create the signed Mac package",
            "Verify the signed Mac sandbox",
        ] {
            for (path, value) in [("if", Yaml::Boolean(false)), ("run", Yaml::Null)] {
                let mut changed = original.clone();
                *node(signing_step(&mut changed, name)?, &[path])? = value;
                assert!(mac_sandbox(&changed).is_err(), "{name}: {path}");
            }
        }
        let mut changed = original;
        *node(&mut changed, &["jobs", "signing", "steps"])? = Yaml::Null;
        assert!(mac_sandbox(&changed).is_err());
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
