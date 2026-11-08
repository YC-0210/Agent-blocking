# Agent Blocking Privacy Policy

Agent Blocking helps you pause the apps and websites you choose for a focus session. You grant Apple Screen Time access on your iPhone and choose what your paired agent can control. The app uses that access to enforce the limits you approve.

## What stays on your iPhone

The app stores your Screen Time selection and authorization state on your iPhone. The hosted relay does not receive your Screen Time selection tokens, browsing history, or installed-app inventory. The app stores its relay credential in the iOS Keychain.

## What the relay receives

The relay stores a randomly assigned device ID, your Apple push token, and the current focus settings and session status. That status includes the number of items selected, approved hours, time zone and maximum session length. The relay also stores session commands and their results so your paired agent can check whether your phone applied them. If you provide labels for app groups, those labels may appear in your agent’s controls.

Railway hosts the Agent Blocking relay. Apple Push Notification service uses your push token to deliver focus notifications. Your paired agent receives the focus status and command results needed to control the sessions you approve. If you connect to a relay operated by someone else, that operator handles the data sent to that relay. Agent Blocking does not use this data for advertising or tracking.

## Your controls and retention

Emergency Unlock ends the current session on your phone, including when you are offline. Disconnect agent removes the approval from your phone and requests deletion of the device record, its commands and its expiry jobs from the relay. If the network request fails, retry Disconnect when you are online. You can also revoke Screen Time or notification permissions in iOS Settings.

The hosted relay expires unused pairing codes after ten minutes and removes finished command records after 30 days. Device registration and the latest focus status are retained until you disconnect or request deletion. Deleted records can remain in backups until those backups expire.

For privacy or deletion requests, email [do-card@do-card.online](mailto:do-card@do-card.online). Please keep pairing codes and access tokens private.
