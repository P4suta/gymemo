//! Verifies the installer submission profile in [Apple WWDR CPS section 4.11.6](https://images.apple.com/certificateauthority/pdf/Apple_WWDR_CPS_v1.32.pdf#page=34).

use crate::failure::{Context, Failure, Result, ensure};
use x509_cert::{
    Certificate,
    der::{Decode, asn1::Null},
    ext::{
        Extension,
        pkix::{BasicConstraints, ExtendedKeyUsage, KeyUsage, KeyUsages},
    },
    spki::ObjectIdentifier,
};

const BASIC_CONSTRAINTS: ObjectIdentifier = ObjectIdentifier::new_unwrap("2.5.29.19");
const KEY_USAGE: ObjectIdentifier = ObjectIdentifier::new_unwrap("2.5.29.15");
const EXTENDED_KEY_USAGE: ObjectIdentifier = ObjectIdentifier::new_unwrap("2.5.29.37");
const PACKAGE_SIGNING: ObjectIdentifier = ObjectIdentifier::new_unwrap("1.2.840.113635.100.4.9");
const INSTALLER_SUBMISSION: ObjectIdentifier =
    ObjectIdentifier::new_unwrap("1.2.840.113635.100.6.1.8");

pub(super) fn verify(der: &[u8]) -> Result<()> {
    let certificate =
        Certificate::from_der(der).context(|| "Decode the installer certificate as DER".into())?;
    verify_extensions(
        certificate
            .tbs_certificate()
            .extensions()
            .map_or(&[], Vec::as_slice),
    )
}

fn required<'a, T: Decode<'a, Error = x509_cert::der::Error>>(
    extensions: &'a [Extension],
    oid: ObjectIdentifier,
) -> Result<T> {
    let mut matching = extensions
        .iter()
        .filter(|extension| extension.extn_id == oid);
    let extension = matching.next().ok_or_else(|| {
        Failure::new(format!(
            "The installer certificate is missing extension {oid}"
        ))
    })?;
    ensure(matching.next().is_none() && extension.critical, || {
        format!("The installer certificate requires one critical extension {oid}")
    })?;
    T::from_der(extension.extn_value.as_bytes())
        .context(|| format!("Decode installer certificate extension {oid}"))
}

fn verify_extensions(extensions: &[Extension]) -> Result<()> {
    let constraints: BasicConstraints = required(extensions, BASIC_CONSTRAINTS)?;
    ensure(
        !constraints.ca && constraints.path_len_constraint.is_none(),
        || "The installer certificate must be an end-entity certificate".into(),
    )?;
    let usage: KeyUsage = required(extensions, KEY_USAGE)?;
    ensure(
        usage == KeyUsage(KeyUsages::DigitalSignature.into()),
        || "The installer certificate must allow digital signatures".into(),
    )?;
    let extended: ExtendedKeyUsage = required(extensions, EXTENDED_KEY_USAGE)?;
    ensure(extended.0 == [PACKAGE_SIGNING], || {
        "The installer certificate must have the Mac Installer Package Signing purpose".into()
    })?;
    let _: Null = required(extensions, INSTALLER_SUBMISSION)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use x509_cert::{
        der::{Encode, asn1::OctetString},
        spki::ObjectIdentifier,
    };

    fn extension(oid: &str, value: &[u8]) -> Extension {
        Extension {
            extn_id: oid.parse().unwrap(),
            critical: true,
            extn_value: OctetString::new(value).unwrap(),
        }
    }

    fn installer() -> Vec<Extension> {
        vec![
            extension("2.5.29.19", &[0x30, 0]),
            extension("2.5.29.15", &[0x03, 0x02, 0x07, 0x80]),
            extension(
                "2.5.29.37",
                &vec![ObjectIdentifier::new_unwrap("1.2.840.113635.100.4.9")]
                    .to_der()
                    .unwrap(),
            ),
            extension("1.2.840.113635.100.6.1.8", &[0x05, 0]),
        ]
    }

    #[test]
    fn accepts_the_installer_submission_profile() -> Result<()> {
        verify_extensions(&installer())
    }

    #[test]
    fn refuses_missing_repeated_noncritical_and_malformed_profile_extensions() {
        let valid = installer();
        for index in 0..valid.len() {
            let mut missing = valid.clone();
            missing.remove(index);
            assert!(verify_extensions(&missing).is_err(), "missing {index}");
            let mut repeated = valid.clone();
            repeated.push(valid[index].clone());
            assert!(verify_extensions(&repeated).is_err(), "repeated {index}");
            let mut noncritical = valid.clone();
            noncritical[index].critical = false;
            assert!(
                verify_extensions(&noncritical).is_err(),
                "noncritical {index}"
            );
            let mut malformed = valid.clone();
            malformed[index].extn_value = OctetString::new([0xff]).unwrap();
            assert!(verify_extensions(&malformed).is_err(), "malformed {index}");
        }
    }

    #[test]
    fn refuses_app_signing_ca_encipherment_and_other_installer_profiles() {
        let valid = installer();
        for replacement in [
            extension("2.5.29.19", &[0x30, 3, 1, 1, 0xff]),
            extension("2.5.29.19", &[0x30, 3, 2, 1, 1]),
            extension("2.5.29.15", &[0x03, 0x02, 0x05, 0x20]),
            extension("2.5.29.15", &[0x03, 0x02, 0x05, 0xa0]),
            extension(
                "2.5.29.37",
                &vec![ObjectIdentifier::new_unwrap("1.3.6.1.5.5.7.3.3")]
                    .to_der()
                    .unwrap(),
            ),
            extension(
                "2.5.29.37",
                &vec![ObjectIdentifier::new_unwrap("1.2.840.113635.100.4.10")]
                    .to_der()
                    .unwrap(),
            ),
            extension(
                "2.5.29.37",
                &vec![
                    ObjectIdentifier::new_unwrap("1.2.840.113635.100.4.9"),
                    ObjectIdentifier::new_unwrap("1.3.6.1.5.5.7.3.3"),
                ]
                .to_der()
                .unwrap(),
            ),
        ] {
            let mut invalid = valid.clone();
            let position = invalid
                .iter()
                .position(|item| item.extn_id == replacement.extn_id)
                .unwrap();
            invalid[position] = replacement;
            assert!(verify_extensions(&invalid).is_err(), "profile {position}");
        }
        for oid in ["1.2.840.113635.100.6.1.7", "1.2.840.113635.100.6.1.10"] {
            let mut invalid = valid.clone();
            invalid[3].extn_id = oid.parse().unwrap();
            assert!(verify_extensions(&invalid).is_err(), "marker {oid}");
        }
    }

    #[test]
    fn refuses_malformed_and_missing_certificate_data() {
        for bytes in [&[][..], &[0x30, 0], &[0xff], &[0x30, 3, 0x05, 0]] {
            assert!(verify(bytes).is_err());
        }
    }
}
