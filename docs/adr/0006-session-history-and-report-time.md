# 0006 — Preserve completed history and report net session time

Status: accepted; local implementation, 2026-11-02.

## Agreed behavior

- Replaying one session ID must not create another history row.
- A saved start time remains authoritative when a snapshot disagrees.
- A completed Emergency Unlock record keeps its ending time and reason when a later
  timer completion arrives. An older active snapshot cannot reopen completed history.
- Report time subtracts the intersection of a recorded, completed break and its session.
- A completed session belongs wholly to the week of its start, with Monday as the boundary.
- Different overlapping session IDs and combining their time are excluded from this batch
  (P5/P6 deferred). Existing summed-session behavior is retained for that situation.

## Implementation

The importer keeps the existing ID-based update/create path and authoritative-start guard.
Before updating an already-ended row, it ignores an active snapshot or any snapshot for a
record already ended by Emergency Unlock. Other completed-to-completed updates keep the
existing behavior. No new ordering timestamp or universal conflict-resolution policy is added.

`SessionReportDuration.seconds` calculates elapsed time minus the overlap of the two saved
break endpoints with the session. A private report helper supplies the saved timestamps.
The summary, average's numerator, profile totals, four-week trend, and qualified-duration
input to Focus Score use this same net duration. Qualification thresholds and score weights
are unchanged. Missing break endpoints retain elapsed-time behavior; treatment of incomplete
break records is outside the agreed cases.

The report accepts a clock and calendar with live defaults. Tests fix report dates to
2026-11-02 in Asia/Taipei. Advanced calculators still have their own time dependencies;
this change does not certify their behavior or alter their scoring formulas.

Saved elapsed timestamps and `BlockedProfileSession.duration` are unchanged. No stored model
field, schema version, migration stage, App Group key, or subscription policy changes.

## Verification design

Seven history integration methods exercise the real importer, and S4 also exercises the
foreground loader through signed, separate shared defaults. File-backed test stores are
saved and reopened with a new container in the same test process; this is not an OS-process
restart. Seven report integration methods exercise actual SwiftData queries and published
report values. One small calculation test checks the five agreed break rows. This totals
15 methods for 13 agreed scenario groups, with P7 split into two independent examples.

The former S5 reopen checks are included in the import cases; manual/schedule precedence
remains in the existing R11 recovery tests. P2 owns report arithmetic. Recovery sequences
are not repeated inside the direct conflicting-message tests.

S7, S8, P4, and P7 were observed failing on the preceding implementation before each fix.
The final combined local run selected 79 methods: 36 schedule, 27 unlock/recovery, one
first-release upgrade, and these 15. Exact executed names and counts were checked against
source declarations; zero tests or skipped tests cannot satisfy the check.

## Limits

The host app still starts normal services. These local tests do not prove independent
extension-process delivery, resolution of the documented completed-session visibility gap,
real NFC reads or Screen Time shields, physical-phone UI, or handling of arbitrary damaged
history. Advanced report cards require their own agreed cases. The PR also selects the three new suites in the existing CI regression gate (78 methods),
followed by the unchanged two-process upgrade check. Hosted verification is separate from these local results.
