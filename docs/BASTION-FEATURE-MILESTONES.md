# Bastion app feature development milestones

Working branch: `feature/bastion-v1-integration`. Keep `feature/bastion-beta` unchanged until device testing and explicit promotion.

**Definition of done:** implementation wired into the app UI and live services; unit/widget tests; CI green; physical-radio verification where applicable; documented limitations. A codec or standalone service alone is **not** a finished feature.

## Milestone A1 — radio configuration and BLE reliability
- [x] Draft node-name editor, validation, owner payload encoding, local admin packet transport helper, and fresh NodeInfo readback helper
- [x] Transport-independent bounded reconnect supervisor and tests
- [x] Confirm ADMIN_APP schema and firmware-specific session authentication against official firmware — generated from `meshtastic/protobufs` v2.8.1; session passkey handled; owner and channel writes verified on firmware 2.7.16
- [ ] Handle admin responses, negative acknowledgments, timeouts, and fresh readback with a single transactional controller — `MeshtasticAdminSession` handles responses, NAKs, timeouts and begin/commit transactions; automatic readback after a write is still missing
- [x] Enable Save only when authenticated, connected, and explicitly confirmed
- [ ] Integrate reconnect supervisor into actual BLE lifecycle; respect manual disconnect and Android Bluetooth state — integrated and respects manual disconnect; Android Bluetooth on/off state is not yet checked
- [x] Add Android foreground service and notification permission flow for background connectivity
- [ ] Physical radio tests on supported firmware and Android versions — passed on one radio (firmware 2.7.16); more firmware and Android versions still to cover

## Milestone A2 — messaging and node intelligence
- [ ] Delivery-state correctness, offline queue reconciliation, channel and DM UX — routing ACK delivery states and per-node DM threads done; offline queue reconciliation not re-verified
- [ ] Node favorites, notes, telemetry, signal history, traceroute and neighbors — favorites, notes, telemetry requests and traceroute (per-hop SNR) done; neighbor info not yet
- [ ] Protocol fixture tests and live radio verification — fixture tests cover admin, traceroute, channel links, nodes, positions and waypoints; live verification partial

## Milestone B1 — maps, GPS, field operations
- [x] Offline map tiles, location permissions, node positions, waypoints — viewed OpenStreetMap areas cached offline for a year (no bulk area downloads under the OSM tile policy)
- [ ] Check-ins, incident logs, emergency templates with delivery disclaimers
- [ ] Privacy controls and battery-aware tracking — phone GPS sharing is opt-in and throttled; no wider privacy settings yet

## Milestone B2 — bot and RF field tools
- [ ] Bot on/off, keywords, rate limits, anti-loop and quiet hours
- [ ] Coverage observations, terrain-assisted link planning and field-test exports

## Milestone C1 — backups, firmware and interface
- [ ] Encrypted/secret-safe backup and restore with explicit key handling
- [ ] Firmware capability checks, maintenance and supported upgrade path
- [ ] Theme, accessibility, notifications, dashboard customization — message notifications done; the rest not started

## Milestone C2 — Bastion exclusive features
- [ ] Network health scores and explainable recommendations
- [ ] Dead-zone and field-test history
- [ ] Optional BackCountrySignal integration with opt-in sharing

## Also delivered outside the milestones
- Every config section and module editable through a generated settings form
- Channel sharing as `meshtastic.org/e/#` links and QR codes, including camera scanning

## Release gates
- No claim of full official-app parity until every required feature is integrated and tested
- No automated release or Play publication without signing, privacy review and approval
- Real BLE and radio behavior cannot be certified by emulator or Flutter unit tests
