# Bastion — Meshtastic Edition

Independent Android Flutter companion for Meshtastic, using Bastion's black/charcoal/cyan visual identity and NODES / CHATS / MAP / TOOLS / SETTINGS navigation.

**Development status: early scaffold.** BLE discovery and the UI shell are the initial scope. BLE discovery does not establish a Meshtastic protocol session. Messaging, actual node data, maps, radio configuration, signing, and device QA are not yet implemented. Do not rely on this scaffold for emergency communications.

## Local setup

Requires Flutter 3.41.5, Java 17 and an Android SDK.

```sh
flutter create --platforms=android --org app.bastion --project-name bastion_meshtastic .
python3 scripts/prepare_android.py
flutter pub get
dart run flutter_launcher_icons
flutter analyze
flutter test
flutter run
```

Android application ID: `app.bastion.bastion_meshtastic` (separate from MeshCore Bastion). The approved Bastion icon belongs at `branding/bastion-icon.png`.

## Milestones

1. Foundation: repository, shell, approved branding, BLE discovery and CI.
2. Protocol: Meshtastic ToRadio/FromRadio protobufs, BLE radio connection, configuration download and node database.
3. Messaging: direct messages, channels, delivery status, history and notifications.
4. Field intelligence: live nodes, GPS/map, telemetry, traceroute, offline maps and coverage sessions.
5. Device tools: supported USB/TCP transports, settings, diagnostics and optional MQTT.
6. Release: full tests, hardware QA, privacy/license review and a **separate** Meshtastic edition release-signing key.

Meshtastic's official Android app and protobuf definitions are GPL-3.0 licensed. Preserve applicable licenses and source-distribution obligations before integrating those components. Bastion Meshtastic is independent and not an official Meshtastic app.

Do **not** use the MeshCore Bastion release keystore for this app.

## Local automations preview

The AUTO tab supports locally saved battery-below-20%, new-node and
12-hour-silence alert presets. Add, disable or remove rules, then use
**TEST WITH SIMULATED DATA** to preview alerts without radio hardware.
Rules persist locally; simulated alerts are temporary and isolated.

This first pass does not connect rules to BLE data, deliver Android system
notifications, or run in the background. Silence checks in the engine require
an active synchronized monitoring session. Repeated alerts are suppressed until
a condition recovers. No paid API or server is used.

## Focused development order

- [x] Local rules engine, saved presets and explicit simulator.
- [ ] Protocol: pinned official protobuf definitions, BLE GATT session,
  configuration completion and verified node repository.
- [ ] Connect node and telemetry events to local rules; persist alert history.
- [ ] Android notification permission and foreground monitoring lifecycle.
- [ ] Channel and direct messaging with delivery feedback and local history.
- [ ] Positions/map, telemetry charts, traceroute and topology inspection.
- [ ] Custom thresholds/targets, geofences and opt-in scheduled messages.
- [ ] Hardware QA, signed release and supported transport expansion.

Background monitoring requires Android lifecycle work and device testing;
scheduled transmissions must respect radio connectivity and mesh airtime.
