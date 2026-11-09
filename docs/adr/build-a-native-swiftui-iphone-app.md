---
date: 2026-11-09
---

# Build a native SwiftUI iPhone app

## Status

Accepted by the owner on 2026-11-09.

## Context

The lifter logs sets on an iPhone in a gym, sometimes offline.
The owner rejected existing apps for their advertisements and clutter.

## Decision

Build one native iPhone app in Swift 6 with SwiftUI for iOS 18.0 and later.
XcodeGen writes the project from `project.yml`.
A local Swift package holds the pure core and the adapters, so `swift test` runs them on the Mac.

## Alternatives

A web app on the home screen would run on any phone without signing.
The owner chose the native app, which uses system controls, Dynamic Type, and VoiceOver directly.
The status quo, a notes app, shows neither the previous session nor a trend.

## Consequences

Delivery needs an Apple Developer team, signing, and a route that a later record decides.
The development Mac has only iOS 27 simulators, so iOS 18 stays unverified until a phone runs the app.

## Confirmation

`mise x -- just check` builds the app, and `mise x -- just ui-test` runs the scenarios and accessibility audits.
Reconsider when the lifter leaves the iPhone.
