---
date: 2026-11-10
---

# Prove the log's rules in a Lean model

## Status

Proposed on 2026-11-10, and the owner hasn't reviewed this choice.

## Context

Property tests sample command sequences, and a lost or repeated row would damage the lifter's records.
No verifier reads Swift code.

## Decision

`specs/lean` states `TrainingLog.apply`, the row changes, and the invariants as a Lean 4 model.
Lean proves that every accepted command keeps the invariants and that the returned changes rebuild the new log.
The package tests write results of the Swift code as vectors, and Lean's kernel checks that the model gives the same results.

## Alternatives

Property tests alone, the status quo, cover no more than their samples.
Kani checks Rust and can't read the Swift core.

## Consequences

The theorems hold for the model, and a difference from the Swift code outside the vectors stays possible.
A changed rule changes the code, the model, and the vectors together.

## Confirmation

`mise x -- just proofs` holds every theorem to Lean's standard axioms.
`mise x -- just check` fails when the vectors differ from the Swift results.
Reconsider when a verifier for Swift code exists.
