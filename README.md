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
- Free local automation presets: battery below 20%, new node and 12-hour silence.
- Locally saved rules and up to 200 live alerts; isolated simulator for use without hardware.
- Foreground-only monitoring: pauses on Bluetooth disconnect, radio reboot or app background.
- Node map with tappable saved positions, distance/bearing measurements and optional online street tiles.
- Local node archive and received telemetry history, separated by radio identity.
- Field dashboard with search, low-battery filtering, node details and battery/SNR observation charts.

**Development build, not a completed release.** BLE hardware validation is pending.
Downloadable offline street maps, system notifications, background monitoring, radio
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
- [x] Bounded local message history (1,000 messages across radios).
- [x] Persistent verified node database and received telemetry history.
- [x] Channel and direct messaging with honest delivery feedback.
- [ ] Android notifications and foreground service for background monitoring.
- [x] Node positions, interactive map and geometric distance/bearing.
- [ ] Downloadable offline basemaps, traceroute and network diagnostics.
- [ ] Custom thresholds/targets, geofences and opt-in scheduled messages.
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
