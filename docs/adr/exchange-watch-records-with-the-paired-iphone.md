---
date: 2026-11-10
---

# Exchange records with the paired iPhone

## Status

Proposed.
The owner chose a paired Watch without cloud synchronization.
It extends [Keep records on the device and back up through files](keep-records-on-the-device-and-back-up-through-files.md).

## Context

Watch sets must reach the paired iPhone without a server.
Contact may fail during training.

## Decision

Keep the iPhone authoritative and queue Watch entries durably.
Use [`updateApplicationContext(_:)`](https://developer.apple.com/documentation/watchconnectivity/wcsession/updateapplicationcontext(_:)) for replaceable summaries and [`transferUserInfo(_:)`](https://developer.apple.com/documentation/watchconnectivity/wcsession/transferuserinfo(_:)) for entries and acknowledgments.
Keep stable set identifiers across retries and acknowledge only committed storage.
Relaunch retains unacknowledged entries, and conflicting identifiers never replace stored sets.
Other devices exchange local logs through backup files.

## Alternatives

Independent Watch records lack the selected phone companion behavior.
Synchronizing through a cloud service conflicts with the owner's choice.
Immediate messages require a reachable counterpart.

## Consequences

Show pending and refused entries while the system schedules delivery.
Disclose paired-device transfer in the privacy policy.
Background transfer requires paired hardware tests.

## Confirmation

Test interruption, persistence, duplicate delivery, refusal, and acknowledgments after commit.
Require paired-device TestFlight acceptance.
Reconsider for cloud synchronization or an independent Watch log.
