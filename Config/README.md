# PostHog retention upload configuration

Only the main app uploads. The monitor and widget write the shared journal.

1. Copy `PostHog.local.xcconfig.example` to `PostHog.local.xcconfig` in this directory.
2. Set `DO_CARD_POSTHOG_TOKEN` to the selected project's **public project token** (`phc_...`).
3. Set `DO_CARD_POSTHOG_HOST` to that project's HTTPS ingestion host. Preserve the
   `https:/$()/` syntax: plain `//` starts an xcconfig comment.
4. Build normally. The app target includes `PostHog.xcconfig` in Debug and Release.
   CI can supply `DO_CARD_POSTHOG_TOKEN` and `DO_CARD_POSTHOG_HOST` as build settings.

The current isolated worktree is configured locally for connected project 706779.
The real local file is ignored and excluded from the patch. A fresh checkout/CI needs
its own configuration. No host/token defaults are supplied and no upload occurs when
configuration is absent or invalid. Never use a personal or admin API credential.

Debug is development; Release is production. These use separate capture journals and
upload checkpoints. Keep the corresponding environment filter on all real insights;
exclude `is_synthetic=true` from production analysis. Both build configurations' expanded
Info.plist values were checked against the connected project without printing the token.

Uploads require the existing analytics disclosure. The first instrumented launch saves
the clean baseline, and the first confirmed successful start enters a cohort. No app-open
or installation events are sent. Foreground polling sends new facts within about a minute;
opening the app later drains offline extension facts with their original timestamps.

The local config is a build input and is not bundled as a resource. The resolved public
host/token are intentionally present in the app's Info.plist. Event payloads contain only
the retention allowlist. See ADR-0012 and the upload tests for the exact contract.
