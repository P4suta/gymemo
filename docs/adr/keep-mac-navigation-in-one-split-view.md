---
date: 2026-11-10
---

# Keep Mac navigation in one split view

## Status

Proposed.

## Context

On macOS 27.2, nesting a navigation split view in the adaptive tab sidebar reserves the sidebar width twice.
History and Analysis lose useful detail space even when their navigation tests pass.

## Decision

Give Mac one native `NavigationSplitView` per selected area.
History and Analysis use app areas, a content list, and a detail column.
Log and Settings use app areas and their content.
Share list and detail views with the other platforms.
Keep typed selections in the window's root view.
Apple's [sidebar guidance](https://developer.apple.com/design/human-interface-guidelines/sidebars) recommends a content list between sidebar items and details for deeper hierarchies.

## Alternatives

The adaptive `TabView` shares more code but produces incorrect geometry on macOS 27.2.
A stack uses less space but hides the list while showing details.
Custom offsets depend on broken layout behavior.

## Consequences

Mac has a dedicated navigation container and standard sidebar commands.
The app preserves history and exercise selections when switching areas.

## Confirmation

Verify column geometry, selection, keyboard navigation, local links, and independent windows.
Reconsider the container when nested adaptive tabs pass those checks without compensating layout.
