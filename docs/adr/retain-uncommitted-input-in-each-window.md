---
date: 2026-11-11
---

# Keep uncommitted input in each window

## Status

Proposed.

## Context

Switching Mac areas removes the day's view and resets its local input.
A native regression test enters 80 kg and seven repetitions, switches areas, and finds the previous suggestion instead.
Saved records remain correct.

## Decision

Keep set drafts and pending exercise selections in the window's root view.
Keep raw input and validation messages in drafts keyed by day and exercise.
Share the window's draft store through the SwiftUI environment.
Apple's [state guidance](https://developer.apple.com/documentation/swiftui/state) places shared state in the highest view that needs it.
Parsing and saving still use the existing core rules and store.

## Alternatives

View-local state follows a screen's lifetime and loses input during navigation.
The shared app model would mix drafts from independent windows.
Disk persistence would add recovery and migration requirements for unfinished input.

## Consequences

Navigation preserves input within a window.
Closing the window discards unfinished input.
Drafts add no stored records or network access.

## Confirmation

Verify area changes, day separation, independent windows, validation, and logging.
Reconsider persistence when relaunch must restore unfinished input.
