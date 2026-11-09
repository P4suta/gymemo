set shell := ["sh", "-eu", "-c"]

swift_paths := "Package.swift Sources Tests App UITests"
project := "gymemo.xcodeproj"

default:
    @just --list

# Writes gymemo.xcodeproj from project.yml.
generate:
    xcodegen generate --quiet

# Rewrites the Swift and Rust sources in the checked style.
format:
    xcrun swift-format format --in-place --recursive {{ swift_paths }}
    cargo fmt

lint:
    xcrun swift-format lint --strict --recursive {{ swift_paths }}
    swiftlint lint --strict --quiet
    gitleaks dir --no-banner --redact --config .gitleaks.toml .
    cargo fmt --check
    cargo clippy --locked --all-targets -- -D warnings

# Tests the source checks, then runs them over the Swift sources.
gates:
    cargo test --locked
    cargo run --locked -p xtask -- gates

test:
    swift test

build: generate
    xcodebuild build -project {{ project }} -scheme gymemo -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData -quiet

# The fast gate: static checks, package tests, and a simulator build.
check: lint gates test build

# Runs the UI scenarios and accessibility audits on the dedicated simulator.
[positional-arguments]
ui-test *args: generate
    cargo run --locked -p xtask -- ui-test "$@"

# Builds the app and opens it on the dedicated simulator, passing arguments to the app.
[positional-arguments]
app *args: generate
    cargo run --locked -p xtask -- app "$@"

# Exports the screenshots that the latest UI test run kept.
screenshots:
    cargo run --locked -p xtask -- screenshots

# Mutates the package sources and reports each change that the package tests miss.
[positional-arguments]
mutate *args:
    swift-mutation-testing run . "$@"

# Runs the package tests under the address and thread sanitizers.
sanitize:
    swift test --sanitize=address
    swift test --sanitize=thread
