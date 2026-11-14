---
date: 2026-11-15
---

# Reuse signed packages before upload

## Status

Proposed.

## Context

A platform-only job can skip while signing succeeds, leaving inspection and upload skipped through [GitHub's dependency rules](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#jobsjob_idneeds).
The preserved signed package already has provenance and must remain the upload input.

## Decision

Use [cancellation-aware conditions](https://docs.github.com/en/actions/reference/workflows-and-actions/expressions#status-check-functions) with explicit successful prerequisites throughout native delivery.
Expose one reusable protected upload workflow for normal delivery and recovery of a preserved signed package.
Recovery requires a completed original run with successful signing and a skipped upload job.
Verify the original main workflow, signed bytes, embedded qualified candidate, checksums, and final SBOM before exposing upload credentials.

## Alternatives

Re-signing repeats a completed stage and can change the preserved bytes.
A separate recovery uploader duplicates the sensitive boundary.

## Consequences

Normal delivery and recovery share signature verification, validation, credentials, and upload behavior.
Recovery refuses every prior upload attempt.
Provider reconciliation remains a separate operation.

## Confirmation

Reject omitted status guards, failed or cancelled prerequisites, foreign origins, changed bytes, and attempted uploads.
Exercise all platforms on GitHub and recover the existing signed package without signing again.
Reconsider when a reconciled provider outcome can permit recovery of an attempted upload.
