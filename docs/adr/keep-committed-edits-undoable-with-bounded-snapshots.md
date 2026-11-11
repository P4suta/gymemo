---
date: 2026-11-10
---

# Keep committed edits undoable with bounded snapshots

## Status

Proposed.

## Context

Native desktop and keyboard use needs predictable undo for saved edits.
The log is a value, and its store supports atomic replacement.

## Decision

Register committed snapshots with the system `UndoManager`.
Keep at most 20 steps and reduce the count for large logs.
Never register a refused or unstored edit.
Use the original action name for undo and redo.
Invalidate snapshots when a Watch transfer changes the phone log, so undo can't remove incoming records.
Apple's [undo guidance](https://developer.apple.com/design/human-interface-guidelines/undo-and-redo) recommends more than one undo step and standard keyboard commands.

## Alternatives

Keeping only text-field undo leaves record deletion irreversible.
Inverse row changes use less memory but need insertion positions and another restoration contract.

## Consequences

Snapshots keep records until their undo steps expire.
Large logs keep at least one snapshot.
Watch doesn't expose undo.

## Confirmation

Exercise committed edits, text-field undo, redo, and native menus.
Reconsider snapshots if measured memory pressure makes the bounded history unsuitable.
