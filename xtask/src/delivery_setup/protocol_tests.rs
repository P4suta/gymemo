use super::*;
use crate::host::fake::{FakeHost, Fault};
use mockito::{Matcher, Mock, Server};

const PREFIX: &str = "repo:P4suta@42543015/gymemo@1453033797";
const TOKEN: &str = "dp.ct.fixture";
const SLUG: &str = "00000000-0000-0000-0000-000000000001";
const IDENTITY: &str = "00000000-0000-0000-0000-000000000002";

fn client(server: &mockito::ServerGuard) -> Doppler {
    Doppler {
        agent: ureq::Agent::config_builder()
            .timeout_global(Some(Duration::from_secs(3)))
            .max_redirects(0)
            .http_status_as_error(false)
            .build()
            .into(),
        credential: TOKEN.into(),
        origin: server.url(),
    }
}

fn reply(server: &mut mockito::ServerGuard, method: &str, path: &str, body: Value) -> Mock {
    server
        .mock(method, path)
        .match_header("authorization", format!("Bearer {TOKEN}").as_str())
        .with_header("content-type", "application/json")
        .with_body(body.to_string())
        .expect(1)
        .create()
}

fn account() -> Value {
    json!({"name":ACCOUNT_NAME,"slug":SLUG,"workplace_role":{"identifier":"no_access"}})
}

fn member() -> Value {
    json!({"slug":SLUG,"roles":[{"role":{"identifier":"viewer"},"access_all_environments":false,"environments":["ci_website"]}]})
}

fn identity() -> Value {
    json!({
        "slug":IDENTITY,
        "name":"GitHub Actions",
        "method":"oidc",
        "ttl_seconds":600,
        "config":{
            "discovery_url":"https://token.actions.githubusercontent.com",
            "claims_type":"exact",
            "claims":{
                "aud":["https://github.com/P4suta"],
                "sub":["repo:P4suta@42543015/gymemo@1453033797:environment:website-production"],
                "repository_id":["1453033797"],
                "repository_owner_id":["42543015"],
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

fn variable_host() -> FakeHost {
    let mut host = FakeHost::new();
    host.prints(
        "website-production/variables/DOPPLER_IDENTITY_ID",
        &json!({"name":"DOPPLER_IDENTITY_ID","value":IDENTITY}).to_string(),
    );
    host
}

#[test]
fn provider_get_and_post_use_private_headers_and_checked_json() -> Result<()> {
    let mut server = Server::new();
    let get = reply(&mut server, "GET", "/metadata", json!({"count":1}));
    let post = server
        .mock("POST", "/metadata")
        .match_header("authorization", format!("Bearer {TOKEN}").as_str())
        .match_header("content-type", "application/json; charset=utf-8")
        .match_body(Matcher::Json(json!({"selected":"one"})))
        .with_body(r#"{"accepted":true}"#)
        .expect(1)
        .create();
    let api = client(&server);
    let first = api.request("/metadata", None);
    get.assert();
    assert_eq!(first?, json!({"count":1}));
    let second = api.request("/metadata", Some(&json!({"selected":"one"})));
    post.assert();
    assert_eq!(second?, json!({"accepted":true}));
    Ok(())
}

#[test]
fn provider_metadata_accepts_large_pages_and_refuses_oversized_bodies() -> Result<()> {
    let mut server = Server::new();
    let large = reply(
        &mut server,
        "GET",
        "/large",
        json!({"padding":"x".repeat(1_500_000)}),
    );
    let result = client(&server).request("/large", None)?;
    assert_eq!(result["padding"].as_str().unwrap().len(), 1_500_000);
    large.assert();
    let oversized = reply(
        &mut server,
        "GET",
        "/oversized",
        json!({"private":"do-not-print","padding":"x".repeat(2_100_000)}),
    );
    let failure = client(&server)
        .request("/oversized", None)
        .expect_err("metadata above the two-mebibyte limit");
    assert!(
        failure
            .to_string()
            .contains("invalid metadata; body withheld")
    );
    assert!(!failure.to_string().contains("do-not-print"));
    oversized.assert();
    Ok(())
}

#[test]
fn public_setup_commands_reach_private_authentication_before_provider_access() {
    let prepare = || {
        let mut host = FakeHost::new();
        host.prints("\"repos/P4suta/gymemo\"", &json!({"id":1453033797,"full_name":"P4suta/gymemo","owner":{"id":42543015},"default_branch":"main","private":false}).to_string());
        host.prints(
            "actions/oidc/customization/sub",
            &json!({"use_default":true,"use_immutable_subject":true,"sub_claim_prefix":PREFIX})
                .to_string(),
        );
        host.prints("\"doppler\"", "");
        host
    };
    for apply in [false, true] {
        let mut host = prepare();
        let failure = run(&mut host, Path::new("/repo"), "selected", apply)
            .expect_err("missing private authentication");
        assert!(
            failure
                .to_string()
                .contains("Unexpected Doppler authentication format")
        );
        assert_eq!(host.transcript().len(), 3);
        assert!(host.transcript().last().unwrap().contains("\"doppler\""));
        for purpose in ["signing", "upload", "version-preparation"] {
            let mut host = prepare();
            let mut arguments = vec!["selected".into(), "connection-1".into(), purpose.into()];
            if apply {
                arguments.push("--apply".into());
            }
            let failure = run_native(&mut host, Path::new("/repo"), &arguments)
                .expect_err("missing private authentication");
            assert!(
                failure
                    .to_string()
                    .contains("Unexpected Doppler authentication format")
            );
            assert_eq!(host.transcript().len(), 3);
        }
    }
    let mut host = prepare();
    let failure = inspect(&mut host, Path::new("/repo"), "selected")
        .expect_err("missing private authentication");
    assert!(
        failure
            .to_string()
            .contains("Unexpected Doppler authentication format")
    );
    assert_eq!(host.transcript().len(), 1);
}

#[test]
fn sync_acknowledgements_require_the_exact_project_config_and_connection() -> Result<()> {
    for purpose in [
        NativePurpose::Signing,
        NativePurpose::Upload,
        NativePurpose::VersionPreparation,
    ] {
        let valid = sync_reply(purpose);
        assert_eq!(admit_sync(&valid, purpose.config(), "connection-1")?, SLUG);
        for field in ["project", "config", "integration"] {
            let mut invalid = valid.clone();
            invalid["sync"][field] = json!("another");
            let failure = admit_sync(&invalid, purpose.config(), "connection-1")
                .expect_err("a different sync destination");
            assert!(
                failure
                    .to_string()
                    .contains("acknowledged a different native sync"),
                "{field}"
            );
        }
        for slug in [Value::Null, json!(""), json!("../sync"), json!("bad value")] {
            let mut invalid = valid.clone();
            invalid["sync"]["slug"] = slug;
            assert!(admit_sync(&invalid, purpose.config(), "connection-1").is_err());
        }
    }
    Ok(())
}

#[test]
fn a_full_identity_quota_stops_before_creating_a_website_account() {
    let mut server = Server::new();
    let workplace = reply(
        &mut server,
        "GET",
        "/v3/workplace",
        json!({"workplace":{"id":"selected"}}),
    );
    let accounts = reply(
        &mut server,
        "GET",
        "/v3/workplace/service_accounts?page=1&per_page=100",
        json!({"service_accounts":[{"slug":"other-one","name":"another"},{"slug":"other-two","name":"another"}]}),
    );
    let first = reply(
        &mut server,
        "GET",
        "/v3/workplace/service_accounts/service_account/other-one/identities?page=1&per_page=100",
        json!({"identities":vec![identity();25]}),
    );
    let second = reply(
        &mut server,
        "GET",
        "/v3/workplace/service_accounts/service_account/other-two/identities?page=1&per_page=100",
        json!({"identities":vec![identity();25]}),
    );
    let post = server.mock("POST", Matcher::Any).expect(0).create();
    let mut host = FakeHost::new();
    let failure = configure(
        &mut host,
        Path::new("/repo"),
        "selected",
        true,
        PREFIX,
        &client(&server),
    )
    .expect_err("the occupied identity quota");
    assert!(
        failure
            .to_string()
            .contains("50-identity limit leaves no room")
    );
    assert!(host.transcript().is_empty());
    for request in [workplace, accounts, first, second, post] {
        request.assert();
    }
}

#[test]
fn errors_rejections_invalid_json_and_redirects_fail_without_response_bodies() {
    for (status, body) in [
        (403, r#"{"private":"do-not-print"}"#),
        (500, r#"{"private":"do-not-print"}"#),
        (200, r#"{"success":false,"private":"do-not-print"}"#),
        (200, "do-not-print"),
        (302, "do-not-print"),
    ] {
        let mut server = Server::new();
        let mock = server
            .mock("POST", "/metadata")
            .with_status(status)
            .with_header("location", "/redirected")
            .with_body(body)
            .expect(1)
            .create();
        let redirected = server.mock("POST", "/redirected").expect(0).create();
        let error = client(&server)
            .request("/metadata", Some(&json!({"name":"one"})))
            .expect_err("a failed or ambiguous provider operation");
        assert!(!error.to_string().contains("do-not-print"));
        mock.assert();
        redirected.assert();
    }
}

#[test]
fn pagination_reads_every_page_and_refuses_missing_or_unbounded_metadata() -> Result<()> {
    let mut server = Server::new();
    let first = reply(
        &mut server,
        "GET",
        "/rows?page=1&per_page=100",
        json!({"rows":vec![json!(1);100]}),
    );
    let last = reply(
        &mut server,
        "GET",
        "/rows?page=2&per_page=100",
        json!({"rows":[2]}),
    );
    let rows = client(&server).list("/rows", "rows")?;
    assert_eq!(rows.len(), 101);
    assert_eq!(rows.last(), Some(&json!(2)));
    first.assert();
    last.assert();

    let missing = reply(
        &mut server,
        "GET",
        "/missing?page=1&per_page=100",
        Value::Null,
    );
    assert!(client(&server).list("/missing", "rows").is_err());
    missing.assert();
    let repeated = server
        .mock(
            "GET",
            Matcher::Regex(r"^/bounded\?selected=one&page=\d+&per_page=100$".into()),
        )
        .with_body(json!({"rows":vec![json!(1);100]}).to_string())
        .expect(10)
        .create();
    assert!(
        client(&server)
            .list("/bounded?selected=one", "rows")
            .is_err()
    );
    repeated.assert();
    Ok(())
}

#[test]
fn private_cli_authentication_is_not_an_argument_and_failures_are_redacted() -> Result<()> {
    let mut host = FakeHost::new();
    host.prints("\"doppler\"", &format!("  {TOKEN}\n"));
    let api = Doppler::open(&mut host, Path::new("/repo"))?;
    assert_eq!(api.credential, TOKEN);
    assert_eq!(api.origin, "https://api.doppler.com");
    assert_eq!(api.agent.config().max_redirects(), 0);
    assert_eq!(
        api.agent.config().timeouts().global,
        Some(Duration::from_secs(20))
    );
    assert!(!api.agent.config().http_status_as_error());
    assert!(host.transcript().iter().all(|line| !line.contains(TOKEN)));
    for value in ["", "wrong-format", "dp.ct.a\nprivate"] {
        host.prints("\"doppler\"", value);
        assert!(Doppler::open(&mut host, Path::new("/repo")).is_err());
    }
    for fault in [
        Fault::Missing,
        Fault::Garbled,
        Fault::Exit(1, "do-not-print"),
    ] {
        let mut host = FakeHost::new();
        host.fail("\"doppler\"", fault);
        assert!(Doppler::open(&mut host, Path::new("/repo")).is_err());
        assert!(host.output.is_empty());
        assert!(host.errors.is_empty());
    }
    Ok(())
}

#[test]
fn missing_or_changed_roles_identifiers_and_capacity_are_refused() -> Result<()> {
    admit_member(&member(), SLUG)?;
    admit_account(&account())?;
    assert_eq!(identifier(&account(), "slug")?, SLUG);
    for value in [Value::Null, json!({"roles":[]}), json!({"roles":[{},{}]})] {
        assert!(admit_member(&value, SLUG).is_err());
    }
    for (path, value) in [
        ("/roles/0/role/identifier", json!("collaborator")),
        ("/roles/0/access_all_environments", json!(true)),
        ("/roles/0/environments", json!(["ci_website", "prd"])),
        ("/slug", json!("another-account")),
    ] {
        let mut changed = member();
        *changed.pointer_mut(path).expect("fixture field") = value;
        assert!(admit_member(&changed, SLUG).is_err(), "{path}");
    }
    for value in [
        "",
        "../another",
        "with space",
        "bad?query",
        &"a".repeat(129),
    ] {
        assert!(identifier(&json!({"slug":value}), "slug").is_err());
    }
    assert!(identifier(&Value::Null, "slug").is_err());
    for value in ["a".repeat(128), "valid_identifier-1".into()] {
        assert_eq!(identifier(&json!({"slug":value}), "slug")?, value);
    }
    for account in [
        Value::Null,
        json!({"name":ACCOUNT_NAME,"workplace_role":{"identifier":"admin"}}),
        json!({"name":"another-account","workplace_role":{"identifier":"no_access"}}),
    ] {
        assert!(admit_account(&account).is_err());
    }
    capacity(49, true)?;
    capacity(50, false)?;
    assert!(capacity(50, true).is_err());
    assert!(capacity(51, false).is_err());
    for key in ["name", "method", "config", "ttl_seconds"] {
        let mut changed = identity();
        changed[key] = Value::Null;
        assert!(admit_identity(&changed, &identity_payload(PREFIX)).is_err());
    }
    Ok(())
}

#[test]
fn preview_reads_metadata_and_performs_no_remote_write() -> Result<()> {
    let mut server = Server::new();
    let workplace = reply(
        &mut server,
        "GET",
        "/v3/workplace",
        json!({"workplace":{"id":"selected"}}),
    );
    let accounts = reply(
        &mut server,
        "GET",
        &format!("{ACCOUNTS}?page=1&per_page=100"),
        json!({"service_accounts":[]}),
    );
    let post = server.mock("POST", Matcher::Any).expect(0).create();
    let mut host = FakeHost::new();
    configure(
        &mut host,
        Path::new("/repo"),
        "selected",
        false,
        PREFIX,
        &client(&server),
    )?;
    workplace.assert();
    accounts.assert();
    post.assert();
    assert!(host.transcript().is_empty());
    assert!(host.output.last().expect("plan").starts_with("Plan:"));
    Ok(())
}

#[test]
fn preparation_creates_only_the_selected_identity_and_reads_back_the_provider_state() -> Result<()>
{
    let mut server = Server::new();
    let fixtures = [
        (
            "GET",
            "/v3/workplace".into(),
            json!({"workplace":{"id":"selected"}}),
        ),
        (
            "GET",
            format!("{ACCOUNTS}?page=1&per_page=100"),
            json!({"service_accounts":[]}),
        ),
        (
            "POST",
            ACCOUNTS.into(),
            json!({"service_account":account()}),
        ),
        (
            "GET",
            format!("{MEMBERS}&page=1&per_page=100"),
            json!({"members":[]}),
        ),
        ("POST", MEMBERS.into(), json!({"success":true})),
        (
            "GET",
            format!("/v3/projects/project/members/member/service_account/{SLUG}?project=gymemo"),
            json!({"member":member()}),
        ),
        (
            "POST",
            format!("{ACCOUNTS}/service_account/{SLUG}/identities"),
            json!({"identity":identity()}),
        ),
        (
            "GET",
            format!("{ACCOUNTS}/service_account/{SLUG}/identities?page=1&per_page=100"),
            json!({"identities":[identity()]}),
        ),
    ];
    let mocks = fixtures
        .into_iter()
        .map(|(method, path, body)| {
            if method != "POST" {
                return reply(&mut server, method, &path, body);
            }
            let expected = match path.as_str() {
                ACCOUNTS => json!({"name":"gymemo-website-delivery","workplace_role":{"identifier":"no_access"}}),
                MEMBERS => json!({"type":"service_account","slug":SLUG,"role":"viewer","environments":["ci_website"]}),
                _ => {
                    let mut expected = identity();
                    expected.as_object_mut().expect("identity fixture").remove("slug");
                    expected
                }
            };
            server
                .mock(method, path.as_str())
                .match_header("authorization", format!("Bearer {TOKEN}").as_str())
                .match_body(Matcher::Json(expected))
                .with_body(body.to_string())
                .expect(1)
                .create()
        })
        .collect::<Vec<_>>();
    let mut host = variable_host();
    configure(
        &mut host,
        Path::new("/repo"),
        "selected",
        true,
        PREFIX,
        &client(&server),
    )?;
    for mock in mocks {
        mock.assert();
    }
    assert!(host.transcript().iter().any(|line| {
        line.contains("\"variable\" \"set\" \"DOPPLER_IDENTITY_ID\"") && line.contains(IDENTITY)
    }));
    assert!(
        host.output
            .last()
            .expect("summary")
            .starts_with("Configured")
    );
    Ok(())
}

#[test]
fn a_retry_reuses_the_matching_account_grant_and_identity_without_creating_them_again() -> Result<()>
{
    let mut server = Server::new();
    let fixtures = [
        (
            "/v3/workplace".into(),
            json!({"workplace":{"id":"selected"}}),
        ),
        (
            format!("{ACCOUNTS}?page=1&per_page=100"),
            json!({"service_accounts":[account()]}),
        ),
        (
            format!("{ACCOUNTS}/service_account/{SLUG}/identities?page=1&per_page=100"),
            json!({"identities":[identity()]}),
        ),
        (
            format!("{MEMBERS}&page=1&per_page=100"),
            json!({"members":[member()]}),
        ),
        (
            format!("/v3/projects/project/members/member/service_account/{SLUG}?project=gymemo"),
            json!({"member":member()}),
        ),
    ];
    let mocks = fixtures
        .into_iter()
        .map(|(path, body)| {
            let mut mock = server
                .mock("GET", path.as_str())
                .with_body(body.to_string());
            if path.contains("/identities?") {
                mock = mock.expect(2);
            } else {
                mock = mock.expect(1);
            }
            mock.create()
        })
        .collect::<Vec<_>>();
    let post = server.mock("POST", Matcher::Any).expect(0).create();
    configure(
        &mut variable_host(),
        Path::new("/repo"),
        "selected",
        true,
        PREFIX,
        &client(&server),
    )?;
    for mock in mocks {
        mock.assert();
    }
    post.assert();
    Ok(())
}

#[test]
fn integration_inspection_reads_only_metadata_from_the_selected_workplace() -> Result<()> {
    let mut server = Server::new();
    let workplace = reply(
        &mut server,
        "GET",
        "/v3/workplace",
        json!({"workplace":{"id":"selected"}}),
    );
    let integrations = reply(
        &mut server,
        "GET",
        "/v3/integrations",
        json!({"integrations":[{
            "slug":"connection-1","name":"GitHub connection","type":"github-actions",
            "credentials":{"access_token":"do-not-print"}
        }]}),
    );
    let options = reply(
        &mut server,
        "GET",
        "/v3/integrations/integration/options?integration=connection-1",
        json!({"options":{"hasMoreRepos":false,"repos":{"P4suta":[{
            "name":"gymemo","id":1453033797,"archived":false,
            "owner":{"id":42543015,"login":"P4suta"}
        }]}},"credential":"do-not-print"}),
    );
    let post = server.mock("POST", Matcher::Any).expect(0).create();
    let mut host = FakeHost::new();
    inspect_integrations(&mut host, "selected", &client(&server))?;
    workplace.assert();
    integrations.assert();
    options.assert();
    post.assert();
    assert!(
        host.output
            .iter()
            .any(|line| line.contains("connection-1") && line.contains("github"))
    );
    assert!(
        host.output
            .iter()
            .all(|line| !line.contains("do-not-print"))
    );
    assert!(
        host.output
            .iter()
            .any(|line| line.contains("P4suta/gymemo"))
    );
    Ok(())
}

#[test]
fn github_destination_requires_the_exact_live_repository() -> Result<()> {
    let value = json!({"options":{"hasMoreRepos":false,"repos":{"P4suta":[{
        "name":"gymemo","id":1453033797,"archived":false,
        "owner":{"id":42543015,"login":"P4suta"}
    }]}}});
    assert_eq!(github_destination(&value)?, "gymemo");
    for (pointer, replacement) in [
        ("/options/repos/P4suta/0/name", json!("another-project")),
        ("/options/repos/P4suta/0/id", json!(1453033798_u64)),
        ("/options/repos/P4suta/0/archived", json!(true)),
        ("/options/repos/P4suta/0/owner/id", json!(42543016_u64)),
        (
            "/options/repos/P4suta/0/owner/login",
            json!("another-owner"),
        ),
    ] {
        let mut invalid = value.clone();
        *invalid.pointer_mut(pointer).unwrap() = replacement;
        assert!(github_destination(&invalid).is_err(), "{pointer}");
    }
    for invalid in [
        Value::Null,
        json!({"options":{"repos":{}}}),
        json!({"options":{"hasMoreRepos":false,"repos":{"P4suta":[]}}}),
        json!({"options":{"hasMoreRepos":true,"repos":{"P4suta":[]}}}),
    ] {
        assert!(github_destination(&invalid).is_err());
    }
    let mut duplicate = value.clone();
    duplicate["options"]["repos"]["P4suta"] = json!([
        value["options"]["repos"]["P4suta"][0],
        value["options"]["repos"]["P4suta"][0]
    ]);
    assert!(github_destination(&duplicate).is_err());
    Ok(())
}

#[test]
fn integration_inspection_refuses_other_workplaces_and_malformed_metadata() {
    for value in [
        Value::Null,
        json!({"integrations":{}}),
        json!({"integrations":[{"slug":"../escape"}]}),
    ] {
        let mut server = Server::new();
        let workplace = reply(
            &mut server,
            "GET",
            "/v3/workplace",
            json!({"workplace":{"id":"selected"}}),
        );
        let integrations = reply(&mut server, "GET", "/v3/integrations", value);
        assert!(inspect_integrations(&mut FakeHost::new(), "selected", &client(&server)).is_err());
        workplace.assert();
        integrations.assert();
    }
    let mut server = Server::new();
    let workplace = reply(
        &mut server,
        "GET",
        "/v3/workplace",
        json!({"workplace":{"id":"another"}}),
    );
    let integrations = server.mock("GET", "/v3/integrations").expect(0).create();
    assert!(inspect_integrations(&mut FakeHost::new(), "selected", &client(&server)).is_err());
    workplace.assert();
    integrations.assert();
}

#[test]
fn native_sync_requires_exact_protection_and_destination() -> Result<()> {
    let environment = json!({
        "name":"native-upload","can_admins_bypass":false,
        "deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true},
        "protection_rules":[{"type":"required_reviewers","prevent_self_review":false,
            "reviewers":[{"type":"User","reviewer":{"id":42543015}}]}]
    });
    let branches = json!({"branch_policies":[{"name":"main","type":"branch"}]});
    admit_native_environment(&environment, &branches, "native-upload")?;
    for (pointer, replacement) in [
        ("/name", json!("another-environment")),
        ("/can_admins_bypass", json!(true)),
        (
            "/deployment_branch_policy/custom_branch_policies",
            json!(false),
        ),
        ("/deployment_branch_policy/protected_branches", json!(true)),
        ("/protection_rules/0/reviewers/0/reviewer/id", json!(1)),
        ("/protection_rules/0/reviewers/0/type", json!("Team")),
    ] {
        let mut invalid = environment.clone();
        *invalid.pointer_mut(pointer).unwrap() = replacement;
        assert!(admit_native_environment(&invalid, &branches, "native-upload").is_err());
    }
    for invalid in [
        Value::Null,
        json!({"branch_policies":[]}),
        json!({"branch_policies":[{"name":"*","type":"branch"}]}),
        json!({"branch_policies":[{"name":"main","type":"tag"}]}),
    ] {
        assert!(admit_native_environment(&environment, &invalid, "native-upload").is_err());
    }
    assert_eq!(
        NativePurpose::parse("signing")?.config(),
        "ci_native_signing"
    );
    assert_eq!(
        NativePurpose::parse("upload")?.environment(),
        "native-upload"
    );
    assert_eq!(NativePurpose::parse("upload")?.config(), "ci_native_upload");
    assert_eq!(
        NativePurpose::parse("signing")?.environment(),
        "native-signing"
    );
    assert!(NativePurpose::parse("website").is_err());
    Ok(())
}

#[test]
fn proposal_preparation_keeps_main_restrictions_without_a_publication_reviewer() -> Result<()> {
    let purpose = NativePurpose::parse("version-preparation")?;
    assert_eq!(purpose.config(), "ci_version_preparation");
    assert_eq!(purpose.environment(), "version-preparation");
    let environment = json!({"name":"version-preparation","can_admins_bypass":false,
        "deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true},
        "protection_rules":[{"type":"branch_policy"}]});
    let branches = json!({"branch_policies":[{"name":"main","type":"branch"}]});
    admit_native_environment(&environment, &branches, purpose.environment())?;
    for (pointer, replacement) in [
        ("/name", json!("native-signing")),
        ("/can_admins_bypass", json!(true)),
        ("/protection_rules", json!([{"type":"required_reviewers"}])),
        (
            "/deployment_branch_policy/custom_branch_policies",
            json!(false),
        ),
    ] {
        let mut invalid = environment.clone();
        *invalid.pointer_mut(pointer).unwrap() = replacement;
        assert!(
            admit_native_environment(&invalid, &branches, purpose.environment()).is_err(),
            "{pointer}"
        );
    }
    let mut host = native_host(purpose, None);
    let mut server = Server::new();
    let expected = native_metadata(&mut server, purpose);
    configure_native(
        &mut host,
        Path::new("/repo"),
        "selected",
        "connection-1",
        purpose,
        false,
        &client(&server),
    )?;
    for expectation in expected {
        expectation.assert();
    }
    Ok(())
}

#[test]
fn native_sync_refuses_a_different_root_config_before_reading_the_connection() {
    for (field, value) in [
        ("project", json!("another-project")),
        ("environment", json!("ci_native_signing")),
        ("name", json!("ci_native_upload_personal")),
        ("root", json!(false)),
    ] {
        let mut server = Server::new();
        let workplace = reply(
            &mut server,
            "GET",
            "/v3/workplace",
            json!({"workplace":{"id":"selected"}}),
        );
        let mut config = json!({"project":"gymemo","environment":"ci_native_upload","name":"ci_native_upload","root":true});
        config[field] = value;
        let selected = reply(
            &mut server,
            "GET",
            "/v3/configs/config?project=gymemo&config=ci_native_upload",
            json!({"config":config}),
        );
        let connection = server
            .mock(
                "GET",
                "/v3/integrations/integration?integration=connection-1",
            )
            .expect(0)
            .create();
        let mut host = FakeHost::new();
        assert!(
            configure_native(
                &mut host,
                Path::new("/repo"),
                "selected",
                "connection-1",
                NativePurpose::Upload,
                true,
                &client(&server)
            )
            .is_err()
        );
        workplace.assert();
        selected.assert();
        connection.assert();
        assert!(host.transcript().is_empty());
    }
}

#[test]
fn native_sync_refuses_a_different_connection_before_reading_its_options() {
    for field in ["slug", "type"] {
        let mut server = Server::new();
        let workplace = reply(
            &mut server,
            "GET",
            "/v3/workplace",
            json!({"workplace":{"id":"selected"}}),
        );
        let config = reply(
            &mut server,
            "GET",
            "/v3/configs/config?project=gymemo&config=ci_native_upload",
            json!({"config":{"project":"gymemo","environment":"ci_native_upload","name":"ci_native_upload","root":true}}),
        );
        let mut integration = json!({"slug":"connection-1","type":"github-actions"});
        integration[field] = json!("another");
        let connection = reply(
            &mut server,
            "GET",
            "/v3/integrations/integration?integration=connection-1",
            json!({"integration":integration}),
        );
        let options = server
            .mock(
                "GET",
                "/v3/integrations/integration/options?integration=connection-1",
            )
            .expect(0)
            .create();
        let post = server.mock("POST", Matcher::Any).expect(0).create();
        let mut host = FakeHost::new();
        let failure = configure_native(
            &mut host,
            Path::new("/repo"),
            "selected",
            "connection-1",
            NativePurpose::Upload,
            true,
            &client(&server),
        )
        .expect_err("an unrelated connection");
        assert!(
            failure.to_string().contains("expected GitHub connection"),
            "{field}"
        );
        assert!(host.transcript().is_empty());
        for request in [workplace, config, connection, options, post] {
            request.assert();
        }
    }
}

#[test]
fn native_sync_refuses_incomplete_variables_and_untracked_secret_copies() {
    for variables in [
        Value::Null,
        json!({"total_count":0,"variables":{}}),
        json!({"total_count":1,"variables":[]}),
        json!({"total_count":2,"variables":[{"name":"DOPPLER_SYNC_ID","value":"one"},{"name":"DOPPLER_SYNC_ID","value":"two"}]}),
        json!({"total_count":1,"variables":[{"name":"DOPPLER_SYNC_ID","value":12}]}),
        json!({"total_count":1,"variables":[{"name":"DOPPLER_SYNC_ID","value":"../sync"}]}),
    ] {
        let mut server = Server::new();
        let metadata = native_metadata(&mut server, NativePurpose::Upload);
        let post = server.mock("POST", Matcher::Any).expect(0).create();
        let mut host = native_host(NativePurpose::Upload, None);
        host.prints("variables?per_page", &variables.to_string());
        assert!(
            configure_native(
                &mut host,
                Path::new("/repo"),
                "selected",
                "connection-1",
                NativePurpose::Upload,
                true,
                &client(&server)
            )
            .is_err()
        );
        for request in metadata {
            request.assert();
        }
        post.assert();
        assert_eq!(host.transcript().len(), 3);
    }
    for secrets in [
        json!({"total_count":1,"secrets":[{"name":"OLD_KEY"}]}),
        json!({"total_count":0,"secrets":[{"name":"OLD_KEY"}]}),
        json!({"total_count":1,"secrets":[]}),
    ] {
        let mut server = Server::new();
        let metadata = native_metadata(&mut server, NativePurpose::Upload);
        let post = server.mock("POST", Matcher::Any).expect(0).create();
        let mut host = native_host(NativePurpose::Upload, None);
        host.prints("secrets?per_page", &secrets.to_string());
        let failure = configure_native(
            &mut host,
            Path::new("/repo"),
            "selected",
            "connection-1",
            NativePurpose::Upload,
            true,
            &client(&server),
        )
        .expect_err("an occupied or inconsistent secret listing");
        assert!(
            failure
                .to_string()
                .contains("already has credential copies")
        );
        for request in metadata {
            request.assert();
        }
        post.assert();
        assert_eq!(host.transcript().len(), 4);
    }
}

fn native_host(purpose: NativePurpose, state: Option<&str>) -> FakeHost {
    let mut host = FakeHost::new();
    let base = format!("repos/P4suta/gymemo/environments/{}", purpose.environment());
    host.prints(
        &format!("{base}\""),
        &json!({
            "name":purpose.environment(),"can_admins_bypass":false,
            "deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true},
            "protection_rules":if matches!(purpose,NativePurpose::VersionPreparation) {
                json!([{"type":"branch_policy"}])
            } else {
                json!([{"type":"required_reviewers","prevent_self_review":false,
                    "reviewers":[{"type":"User","reviewer":{"id":42543015}}]}])
            }
        })
        .to_string(),
    );
    host.prints(
        "deployment-branch-policies",
        &json!({"branch_policies":[{"name":"main","type":"branch"}]}).to_string(),
    );
    host.prints(
        "variables?per_page",
        &match state {
            None => json!({"total_count":0,"variables":[]}),
            Some(value) => {
                json!({"total_count":1,"variables":[{"name":"DOPPLER_SYNC_ID","value":value}]})
            }
        }
        .to_string(),
    );
    host.prints(
        "secrets?per_page",
        &json!({"total_count":0,"secrets":[]}).to_string(),
    );
    host.prints(
        "variables/DOPPLER_SYNC_ID",
        &json!({"value":SLUG}).to_string(),
    );
    host.prints_at(5, &json!({"value":"pending"}).to_string());
    host
}

fn native_metadata(server: &mut mockito::ServerGuard, purpose: NativePurpose) -> Vec<Mock> {
    let config = purpose.config();
    vec![
        reply(
            server,
            "GET",
            "/v3/workplace",
            json!({"workplace":{"id":"selected"}}),
        ),
        reply(
            server,
            "GET",
            &format!("/v3/configs/config?project=gymemo&config={config}"),
            json!({"config":{"project":"gymemo","environment":config,"name":config,"root":true}}),
        ),
        reply(
            server,
            "GET",
            "/v3/integrations/integration?integration=connection-1",
            json!({"integration":{"slug":"connection-1","type":"github-actions"}}),
        ),
        reply(
            server,
            "GET",
            "/v3/integrations/integration/options?integration=connection-1",
            json!({"options":{"repos":{"P4suta":[{"name":"gymemo","id":1453033797,"archived":false,"owner":{"id":42543015,"login":"P4suta"}}]}}}),
        ),
    ]
}

fn sync_reply(purpose: NativePurpose) -> Value {
    json!({"sync":{"slug":SLUG,"project":"gymemo","config":purpose.config(),"integration":"connection-1"}})
}

#[test]
fn native_sync_plans_both_purposes_without_writes() -> Result<()> {
    for purpose in [NativePurpose::Signing, NativePurpose::Upload] {
        let mut server = Server::new();
        let metadata = native_metadata(&mut server, purpose);
        let post = server.mock("POST", Matcher::Any).expect(0).create();
        let mut host = native_host(purpose, None);
        configure_native(
            &mut host,
            Path::new("/repo"),
            "selected",
            "connection-1",
            purpose,
            false,
            &client(&server),
        )?;
        for request in metadata {
            request.assert();
        }
        post.assert();
        assert_eq!(host.transcript().len(), 4);
        assert!(host.output.join("\n").contains(purpose.config()));
        assert!(host.output.join("\n").contains(purpose.environment()));
    }
    Ok(())
}

#[test]
fn native_sync_records_pending_before_creation_and_reads_back_its_identity() -> Result<()> {
    let purpose = NativePurpose::Upload;
    let mut server = Server::new();
    let metadata = native_metadata(&mut server, purpose);
    let create = server.mock("POST", "/v3/configs/config/syncs?project=gymemo&config=ci_native_upload")
        .match_header("authorization", format!("Bearer {TOKEN}").as_str())
        .match_body(Matcher::Json(json!({
            "integration":"connection-1","import_option":"none","await_initial_sync":true,
            "data":{"feature":"actions","sync_target":"repo","repo_name":"gymemo","environment_name":"native-upload","sync_unmasked_as_variables":false}
        })))
        .with_body(sync_reply(purpose).to_string()).expect(1).create();
    let observed = reply(
        &mut server,
        "GET",
        &format!(
            "/v3/configs/config/syncs/sync?project=gymemo&config=ci_native_upload&sync={SLUG}"
        ),
        sync_reply(purpose),
    );
    let mut host = native_host(purpose, None);
    configure_native(
        &mut host,
        Path::new("/repo"),
        "selected",
        "connection-1",
        purpose,
        true,
        &client(&server),
    )?;
    for request in metadata {
        request.assert();
    }
    create.assert();
    observed.assert();
    let calls = host.transcript();
    assert!(calls[4].contains("\"--body\" \"pending\""));
    assert!(calls[5].contains("variables/DOPPLER_SYNC_ID"));
    assert!(calls[6].contains(&format!("\"--body\" \"{SLUG}\"")));
    assert!(calls[7].contains("variables/DOPPLER_SYNC_ID"));
    assert!(host.output.iter().all(|line| !line.contains(TOKEN)));
    Ok(())
}

#[test]
fn native_sync_reuses_a_verified_sync_and_holds_an_unresolved_creation() -> Result<()> {
    for state in ["pending", SLUG] {
        let purpose = NativePurpose::Signing;
        let mut server = Server::new();
        let metadata = native_metadata(&mut server, purpose);
        let observed = server.mock("GET", format!("/v3/configs/config/syncs/sync?project=gymemo&config=ci_native_signing&sync={SLUG}").as_str())
            .with_body(sync_reply(purpose).to_string()).expect(usize::from(state == SLUG)).create();
        let post = server.mock("POST", Matcher::Any).expect(0).create();
        let mut host = native_host(purpose, Some(state));
        let result = configure_native(
            &mut host,
            Path::new("/repo"),
            "selected",
            "connection-1",
            purpose,
            true,
            &client(&server),
        );
        assert_eq!(result.is_ok(), state == SLUG);
        for request in metadata {
            request.assert();
        }
        observed.assert();
        post.assert();
        assert_eq!(host.transcript().len(), 3);
    }
    Ok(())
}

#[test]
fn native_sync_stops_before_creation_when_the_pending_marker_fails() {
    for fault in [
        Fault::Missing,
        Fault::Exit(1, "do-not-print"),
        Fault::Garbled,
    ] {
        let purpose = NativePurpose::Upload;
        let mut server = Server::new();
        let metadata = native_metadata(&mut server, purpose);
        let post = server.mock("POST", Matcher::Any).expect(0).create();
        let mut host = native_host(purpose, None);
        host.fail_at(4, fault);
        let error = configure_native(
            &mut host,
            Path::new("/repo"),
            "selected",
            "connection-1",
            purpose,
            true,
            &client(&server),
        )
        .unwrap_err()
        .to_string();
        assert!(!error.contains("do-not-print"));
        for request in metadata {
            request.assert();
        }
        post.assert();
    }
}

#[test]
fn native_sync_keeps_an_uncertain_creation_pending_and_withholds_provider_bodies() {
    for (status, body) in [
        (500, "do-not-print"),
        (400, "do-not-print"),
        (200, "not-json"),
        (
            200,
            r#"{"sync":{"slug":"one","project":"other","config":"ci_native_upload","integration":"connection-1"}}"#,
        ),
    ] {
        let purpose = NativePurpose::Upload;
        let mut server = Server::new();
        let metadata = native_metadata(&mut server, purpose);
        let create = server
            .mock(
                "POST",
                "/v3/configs/config/syncs?project=gymemo&config=ci_native_upload",
            )
            .with_status(status)
            .with_body(body)
            .expect(1)
            .create();
        let mut host = native_host(purpose, None);
        let error = configure_native(
            &mut host,
            Path::new("/repo"),
            "selected",
            "connection-1",
            purpose,
            true,
            &client(&server),
        )
        .unwrap_err()
        .to_string();
        for request in metadata {
            request.assert();
        }
        create.assert();
        assert_eq!(host.transcript().len(), 6);
        assert!(host.transcript()[4].contains("\"pending\""));
        assert!(!error.contains("do-not-print"));
        assert!(
            host.output
                .iter()
                .all(|line| !line.contains("do-not-print") && !line.contains(TOKEN))
        );
    }
}

#[test]
fn malformed_native_setup_arguments_never_start_a_program() {
    for arguments in [
        vec![],
        vec!["workplace"],
        vec!["workplace", "connection", "website"],
        vec!["workplace", "../connection", "upload"],
        vec!["workplace", "connection", "upload", "--force"],
        vec!["workplace", "connection", "upload", "--apply", "extra"],
    ] {
        let mut host = FakeHost::new();
        assert!(
            run_native(
                &mut host,
                Path::new("/repo"),
                &arguments.into_iter().map(str::to_owned).collect::<Vec<_>>()
            )
            .is_err()
        );
        assert!(host.transcript().is_empty());
    }
}
