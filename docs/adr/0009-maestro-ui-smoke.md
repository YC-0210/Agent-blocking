# 0009 — Four core locking journeys at the top of the test pyramid

Status: local implementation, not published.

Replace the five basic UI smoke flows with manual card lock/unlock, scheduled
start/end, early card unlock during a schedule, and complete Emergency Unlock.
Each must create a real session, request restrictions, end that session and preserve
history after app relaunch. Early unlock must survive repeated schedule delivery and
relaunch. Emergency Unlock must spend one use and save one audit event.

Use real UI, session orchestration, card validation, restriction policy, schedule
handlers, suppression storage and SwiftData. Simulate hardware input, OS restriction
writes, the clock, callback delivery, quota storage and unrelated system effects.
A Debug-simulator-only panel exposes external-event controls and read-only observations;
it does not set session state. A Debug-simulator runtime fallback supports asynchronous
UI callbacks; existing TaskLocal test dependencies retain priority. Release/device
builds have no harness or runtime override.

The shared schedule handler is exercised in the app process, not through Apple's
background delivery/extension process. A real-phone check remains necessary for NFC,
shielding and background delivery. Do not call these full hardware end-to-end tests.

Keep detailed timing/access permutations in lower-level tests. Add one focused
manual-card round-trip integration test; existing scheduled and emergency recovery
suites cover the other journeys. Update exact CI counts to include that new test.

The Maestro job remains manual opt-in after regression, two-process upgrade and
Release checks. Reuse the existing Debug app artifact and require four exact SUCCESS
results. Reject old flow names. Keep reports/screenshots/logs and prove a deliberate
failure propagates. See docs/testing/maestro.md and the local locking validation report.
