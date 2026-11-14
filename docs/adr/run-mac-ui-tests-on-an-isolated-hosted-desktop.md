---
date: 2026-11-14
---

# Use an isolated desktop for native tests

## Status

Proposed.

## Context

Mac tests followed another foreground app on the shared desktop.
[App Intents Testing](https://developer.apple.com/documentation/appintentstesting/testing-your-app-intents-code) requires a live app and the same signing team.

## Decision

Run the complete Mac UI suite on demand on a [fresh GitHub-hosted Mac](https://docs.github.com/en/actions/concepts/runners/github-hosted-runners).
Build without secrets, sign preserved products in the protected native-signing environment, then test in a separate job without signing credentials.
Verify source-bound provenance and sign [inside out](https://developer.apple.com/library/archive/technotes/tn2206/_index.html).
Require a successful exact-source run before local qualification starts its remaining checks.
Keep simulator tours, sanitizers, mutation testing, and proofs local.

## Alternatives

Reserving the shared desktop interrupts other work.
Ad hoc signing doesn't establish the genuine matching team.

## Consequences

Mac qualification consumes hosted minutes and a protected signing approval.
The local command remains available for scheduled diagnosis.

## Confirmation

Reject absent, failed, incomplete, or different-source runs.
Require every Mac test to pass without skips and verify the actual protected workflow.
Reconsider when a private desktop becomes available.
