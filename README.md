# Bastion — Meshtastic Edition

Independent Android Flutter companion for Meshtastic with Bastion's black/charcoal/cyan identity.

## Implemented in this development branch

- Filtered Meshtastic BLE discovery, GATT validation and manual radio connection.
- ToRadio/FromRadio protobuf session with configuration nonce validation and timeout.
- Read-only configuration/channel/module download and firmware/local-node information.
- Verified node database view with names, last heard, battery/external power, SNR/RSSI,
  hop information when supplied, and positions.
- Live telemetry and node updates with bounded packet deduplication.
- Channel and direct text messaging with UTF-8 byte limits and enabled-channel validation.
- Locally saved chat history scoped by radio; routing acknowledgement/failure and unconfirmed status.
- Editable free local automations: battery thresholds, new nodes and silence timers, with radio/node targeting.
- Locally saved rules and up to 200 live alerts; isolated simulation matches custom thresholds and targets.
- Opt-in Android notifications for new live alerts, with a permission flow and test button.
- Copyable connection diagnostics that exclude channel keys, messages, node coordinates and BLE addresses.
- Foreground-only monitoring: pauses on Bluetooth disconnect, radio reboot or app background.
- Node map with tappable saved positions, distance/bearing measurements and optional online street tiles.
- Local node archive and received telemetry history, separated by radio identity.
- Field dashboard with search, low-battery filtering, node details and battery/SNR observation charts.

**Development build, not a completed release.** BLE hardware validation is pending.
Downloadable offline street maps, background monitoring, radio
configuration writes and release signing remain outstanding. Do not rely on this
development build for emergency communications.

## Build

Requires Flutter 3.41.5, Java 17, Android SDK 36, Python 3 and protoc.
This Android build supports Android 7.0/API 24 and newer.
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
Android notifications can be enabled in AUTO. Background monitoring is not implemented;
notifications only reflect live alerts produced while the app is open and connected.

## Focused roadmap

- [x] Saved local rules and isolated simulation.
- [x] Pinned official protocol definitions and testable session.
- [x] BLE connection, configuration download and verified node view.
- [x] Live node/telemetry events connected to local rules and saved alert history.
- [ ] Hardware pairing/reconnect/interoperability QA.
- [x] Bounded local message history (1,000 messages across radios).
- [x] Persistent verified node database and received telemetry history.
- [x] Channel and direct messaging with honest delivery feedback.
- [x] Opt-in Android notifications for live alerts.
- [ ] Foreground service and background monitoring.
- [x] Node positions, interactive map and geometric distance/bearing.
- [ ] Downloadable offline basemaps, traceroute and network diagnostics.
- [x] Custom thresholds, node/radio targets and rule editing.
- [ ] Geofences and opt-in scheduled messages.
- [ ] Field coverage sessions and repeater dashboard.
- [ ] Release signing, privacy/license review and transport expansion.

## Licenses

The vendored Meshtastic definitions and generated bindings are GPL-3.0-only.
See NOTICE.md and protos/LICENSE for source-distribution requirements.
FlutterBluePlus 2.1.0 has a separate license: present use is personal/noncommercial;
review that dependency before commercial distribution. No Socialmesh implementation
or branding is copied. Bastion is independent and not an official Meshtastic app.

## Messaging

Open CHATS after the radio reaches Ready, choose an enabled channel or a discovered
remote node, type a message and send. Direct messages use the current primary channel;
the radio controls encryption. This build does not promise recipient-only encryption.

Chat history is stored locally (up to 1,000 messages), separated by radio node number,
channel or direct peer, and can be browsed offline. A Bluetooth write is shown as
**Written to radio**, not delivery. Routing replies produce **Mesh acknowledged**
or a radio failure. An acknowledgement is not a read receipt or cryptographic
proof. Disconnects, write interruptions, app restarts and acknowledgement timeouts
leave unresolved sends **Delivery unconfirmed**. There are no automatic retries or
offline transmissions. Check history before manually resending.

Text payloads are limited to 233 UTF-8 bytes; emoji can consume multiple bytes.
Channel reconfiguration may change what a saved channel index refers to. Hardware
messaging and acknowledgement interoperability testing remains pending.

## Map and field history

MAP starts with saved position markers on a plain background and makes no tile
requests until **Online street map** is enabled. The online layer requests visible
areas from OpenStreetMap, with attribution, an app-specific user agent and the map
library's normal HTTP tile cache. It only runs while MAP is the active tab.
It does not download regions or guarantee offline street tiles. Cached node markers
and distance calculations work without internet. Distance/bearing is great-circle
geometry; it is not a terrain, line-of-sight, radio connectivity or coverage estimate.
Zero/zero, invalid and incomplete position reports cannot replace known positions.

TOOLS is the field dashboard. Tap a saved node for its details and received battery,
voltage, SNR/RSSI, channel utilization and transmit airtime values. Charts display
individual observations at their actual reception times, without interpolating
silent periods or filling in missing telemetry from cached values. Position timestamps
and last-heard times are shown separately. A last-known position can be stale, fixed
or imprecise, and battery summaries do not prove current reachability.

Phone-local storage retains up to 2,000 nodes and 4,000 readings across radios;
readings older than 30 days are removed. Clear a selected radio's node archive in
TOOLS; chats and automation history are separate. No node coordinates or telemetry
are uploaded by the archive. Enabling street tiles reveals the viewed map area to
OpenStreetMap's tile service. Reinstalling or clearing app data removes local history.

## Custom automations and Android alerts

AUTO → ADD RULE opens an editor with a name, trigger, threshold, radio scope and
optional target node. Battery rules accept 1–100%; silence durations accept
0.25–168 hours (0.5 means 30 minutes). Choose a known target or enter its eight-digit
hex node ID. Existing rules can be edited, disabled or removed. Up to 50 rules are
saved. Old preset rules remain compatible and default to any connected radio.

Each completed configuration download seeds a fresh monitor silently. Switching
radios discards the previous monitor's node set, and radio-scoped rules evaluate
only on the chosen radio. Battery rules consume fresh battery telemetry; unrelated
packets carrying a cached low reading cannot fire a battery alert. Conditions alert
once per monitoring session and rearm after recovery or a rule edit. Silence checks
run approximately once a minute and require continuous foreground monitoring for
the full selected duration. Alerts carry their source radio, and history can be
filtered or cleared independently of saved rules. Legacy alerts may have no radio ID.

Android notifications are off by default. Enable them in AUTO and accept the phone's
permission prompt, then use SEND TEST NOTIFICATION. New live alerts use a local
notification channel; restored history and simulated rules do not replay as system
notifications. Notification taps open AUTO. OS permission/channel settings and Do
Not Disturb may suppress notifications; in-app history remains available. Disabling
the toggle stops future notifications. This feature does not schedule alarms,
transmit messages or keep Bluetooth running after Bastion enters the background.
The native notification permission, icon and desugaring setup is generated by
scripts/prepare_android.py. Notification behavior requires Android device QA.

SETTINGS → COPY DIAGNOSTICS copies firmware, connection state, local node identity,
node/channel counts and malformed-frame count for support. It omits raw configuration,
channel keys, channel names, messages, coordinates and Bluetooth addresses.
