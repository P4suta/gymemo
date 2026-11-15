use super::{ImportedIdentity, KeychainApi, Request, execute, imported_identities, variable};
use crate::{
    failure::{Context, Result},
    host::Host,
};
use base64::{Engine as _, engine::general_purpose::STANDARD};
use security_framework::os::macos::keychain::{CreateOptions, KeychainSettings, SecKeychain};
use std::{
    path::{Path, PathBuf},
    process::Command,
};

struct Framework {
    importer: PathBuf,
}

struct InstallerKeychain {
    handle: SecKeychain,
    path: PathBuf,
}

impl KeychainApi for Framework {
    type Keychain = InstallerKeychain;

    fn create(&mut self, path: &Path, password: &str, prompt_user: bool) -> Result<Self::Keychain> {
        CreateOptions::new()
            .password(password)
            .prompt_user(prompt_user)
            .create(path)
            .context(|| "Create the dedicated installer keychain".into())
            .map(|handle| InstallerKeychain {
                handle,
                path: path.to_path_buf(),
            })
    }

    fn unlock(&mut self, keychain: &mut Self::Keychain, password: &str) -> Result<()> {
        keychain
            .handle
            .unlock(Some(password))
            .context(|| "Unlock the installer keychain".into())
    }

    fn import(
        &mut self,
        keychain: &Self::Keychain,
        data: &[u8],
        password: &str,
        trusted_tool: &Path,
    ) -> Result<Vec<Option<ImportedIdentity>>> {
        let output = Command::new(&self.importer)
            .arg(&keychain.path)
            .arg(trusted_tool)
            .env_clear()
            .env("GYMEMO_PKCS12_BASE64", STANDARD.encode(data))
            .env("GYMEMO_PKCS12_PASSWORD", password)
            .output()
            .context(|| "Run the native installer import tool".into())?;
        imported_identities(output.status.success(), &output.stdout)
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
            .handle
            .set_settings(&settings)
            .context(|| "Set the installer keychain lock policy".into())
    }
}

pub(in crate::mac_installer) fn run(host: &mut impl Host, request: &Request) -> Result<()> {
    let _interaction = SecKeychain::disable_user_interaction()
        .context(|| "Disable interactive keychain prompts".into())?;
    let importer = std::env::current_exe()
        .context(|| "Locate the installer controller".into())?
        .with_file_name("installer-import");
    execute(host, request, &mut Framework { importer }, variable)
}

#[cfg(test)]
mod tests;
