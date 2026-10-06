# Bastion

Independent Android Flutter companion for Meshtastic® devices, developed by **BackCountrySignal**, with a charcoal, muted sage and warm off-white theme.

**Website:** https://backcountrysignal.org/
**Repository:** https://github.com/backcountrysignal/Bastion-Meshtastic

Bastion brings radio connections, mesh messaging, node information, mapping and local field automations into one Android app. It remains a development build pending physical-radio QA and production signing.

## Implemented features

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
- Foreground monitoring by default; opt-in Android connected-device service supports screen-off operation. Disconnects pause rules and Bot Mode.
- Node map with tappable saved positions, distance/bearing measurements and optional online street tiles.
- Local node archive and received telemetry history, separated by radio identity.
- Field dashboard with search, low-battery filtering, node details and battery/SNR observation charts.

**Development build, not a completed release.** BLE hardware validation is pending.
Provider-downloaded offline maps, production signing, radio
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
alerts. Silence alerts require continuously connected monitoring for
the configured duration; phone disconnection is not a repeater outage.
Android notifications can be enabled in AUTO. Screen-off monitoring requires the explicit
NODES connection service; notifications reflect new live alerts while connected.

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
- [x] Opt-in Android connected-device service; screen-off hardware validation pending.
- [x] Node positions, interactive map and geometric distance/bearing.
- [x] Importable offline XYZ PNG map packs.
- [ ] Provider downloads, MBTiles/PMTiles, GPX and traceroute diagnostics.
- [x] Custom thresholds, node/radio targets and rule editing.
- [ ] Geofences and opt-in scheduled messages.
- [x] Measured receiver observations with explicit phone fix and CSV copying.
- [ ] Full field missions and repeater dashboard.
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
Online mode does not download regions or guarantee offline tiles. Imported packs (below) supply offline tiles. Cached node markers
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
run approximately once a minute and require continuous connected monitoring for
the full selected duration. Alerts carry their source radio, and history can be
filtered or cleared independently of saved rules. Legacy alerts may have no radio ID.

Android notifications are off by default. Enable them in AUTO and accept the phone's
permission prompt, then use SEND TEST NOTIFICATION. New live alerts use a local
notification channel; restored history and simulated rules do not replay as system
notifications. Notification taps open AUTO. OS permission/channel settings and Do
Not Disturb may suppress notifications; in-app history remains available. Disabling
the toggle stops future notifications. This feature does not schedule alarms,
keep Bluetooth running themselves. The separate NODES screen-off service is required for background monitoring.
The native notification permission, icon and desugaring setup is generated by
scripts/prepare_android.py. Notification behavior requires Android device QA.

SETTINGS → COPY DIAGNOSTICS copies firmware, connection state, local node identity,
node/channel counts and malformed-frame count for support. It omits raw configuration,
channel keys, channel names, messages, coordinates and Bluetooth addresses.

## Bot Mode (v0.4)

Open **AUTO → BOT SETTINGS** to customize an away reply, choose `!help` / `!status`,
set a 1–60 minute sender cooldown, and optionally select channels for commands.
Save, connect a radio, and switch **Bot Mode ON**. It defaults OFF on every app
launch and turns OFF on disconnect or settings changes. Without the explicit screen-off service, backgrounding also turns it OFF. It is
armed only for the current connected radio. There is no automatic service start,
server, AI service, subscription, scheduling, reply queue, or automatic retry.

Normal direct messages can receive the custom away reply. Channel replies are
OFF by default; if enabled, only exact `!help` and `!status` commands on explicitly
selected, currently enabled channel indices trigger a broadcast reply. Ordinary
channel conversations never trigger away replies. `!status` shares the radio ID,
known-node count and active bot status, without coordinates, messages, channel
keys or firmware/configuration contents. Direct-message encryption follows radio
configuration, as it does for manually sent messages.

Every reply starts with `[Bastion bot]`. The bot ignores this marker, outgoing
messages/status events, duplicate packet IDs, invalid senders, missing packet IDs,
messages older than two minutes, future-dated packets, and unknown `!commands`.
One cooldown is shared across channels for each sender/radio pair. A global
30-second spacing and **six reply attempts per rolling hour across all radios**
are always enforced. Failed or unconfirmed writes consume the limit. Limits
survive app restart, editing settings and clearing the activity log. These
safeguards reduce loops and traffic; they cannot identify every third-party bot.
A packet without a radio receive timestamp uses its local receipt time, so its
original age cannot be verified.

The activity log retains 100 entries and shows the latest 20, including skipped
triggers and actual send-state updates. A radio write is not delivery; mesh
acknowledgement is not a read receipt. Bot replies also appear in CHATS. Logs and
settings stay on the phone; incoming message bodies are not duplicated in bot
logs. Replies plus the bot marker must fit Meshtastic's 233-byte UTF-8 payload.
Real-radio interoperability and Android lifecycle testing remain required.


## Field connection, offline maps and measurements (v0.5)

**NODES** now offers two explicit controls, OFF on every launch:

- **Keep connection with screen off:** starts an Android `connectedDevice` foreground
  service while the app is visible and a verified radio is connected. Notification
  permission is required so the persistent connection notification and STOP action
  remain available. A retained Flutter engine owns the existing BLE session. A
  partial wake lock and a six-hour maximum lease support Dart timers with the screen
  off. A missing heartbeat for 90 seconds ends the lease. This consumes more phone
  battery; manufacturers' process/battery restrictions can still interrupt operation.
- **Recover dropped connections:** retries only the user-selected BLE transport with
  5/10/20/40/60 second delays (at most five attempts per outage). Configuration must
  complete and match the originally verified node ID. Different identity or exhausted
  retries stop the service. Manual DISCONNECT, notification STOP, app closure from
  Recents, force-stop and reboot end the session. There is no boot receiver, sticky
  restart, message retransmission, or automatic Bot Mode rearming after a drop.

With the service active, connected monitoring and explicitly enabled Bot Mode can
continue while switching apps or turning the screen off. Without it, backgrounding
still disconnects the radio. Turning the service toggle OFF disconnects and cancels
recovery. Real-phone screen-off, STOP, pairing, reconnect and power-use tests remain
required; CI does not verify Android scheduling or radio interoperability.

**MAP → OFFLINE MAP PACK** imports one local ZIP containing XYZ `z/x/y.png` tiles
and `metadata.json` at the ZIP root. Metadata requires a name, attribution/license
notice, center latitude/longitude and integer min/max zoom. The UI contains an example.
Tiles are square PNG images of 256 or 512 pixels, zoom 0–19, with valid XYZ indices.
The importer rejects path traversal, duplicate files, unexpected files, data-bearing
ZIP directories and oversized input; limits are 128 MiB compressed, 256 MiB expanded,
10,000 tiles and 12,000 total entries. A failed/cancelled import retains the previous
pack; replacement uses staging and rollback. Pack attribution stays on the map.
Missing areas remain blank, with no network fallback. Use legally obtained packs;
Bastion does not bulk-download OpenStreetMap or other providers. MBTiles/PMTiles,
GPX routes and provider region downloads remain future work.

**TOOLS → CAPTURE RECEIVER POINT** requests a fresh phone location only while the
app is visible. No background GPS permission or continuous GPS tracking is used.
A fix must have reported accuracy within 100 m and is valid for two minutes. Hold
still at that point. Received packets containing SNR/RSSI become measured receiver
observations, at most one per sender/radio per 30 seconds; MQTT and stale/invalid
readings are excluded. Positions from remote nodes are not substituted for the phone.
The radio's reported SNR/RSSI can describe the last relay hop rather than the original
sender, so these points are evidence of reception near a captured receiver fix, not
proof of a direct link or continuous coverage. Unmeasured areas remain unknown.
Disconnect and expired location fixes pause recording; reconnect never rearms it.

Up to 2,000 points are retained for 30 days, separately from node, chat and bot
history. MAP shows amber receiver-observation markers; tap one for readings and fix
age/accuracy, or fit recorded points. CSV copying includes receiver coordinates,
packet/record/fix timestamps, source/receiver node IDs and present signal readings.
Clearing observations keeps node/chat/automation history and offline tiles.

## Branding and trademark attribution

Bastion is independently branded and is not affiliated with or endorsed by
Meshtastic LLC or the Meshtastic project. The Meshtastic name is used descriptively
to identify device compatibility, not in the app name or launcher branding.
No official Meshtastic logo is incorporated into Bastion's icon.

Meshtastic® is a registered trademark of Meshtastic LLC. Meshtastic software
components are released under various licenses, see GitHub for details.
No warranty is provided - use at your own risk.

Project: https://meshtastic.org
Software licenses: https://github.com/meshtastic
Trademark guidance: https://meshtastic.org/docs/legal/licensing-and-trademark/

## Interface and project goals

- **NODES:** Bluetooth discovery, verified radio sessions and live node information.
- **CHATS:** Channel and direct messages, saved history and send status.
- **MAP:** Node positions, optional online street tiles and imported offline map packs.
- **TOOLS:** Field dashboard, telemetry observations and receiver measurement capture.
- **AUTO:** Editable local alert rules and optional Bot Mode.
- **SETTINGS:** Read-only radio information, diagnostics and compatibility notices.

Bastion focuses on off-grid operation, field-friendly navigation, network visibility and useful local automation. USB/TCP transports, writable radio settings, traceroute and additional offline map formats remain future work.

## Contributing and hardware testing

Report bugs, feature requests and hardware findings at https://github.com/backcountrysignal/Bastion-Meshtastic/issues. Include the phone model, Android version, radio model and firmware version. Copy diagnostics from SETTINGS; do not publish channel keys or private messages.

Before release, verify pairing, configuration download, channel/direct messaging with a second radio, acknowledgements, disconnect/recovery, notification STOP, screen-off operation, GPS capture and offline-pack import on physical Android hardware. CI verifies source analysis, automated tests and Android compilation; it cannot perform these radio checks.
