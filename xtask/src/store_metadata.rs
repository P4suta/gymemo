use crate::{
    app_version,
    failure::{Context, Result, ensure},
    host::{Host, Invocation, Streams},
};
use std::{
    collections::{BTreeMap, BTreeSet},
    path::{Path, PathBuf},
};

pub fn prepare(host: &mut impl Host, root: &Path) -> Result<PathBuf> {
    let version = app_version::read(host, root)?;
    let source = root.join("metadata/app-store");
    let directory = root.join("target/app-store").join(version.to_string());
    let mut files = Vec::new();
    let mut expected = BTreeSet::new();
    for kind in ["app-info", "version"] {
        for language in ["en-US", "ja", "zh-Hans", "zh-Hant"] {
            let relative = Path::new(kind).join(format!("{language}.json"));
            let input = source.join(&relative);
            let text = host
                .read(&input)
                .context(|| format!("Read {}", input.display()))?;
            let _: BTreeMap<String, String> = serde_json::from_str(&text)
                .context(|| format!("{} must contain string metadata fields", input.display()))?;
            let output = if kind == "version" {
                directory
                    .join(kind)
                    .join(version.to_string())
                    .join(format!("{language}.json"))
            } else {
                directory.join(relative)
            };
            expected.insert(input);
            files.push((output, text));
        }
    }
    let actual = host
        .files(&source)
        .context(|| "List public store metadata".into())?
        .into_iter()
        .collect::<BTreeSet<_>>();
    ensure(actual == expected, || {
        "Store metadata has unexpected or missing locale files".into()
    })?;
    for (output, text) in files {
        let parent = output
            .parent()
            .expect("a generated metadata destination has a parent");
        host.create_directories(parent)
            .context(|| format!("Create {}", parent.display()))?;
        host.write(&output, &text)
            .context(|| format!("Write {}", output.display()))?;
    }
    Ok(directory)
}

pub fn check(host: &mut impl Host, root: &Path) -> Result<()> {
    let directory = prepare(host, root)?;
    let command = Invocation::new("asc")
        .current_dir(root)
        .args(["metadata", "validate", "--dir"])
        .arg(directory)
        .args(["--output", "table"]);
    let output = host
        .run(&command, Streams::Shown)
        .context(|| "Start store metadata validation".into())?;
    ensure(output.status.success(), || {
        "Store metadata validation failed".into()
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::host::fake::{FakeHost, Fault};

    fn prepared() -> FakeHost {
        let mut host = FakeHost::new();
        host.file("/repo/Config/MarketingVersion.txt", "1.2.3\n");
        for kind in ["app-info", "version"] {
            for language in ["en-US", "ja", "zh-Hans", "zh-Hant"] {
                host.file(
                    &format!("/repo/metadata/app-store/{kind}/{language}.json"),
                    &format!("{{\"description\":\"{language}\"}}\n"),
                );
            }
        }
        host
    }

    #[test]
    fn prepares_every_locale_under_the_selected_version_without_running_a_program() -> Result<()> {
        let mut host = prepared();
        let directory = prepare(&mut host, Path::new("/repo"))?;
        assert_eq!(directory, Path::new("/repo/target/app-store/1.2.3"));
        for kind in ["app-info", "version/1.2.3"] {
            for language in ["en-US", "ja", "zh-Hans", "zh-Hant"] {
                assert_eq!(
                    host.read(&directory.join(kind).join(format!("{language}.json")))
                        .unwrap(),
                    format!("{{\"description\":\"{language}\"}}\n")
                );
            }
        }
        assert!(
            host.transcript()
                .iter()
                .all(|line| !line.starts_with("capture ") && !line.starts_with("show "))
        );
        Ok(())
    }

    #[test]
    fn refuses_missing_malformed_and_unexpected_source_metadata_before_writing() {
        for invalid in ["not JSON", "[]", "{\"description\":4}"] {
            let mut host = prepared();
            host.file("/repo/metadata/app-store/version/ja.json", invalid);
            assert!(prepare(&mut host, Path::new("/repo")).is_err());
            assert!(
                host.transcript()
                    .iter()
                    .all(|line| !line.starts_with("write "))
            );
        }
        let mut host = prepared();
        host.remove_file(Path::new("/repo/metadata/app-store/version/ja.json"))
            .unwrap();
        assert!(prepare(&mut host, Path::new("/repo")).is_err());
        assert!(
            host.transcript()
                .iter()
                .all(|line| !line.starts_with("write "))
        );
        let mut host = prepared();
        host.file("/repo/metadata/app-store/version/another.json", "{}");
        assert!(prepare(&mut host, Path::new("/repo")).is_err());
        assert!(
            host.transcript()
                .iter()
                .all(|line| !line.starts_with("write "))
        );
    }

    #[test]
    fn propagates_output_and_provider_failures() {
        let mut host = prepared();
        host.directory("/repo/target/app-store/1.2.3/app-info/en-US.json", &[]);
        assert!(prepare(&mut host, Path::new("/repo")).is_err());
        let mut host = prepared();
        host.fail("\"asc\"", Fault::Exit(1, "invalid metadata"));
        assert!(check(&mut host, Path::new("/repo")).is_err());
    }

    #[test]
    fn the_provider_validates_only_the_generated_current_version() -> Result<()> {
        let mut host = prepared();
        check(&mut host, Path::new("/repo"))?;
        let commands = host
            .transcript()
            .iter()
            .filter(|line| line.starts_with("show "))
            .collect::<Vec<_>>();
        assert_eq!(
            commands,
            [
                "show cd \"/repo\" && \"asc\" \"metadata\" \"validate\" \"--dir\" \"/repo/target/app-store/1.2.3\" \"--output\" \"table\""
            ]
        );
        Ok(())
    }
}
