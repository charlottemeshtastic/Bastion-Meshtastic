# Bastion — Meshtastic Edition

Independent Android Flutter companion for Meshtastic with Bastion's black/charcoal/cyan identity.

## Implemented in this development branch

- Filtered Meshtastic BLE discovery, GATT validation and manual radio connection.
- ToRadio/FromRadio protobuf session with configuration nonce validation and timeout.
- Read-only configuration/channel/module download and firmware/local-node information.
- Verified node database view with names, last heard, battery/external power, SNR/RSSI,
  hop information when supplied, and positions.
- Live telemetry and node updates with bounded packet deduplication.
- Free local automation presets: battery below 20%, new node and 12-hour silence.
- Locally saved rules and up to 200 live alerts; isolated simulator for use without hardware.
- Foreground-only monitoring: pauses on Bluetooth disconnect, radio reboot or app background.

**Development build, not a completed release.** BLE hardware validation is pending.
Channel/direct messaging, maps, system notifications, background monitoring, radio
configuration writes and release signing remain outstanding. Do not rely on this
development build for emergency communications.

## Build

Requires Flutter 3.41.5, Java 17, Android SDK, Python 3 and protoc.
On Ubuntu install protoc with `sudo apt-get install protobuf-compiler`.

```sh
flutter create --platforms=android --org app.bastion --project-name bastion_meshtastic .
rm -f test/widget_test.dart
python3 scripts/prepare_android.py
flutter pub get
python3 scripts/generate_protos.py
dart run flutter_launcher_icons
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64
```

Protocol source is vendored at a pinned upstream revision in protos/UPSTREAM.md.
The generator uses protoc_plugin 25.0.0 and protobuf 6.0.0. Generated Dart files
are reproducible build outputs. CI performs the same generation and validation.

Android app ID: `app.bastion.bastion_meshtastic`.
Use a separate Meshtastic edition signing key; do not reuse the MeshCore key.
The CI APK is a development artifact and does not establish production signing.

## Try a radio

1. Enable Bluetooth on the radio and phone.
2. Open NODES, scan, and select a radio. Accept the Android pairing request.
3. Wait for **Ready · verified Meshtastic session**. Only a matching completed
   configuration download marks the session ready.
4. Inspect verified nodes, and open SETTINGS for read-only radio information.
5. Add an AUTO rule. Live telemetry creates in-app alerts and saved history.

Downloaded node history seeds the automation engine silently, so reconnecting
does not label the entire database as newly discovered. Unknown timestamps and
battery readings remain unknown. Powered radios do not trigger low-battery
alerts. Silence alerts require continuously connected foreground monitoring for
the configured duration; phone disconnection is not a repeater outage.
Android system notifications and background execution are not implemented.

## Focused roadmap

- [x] Saved local rules and isolated simulation.
- [x] Pinned official protocol definitions and testable session.
- [x] BLE connection, configuration download and verified node view.
- [x] Live node/telemetry events connected to local rules and saved alert history.
- [ ] Hardware pairing/reconnect/interoperability QA.
- [ ] Persistent verified node/message database and telemetry history.
- [ ] Channel and direct messaging with honest delivery feedback.
- [ ] Android notifications and foreground service for background monitoring.
- [ ] Map/positions, traceroute and network diagnostics.
- [ ] Custom thresholds/targets, geofences and opt-in scheduled messages.
- [ ] Field coverage sessions and repeater dashboard.
- [ ] Release signing, privacy/license review and transport expansion.

## Licenses

The vendored Meshtastic definitions and generated bindings are GPL-3.0-only.
See NOTICE.md and protos/LICENSE for source-distribution requirements.
FlutterBluePlus 2.1.0 has a separate license: present use is personal/noncommercial;
review that dependency before commercial distribution. No Socialmesh implementation
or branding is copied. Bastion is independent and not an official Meshtastic app.
