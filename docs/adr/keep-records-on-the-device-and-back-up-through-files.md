---
date: 2026-11-09
---

# Keep records on the device and back up through files

## Status

Accepted by the owner on 2026-11-09.

## Context

The owner wants no account, no advertisement, and no network use.
A lost or replaced phone must not end the log.

## Decision

Store every record in the app's container and call no networking API.
Settings writes a JSON backup of all exercises, sets, and memos.
It reads one back after a confirmation and replaces the current log.
The backup carries `formatVersion` 1, and the reader refuses any other number.
Settings also writes a CSV file under [RFC 4180](https://www.rfc-editor.org/rfc/rfc4180) with a byte order mark, which lets [Excel open UTF-8 normally](https://support.microsoft.com/en-us/office/opening-csv-utf-8-files-correctly-in-excel-8a935af5-3416-4edd-ba7e-3dfd2bc4a032).

## Alternatives

Sync through a server would copy the log automatically, and it needs an account.
Without an export, the log ends with the phone.

## Consequences

A backup exists only when the lifter writes one.
An import discards the current log instead of merging.

## Confirmation

A property test reads back every written backup, and a UI scenario exports and imports one.
The source check refuses networking APIs.
Reconsider when the lifter wants two devices.
