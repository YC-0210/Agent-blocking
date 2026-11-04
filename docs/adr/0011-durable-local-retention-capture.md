# 0011 — Save retention facts separately from transient session snapshots

Date: 2026-11-03. Scope: local capture. PostHog transport is a later step.

## Decision

Keep the pure calculator from ADR-0010. Add `RetentionJournal`, a Codable state file
under the existing `group.DO.version3` container's `retention-v1` directory. Every read
and write takes an exclusive BSD file lock; writes replace the state atomically. The
lock is separate from the replaced file and closes automatically on process death.
On iOS, state remains protected until the first unlock after boot, then accessible
to scheduled callbacks while the device is locked. No SwiftData schema changes.

Activate the baseline before foreground services can start a session. Activation is
idempotent; extensions cannot create a baseline. Reuse the anonymous installation ID.
Existing analytics/onboarding/card-pairing evidence gives `existing_install`; absent
evidence gives `unknown`. Do not call an empty or partially reset installation new.
Reliable `new_install` classification needs additional installation evidence in a
later step. Classification and cohort timezone are saved once.

Capture foreground starts only from the strategy's successful-start callback, after
saving the session, with current approved authorization, valid subscription access
and an effective shield selection. Failed timer registration rolls back before this
callback. Scheduled starts are captured after restriction application, including the
schedule restored after a manual timer ends. These are app-recorded restriction
intervals, not independent proof of continuous OS enforcement.

Foreground `endSessionFully` records after a successful save, including its save retry.
Shared timer/schedule completion records before the transient completion buffer can
be cleared. Import reconciles with saved canonical SwiftData facts so break and
Emergency Unlock preservation applies. A missing registered start cannot create time
or retroactively enter a cohort. The first successful captured start fixes the
denominator; excluding a later ambiguous session does not remove that installation.

Break changes are recorded independently so a schedule snapshot with missing break fields
cannot erase known break time. A late break fact revises an already saved completion.
Completion calls the calculator and stores daily seconds with stable session/date
keys and monotonic session revisions. Duplicate facts do nothing. Corrections replace
all that session's rows; removed dates remain as zero-valued retractions. A delayed
timer record cannot replace a saved Emergency Unlock. A running session contributes
nothing. No daily rounding, historical backfill limit or period weighting is added.

Recovery paths that invent an end time at app launch exclude an unfinished journal
session rather than counting the entire stale interval. This exclusion persists
through later imports; already recorded verified completions are preserved. This
conservative choice can undercount a session whose valid end arrives only after the
exclusion. Recovering such evidence is deferred, rather than inflating time now.

Only the install ID, classification, timestamps, session ID, trigger, end reason,
revision and calculated daily allocation are saved. Card tags, profile names, app
tokens, selected apps and gallery content are not copied into the journal.

## Delivery boundary and limitations

This step sends no new network requests and introduces no PostHog dependency. Remove
the HomeView invocation of the old deleted-project Supabase reporter. Its unused
implementation remains for a separate removal change.

The journal is the source for later PostHog delivery. Do not erase facts when an SDK
capture method returns; it is not server acknowledgment. Delivery must respect the
existing `AnalyticsConsent.disclosureShown` gate, use explicit anonymous identity,
disable automatic tracking, and deduplicate revisions before summing seconds.
The baseline begins on the first launch of this instrumented build, not installation
time or the date this patch was written. An extension firing before that launch
cannot enter the cohort. This code is not deployed and has not started measurement.

Capture errors are logged and do not change blocking/unlocking decisions. Failed
writes can lose facts; corruption fails closed rather than resetting a cohort. There
is no upload acknowledgment, retry worker, backup recovery or retention/compaction
policy yet. The JSON file grows with recorded session history and is rewritten under
the lock. Review this cost before long-term production deployment.

## Validation

Calculator and journal tests cover replay, revisions/retractions, breaks, stale
recovery, clean baseline exclusion, corrupted storage and concurrent writers.
Native capture tests exercise real SharedData completion/clear paths and saved
SwiftData Emergency Unlock. Existing deterministic tests check session, recovery,
subscription and selection behavior. See the implementation report for actual runs.

Physical-device checks remain required before release: manual/card start/end,
Emergency Unlock, failed timer registration, expiry while terminated, scheduled
starts/ends while locked, upgrade with an already-running session and offline use.
No change is made to RequestAuthorization, NFC validation, entitlement policy,
Emergency Unlock availability, existing report arithmetic or SwiftData migrations.
