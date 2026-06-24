# Today's Tasks stored in lightweight settings, not SwiftData

Today's Tasks (今日目標) is ephemeral daily state — up to three goals, each with a name, optional detail, and done flag, reset/carried-over per local day, with no past-days history and no extension consumers. We store it as JSON in UserDefaults rather than adding a SwiftData `@Model`, to avoid a schema-version bump (V5 → V6) and its migration snapshot plus App Store submission-checklist risk for what is essentially throwaway data.

## Considered Options

- **SwiftData `@Model` (like `MotivationPhoto`)** — rejected. It's the consistent-looking choice, but every schema change in this project requires a migration snapshot in `AppMigrationPlan.swift` and is a flagged high-risk item on the App Store submission checklist. That ceremony isn't justified for tiny, intentionally-disposable daily state.
- **UserDefaults JSON (chosen)** — a small self-contained store, the same class of storage the app already uses for on/off switches and subscription state. No schema bump, nothing new to verify at submission time.
