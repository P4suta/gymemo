---
date: 2026-11-15
status: Proposed
---

# Restore Mac sandbox permissions before export

## Context

The unsigned Mac archive has no entitlements.
The qualified source declares App Sandbox and user-selected file access, and the hosted UI build includes both.
[Apple requires App Sandbox for Mac App Store distribution](https://developer.apple.com/documentation/security/app-sandbox).

## Decision

Read the entitlements from the qualified source commit and apply an ad hoc signature to the extracted app before [Xcode export](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac).
Select the installed distribution profile explicitly and inspect the exported package's sandbox permissions before preservation.
Keep the original archive and build identity.

## Alternatives

A fresh archive would repeat qualification for unchanged app sources.
Manual packaging would replace Apple's recommended Xcode export for an Xcode app.
Retaining the current export would omit required permissions.

## Consequences

The signing stage needs the qualified entitlements file.
No developer certificate or additional permission is required.
The [CI packaging proposal](sign-mac-packages-with-apple-tools.md) addresses Xcode export timeouts.

## Confirmation

Reject missing preparation and permissions in regression fixtures.
Confirm the protected export, final signature, entitlements, and App Store processing.
Reconsider when the app gains nested executable code.
