---
date: 2026-11-15
status: Proposed
---

# Sign Mac packages with Apple tools

## Context

Three Xcode exports timed out after 20 minutes.
The qualified archive contains one executable app.
The expected certificates and distribution profile resolve without errors.

## Decision

Use `codesign` and `productbuild` in CI, following Apple's [Mac App Store packaging procedure](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution).
Sign the extracted app with its qualified sandbox permissions and profile identity, then package it with the verified installer certificate.
Keep the original archive, build number, signature checks, dependency inventory, and separate upload approval.
Bound the native commands to five minutes.

## Alternatives

Xcode is the preferred exporter for an Xcode app but hasn't completed.
A longer timeout supplies no evidence of progress.
A fresh archive changes the qualified input without addressing export.

## Consequences

Native command output identifies the signing or packaging phase.
The pipeline must preserve profile identity and entitlement checks.

## Confirmation

Require regression fixtures, both signatures, sandbox permissions, provenance, and successful App Store processing.
Reconsider when Xcode export works or the app gains nested code.
