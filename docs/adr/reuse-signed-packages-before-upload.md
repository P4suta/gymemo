---
date: 2026-11-15
---

# Reuse signed packages before upload

## Status

Proposed.

## Context

Optional jobs skipped inspection after successful signing.
A credential-purpose failure also prevented either provider step.

## Decision

Use [cancellation-aware conditions](https://docs.github.com/en/actions/reference/workflows-and-actions/expressions#status-check-functions) and explicit prerequisites.
Share one protected upload workflow for normal delivery and recovery.
Pass five named upload secrets, as [GitHub requires](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows#using-inputs-and-secrets-in-a-reusable-workflow).
Recover preserved bytes after successful signing and complete evidence of no provider transfer.
Accept failed credential-purpose checks only when both provider steps are completed and skipped.
Verify origin, candidate qualification, provenance, checksums, and SBOM before credentials.

## Alternatives

Re-signing changes preserved bytes.
Separate uploaders duplicate sensitive code.

## Consequences

Recovery depends on exact provider step names.
Attempted or unknown transfers require provider reconciliation.

## Confirmation

Reject missing secrets, incomplete history, changed bytes, and attempted transfers.
Exercise all platforms and recover the existing signed package.
Reconsider when reconciliation can permit a repeated transfer.
