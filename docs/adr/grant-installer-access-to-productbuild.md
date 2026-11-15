---
date: 2026-11-15
status: Proposed
---

# Grant installer access to productbuild

## Context

App signing passes, but productbuild times out.
The default [keychain access policy](https://developer.apple.com/documentation/security/secaccesscreate(_:_:_:)) trusts the importing process for signing.
The pinned Rust wrapper lacks a safe access constructor.

## Decision

Use a small Swift Security bridge to import the installer identity with the trusted tool selected by the Rust controller.
Build and attest both executables before signing inputs, then verify both before import.
Pass private inputs through the child environment and return only public certificate metadata.
Keep identity validation and rollback in Rust.

## Alternatives

Default access leaves productbuild untrusted.
The security command's legacy importer doesn't support every modern PKCS#12 encoding.
Direct unsafe Rust bindings conflict with the crate's safety policy.

## Consequences

Dedicated keychain files use Apple's [file-based access model](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains), isolated in the bridge.
The build gains one native executable.

## Confirmation

Require disposable-keychain tests of valid and invalid import and stored tool access, workflow contracts, successful package signatures, and App Store processing.
Reconsider when the Rust wrapper supports explicit access or Apple replaces file-based signing keychains.
