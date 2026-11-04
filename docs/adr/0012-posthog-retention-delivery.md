# 0012 — Upload retention with the batch API and durable revision checkpoints

Date: 2026-11-03. Extends ADR-0010/0011. No production deployment.

## Decision

Use PostHog's documented `/batch/` capture API with URLSession and the existing journal.
This replaces the initial SDK transport proposal: the journal already owns offline
persistence, and HTTP acceptance gives a concrete checkpoint without a second bounded
SDK queue. No SDK is added, so lifecycle events, screen tracking, replay, feature flags
and SDK enrichment cannot start automatically. Only the two agreed retention events
are constructed through an explicit property allowlist.

`RetentionEventBuilder` copies saved cohort context to every event, uses the install
UUID as distinct_id, retains original timestamps, and emits daily contribution keys,
revisions, period end instants and zero-valued retractions. Upload app version is named
explicitly; it is not presented as the version that recorded historical activity.
`$process_person_profile=false` requests anonymous events. GeoIP is disabled and an
explicit `0.0.0.0` IP placeholder prevents storing the connection IP as an event property
in the verified project. The server still receives network connections; this does not
claim network-level IP invisibility.

Stable retry UUIDs supplement, but do not replace, SQL deduplication by install,
environment, metric version, contribution key and highest revision. Never sum raw
contribution events. Corrections can have earlier event timestamps than old revisions;
revision, rather than delivery/event time, chooses the authoritative value.

## Delivery

The main app drains at launch/foreground, immediately after disclosure acknowledgement,
and every 60 seconds while foreground. Extensions only append facts. Each request has
at most 50 events and each tick drains at most five requests. Networking happens after
releasing the journal's file lock; blocking/unlocking paths perform no networking.

The uploader accepts HTTP 2xx with a recognized JSON success receipt: current Cloud
returns `{"status":"Ok"}`; the numeric `{"status":1}` shape is supported too. Error
statuses, invalid receipts, empty bodies and transport errors leave facts pending.
The live check exposed the string receipt; a regression test now covers it.

A separate protected delivery file, under the same cross-process lock, stores accepted
revisions and retry state. It is keyed by a digest of host, project token and environment.
Acceptance advances only the revisions actually sent, so a concurrent correction stays
pending. Facts are never deleted after upload. A crash/lost response before checkpointing
resends the same revision/UUID. Corrupt checkpoints fail explicitly rather than being
silently reset. HTTP acceptance is not downstream ingestion confirmation.

Failure backoff starts at 30 seconds, doubles to a one-hour cap, and survives restart.
Numeric Retry-After values are honored up to 24 hours. Cancellation leaves pending
facts without adding failure backoff. Periodic foreground ticks retry after the saved
deadline; there is no guarantee of background execution or schedule-only timely upload.

## Configuration and environments

No host or token fallback is compiled into Swift source. The app target includes
`Config/PostHog.xcconfig`, which optionally includes ignored `PostHog.local.xcconfig`.
CI may supply the same build settings. Info.plist substitution provides runtime config.
A missing/invalid config disables upload. Personal/admin keys are rejected.

Debug uses development and Release uses production. Capture uses separate directories
`retention-v1-development` and `retention-v1-production` in the existing App Group;
upload requires the configuration environment to match. This prevents debug activity
from carrying into production through a shared journal. Both the app and shared-source
extension targets compile the same environment rule. The previous unshipped generic
`retention-v1` journal is not imported; any such local scratch file remains untouched.

The connected project is 706779, US Cloud. Its public ingestion configuration is in the
ignored local file; it is not in the review patch. See `Config/README.md` for setup.
No project settings, flags, existing insights or production users were modified.

## Validation and limits

16 upload tests join the existing 47 retention tests in the deterministic CI portfolio.
They cover payloads, disclosure, acceptance persistence, offline replay, error receipts,
rate limiting, cancellation, correction races, project isolation, bounded batches,
UUID stability, retractions, no-cohort/running behavior, invalid config and backoff.
The implementation report records native tests, builds and live ingestion verification.

The live test executes identical Swift payload/journal/URLSession code from a macOS
harness, sends only marked development fixtures, and verifies actual stored events with
PostHog SQL. It is not a physical-device end-to-end test. The final fixture's corrected
period totals are 3,000 seconds each, with a zero retraction retained. Period 2 is still
pending; the original cohort denominator is unchanged.

The journal still grows with history. There is no compaction, ingestion-query API key on
the device, or automated repair after a server accepts then drops an event. Monitoring
PostHog ingestion warnings and physical-device App Group/offline/schedule checks remain
release requirements. The app sends no query/admin credential. No SwiftData schema,
NFC validation, authorization policy, access gate or Emergency Unlock behavior changes.

Official contract: https://posthog.com/docs/api/capture
