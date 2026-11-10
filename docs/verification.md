# Verification

gymemo checks its rules with the package tests, source checks, mutation runs, a Lean model, and Kani harnesses.
`AGENTS.md` names the commands, and each section below says what a run establishes and what it leaves open.
`docs/adr/prove-the-log-rules-in-a-lean-model.md` records the choice of the model.

## The fast gate

`mise x -- just check` runs the lint, the source checks of `xtask`, the package tests, and a simulator build.
The source checks refuse text outside the String Catalog, effects in the pure core, console output, and networking.
They also refuse a required reason API without a declared reason and a color or a material outside the system design.
They read the Swift sources through one lexer in `xtask/src/swift_source.rs`, which follows the lexical grammar of Swift for comments, string literals, interpolation, raw strings, regular expression literals, and raw identifiers.
The grammar leaves the reading of a bare regular expression literal to the compiler, so the lexer follows the rules of the compiler.
The doc comments of the lexer name the source of each rule.
The module doc of the lexer lists the known exceptions, each with an example, and its `fixture` module holds the planted sources of each family.
A test of each check plants a violation behind each construct and expects the refusal on the right line.

## Mutation runs of the package

`mise x -- just mutate` runs swift-mutation-testing over `Sources` with every operator of its experimental tier.
The tool changes one place at a time and runs the package tests on each change, and `xtask` reads the report.
The run passes when the tests detected every change or the change failed to compile.
A change that the tests miss fails the run with its file, line, and operator.
A change that reached the timeout of 90 seconds, or a change that the tests detected without running the changed code, leaves the run inconclusive with exit code 75.
The package tests finish within 5 seconds, so a timeout reports a change that keeps the tests from ending, never a slow host.

The run covers `Sources` and leaves `App` out.
The UI tests are the only tests of `App`, and one pass of them takes about 16 minutes, so one change there costs more than a whole run over `Sources`.
A probe over `App/AppModel.swift` reported 2 changes without coverage after 48 minutes and 30 seconds.
The screens get their rules from `GymemoCore`, which the run covers, and the UI tests exercise the screens in four appearances.

## Mutation runs of xtask

`mise x -- just mutate-xtask` runs cargo-mutants over the `xtask` package inside the Rust image, in shards of at most 100 mutants, and reads the files that each shard wrote.
The run passes when the tests caught every mutant, none timed out, and the shards account for every listed mutant.
`.cargo/mutants.toml` fixes the timeouts and holds one exclusion: the Kani harnesses in the `proofs` module of `xtask/src/swift_source.rs`, which compile under `cfg(kani)` alone, so no test can tell a mutant there from the source.
The file states the evidence and the condition for reconsidering the exclusion.

## Proofs

`mise x -- just proofs` runs six steps and stops at the first one that fails or stays inconclusive.
It checks that `specs/lean/lean-toolchain` and the Lean image pin the same release, and that `specs/lean/Gymemo.lean` imports every module file and nothing else.
It builds the library with `lake build --wfail`, so a warning such as `sorry` fails the build.
It runs `specs/lean/Axioms.lean`, which lists every declaration of the library whose type is a proposition with the axioms under it.
It refuses any axiom beyond `propext`, `Classical.choice`, and `Quot.sound`, any axiom that the library declares, and any theorem of the sources that the listing lacks.
It replays the root module and every module through `leanchecker --fresh`, so the kernel checks each declaration again from its stored form.
It verifies the Kani harnesses of `xtask` and requires that the harnesses the sources declare, the ones Kani lists, and the ones Kani verifies are the same set.

The Lean model in `specs/lean` states `TrainingLog.apply`, the row changes, the invariants, the strength estimate, and the steppers.
The theorems show that every accepted command keeps the invariants and that the returned changes rebuild the new log.
The package tests write the results of the Swift code as vectors, `mise x -- just gen` stores them under `specs/lean/Gymemo`, and the kernel checks that the model gives each stored result.
A package test fails while a stored vector differs from the Swift results.

The model simplifies the code in ways that the vectors can't observe.
Identifiers are numbers, texts are numbers of a table, and parse results are inputs.
A day is its number of days since 1970, and a Swift test pins the rendering to that number.
The SQLite store, the backup format, and the CSV export have no model, and the package tests cover them.
A change that the vectors can't tell apart, such as a relaxed `Admissible` or a `<` turned into `≤` in the memo days, fails the hand-written proofs instead.

Four Kani harnesses cover the lexer of `xtask/src/swift_source.rs` on every source of up to three characters, where each character is any Unicode scalar value.
A test runs every source of up to four characters over 31 characters, one for each set of characters that the lexer reads alike.
Another test runs every source of up to five characters over the 17 characters that open and close the constructs of the lexer.
A third test holds each character outside the 31 to its stand-in on sources of up to three characters.
No source over those characters spells a keyword, and a test with expected values from swiftc holds the reading after each keyword instead.

## Bounded runs

lean, lake, cargo-kani, and cargo-mutants run only in containers that `xtask` builds from `xtask/proofs/lean/Dockerfile` and `xtask/proofs/rust/Dockerfile`.
Each container gets 2 CPUs, 2 GiB of memory without swap, 256 processes, 900 seconds, and no network.
A run that reaches the time limit or the memory limit ends the command with a message that starts with `INCONCLUSIVE` and exit code 75.
That outcome is neither a pass nor a failure.
`xtask` removes each container after every outcome, and the listing and the replay steps mount the repository without write access.
The gates catch the mistakes and unsound shortcuts of a cooperating contributor, and they don't withstand a committer who writes code to detect or deceive them.
Two runs at a time share the image names, so the campaigns run one at a time.

## Interface tests and sanitizers

`mise x -- just ui-test` runs the UI scenarios and the accessibility audits in the light and the dark appearance, and in both with Increase Contrast.
`mise x -- just sanitize` runs the package tests under the address and thread sanitizers.
