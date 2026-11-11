set shell := ["sh", "-eu", "-c"]

swift_paths := "Package.swift Sources Tests App UITests"
project := "gymemo.xcodeproj"

default:
    @just --list

# Installs the website verification dependencies.
setup:
    cd website && mise x -- npm ci --ignore-scripts

# Checks workflow syntax and security.
lint-workflows:
    actionlint
    zizmor --pedantic --offline .github/workflows

# Validates public App Store metadata without contacting App Store Connect.
check-store:
    cargo run --locked -p xtask -- check-store

# Inspects and preserves an unsigned archive and its dependency inventory.
[positional-arguments]
seal-native *args:
    cargo run --locked -p xtask -- seal-native "$@"

# Verifies the selected candidate before a protected signing operation.
[positional-arguments]
verify-native *args:
    cargo run --locked -p xtask -- verify-native "$@"

# Checks the Rust dependency advisories, licenses, and registries.
check-dependencies:
    cargo deny --manifest-path xtask/Cargo.toml --config xtask/deny.toml check

# Validates the product, version, and dependency scope of a preserved SBOM.
[positional-arguments]
check-sbom *args:
    cargo run --locked -p xtask -- check-sbom "$@"

# Prepares localized metadata for the canonical app version without contacting the store.
prepare-store-metadata:
    cargo run --locked -p xtask -- prepare-store-metadata

# Plans the website identity setup; --apply enables the reviewed provider changes.
[positional-arguments]
setup-delivery *args:
    cargo run --locked -p xtask -- setup-delivery "$@"

# Reads delivery integration metadata without changing provider resources.
[positional-arguments]
inspect-delivery *args:
    cargo run --locked -p xtask -- inspect-delivery "$@"

# Plans native credential syncs; --apply enables the reviewed provider changes.
[positional-arguments]
setup-native-delivery *args:
    cargo run --locked -p xtask -- setup-native-delivery "$@"

# Writes gymemo.xcodeproj from project.yml.
generate:
    cargo run --locked -p xtask -- generate-version
    xcodegen generate --quiet

# Renders the shared vector layers for the visionOS texture stack with ImageMagick.
icons:
    magick -background none App/AppIcon.icon/Assets/Bar.svg -resize 1024x1024 Config/VisionAssets.xcassets/AppIcon.solidimagestack/Front.solidimagestacklayer/Content.imageset/Bar.png
    magick -background none App/AppIcon.icon/Assets/Plates.svg -resize 1024x1024 Config/VisionAssets.xcassets/AppIcon.solidimagestack/Middle.solidimagestacklayer/Content.imageset/Plates.png
    magick Config/IconLayers/VisionBackground.svg -resize 1024x1024 Config/VisionAssets.xcassets/AppIcon.solidimagestack/Back.solidimagestacklayer/Content.imageset/Background.png

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

build-mac: generate
    xcodebuild build -project {{ project }} -scheme gymemo -destination 'generic/platform=macOS' -derivedDataPath DerivedData -quiet CODE_SIGNING_ALLOWED=NO

build-vision: generate
    xcodebuild build -project {{ project }} -scheme gymemo -destination 'generic/platform=visionOS Simulator' -derivedDataPath DerivedData -quiet CODE_SIGNING_ALLOWED=NO

build-watch: generate
    xcodebuild build -project {{ project }} -scheme gymemoWatch -destination 'generic/platform=watchOS Simulator' -derivedDataPath DerivedData -quiet CODE_SIGNING_ALLOWED=NO

# Checks the native sources, package tests, and all native SDK builds.
check-native: lint gates check-dependencies test build build-mac build-vision build-watch

# Checks the support website and its browser interactions.
check-website:
    cd website && mise x -- just check

# Runs the same browser scenarios against the public custom domain.
check-public-website:
    cd website && GYMEMO_WEBSITE_TARGET=production mise x -- just e2e

# Runs all fast checks.
check: check-native check-website check-store lint-workflows

# Runs the UI scenarios and accessibility audits on the dedicated simulator.
[positional-arguments]
ui-test *args: generate
    cargo run --locked -p xtask -- ui-test "$@"

# Runs all four appearance passes on the selected simulator.
[positional-arguments]
ui-test-on *args: generate
    cargo run --locked -p xtask -- ui-test-on "$@"

# Plans the local release checks for one source commit; --run executes them.
[positional-arguments]
qualify *args:
    cargo run --target-dir target/qualification --locked -p xtask -- qualify "$@"

# Refuses a candidate without the owner's successful local qualification.
[positional-arguments]
require-qualification *args:
    cargo run --locked -p xtask -- require-qualification "$@"

# Runs the native layout and keyboard scenarios on an Xcode destination.
[positional-arguments]
native-test *args: generate
    xcodebuild test -project {{ project }} -scheme gymemoNative -derivedDataPath target/native-test-build -parallel-testing-enabled NO -quiet "$@"

# Runs the Watch scenarios on a paired simulator or device.
[positional-arguments]
watch-test *args: generate
    xcodebuild test -project {{ project }} -scheme gymemoWatch -derivedDataPath DerivedData -parallel-testing-enabled NO -quiet "$@"

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
    cargo run --locked -p xtask -- mutate "$@"

# Mutates xtask in bounded containers and reports each mutant that its tests miss.
[positional-arguments]
mutate-xtask *args:
    cargo run --locked -p xtask -- mutate-xtask "$@"

# Checks the Lean proofs and the Kani harnesses in bounded containers.
proofs:
    cargo run --locked -p xtask -- proofs

# Writes the Lean vectors from the Swift results.
gen:
    GYMEMO_WRITE_VECTORS=1 swift test --filter LeanVectorsTests

# Runs the package tests under the address and thread sanitizers.
sanitize:
    swift test --sanitize=address
    swift test --sanitize=thread
