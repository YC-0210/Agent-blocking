# Throwaway blocking screen study

Question: which minimal English interruption should replace the current translated,
paragraph-heavy shield? Three directions on one route: A Quiet, B Hard stop,
C One button. Verdict: pending user comparison.

Run from the worktree root:

```sh
npm --prefix experiments/agent-focus run prototype:shield
```

Open http://127.0.0.1:8804/prototype/blocking-screen?variant=A and use the floating
arrows, A/B/C links or keyboard arrow keys. The variant is stored in the URL;
other state stays in memory. Expand the state panel to inspect the native fields.

The source lives next to the shield extension for context. This route is served
only by the local prototype runner, not by the production relay or MCP resource.
No production target, device installation, blocking behavior, permissions,
translation files or live server are changed. Do not merge this directory into
the app target. Keep this entire prototype on `codex/prototype-blocking-screen`.

Apple's shield controls layout, font metrics and spacing. These are browser
approximations using supported categories of fields (icon, title, subtitle,
button label and colors), not exact native screenshots or a promise of arbitrary
SwiftUI layout. The final choice needs native validation, including the nil-title
composition in C and the low-emphasis button contrast in A.

All three use English text directly. Emergency Unlock remains in DO Card; the
preview button only simulates closing the blocked app, never unlocking it.

Source: https://developer.apple.com/documentation/managedsettingsui/shieldconfiguration

There is no implementation issue specified for this design study. This file is
the branch-local context pointer until a winner and implementation issue exist.
