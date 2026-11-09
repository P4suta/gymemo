---
date: 2026-11-09
---

# Derive every screen from one immutable training log

## Status

Accepted by the owner with the implementation plan on 2026-11-09.

## Context

The rules for suggested values, personal bests, and weekly counts need tests that run without a simulator.
A screen must never show a set that the file doesn't hold.

## Decision

`GymemoCore` holds the whole log as one immutable value.
A command returns a new value with the row changes to store, or a named refusal.
The app stores the changes in one transaction and only then shows the new value.
Every screen computes its content from that value and today's date with pure functions.
The store reads all rows at launch.

## Alternatives

Querying the database for each screen keeps memory constant.
It moves the rules into SQL, beyond the reach of the purity check and the property tests.

## Consequences

Memory and launch time grow with the number of sets, estimated at 52,000 after ten years.
Each change rebuilds the value's indexes.

## Confirmation

The purity check refuses effects in the core, and property tests cover random command sequences.
Reconsider when loading 50,000 sets takes over half a second on the lifter's phone.
