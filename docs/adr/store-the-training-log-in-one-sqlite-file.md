---
date: 2026-11-09
---

# Store the training log in one SQLite file

## Status

Accepted by the owner with the implementation plan on 2026-11-09.

## Context

A logged set must survive the app's exit right after the tap.
Ten years of training is about 52,000 sets by estimate.

## Decision

Keep one SQLite file in Application Support through the system library.
Each operation writes its rows in one `BEGIN IMMEDIATE` transaction, which SQLite documents as [atomic and durable](https://www.sqlite.org/transactional.html).
Every connection sets `foreign_keys` on and `synchronous` to `EXTRA`, as the [pragma reference](https://www.sqlite.org/pragma.html) advises for durability.
`user_version` numbers the schema, and the store refuses an unknown number.
`CHECK` constraints validate rows, because `STRICT` needs SQLite 3.37.0, unverified on iOS 18.

## Alternatives

SwiftData needs the least code, and it manages mutable model objects in a context, against the immutable core.
One JSON file rewritten per change is simplest, and it rewrites megabytes for each set at that size.

## Consequences

The adapter calls a C API through pointers and maintains migrations by hand.

## Confirmation

Contract tests compare reloaded files with the in-memory log, and `mise x -- just sanitize` runs them under sanitizers.
Reconsider when a feature needs concurrent writers.
