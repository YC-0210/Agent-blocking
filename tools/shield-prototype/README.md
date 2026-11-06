# Throwaway blocking screen study

Question: which minimal English interruption should replace the current translated,
paragraph-heavy shield? Three directions on one route: A Quiet, B Hard stop,
C One button. Decision: user chose A’s minimal layout and requested the existing app palette.
Revised A uses orange `#f25b36`, ink `#2d281f`, and cream `#fff5e6`, matching
`AgentFocusView.Palette`. Layout and English copy are unchanged. The selected A design has been ported to the native shield on the integration branch.

Run from the worktree root:

```sh
npm --prefix experiments/agent-focus run prototype:shield
```

Open http://127.0.0.1:8804/prototype/blocking-screen?variant=A and use the floating
arrows, A/B/C links or keyboard arrow keys. The variant is stored in the URL;
other state stays in memory. Expand the state panel to inspect the native fields.

The source is archived under `tools/shield-prototype` outside the shield extension target. This route is served
only by the local prototype runner, not by the production relay or MCP resource.
The prototype runner itself does not modify the phone or relay. The selected A design
is now implemented separately in `DoCardShieldConfig/ShieldConfigurationExtension.swift`.
The prototype HTML remains outside the app targets and is not shipped. The source
worktree/branch is preserved; integration occurs on `codex/agent-focus-integration`.

Apple's shield controls layout, font metrics and spacing. These are browser
approximations using supported categories of fields (icon, title, subtitle,
button label and colors), not exact native screenshots or a promise of arbitrary
SwiftUI layout. The final choice needs native validation, including the nil-title
composition in C and the low-emphasis button contrast in A.

All three use English text directly. Emergency Unlock remains in DO Card; the
preview button only simulates closing the blocked app, never unlocking it.

Source: https://developer.apple.com/documentation/managedsettingsui/shieldconfiguration

The user approved A and requested integration. Its native implementation and
validation status are recorded in `docs/design/agent-quiet-shield/README.md`.
