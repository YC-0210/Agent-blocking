# Agent Blocking release runbook

## Apple distribution

1. In Apple Developer, the Account Holder requests Family Controls distribution for `online.do.card.agentblocking` and the `.FocusNotification`, `.FocusMonitor`, and `.FocusShield` bundle IDs. Wait for **Assigned** on each identifier and sign in to team `L546HV5KY7` in Xcode.
2. Create the iOS app record in App Store Connect with the standalone bundle ID. Set an unused build number in `AgentBlocking/project.yml` and regenerate the project. Archive and export from the tested Git commit.

   ```sh
   xcodebuild -project AgentBlocking/AgentBlocking.xcodeproj -scheme AgentBlocking \
     -configuration Release -destination 'generic/platform=iOS' \
     -archivePath /tmp/AgentBlocking.xcarchive -allowProvisioningUpdates archive
   xcodebuild -exportArchive -archivePath /tmp/AgentBlocking.xcarchive \
     -exportPath /tmp/AgentBlocking-Distribution \
     -exportOptionsPlist AgentBlocking/ExportOptions.plist -allowProvisioningUpdates
   ```

3. Validate the exported app and all three extensions. Verify Family Controls on all four binaries, the App Group on the app, notification service and monitor, and `aps-environment=production` on the app. Verify the privacy manifest is packaged and the policy link works. Upload the validated build and start with internal TestFlight.

## Production APNs relay

The `relay-production-apns` service in the `agent-blocking` Railway project uses its own `/data` volume, agent credential and public origin. The `relay` service serves Sandbox APNs. In the production service, set `APNS_KEY_ID` and pipe the Production `.p8` into `APNS_PRIVATE_KEY` using `railway variable set --stdin --skip-deploys`. The key must authorize `online.do.card.agentblocking`. The production relay must advertise `apnsEnvironment: production` at `/v1/phone-app`.

Stage only the Dockerfile, `.dockerignore`, package manifests, and `src` from the reviewed commit. Deploy using `railway up` with the exact project, environment and service selectors and the commit SHA in the deployment message. Verify `/healthz`, unauthenticated rejection, authenticated pairing and the full physical test below. Do not direct Sandbox phones to the production service.

Use the operator token only to issue scoped agent credentials through authenticated `POST /v1/agents`. Save each returned token in the recipient's private MCP token file. Each scoped agent can pair phones and access only its own devices. The hosted release is invite-only until a self-service enrollment flow and abuse limits are in place.

Set daily backups, verify backup creation, and rehearse restoring to a non-live copy before onboarding users. Route `command_receipt_missing`, `expiry_delivery_exhausted`, and `expiry_worker_failed` warnings into the production alert destination. Run a health monitor separately from the Railway deploy health check. Treat APNs acceptance as delivery to Apple and require the phone's receipt for command execution.

## Physical TestFlight checks

1. Pair a fresh install using a scoped test credential and confirm a phone snapshot appears.
2. Start a short session with Agent Blocking closed. Verify the selected app is shielded and an unselected app opens.
3. Send a remote stop with Agent Blocking closed. Relaunch the selected app and verify it opens.
4. Start another session and let it expire. Leave the selected app before the deadline and launch it fresh afterward. Verify both the visible result and the cleared phone snapshot.
5. While a session is active, go offline and use Emergency Unlock. Verify the shield clears on the phone.
6. Repeat lock and expiry after an app-switcher force quit. Disable notification alerts and verify the app explains how to re-enable them. Reconnect and verify expired commands cannot replay.
7. Restart the phone during a session and verify expiry after first unlock. Restart the relay during another session and verify the phone can still unlock locally.
8. Disconnect and verify the old credential cannot reach the phone. Confirm a new invitation can pair it again. Repeat the core checks on a second supported iPhone.

## App Review preparation

Describe the app as an individual focus tool that uses Screen Time to restrict only the apps and sites the user selected, within the approved hours and maximum duration. Explain the opt-in relay, visible notification results, automatic expiry, Emergency Unlock and Disconnect. Provide a reviewer-specific scoped credential and a simple way to issue a fresh pairing invitation and run start and stop. The review path must be available throughout review because pairing codes expire in ten minutes.

Use the [privacy policy](PRIVACY.md) for the metadata URL after verifying the public link. The manifest records device identifiers, product interaction, and app group labels for app functionality. Confirm the final disclosures against the deployed service and any integrated agent or SDK. Use the product support contact `do-card@do-card.online` and confirm the support URL. Capture current App Store screenshots showing app selection, approved limits, an active session and Emergency Unlock.
