---
date: 2026-11-10
---

# Share log rules across native Apple apps

## Status

Proposed.
It extends [Build a native SwiftUI iPhone app](build-a-native-swiftui-iphone-app.md).

## Context

The owner requests native Apple platform experiences.
The package separates log rules and storage from screens.

## Decision

Use one SwiftUI target for iOS, macOS, and visionOS, and a separate watchOS companion target.
Apple's [multiplatform guide](https://developer.apple.com/documentation/xcode/configuring-a-multiplatform-app-target) recommends sharing overlapping SwiftUI targets and requires a separate watchOS target.
Share the rules, storage format, and catalog while giving each platform its own navigation and input behavior.
Use adaptive system containers to preserve state across [iPhone Duo displays](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo).

## Alternatives

The iPhone app already works.
iPad compatibility requires less code but lacks native desktop and spatial behavior.
Separate targets isolate configuration but duplicate shared settings.

## Consequences

Each platform needs its own native checks and store assets.
Mac and visionOS can ship independently of the iOS package.
Watch and Vision Pro hardware acceptance needs external testers.

## Confirmation

Build each SDK destination and exercise its native navigation, inputs, file access, and accessibility.
Reconsider target sharing if platform differences dominate the shared code.
