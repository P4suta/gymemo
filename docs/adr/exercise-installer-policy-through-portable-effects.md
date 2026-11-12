---
date: 2026-11-12
---

# Exercise installer policy through portable effects

## Status

Proposed.

## Context

The mutation runner uses Linux.
Rust [conditional compilation](https://doc.rust-lang.org/reference/conditional-compilation.html#the-cfg-attribute) removes the macOS installer implementation and its tests there.
The campaign reported 71 missed mutations there.

## Decision

Compile the controller and its tests on both hosts.
Inject environment reads and Security framework operations through narrow ports.
Keep credential validation, filesystem refusal, identity validation, command failures, and preference recovery in the controller.
Measure those decisions in the bounded Linux mutation campaign.
Keep only direct Security framework translations in a macOS module.
Test that module on macOS and verify actual certificate import in the credential workflow.
State the platform boundary beside the mutation configuration.

## Alternatives

Leaving the controller behind macOS conditional compilation measures code the Linux tests can't execute.
A native macOS mutation campaign would cover the API adapter but conflicts with the required container runner.

## Consequences

Linux tests can't establish Security framework behavior.
The macOS tests and credential verification remain required.

## Confirmation

Reject each invalid input independently and test command, import, preference, and cleanup failures.
Run the affected mutation inventory and native tests.
Reconsider when the bounded runner supports macOS or the API module gains policy decisions.
