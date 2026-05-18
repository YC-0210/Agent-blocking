<p align="center">
  <img src="./DoCard/Assets.xcassets/AppIcon.appiconset/AppIcon~ios-marketing.png" width="250" style="border-radius: 40px;">
</p>

<h1 align="center">DO</h1>

<p align="center">
  <strong>DO, the physical way</strong>
</p>

<p align="center">
  DO helps you put your most distracting apps behind a quick tap of your DO Card (NFC) so you can stay in the zone and build better digital habits.
</p>

---

## Features

- **NFC Card Blocking** — Start or stop focus sessions by tapping your DO Card
- **Multiple Strategies** — Manual, NFC, NFC + Manual, NFC + Timer
- **Timer-Based Blocking** — Block for a set duration, then unblock with your DO Card
- **Physical Unblock** — Optionally require a specific card to stop a session
- **Profiles** — Create profiles for work, study, sleep, or whatever you need
- **Habit Tracking** — See your focus streaks and session history at a glance
- **Smart Breaks** — Take a breather without stopping your session
- **Live Activities** — Real-time status on your Lock Screen and Dynamic Island
- **Widgets** — Home Screen widgets for quick profile control

## Requirements

- iOS 17.6+
- iPhone with NFC capability
- Screen Time permissions (for app blocking)

## Getting Started

### Setting Up Your DO Card

1. Get a DO Card or any NFC tag (NTAG213 or similar)
2. Create a profile in the app
3. Write the tag from within the app
4. Tap your DO Card to start or stop a focus session

## Development

### Prerequisites

- Xcode 15.0+
- iOS 17.0+ SDK
- Swift 5.9+
- Apple Developer Account (for Screen Time and NFC entitlements)

### Building the Project

```bash
git clone <your-repo-url>
cd DO.1
open DoCard.xcodeproj
```

### Project Structure

```
DO.1/
├── DoCard/                    # Main app target
│   ├── Views/                 # SwiftUI views
│   ├── Models/                # Data models
│   │   └── Strategies/        # Blocking strategies
│   ├── Components/            # Reusable UI components
│   ├── Utils/                 # Utility functions
│   └── Intents/               # App Intents & Shortcuts
├── DoCardWidget/              # Widget extension
└── DoCardDeviceMonitor/       # Device monitoring extension
```

### Key Technologies

- **SwiftUI** — Declarative UI
- **SwiftData** — Local persistence
- **Family Controls** — App blocking
- **Core NFC** — DO Card reading/writing
- **BackgroundTasks** — Background processing
- **Live Activities** — Dynamic Island + Lock Screen updates
- **WidgetKit** — Home Screen widgets
- **App Intents** — Shortcuts and automation

## Blocking Strategies

All strategies live in `DoCard/Models/Strategies/` and are orchestrated by `DoCard/Utils/StrategyManager.swift`.

- **NFC (`NFCBlockingStrategy`)** — Scan any NFC tag to start; scan the same tag to stop. Optionally set `physicalUnblockNFCTagId` to require a specific tag to stop.

- **Manual (`ManualBlockingStrategy`)** — Start and stop entirely from within the app.

- **NFC + Manual (`NFCManualBlockingStrategy`)** — Start manually from within the app; stop by scanning an NFC tag.

- **NFC + Timer (`NFCTimerBlockingStrategy`)** — Select a duration to block; scan an NFC tag to end early.

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

## Acknowledgments

This project is based on [Foqos](https://github.com/awaseem/foqos) by [Ali Waseem](https://github.com/awaseem), licensed under the MIT License.
