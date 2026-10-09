# Bastion app feature development milestones

Working branch: `feature/bastion-v1-integration`. Keep `feature/bastion-beta` unchanged until device testing and explicit promotion.

**Definition of done:** implementation wired into the app UI and live services; unit/widget tests; CI green; physical-radio verification where applicable; documented limitations. A codec or standalone service alone is **not** a finished feature.

## Milestone A1 — radio configuration and BLE reliability
- [x] Draft node-name editor, validation, owner payload encoding, local admin packet transport helper, and fresh NodeInfo readback helper
- [x] Transport-independent bounded reconnect supervisor and tests
- [ ] Confirm ADMIN_APP schema and firmware-specific session authentication against official firmware
- [ ] Handle admin responses, negative acknowledgments, timeouts, and fresh readback with a single transactional controller
- [ ] Enable Save only when authenticated, connected, and explicitly confirmed
- [ ] Integrate reconnect supervisor into actual BLE lifecycle; respect manual disconnect and Android Bluetooth state
- [ ] Add Android foreground service and notification permission flow for background connectivity
- [ ] Physical radio tests on supported firmware and Android versions

## Milestone A2 — messaging and node intelligence
- [ ] Delivery-state correctness, offline queue reconciliation, channel and DM UX
- [ ] Node favorites, notes, telemetry, signal history, traceroute and neighbors
- [ ] Protocol fixture tests and live radio verification

## Milestone B1 — maps, GPS, field operations
- [ ] Offline map tiles, location permissions, node positions, waypoints
- [ ] Check-ins, incident logs, emergency templates with delivery disclaimers
- [ ] Privacy controls and battery-aware tracking

## Milestone B2 — bot and RF field tools
- [ ] Bot on/off, keywords, rate limits, anti-loop and quiet hours
- [ ] Coverage observations, terrain-assisted link planning and field-test exports

## Milestone C1 — backups, firmware and interface
- [ ] Encrypted/secret-safe backup and restore with explicit key handling
- [ ] Firmware capability checks, maintenance and supported upgrade path
- [ ] Theme, accessibility, notifications, dashboard customization

## Milestone C2 — Bastion exclusive features
- [ ] Network health scores and explainable recommendations
- [ ] Dead-zone and field-test history
- [ ] Optional BackCountrySignal integration with opt-in sharing

## Release gates
- No claim of full official-app parity until every required feature is integrated and tested
- No automated release or Play publication without signing, privacy review and approval
- Real BLE and radio behavior cannot be certified by emulator or Flutter unit tests
