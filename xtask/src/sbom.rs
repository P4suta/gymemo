use crate::{
    failure::{Context, Failure, Result, ensure},
    host::Host,
};
use serde_json::Value;
use std::path::Path;

#[derive(Clone, Copy)]
enum Product {
    Native,
    Website,
}

impl Product {
    fn parse(value: &str) -> Result<Self> {
        match value {
            "native" => Ok(Self::Native),
            "website" => Ok(Self::Website),
            _ => Err(Failure::new("The SBOM product must be native or website")),
        }
    }

    fn name(self) -> &'static str {
        match self {
            Self::Native => "gymemo",
            Self::Website => "gymemo-support",
        }
    }
}

fn admit(text: &str, product: Product, version: &str) -> Result<()> {
    let sbom: Value = serde_json::from_str(text).context(|| "Read the CycloneDX SBOM".into())?;
    ensure(
        sbom["bomFormat"] == "CycloneDX"
            && sbom["specVersion"] == "1.7"
            && sbom["metadata"]["component"]["name"] == product.name()
            && sbom["metadata"]["component"]["version"] == version,
        || "The SBOM names a different product, version, or format".into(),
    )?;
    let components = match sbom.get("components") {
        None => &[][..],
        Some(value) => value
            .as_array()
            .ok_or_else(|| Failure::new("The SBOM component inventory is malformed"))?
            .as_slice(),
    };
    ensure(
        components.iter().all(|component| {
            component["type"] == "file"
                || (matches!(product, Product::Native)
                    && component["type"] == "library"
                    && matches!(component["name"].as_str(), Some("gymemo" | "gymemoWatch"))
                    && component["version"] == version)
        }),
        || {
            "The SBOM contains a dependency without a project license and vulnerability policy"
                .into()
        },
    )
}

pub fn admit_native(text: &str, version: &str) -> Result<()> {
    admit(text, Product::Native, version)
}

pub fn check(host: &mut impl Host, root: &Path, arguments: &[String]) -> Result<()> {
    ensure(arguments.len() == 3, || {
        "check-sbom requires native|website VERSION FILE".into()
    })?;
    let product = Product::parse(&arguments[0])?;
    let version = &arguments[1];
    match product {
        Product::Native => {
            crate::app_version::AppVersion::parse(version)?;
        }
        Product::Website => ensure(
            version.len() == 40
                && version
                    .bytes()
                    .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b)),
            || "Website inventory requires a full source commit identifier".into(),
        )?,
    }
    let text = host
        .read(&root.join(&arguments[2]))
        .context(|| "Read the preserved dependency inventory".into())?;
    admit(&text, product, version)?;
    host.print(&format!("PASS SBOM: {} {version}", product.name()));
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::host::fake::FakeHost;
    use serde_json::json;

    #[test]
    fn checks_the_exact_preserved_inventory_for_each_product() -> Result<()> {
        for (product, name, version) in [
            ("native", "gymemo", "1.0.0"),
            (
                "website",
                "gymemo-support",
                "0123456789abcdef0123456789abcdef01234567",
            ),
        ] {
            let mut host = FakeHost::new();
            let valid = json!({"bomFormat":"CycloneDX","specVersion":"1.7","metadata":{"component":{"name":name,"version":version}},"components":[]});
            host.file("/repo/inventory.json", &valid.to_string());
            let arguments = [product, version, "inventory.json"].map(str::to_owned);
            check(&mut host, Path::new("/repo"), &arguments)?;
            for (pointer, value) in [
                ("/metadata/component/name", json!("another")),
                ("/metadata/component/version", json!("another")),
                (
                    "/components",
                    json!([{"type":"library","name":"uncovered"}]),
                ),
            ] {
                let mut invalid = valid.clone();
                *invalid.pointer_mut(pointer).unwrap() = value;
                host.file("/repo/inventory.json", &invalid.to_string());
                assert!(
                    check(&mut host, Path::new("/repo"), &arguments).is_err(),
                    "{pointer}"
                );
            }
        }
        Ok(())
    }

    #[test]
    fn refuses_invalid_selections_missing_files_and_malformed_inventories() {
        for args in [
            vec![],
            vec!["native"],
            vec!["another", "1.0.0", "inventory.json"],
            vec!["native", "1.0", "inventory.json"],
            vec!["website", "main", "inventory.json"],
        ] {
            let mut host = FakeHost::new();
            assert!(
                check(
                    &mut host,
                    Path::new("/repo"),
                    &args.into_iter().map(str::to_owned).collect::<Vec<_>>()
                )
                .is_err()
            );
            assert!(host.transcript().is_empty());
        }
        let mut host = FakeHost::new();
        let args = ["native", "1.0.0", "inventory.json"].map(str::to_owned);
        assert!(check(&mut host, Path::new("/repo"), &args).is_err());
        host.file("/repo/inventory.json", "{}");
        assert!(check(&mut host, Path::new("/repo"), &args).is_err());
    }

    #[test]
    fn refuses_invalid_source_identifier_lengths_and_characters_before_reading() {
        for version in [
            String::new(),
            "a".to_owned(),
            "a".repeat(39),
            "a".repeat(41),
            "g".repeat(40),
            format!("g{}", "a".repeat(39)),
            format!("{}g", "a".repeat(39)),
            "A".repeat(40),
            "`".repeat(40),
            " ".repeat(40),
            "é".repeat(20),
        ] {
            let mut host = FakeHost::new();
            let arguments = [
                "website".to_owned(),
                version.clone(),
                "inventory.json".into(),
            ];
            assert!(
                check(&mut host, Path::new("/repo"), &arguments).is_err(),
                "{version:?}"
            );
            assert!(host.transcript().is_empty(), "{version:?}");
        }
    }
}
