# 0008 — Local focus without Co-Focus or device synchronization

Status: user-approved scope, 2026-11-02; local implementation verified with 142 selected methods and Debug/Release simulator builds.

The next app version removes Co-Focus and device synchronization. Remove the UI,
report card, app startup services, NFC diversion, external-device pairing, status
badge, subscription advertising, foreground/extension network calls and client SDK.
Physical DO Card pairing, local NFC starts/stops, schedules, recovery, reports and
paid-only access remain. This supersedes ADR-0007's references to those removed features.

Deleting the clients rather than hiding their screens ensures background work cannot
continue using an old pairing. No backend tables, server functions, saved pairing
credentials or separate browser/iPad app repositories are modified. Existing remote
clients and server records are outside this local app change; their unpair/reset controls
remain the way to clear an old remote pairing or shield.

Usage analytics is separate from session synchronization. Its existing URL and public
anonymous key now belong to its own REST client, with its own transport errors. Keep
its existing payload shape: the retired-feature fields remain false/zero. Do not turn
feature removal into a backend schema change or an analytics migration.

The two remaining review fixes preserve expiry history and authenticate cached grants:
- Merge saved break facts into subscription-expiry imports; close an open break at the
  actual removal time. Keep the ordinary import path and stored schema unchanged.
- Require a valid HMAC for the new subscriptionGrants key. Missing, damaged or wrong-key
  signatures cannot grant access or trigger automatic signing. Legacy keys retain their
  old upgrade path. If the signing key is unavailable, the new grant is not trusted.

Verification uses real local session/storage/report paths, recorded blocking commands,
fixed clocks, the existing Apple-local StoreKit cases and Debug/Release simulator builds.
The expiry test covers completed/open breaks and foreground/background cleanup. Settings
layout checks protect the remaining local feature navigation. Real tokens, physical
shields, independent iOS delivery and real purchases still need the deferred phone checks.
Local verification does not claim a hosted pass or change App Store settings or distribution.
GitHub publication is a separate, subsequently user-authorized step.
