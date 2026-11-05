# APNs expiry-purpose transport regression

The approved seam is `createApnsPush` against an actual loopback HTTP/2 server, using
an ephemeral, generated P-256 signing key. No live APNs service, environment secrets,
stored keys, phone, relay or external network is used. Each fixture binds an ephemeral
loopback port and destroys tracked HTTP/2 sessions and closes its server on completion.

Run:

```sh
node --test experiments/agent-focus/test/apns-expiry.test.mjs
```

Three tests cover:

1. `purpose: 'expiry'`, `kind: 'alert'` produces a visible mutable alert with
   `docardExpiry: true`, `docardAgent: true`, and the original opaque `commandId`.
   Payload top-level fields are restricted; synthetic token/team/key values are absent.
   The supplied `expiresAt` is preserved as the APNs expiration seconds: the example
   1793923320000 milliseconds becomes `1793923320`, with no transport TTL shortening.
2. Recovery collapse identity is the fixed SHA-256 reference for
   `expiry:focus-command-opaque-17`, distinct from the original command alert identity
   and stable across retries. Both pushes retain the original body `commandId`.
3. Ordinary alert and background pushes preserve their existing aps bodies, push types,
   priorities, expiration and collapse identity, with no `docardExpiry` property.

Initial RED evidence before production changes: three tests executed, one passed and
two failed. The expiry marker was absent, and expiry collapse matched the ordinary
command hash. The ordinary/background compatibility case passed immediately. The
coordinating agent owns production `apns.mjs` changes and final GREEN validation.

This suite validates the transport protocol only. It does not prove APNs acceptance
outside the loopback fixture, notification delivery, notification-service-extension
execution, or physical release. Nor does it establish the sender's computation of
`dueAt + 24h`: the sender supplies that expiration to this seam. Native expiry handling
must use the locally stored deadline and must not execute an old start command.

Parent integration validation after implementing the expiry marker and collapse domain:
all3 transport tests pass. Combined Node/UI build:79 pass. Native release-only delivery
coverage:76 Swift tests pass; signed Debug phone build succeeded. The manual live push
cleared the previously expired session and was confirmed by both a fresh snapshot and
the owner without opening DO Card. Automated original-deadline reboot recovery is the
next physical check; transport acceptance alone does not establish release.
