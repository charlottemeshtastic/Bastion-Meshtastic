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
