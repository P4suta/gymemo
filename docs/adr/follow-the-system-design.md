---
date: 2026-11-09
---

# Follow the system design

## Status

Accepted by the owner on 2026-11-09.
It replaces the iOS 18.0 floor in [Build a native SwiftUI iPhone app](build-a-native-swiftui-iphone-app.md).

## Context

The screens used a custom black and white style, unlike the rest of the system.
Apple's [adoption guide](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) gives the Liquid Glass material to standard components, and its APIs need iOS 26.

## Decision

Build every screen from standard SwiftUI components and system colors, with system indigo as the one accent.
Keep Liquid Glass in the layer that the system draws.
The owner's Figma file, built on Apple's iOS 27 kit, is the reference for the screens.
Support iOS 26.0 and later.

## Alternatives

The status quo let a source check prove its palette but looked unlike the platform.
Keeping iOS 18 needs a second look that no simulator here can show.

## Consequences

A phone without iOS 26 can't run the app.
iOS 26 stays unverified until a phone runs the app, because the simulators here run iOS 27.

## Confirmation

The source check refuses custom glass, custom bar backgrounds, and colors built from numbers.
Reconsider when the lifter's phone can't run iOS 26.
