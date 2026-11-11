---
date: 2026-11-11
---

# Derive build and store versions from one source

## Status

Proposed.

## Context

Apple requires [three numeric components](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleshortversionstring).
Build settings, store metadata, and delivery must agree.

## Decision

Keep `Config/MarketingVersion.txt` as the canonical marketing version, initially `1.0.0`.
Generate Xcode settings and store paths.
Keep localized text at stable source paths.
Use [release-please](https://github.com/googleapis/release-please-action) for separate manual version proposals and unpublished release drafts.
Create the source tag with each draft to provide the next proposal's baseline.
Select platform delivery independently and use GitHub's [repository-wide run identifier](https://docs.github.com/en/actions/reference/workflows-and-actions/variables) as Apple's [numeric build string](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleversion).
Retries preserve that identifier.

## Alternatives

Repeated fields can drift.
Separate platform versions add coordination.
Proposals alone need separate baseline and label reconciliation.

## Consequences

Tagged drafts fix their source revision.
Later source changes require another version.
App Store delivery and GitHub publication remain separate.

## Confirmation

Reject malformed versions and mismatched bundles.
Validate generated metadata and a real proposal.
Reconsider when platforms need separate versions.
