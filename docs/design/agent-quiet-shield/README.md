# Quiet shield integration

Integrated the chosen A design from `codex/prototype-blocking-screen`, commits
`e0f84a1` and `5297c17`, into `codex/agent-focus-integration` on 2026-11-06.
The source worktree `/Users/chen/Documents/ChatGPT/DOCard-ios-shield-prototype`
was not modified.

Native app, category and website shields now use:

- Solid orange `#f25b36` background, ink `#2d281f` title/button and cream
  `#fff5e6` button text.
- “Go back to work.” title and one “Close app” primary button.
- No custom icon, subtitle, secondary button or background blur.

iOS controls native positioning and typography; the browser prototype is not a
pixel-exact native reference. Blocking ownership, expiry, pairing, limits,
selected app metadata and Emergency Unlock are unchanged. The primary action
uses the existing system shield action; no unlock handler is added.

The extension's own `AgentFocus.xcstrings` contains English and Traditional
Chinese translations. Normal builds use the app/device language. The explicitly
enabled `DEBUG && DO_CARD_ENGLISH_DEMO` path uses the English bundle. This is
necessary because main-app language launch arguments do not configure a separate
extension process. Build it with:

```sh
DO_CARD_DEMO_LANGUAGE=en bash tools/selected-app-icons/build-identification.sh
```

The main app still uses the previously documented temporary English launch
arguments. No device language setting is changed.

The browser study is archived under `tools/shield-prototype`, outside all app
target groups; `npm --prefix experiments/agent-focus run prototype:shield`
still serves the study through its updated file path.

Validation:

- 87 existing Swift tests and 100 existing Node tests passed.
- Signed Debug demo build and SDK/profile preflight passed.
- Unsigned Release build passed with ordinary localization and entitlements.
- Compiled Debug and Release extension resources contain both new keys in both
  languages. Neither extension bundle contains prototype HTML/directories.
- Swift-format lint, shell syntax and diff whitespace checks passed.
- The relocated prototype route returned the selected A study successfully.
- Spec review caught the separate extension-catalog requirement; it was fixed
  and verified in the built bundles. No remaining review blockers.
- Installed the signed experiment over the paired iPhone 13 and launched the
  main app with temporary English settings. No focus command was sent.

Still needs physical verification: start a user-confirmed short session, open a
selected app, inspect the native layout, and confirm “Close app” dismisses the
blocked app while the session remains active. Build/tests do not prove the
system-owned visual layout or button behavior.

Local evidence: `/tmp/docard-quiet-shield-{build,release,swift,node}.log`.
