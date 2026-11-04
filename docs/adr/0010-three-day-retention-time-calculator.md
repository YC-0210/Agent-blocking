# 0010 — Calculate retention time in fixed three-calendar-day periods

Date: 2026-11-03. Original scope: pure calculation and tests. Local capture is now
covered by ADR-0011; PostHog delivery remains a later step.

## Decision

`RetentionTimeCalculator` accepts a confirmed cohort start, a fixed timezone identifier,
plain session timestamps and an explicit `asOf` clock. It has no SwiftData, network,
App Group, subscription, permission or UI dependency. The caller owns successful-start
validation, cohort/identity persistence and the choice of authoritative session revisions.

Day 1 is the first successful post-instrumentation session's calendar date, even if
it starts at 23:00. Gregorian calendar dates in the saved timezone define periods
1 (days 1–3), 2 (days 4–6), and so on. They are not 72-hour sliding windows.
An installation qualifies at 7,200 completed locked seconds total in a period; no
daily-use or streak requirement remains. Manual and scheduled sessions, including
Emergency Unlock, use the same arithmetic without weighting or filtering by reason.

`contributions(for:cohort:asOf:)` splits finished eligible sessions at midnight,
subtracting each day's overlap with a break. An open break is clipped at session end.
Half-open intervals prevent midnight from adding time to two days. Calendar-day
operations preserve real elapsed seconds through DST and use the entry timezone
after travel. Stable session/date contribution keys support later event delivery.

`periods(for:cohort:asOf:)` sums the supplied canonical sessions and returns all
periods through the current one, including zero-usage periods. `isActive` is nil
until a period ends; then it is true or false at the unrounded threshold. Each
period stands alone. Recalculating with later finished data can revise earlier results.
Sessions started before entry, unfinished sessions and sessions ending after `asOf`
do not contribute. A zero-length session adds no time.

Exact duplicate session inputs count once. Conflicting inputs with the same session
ID throw instead of selecting a revision from timestamps or array order. Invalid
dates, negative intervals and malformed break endpoints also throw; corrupt data
must not become plausible zero-usage rows. Different overlapping session IDs are
outside this task, as agreed; no new overlap policy is introduced.

## Alternatives

- Reusing `SessionReportDuration` would provide only a scalar total and retain its
  different incomplete-break semantics. Retention needs day/period allocation.
- Reusing the daily Supabase aggregator would preserve rounded minutes, start-day
  attribution and missed-day reporting limits that do not match the retention rule.
- Dividing elapsed seconds by 259,200 would move calendar boundaries during DST.
- No runtime hooks are added yet: wiring them now would combine delivery/lifecycle
  risks with the independently testable calculation step requested by the user.

## Compatibility and verification

Existing report arithmetic, session stores, schema versions, App Group keys,
RequestAuthorization, Emergency Unlock, NFC triggers and product gates are unchanged.
The pure helper is included in the app through Xcode's synchronized source group.
The 26 XCTest methods are selected by the existing deterministic CI portfolio.

Tests cover threshold edges, split days/periods, breaks, late/night entry, pending
periods, later returns, late completions, replays, input errors, spring/fall DST,
travel, and the six-install worked example from the PostHog proof (3, 2, 2, 0 active
installs across four completed periods). Cohort denominators and new/existing user
classification remain outside this per-install calculator and belong to capture/SQL.

See `DO_Card_Changelog.md` for the actual local build/test results. No device-delivery,
real-shield, production PostHog ingestion or release verification is claimed here.
