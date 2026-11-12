use super::{ImportedIdentity, KeychainApi, Request, execute, variable};
use crate::{
    failure::{Context, Result},
    host::Host,
};
use security_framework::{
    import_export::Pkcs12ImportOptions,
    os::macos::keychain::{CreateOptions, KeychainSettings, SecKeychain},
};
use std::path::Path;

struct Framework;

impl KeychainApi for Framework {
    type Keychain = SecKeychain;

    fn create(&mut self, path: &Path, password: &str, prompt_user: bool) -> Result<Self::Keychain> {
        CreateOptions::new()
            .password(password)
            .prompt_user(prompt_user)
            .create(path)
            .context(|| "Create the dedicated installer keychain".into())
    }

    fn unlock(&mut self, keychain: &mut Self::Keychain, password: &str) -> Result<()> {
        keychain
            .unlock(Some(password))
            .context(|| "Unlock the installer keychain".into())
    }

    fn import(
        &mut self,
        keychain: &Self::Keychain,
        data: &[u8],
        password: &str,
    ) -> Result<Vec<Option<ImportedIdentity>>> {
        Pkcs12ImportOptions::new()
            .keychain(keychain.clone())
            .passphrase(password)
            .import(data)
            .context(|| "Import the installer identity".into())?
            .into_iter()
            .map(|item| {
                item.identity
                    .map(|identity| {
                        let certificate = identity
                            .certificate()
                            .context(|| "Read the imported installer certificate".into())?;
                        Ok(ImportedIdentity {
                            der: certificate.to_der(),
                            subject: certificate.subject_summary(),
                            private_key: identity.private_key().is_ok(),
                        })
                    })
                    .transpose()
            })
            .collect()
    }

    fn settings(
        &mut self,
        keychain: &mut Self::Keychain,
        lock_on_sleep: bool,
        interval: u32,
    ) -> Result<()> {
        let mut settings = KeychainSettings::new();
        settings.set_lock_on_sleep(lock_on_sleep);
        settings.set_lock_interval(Some(interval));
        keychain
            .set_settings(&settings)
            .context(|| "Set the installer keychain lock policy".into())
    }
}

pub(in crate::mac_installer) fn run(host: &mut impl Host, request: &Request) -> Result<()> {
    let _interaction = SecKeychain::disable_user_interaction()
        .context(|| "Disable interactive keychain prompts".into())?;
    execute(host, request, &mut Framework, variable)
}

#[cfg(test)]
mod tests;
