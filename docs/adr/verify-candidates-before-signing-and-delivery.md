---
date: 2026-11-11
---

# Verify candidates before signing and delivery

## Status

Proposed.

## Context

The owner requests public source and CI/CD with independent native and website operations.

## Decision

Use GitHub Actions for checks and delivery.
Run fast checks on pull requests and merge groups.
Run mutation, proof, and simulator checks locally for the exact source commit.
Record the result as a commit status through the verification command.
Bind candidates to an immutable source commit and their artifact digests.
Build without credentials.
Use separate protected jobs for signing, upload, submission, app release, and website publication.
Use a Doppler OIDC identity for website publication.
Use Doppler's native GitHub Secrets sync for native environments because the workplace uses all 50 workload identities.
Protect both credential paths with environment approvals and branch restrictions.
Confirm provider state and preserve candidate identity.

## Alternatives

Cloudflare's Git builds cover the website alone.
Local publication depends on one Mac and its credential state.

## Consequences

Delivery requires artifact validation and scoped authentication.
Physical Watch and Vision Pro acceptance remains separate from hosted simulator checks.

## Confirmation

Test failed prerequisites, malformed identities, changed artifacts, and repeated operations.
Verify the actual hosted pipelines before reporting automation complete.
Reconsider when another distribution target changes the trust boundary.
