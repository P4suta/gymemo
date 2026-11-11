---
date: 2026-11-10
---

# Route log shortcuts through the active scene

## Status

Proposed.

## Context

The owner requests applicable Apple accessibility recommendations.
Opening today's log is a frequent task suitable for Siri and Shortcuts.

## Decision

Use a foreground App Intent to open one validated local URL.
Keep navigation in the receiving scene through `onOpenURL`.
The [custom URL guidance](https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app) permits local links but strongly recommends universal links.
The private route accepts no parameters and only opens today's log.
It never reads, creates, or deletes records.
Compile the shared String Catalog into the app for system metadata and use Apple's separate `AppShortcuts` table for phrases.

## Alternatives

Typed scene routing is preferable, but iOS 27.2 rejects its scene delegate in both Shortcuts and App Intents Testing.
Universal links require a website association for private navigation.
A process-wide mutable navigator interferes with independent windows.

## Consequences

The intent opens the log on iPhone, iPad, Mac, and Vision Pro.
Other apps can invoke the same harmless route.
Spoken phrase recognition still needs Siri acceptance on a device.

## Confirmation

Run the intent through App Intents Testing from another tab and verify the selected scene.
Verify catalog extraction and localized phrases.
Reconsider typed routing after Apple fixes the delegate failure.
