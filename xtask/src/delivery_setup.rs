//! Prepares scoped delivery credentials for the website and native apps.

use crate::{
    failure::{Context, Failure, Result, ensure},
    host::{Host, Invocation, Streams},
};
use serde_json::{Value, json};
use std::{path::Path, time::Duration};

const REPOSITORY: &str = "P4suta/gymemo";
const REPOSITORY_ID: u64 = 1_453_033_797;
const OWNER_ID: u64 = 42_543_015;
const ACCOUNT_NAME: &str = "gymemo-website-delivery";
const ENVIRONMENT: &str = "website-production";
const ACCOUNTS: &str = "/v3/workplace/service_accounts";
const MEMBERS: &str = "/v3/projects/project/members?project=gymemo";
const IDENTITY_LIMIT: usize = 50;

#[derive(Clone, Copy)]
enum NativePurpose {
    Signing,
    Upload,
    VersionPreparation,
}

impl NativePurpose {
    fn parse(value: &str) -> Result<Self> {
        match value {
            "signing" => Ok(Self::Signing),
            "upload" => Ok(Self::Upload),
            "version-preparation" => Ok(Self::VersionPreparation),
            _ => Err(Failure::new(
                "Native delivery purpose must be signing, upload, or version-preparation",
            )),
        }
    }

    fn config(self) -> &'static str {
        match self {
            Self::Signing => "ci_native_signing",
            Self::Upload => "ci_native_upload",
            Self::VersionPreparation => "ci_version_preparation",
        }
    }

    fn environment(self) -> &'static str {
        match self {
            Self::Signing => "native-signing",
            Self::Upload => "native-upload",
            Self::VersionPreparation => "version-preparation",
        }
    }
}

fn admit_native_environment(value: &Value, branches: &Value, name: &str) -> Result<()> {
    let rules = value["protection_rules"]
        .as_array()
        .ok_or_else(|| Failure::new("GitHub omitted environment protection rules"))?;
    let review = rules
        .iter()
        .find(|rule| rule["type"] == "required_reviewers");
    let review_is_valid = if name == "version-preparation" {
        rules.iter().all(|rule| rule["type"] == "branch_policy")
    } else {
        review.is_some_and(|rule| {
            rule["prevent_self_review"].as_bool() == Some(false)
                && rule["reviewers"].as_array().is_some_and(|reviewers| {
                    reviewers.len() == 1
                        && reviewers[0]["type"] == "User"
                        && reviewers[0]["reviewer"]["id"].as_u64() == Some(OWNER_ID)
                })
        })
    };
    ensure(
        value["name"].as_str() == Some(name)
            && value["can_admins_bypass"].as_bool() == Some(false)
            && value["deployment_branch_policy"]
                == json!({"protected_branches":false,"custom_branch_policies":true})
            && review_is_valid
            && branches["branch_policies"]
                .as_array()
                .is_some_and(|policies| {
                    policies.len() == 1
                        && policies[0]["name"] == "main"
                        && policies[0]["type"] == "branch"
                }),
        || {
            "Native credentials require main, no administrator bypass, and purpose-specific review protection".into()
        },
    )
}

fn set_sync_state(host: &mut impl Host, root: &Path, environment: &str, state: &str) -> Result<()> {
    captured(
        host,
        root,
        Invocation::new("gh").args([
            "variable",
            "set",
            "DOPPLER_SYNC_ID",
            "--repo",
            REPOSITORY,
            "--env",
            environment,
            "--body",
            state,
        ]),
    )?;
    let value = gh(
        host,
        root,
        &format!("repos/{REPOSITORY}/environments/{environment}/variables/DOPPLER_SYNC_ID"),
    )?;
    ensure(value["value"].as_str() == Some(state), || {
        "GitHub didn't preserve the native sync state; inspect the environment before retrying"
            .into()
    })
}

fn admit_sync(value: &Value, config: &str, integration: &str) -> Result<String> {
    let value = &value["sync"];
    ensure(
        value["project"] == "gymemo"
            && value["config"] == config
            && value["integration"] == integration,
        || {
            "Doppler acknowledged a different native sync; inspect provider state before retrying"
                .into()
        },
    )?;
    identifier(value, "slug")
}

pub fn run_native(host: &mut impl Host, root: &Path, arguments: &[String]) -> Result<()> {
    ensure(arguments.len() == 3 || arguments.len() == 4, || {
        "setup-native-delivery requires WORKPLACE INTEGRATION signing|upload|version-preparation and optional --apply"
            .into()
    })?;
    let purpose = NativePurpose::parse(&arguments[2])?;
    let apply = match arguments.get(3).map(String::as_str) {
        None => false,
        Some("--apply") => true,
        Some(_) => {
            return Err(Failure::new(
                "Native delivery accepts only --apply after the purpose",
            ));
        }
    };
    let connection = identifier(&json!({"slug":arguments[1]}), "slug")?;
    repository_scope(
        &gh(host, root, "repos/P4suta/gymemo")?,
        &gh(
            host,
            root,
            "repos/P4suta/gymemo/actions/oidc/customization/sub",
        )?,
    )?;
    let api = Doppler::open(host, root)?;
    configure_native(host, root, &arguments[0], &connection, purpose, apply, &api)
}

fn configure_native(
    host: &mut impl Host,
    root: &Path,
    workplace: &str,
    connection: &str,
    purpose: NativePurpose,
    apply: bool,
    api: &Doppler,
) -> Result<()> {
    let actual = api.request("/v3/workplace", None)?;
    ensure(
        actual["workplace"]["id"].as_str() == Some(workplace),
        || "The authenticated Doppler workplace differs from the selected workplace".into(),
    )?;
    let config = purpose.config();
    let environment = purpose.environment();
    let selected = api.request(
        &format!("/v3/configs/config?project=gymemo&config={config}"),
        None,
    )?;
    ensure(
        selected["config"]["project"] == "gymemo"
            && selected["config"]["environment"] == config
            && selected["config"]["name"] == config
            && selected["config"]["root"] == true,
        || "Native delivery requires the purpose-specific root config".into(),
    )?;
    let integration = api.request(
        &format!("/v3/integrations/integration?integration={connection}"),
        None,
    )?;
    ensure(
        integration["integration"]["slug"] == connection
            && integration["integration"]["type"] == "github-actions",
        || "The selected integration isn't the expected GitHub connection".into(),
    )?;
    github_destination(&api.request(
        &format!("/v3/integrations/integration/options?integration={connection}"),
        None,
    )?)?;
    let base = format!("repos/{REPOSITORY}/environments/{environment}");
    admit_native_environment(
        &gh(host, root, &base)?,
        &gh(host, root, &format!("{base}/deployment-branch-policies"))?,
        environment,
    )?;
    let variables = gh(host, root, &format!("{base}/variables?per_page=100"))?;
    let entries = variables["variables"]
        .as_array()
        .ok_or_else(|| Failure::new("GitHub omitted native environment variables"))?;
    ensure(
        variables["total_count"].as_u64() == Some(entries.len() as u64),
        || "Native environment variables exceed the checked page".into(),
    )?;
    let states = entries
        .iter()
        .filter(|value| value["name"] == "DOPPLER_SYNC_ID")
        .collect::<Vec<_>>();
    let existing = match states.as_slice() {
        [] => None,
        [value] => {
            ensure(value["value"] != "pending", || {
                "Native sync creation has an unresolved outcome; inspect Doppler before retrying"
                    .into()
            })?;
            Some(identifier(&json!({"slug":value["value"]}), "slug")?)
        }
        _ => return Err(Failure::new("GitHub returned duplicate native sync states")),
    };
    if let Some(slug) = existing {
        let observed = api.request(
            &format!("/v3/configs/config/syncs/sync?project=gymemo&config={config}&sync={slug}"),
            None,
        )?;
        ensure(admit_sync(&observed, config, connection)? == slug, || {
            "Doppler returned a different sync identifier".into()
        })?;
        host.print(&format!(
            "Verified existing native sync {slug}; no remote changes"
        ));
        return Ok(());
    }
    let secrets = gh(host, root, &format!("{base}/secrets?per_page=100"))?;
    ensure(
        secrets["total_count"] == 0 && secrets["secrets"] == json!([]),
        || {
            "The native environment already has credential copies without a recorded Doppler sync"
                .into()
        },
    )?;
    host.print(&format!("Plan: sync gymemo/{config} through {connection} to {REPOSITORY}:{environment}; don't import existing secrets or expose values as variables"));
    if !apply {
        return Ok(());
    }
    set_sync_state(host, root, environment, "pending")?;
    let created = api.request(&format!("/v3/configs/config/syncs?project=gymemo&config={config}"), Some(&json!({
        "integration":connection,"import_option":"none","await_initial_sync":true,
        "data":{"feature":"actions","sync_target":"repo","repo_name":"gymemo","environment_name":environment,"sync_unmasked_as_variables":false}
    })))?;
    let slug = admit_sync(&created, config, connection)?;
    host.print(&format!(
        "Created Doppler sync {slug}; checking its stored identity"
    ));
    let observed = api.request(
        &format!("/v3/configs/config/syncs/sync?project=gymemo&config={config}&sync={slug}"),
        None,
    )?;
    ensure(admit_sync(&observed, config, connection)? == slug, || {
        "Doppler returned a different sync identifier".into()
    })?;
    set_sync_state(host, root, environment, &slug)?;
    host.print(&format!("Configured gymemo/{config} sync {slug} to {environment}; credential use still requires its read-only workflow check"));
    Ok(())
}

fn repository_scope(repository: &Value, subject: &Value) -> Result<String> {
    ensure(
        repository["id"].as_u64() == Some(REPOSITORY_ID)
            && repository["full_name"].as_str() == Some(REPOSITORY)
            && repository["owner"]["id"].as_u64() == Some(OWNER_ID)
            && repository["default_branch"].as_str() == Some("main")
            && repository["private"].as_bool() == Some(false),
        || "Delivery setup requires the public P4suta/gymemo repository and its main branch".into(),
    )?;
    let prefix = format!("repo:P4suta@{OWNER_ID}/gymemo@{REPOSITORY_ID}");
    ensure(
        subject["use_default"].as_bool() == Some(true)
            && subject["use_immutable_subject"].as_bool() == Some(true)
            && subject["sub_claim_prefix"].as_str() == Some(&prefix),
        || {
            "GitHub's immutable OIDC subject differs; inspect the identity policy before changing it".into()
        },
    )?;
    Ok(prefix)
}

fn identifier(value: &Value, name: &str) -> Result<String> {
    let text = value[name]
        .as_str()
        .ok_or_else(|| Failure::new(format!("Missing {name} metadata")))?;
    ensure(
        !text.is_empty()
            && text.len() <= 128
            && text
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || b"_-".contains(&byte)),
        || format!("Invalid {name} metadata"),
    )?;
    Ok(text.to_owned())
}

fn identity_payload(prefix: &str) -> Value {
    json!({
        "name":"GitHub Actions",
        "method":"oidc",
        "ttl_seconds":600,
        "config":{
            "discovery_url":"https://token.actions.githubusercontent.com",
            "claims_type":"exact",
            "claims":{
                "aud":["https://github.com/P4suta"],
                "sub":[format!("{prefix}:environment:{ENVIRONMENT}")],
                "repository_id":[REPOSITORY_ID.to_string()],
                "repository_owner_id":[OWNER_ID.to_string()],
                "workflow_ref":[
                    "P4suta/gymemo/.github/workflows/website.yml@refs/heads/main",
                    "P4suta/gymemo/.github/workflows/credentials.yml@refs/heads/main"
                ],
                "ref":["refs/heads/main"],
                "event_name":["workflow_dispatch"]
            }
        }
    })
}

fn admit_identity(identity: &Value, expected: &Value) -> Result<()> {
    for key in ["name", "method", "config", "ttl_seconds"] {
        ensure(identity.get(key) == expected.get(key), || {
            format!(
                "The existing Doppler identity differs at {key}; no identity policy was overwritten"
            )
        })?;
    }
    Ok(())
}

fn admit_member(member: &Value, slug: &str) -> Result<()> {
    ensure(member["slug"].as_str() == Some(slug), || {
        "Doppler returned a different project member".into()
    })?;
    let roles = member["roles"]
        .as_array()
        .ok_or_else(|| Failure::new("Doppler omitted the member's complete role assignments"))?;
    let [role] = roles.as_slice() else {
        return Err(Failure::new(
            "The website account must have exactly one project role",
        ));
    };
    ensure(
        role["role"]["identifier"].as_str() == Some("viewer")
            && role["access_all_environments"].as_bool() == Some(false)
            && role["environments"] == json!(["ci_website"]),
        || "The website account must read only the ci_website environment".into(),
    )
}

fn capacity(current: usize, creating: bool) -> Result<()> {
    ensure(
        current <= IDENTITY_LIMIT && (!creating || current < IDENTITY_LIMIT),
        || {
            format!(
                "Doppler's {IDENTITY_LIMIT}-identity limit leaves no room for the website account"
            )
        },
    )
}

fn captured(host: &mut impl Host, root: &Path, invocation: Invocation) -> Result<String> {
    let output = host
        .run(&invocation.current_dir(root), Streams::Captured)
        .context(|| "Start delivery setup metadata lookup".into())?;
    ensure(output.status.success(), || {
        "Delivery setup command failed; response withheld; inspect provider state before retrying"
            .into()
    })?;
    String::from_utf8(output.stdout)
        .map_err(|_| Failure::new("Delivery setup response isn't UTF-8; response withheld"))
}

fn gh(host: &mut impl Host, root: &Path, path: &str) -> Result<Value> {
    serde_json::from_str(&captured(
        host,
        root,
        Invocation::new("gh").args(["api", path]),
    )?)
    .map_err(|_| Failure::new("GitHub returned invalid metadata; response withheld"))
}

struct Doppler {
    agent: ureq::Agent,
    credential: String,
    origin: String,
}

impl Doppler {
    fn open(host: &mut impl Host, root: &Path) -> Result<Self> {
        let credential = captured(
            host,
            root,
            Invocation::new("doppler")
                .args([
                    "configure",
                    "get",
                    "token",
                    "--plain",
                    "--no-read-env",
                    "--no-check-version",
                    "--scope",
                ])
                .arg(root),
        )?;
        let credential = credential.trim().to_owned();
        ensure(
            credential.starts_with("dp.")
                && credential
                    .bytes()
                    .all(|byte| byte.is_ascii_alphanumeric() || b"._-".contains(&byte)),
            || "Unexpected Doppler authentication format; value withheld".into(),
        )?;
        Ok(Self {
            agent: ureq::Agent::config_builder()
                .timeout_global(Some(Duration::from_secs(20)))
                .max_redirects(0)
                .http_status_as_error(false)
                .build()
                .into(),
            credential,
            origin: "https://api.doppler.com".into(),
        })
    }

    fn request(&self, path: &str, body: Option<&Value>) -> Result<Value> {
        let url = format!("{}{path}", self.origin);
        let authorization = format!("Bearer {}", self.credential);
        let response = match body {
            None => self
                .agent
                .get(&url)
                .header("Authorization", &authorization)
                .call(),
            Some(body) => self
                .agent
                .post(&url)
                .header("Authorization", &authorization)
                .send_json(body),
        };
        let mut response = response.map_err(|_| {
            Failure::new(format!("Doppler transport failed at {path}; body withheld; inspect provider state before retrying"))
        })?;
        ensure(response.status().is_success(), || {
            format!(
                "Doppler returned HTTP {} at {path}; body withheld",
                response.status()
            )
        })?;
        let value: Value = response
            .body_mut()
            .with_config()
            .limit(2 * 1024 * 1024)
            .read_json()
            .map_err(|_| Failure::new("Doppler returned invalid metadata; body withheld"))?;
        ensure(value["success"].as_bool() != Some(false), || {
            "Doppler rejected delivery setup; body withheld".into()
        })?;
        Ok(value)
    }

    fn list(&self, path: &str, key: &str) -> Result<Vec<Value>> {
        let separator = if path.contains('?') { '&' } else { '?' };
        let mut rows = Vec::new();
        for page in 1..=10 {
            let response =
                self.request(&format!("{path}{separator}page={page}&per_page=100"), None)?;
            let values = response[key]
                .as_array()
                .ok_or_else(|| Failure::new(format!("Doppler omitted {key} metadata")))?;
            rows.extend(values.iter().cloned());
            if values.len() < 100 {
                return Ok(rows);
            }
        }
        Err(Failure::new(
            "Doppler metadata exceeded the pagination limit",
        ))
    }
}

fn account_path(account: &Value) -> Result<String> {
    Ok(format!(
        "{ACCOUNTS}/service_account/{}",
        identifier(account, "slug")?
    ))
}

fn admit_account(account: &Value) -> Result<()> {
    ensure(
        account["name"].as_str() == Some(ACCOUNT_NAME)
            && account["workplace_role"]["identifier"].as_str() == Some("no_access"),
        || "The website service account has unexpected workplace access".into(),
    )
}

pub fn inspect(host: &mut impl Host, root: &Path, workplace: &str) -> Result<()> {
    let api = Doppler::open(host, root)?;
    inspect_integrations(host, workplace, &api)
}

fn inspect_integrations(host: &mut impl Host, workplace: &str, api: &Doppler) -> Result<()> {
    let actual = api.request("/v3/workplace", None)?;
    ensure(
        actual["workplace"]["id"].as_str() == Some(workplace),
        || "The authenticated Doppler workplace differs from the selected workplace".into(),
    )?;
    let response = api.request("/v3/integrations", None)?;
    let integrations = response["integrations"]
        .as_array()
        .ok_or_else(|| Failure::new("Doppler omitted the integration metadata"))?;
    for integration in integrations {
        let slug = identifier(integration, "slug")?;
        let name = integration["name"].as_str().unwrap_or("unnamed");
        let kind = integration["type"].as_str().unwrap_or("unspecified");
        host.print(&format!("Integration {slug}: {name}; type {kind}"));
        if kind == "github-actions" {
            let options = api.request(
                &format!("/v3/integrations/integration/options?integration={slug}"),
                None,
            )?;
            let name = github_destination(&options)?;
            host.print(&format!(
                "Integration {slug} can sync Actions secrets to P4suta/{name} ({REPOSITORY_ID})"
            ));
        }
    }
    host.print(&format!(
        "Inspected {} integration connection(s); no remote changes",
        integrations.len()
    ));
    Ok(())
}

fn github_destination(value: &Value) -> Result<String> {
    let repositories = value["options"]["repos"]["P4suta"]
        .as_array()
        .ok_or_else(|| Failure::new("Doppler omitted GitHub repository options"))?;
    let matching = repositories
        .iter()
        .filter(|repository| repository["id"].as_u64() == Some(REPOSITORY_ID))
        .collect::<Vec<_>>();
    let [repository] = matching.as_slice() else {
        return Err(Failure::new(
            "Doppler's GitHub options must include the unique Gymemo repository; inspect integration access or pagination",
        ));
    };
    ensure(
        repository["name"].as_str() == Some("gymemo")
            && repository["owner"]["id"].as_u64() == Some(OWNER_ID)
            && repository["owner"]["login"].as_str() == Some("P4suta")
            && repository["archived"].as_bool() == Some(false),
        || "Doppler's GitHub destination has a different owner, name, or archive state".into(),
    )?;
    Ok("gymemo".into())
}

pub fn run(host: &mut impl Host, root: &Path, workplace: &str, apply: bool) -> Result<()> {
    let repository = gh(host, root, "repos/P4suta/gymemo")?;
    let subject = gh(
        host,
        root,
        "repos/P4suta/gymemo/actions/oidc/customization/sub",
    )?;
    let prefix = repository_scope(&repository, &subject)?;
    let api = Doppler::open(host, root)?;
    configure(host, root, workplace, apply, &prefix, &api)
}

fn configure(
    host: &mut impl Host,
    root: &Path,
    workplace: &str,
    apply: bool,
    prefix: &str,
    api: &Doppler,
) -> Result<()> {
    let actual = api.request("/v3/workplace", None)?;
    ensure(
        actual["workplace"]["id"].as_str() == Some(workplace),
        || "The authenticated Doppler workplace differs from the selected workplace".into(),
    )?;
    let accounts = api.list(ACCOUNTS, "service_accounts")?;
    let matches = accounts
        .iter()
        .filter(|account| account["name"].as_str() == Some(ACCOUNT_NAME))
        .collect::<Vec<_>>();
    ensure(matches.len() <= 1, || {
        "Duplicate website service accounts require inspection".into()
    })?;
    let expected = identity_payload(prefix);
    let mut count = 0;
    let mut existing = Vec::new();
    for account in &accounts {
        let identities = api.list(
            &format!("{}/identities", account_path(account)?),
            "identities",
        )?;
        count += identities.len();
        if account["name"].as_str() == Some(ACCOUNT_NAME) {
            admit_account(account)?;
            existing = identities;
        }
    }
    ensure(existing.len() <= 1, || {
        "The website account has extra identities".into()
    })?;
    if let Some(identity) = existing.first() {
        admit_identity(identity, &expected)?;
    }
    capacity(count, existing.is_empty())?;
    host.print(&format!(
        "Doppler identities: {count}/{IDENTITY_LIMIT}; website identity required: {}",
        existing.is_empty()
    ));
    if !apply {
        host.print("Plan: give gymemo-website-delivery read-only access to gymemo/ci_website, bind main and the two website workflows, and configure the website-production environment variable.");
        return Ok(());
    }
    let account = match matches.first() {
        Some(account) => (*account).clone(),
        None => api.request(
            ACCOUNTS,
            Some(&json!({"name":ACCOUNT_NAME,"workplace_role":{"identifier":"no_access"}})),
        )?["service_account"]
            .clone(),
    };
    admit_account(&account)?;
    let slug = identifier(&account, "slug")?;
    let members = api.list(MEMBERS, "members")?;
    if !members
        .iter()
        .any(|member| member["slug"].as_str() == Some(&slug))
    {
        api.request(MEMBERS, Some(&json!({"type":"service_account","slug":slug,"role":"viewer","environments":["ci_website"]})))?;
    }
    let member = api.request(
        &format!("/v3/projects/project/members/member/service_account/{slug}?project=gymemo"),
        None,
    )?;
    admit_member(&member["member"], &slug)?;
    if existing.is_empty() {
        api.request(
            &format!("{}/identities", account_path(&account)?),
            Some(&expected),
        )?;
    }
    let identities = api.list(
        &format!("{}/identities", account_path(&account)?),
        "identities",
    )?;
    let [identity] = identities.as_slice() else {
        return Err(Failure::new(
            "Doppler didn't preserve exactly one website identity",
        ));
    };
    admit_identity(identity, &expected)?;
    let identity_id = identifier(identity, "slug")?;
    captured(
        host,
        root,
        Invocation::new("gh").args([
            "variable",
            "set",
            "DOPPLER_IDENTITY_ID",
            "--repo",
            REPOSITORY,
            "--env",
            ENVIRONMENT,
            "--body",
            &identity_id,
        ]),
    )?;
    let variable = gh(
        host,
        root,
        "repos/P4suta/gymemo/environments/website-production/variables/DOPPLER_IDENTITY_ID",
    )?;
    ensure(variable["value"].as_str() == Some(&identity_id), || {
        "GitHub didn't preserve the Doppler identity variable".into()
    })?;
    host.print("Configured the website workload identity and verified its metadata; live workflow authentication remains a separate check.");
    Ok(())
}

#[cfg(test)]
mod protocol_tests;

#[cfg(test)]
mod tests {
    use super::*;

    fn repository() -> Value {
        json!({"id":REPOSITORY_ID,"full_name":REPOSITORY,"owner":{"id":OWNER_ID},"default_branch":"main","private":false})
    }

    fn subject() -> Value {
        json!({"use_default":true,"use_immutable_subject":true,"sub_claim_prefix":"repo:P4suta@42543015/gymemo@1453033797"})
    }

    #[test]
    fn the_identity_binds_the_actual_public_repository_and_immutable_subject() -> Result<()> {
        assert_eq!(
            repository_scope(&repository(), &subject())?,
            "repo:P4suta@42543015/gymemo@1453033797"
        );
        Ok(())
    }

    #[test]
    fn changed_repository_owner_branch_or_subject_is_refused() {
        for (path, value) in [
            ("/id", json!(REPOSITORY_ID + 1)),
            ("/full_name", json!("another/gymemo")),
            ("/owner/id", json!(OWNER_ID + 1)),
            ("/default_branch", json!("another")),
            ("/private", json!(true)),
        ] {
            let mut changed = repository();
            *changed.pointer_mut(path).expect("fixture field") = value;
            assert!(repository_scope(&changed, &subject()).is_err(), "{path}");
        }
        for (key, value) in [
            ("use_default", json!(false)),
            ("use_immutable_subject", json!(false)),
            ("sub_claim_prefix", json!("repo:P4suta/another")),
        ] {
            let mut changed = subject();
            changed[key] = value;
            assert!(repository_scope(&repository(), &changed).is_err(), "{key}");
        }
        assert!(repository_scope(&Value::Null, &subject()).is_err());
        assert!(repository_scope(&repository(), &Value::Null).is_err());
    }
}
