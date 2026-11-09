---
date: 2026-11-09
---

# Localize with one tested catalog of strings

## Status

Accepted by the owner on 2026-11-09 for English, Japanese, and Chinese.

## Context

A screen that writes its own sentences can ship a word that one language lacks.
A build reports no missing translation.

## Decision

Keep every word in one String Catalog inside the `GymemoCopy` package target, with English as the source.
Screens read words through typed accessors, and dates and numbers follow the device's region.
The catalog serves English, Japanese, Simplified Chinese, and Traditional Chinese.
A first launch names the starter exercises in the device language.

## Alternatives

SwiftUI literals with Xcode's extraction need the least code, and nothing checks them outside Xcode.
Japanese alone was the status quo.

## Consequences

Each new string needs a key, an accessor, and four translations.
No native speaker has reviewed the Chinese text.

## Confirmation

Package tests require every key in every language with the placeholders of the English text.
A source check refuses a sentence written as a literal in a screen.
UI tests audit each screen in each language.
Reconsider when a language that reads from right to left joins.
