# Native Bold UI capture harness

Simulator-only renderer of the production SwiftUI view with sample runtime and
Screen Time authorization. No network, Keychain, native shield or live-device effects.
The fixture's Emergency Unlock updates its in-memory status; it does not validate the
real phone's hardware release. The phone core is checked separately by `swift test`.

```sh
python3 tools/ui-capture/sync-view.py
xcodegen generate --spec tools/ui-capture/project.yml
xcodebuild -project tools/ui-capture/AgentUICapture.xcodeproj -scheme Capture \
  -destination 'platform=iOS Simulator,name=DO Card Agent UI Audit' \
  -derivedDataPath /tmp/DOCardBoldCapture \
  -resultBundlePath /tmp/DOCardBoldCapture-New.xcresult test
```

Use an available simulator name, or create a separate iPhone 13 simulator on iOS 26.2.
The generated copy of AgentFocusView is ignored. `sync-view.py` changes only the initial
setup step for the `setup-limits` launch argument. The other screen layout, validation,
buttons and input handling are unchanged. No fixture hooks enter the application target.
The generated project is also ignored; XcodeGen is required to regenerate it.

Walkthroughs capture active/idle/unknown/applying/offline presentations, release-button
reachability including large text, initial connection validation, authorization and
empty-selection gates, the real system picker, and the limits view with connection
properly disabled when nothing is selected. The simulator's all-category checkbox does
not produce usable selected tokens in this fixture; that approval path still needs
physical-device verification. Export screenshots with `xcresulttool export attachments`.
