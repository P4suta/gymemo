# Verification

gymemo checks its rules with the package tests, source checks, mutation runs, a Lean model, and Kani harnesses.
`AGENTS.md` names the commands, and each section below says what a run establishes and what it leaves open.
`docs/adr/prove-the-log-rules-in-a-lean-model.md` records the choice of the model.

## The fast gate

`mise x -- just check` runs the native, website, store metadata, and workflow checks.
`mise x -- just check-native` runs the lint, the source checks of `xtask`, the package tests, and builds for iOS, macOS, watchOS, and visionOS.
`mise x -- just check-website` checks types, HTML, CSS, localization, browser interactions, and the deployment dry run.
`mise x -- just lint-workflows` checks GitHub Actions syntax and security.
`mise x -- just check-store` validates the public App Store metadata without credentials or network access.
`mise x -- just check-dependencies` checks Rust advisories, licenses, and registries.
The website gate also audits its locked npm dependencies.
Pull requests and merge groups run the affected fast checks in hosted CI.
Mutation runs, proofs, sanitizers, and simulator tours run locally before release.
The source checks refuse text outside the String Catalog, effects in the pure core, console output, and server or cloud APIs.
Only `App/CompanionSession.swift` can import Watch Connectivity or use `WCSession`.
They also refuse a required reason API without a declared reason and a color or a material outside the system design.
They read the Swift sources through one lexer in `xtask/src/swift_source.rs`, which follows the lexical grammar of Swift for comments, string literals, interpolation, raw strings, regular expression literals, and raw identifiers.
The grammar leaves the reading of a bare regular expression literal to the compiler, so the lexer follows the rules of the compiler.
The doc comments of the lexer name the source of each rule.
The module doc of the lexer lists the known exceptions, each with an example, and its `fixture` module holds the planted sources of each family.
A test of each check plants a violation behind each construct and expects the refusal on the right line.

## Accessibility audits

Privacy tours bind each newly reached fact to a captured text frame.
With Increase Contrast, the image check requires at least 4.5:1 for every fully visible body text and navigation title, using the [Web Content Accessibility Guidelines contrast calculation](https://www.w3.org/TR/WCAG22/#dfn-contrast-ratio).
Missing reached facts, ambiguous measurements, and insufficient contrast fail the check.
The [iOS 26.4 Simulator contrast audit timeout](https://github.com/P4suta/gymemo/issues/27) also occurs when contrast runs alone.
Privacy tours measure contrast from rendered pixels and keep the remaining [Apple accessibility audits](https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app).
Other screens keep the SDK contrast audit and their existing measured checks.

## Local release qualification

`mise x -- just qualify SHA FLOOR IPAD DUO WATCH VISION` prints the complete local check plan without running a check or changing GitHub.
`SHA` is a full commit identifier.
The remaining arguments are available simulator identifiers for an iPhone on iOS 26, an iPad, iPhone Duo, Apple Watch, and Vision Pro.
`xcrun simctl list devices available` lists those identifiers.

Adding `--run` requires a clean checkout of that commit and confirms that the commit already belongs to the public repository's `main` branch.
The command checks device types and runtimes before starting expensive work.
It runs the fast gate, both iPhone runtime tours, native platform scenarios, Watch scenarios, sanitizers, both mutation campaigns, and proofs in order.
Swift mutation testing uses two workers.
The command checks the source again after every step and reports `Local qualification` on that commit through GitHub's commit status API.
A failed, interrupted, or inconclusive step never reports success.
Distribution signing and upload run in the separate native delivery workflow.

`mise x -- just require-qualification SHA` requires the most recently created `Local qualification` status for that exact source commit to report success under the repository owner's identity.
An older success can't override a more recent failure.
The command refuses a status linked to another source commit.
The command only reads [GitHub commit statuses](https://docs.github.com/en/rest/commits/statuses).

## Native candidates and delivery

The native candidate workflow selects iOS with its companion Watch app, macOS, or visionOS.
The archive uses the repository-wide GitHub run identifier as its build number and keeps that identity on retries.
`mise x -- just seal-native PLATFORM SHA RUN` checks the archive's bundle identifiers, versions, deployment floors, architectures, and privacy manifests.
It inventories the archived dependencies with Syft and preserves the archive, CycloneDX SBOM, and typed candidate manifest.
The workflow attests the preserved bytes.

`mise x -- just verify-native PLATFORM SHA RUN` rechecks qualification, the successful build run, provenance, checksums, and SBOM before signing.
The protected signing job uses the selected distribution identities in temporary keychains and exports from that preserved archive.
`mise x -- just install-mac-installer KEYCHAIN PASSWORD_FILE CERT_SHA256` plans the import without reading credentials.
With `--confirm`, the command reads the installer certificate and password from the protected `gymemo/ci_native_signing` environment.
It requires one identity with the Mac App Store installer subject, its private key, the expected certificate fingerprint, and basic certificate trust.
It checks the critical extensions of Apple's [installer submission profile](https://images.apple.com/certificateauthority/pdf/Apple_WWDR_CPS_v1.32.pdf#page=34), including digital signatures, package signing, and the installer marker.
The delivery job validates the exported package signature with `pkgutil --check-signature` after signing.
The new keychain preserves the default keychain and search list unless `--add-to-search-list` requests activation.
A failed import restores the search policy and deletes its own keychain.
Both credential verification and delivery build the importer in a separate job without signing secrets and verify its provenance before use.
Artifacts passed across approval gates stay available for 35 days, matching GitHub's [workflow execution limit](https://docs.github.com/en/actions/reference/limits).
visionOS uses explicit export options because the provider CLI can't generate its manual signing options.
A fresh job validates the signed package's dependency inventory and checksums.
The upload job requires its own approval and App Store Connect key and receives the verified bytes.
An uncertain upload requires provider reconciliation before retrying.

## Version preparation

`Config/MarketingVersion.txt` supplies the marketing version for every app target.
`mise x -- just generate` derives the Xcode configuration, and `mise x -- just prepare-store-metadata` derives the store directory under `target/app-store/`.
Localized text stays in `metadata/app-store/` without a version in its source paths.

Select `check-access`, `propose`, or `draft` in the version preparation workflow.
The draft operation creates the source tag and an unpublished GitHub release draft after the version PR merges.
The tag provides release-please's baseline for later proposals without publishing the draft.
A tagged source revision stays fixed.
App Store delivery remains independent of GitHub draft creation.
An empty first manifest marks the app as unreleased.

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
The runner fixes `--gitignore=true` and refuses caller overrides, so ignored build caches stay outside the copied tree.
The [copying policy](https://mutants.rs/build-dirs.html) otherwise leaves Git ignore filtering off by default.
Linux build outputs stay in the container's `/tmp/gymemo-target`, apart from native build outputs.
The run passes when the tests caught every mutant, none timed out, and the shards account for every listed mutant.
`.cargo/mutants.toml` fixes the timeouts and excludes the Kani harnesses, which compile under `cfg(kani)` alone.
It also excludes only the five Security framework translation functions in `xtask/src/mac_installer/native/security.rs`.
Linux can't execute those macOS API effects.
The portable installer controller keeps credential, destination, identity, preference, and cleanup decisions inside the measured scope.
A Rust syntax check rejects branches, comparisons, loops, macros, and selected predicate methods in the platform translation.
Native Mac tests exercise a disposable keychain, wrong-password refusal, invalid import, lock settings, and restored preferences without reading owner credentials.
The dedicated credential workflow verifies actual certificate import.
The configuration states each platform boundary and its condition for reconsideration.

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
The SQLite store, paired-device protocol and queue, backup format, and CSV export have no Lean model, and the package tests cover them.
A change that the vectors can't tell apart, such as a relaxed `Admissible` or a `<` turned into `≤` in the memo days, fails the hand-written proofs instead.

Four Kani harnesses cover the lexer of `xtask/src/swift_source.rs` on every source of up to three characters, where each character is any Unicode scalar value.
A test runs every source of up to four characters over 31 characters, one for each set of characters that the lexer reads alike.
Another test runs every source of up to five characters over the 17 characters that open and close the constructs of the lexer.
A third test holds each character outside the 31 to its stand-in on sources of up to three characters.
No source over those characters spells a keyword, and a test with expected values from swiftc holds the reading after each keyword instead.

## Bounded runs

lean, lake, cargo-kani, and cargo-mutants run only in containers that `xtask` builds from `xtask/proofs/lean/Dockerfile` and `xtask/proofs/rust/Dockerfile`.
Each container gets 2 CPUs, 2 GiB of memory without swap, 256 processes, 900 seconds, and no network.
Before building the Rust image, the runner fetches the locked dependencies into `target/verification-cargo` on the host.
Rust containers mount only that cache's registry without write access and set `CARGO_NET_OFFLINE=true`.
The registry cache uses its own Cargo home.
A run that reaches the time limit or the memory limit ends the command with a message that starts with `INCONCLUSIVE` and exit code 75.
That outcome is neither a pass nor a failure.
`xtask` removes each container after every outcome, and the listing and the replay steps mount the repository without write access.
The gates catch the mistakes and unsound shortcuts of a cooperating contributor, and they don't withstand a committer who writes code to detect or deceive them.
Two runs at a time share the image names, so the campaigns run one at a time.

## Interface tests and sanitizers

`mise x -- just ui-test` runs the UI scenarios and the accessibility audits in the light and the dark appearance, and in both with Increase Contrast.
`FontTests` checks that public Core Text APIs map sample characters for all four supported languages without missing glyphs.
Screenshots and accessibility labels don't replace that rendering prerequisite.
The settings growth check accepts 1 image pixel at viewport boundaries for fractional accessibility frames.
The check derives pixel size in [logical points](https://developer.apple.com/documentation/uikit/uiscreen/scale) from the app frame and screenshot dimensions.
Larger overlaps, empty frames, and invalid geometry fail the check.
`mise x -- just sanitize` runs the package tests under the address and thread sanitizers.

`mise x -- just native-test -destination 'platform=macOS,arch=arm64'` checks Mac navigation, range selection, standard keyboard commands, Return, Escape, Undo, and Redo.
The Mac App Intents tests require [the same development signing team](https://developer.apple.com/documentation/appintentstesting/testing-your-app-intents-code) for the app and its UI test runner.
Set `DEVELOPMENT_TEAM` in the ignored `Signing.local.xcconfig` to select the local development identity.
Xcode [registers Mac build products](https://github.com/swiftlang/swift-build/blob/main/Sources/SWBTaskConstruction/TaskProducers/OtherTaskProducers/ProductPostprocessingTaskProducer.swift#L649-L674) with Launch Services.
The fast Mac build and native tests share `target/native-test-build`, so a signed test build replaces the unsigned app at the same registered path.
The native test command cleans that build directory before rebuilding to replace unsigned preview libraries as well.
Past builds with the same bundle identifier can conflict with App Intents discovery.
XCTest may ask for macOS authentication to enable UI automation.
The same command accepts an iPad, iPhone Duo, or visionOS Simulator destination from `xcodebuild -showdestinations -scheme gymemoNative`.
Its history and analysis scenarios check the selected detail and keep screenshots.
The iOS and visionOS runs audit control descriptions and element detection.
Swift Charts draws axis text without separate elements, and the audit accepts reports without an element only while the progress chart is present.
Each chart mark still has a spoken date and value, and the session list supplies the underlying sets as text.

`mise x -- just watch-test -destination DESTINATION` runs the Watch scenarios with a paired destination from `xcodebuild -showdestinations -scheme gymemoWatch`.
The fixture disables transport and uses a separate journal.
It checks spoken input values, the local privacy policy, and a pending set after process termination and relaunch.
The protocol and SQLite tests cover duplicate delivery, conflicting identifiers, failed commits, schema migration, malformed files, queue bounds, and stale receipts.
Apple requires [paired hardware](https://developer.apple.com/documentation/watchconnectivity/wcsession/transferuserinfo(_:)) for background-transfer validation.
Simulator success doesn't establish background delivery, installation through TestFlight, or Vision Pro comfort.
