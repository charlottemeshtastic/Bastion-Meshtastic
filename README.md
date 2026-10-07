# Bastion — Meshtastic Edition

**Bastion Meshtastic** is an independent Android Flutter companion for Meshtastic, developed by **BackCountrySignal** with a field-focused interface for off-grid mesh communications.

**Website:** [backcountrysignal.org](https://backcountrysignal.org/)  
**Repository:** [BastionMeshApp/Bastion-Meshtastic](https://github.com/BastionMeshApp/Bastion-Meshtastic)

> **Development status:** Bastion Meshtastic is currently under active development. The present repository is an early application scaffold. BLE discovery and the core UI shell are the initial scope; BLE discovery alone does not establish a Meshtastic protocol session. Messaging, live node data, mapping, radio configuration, signing, and hardware QA must be completed and tested before the app should be relied upon for field or emergency communications.

## Mission

Bastion is being built as a clean, capable Meshtastic client for backcountry users, community mesh networks, radio enthusiasts, preparedness, field deployments, and emergency communications.

The project emphasizes:

- Reliable off-grid operation
- Field-friendly controls and navigation
- Clear mesh and radio diagnostics
- Low-distraction visual design
- Offline-capable mapping and tools
- Network visibility and node intelligence
- Privacy-conscious operation
- Open-source development
- Useful automation without unnecessary complexity

## Interface

Bastion uses a black/charcoal field-oriented visual identity with streamlined primary navigation:

- **NODES** — discovered nodes, status, telemetry, signal information, and network intelligence
- **CHATS** — direct messages and channel communications
- **MAP** — node locations, field information, coverage, and future offline mapping
- **TOOLS** — diagnostics, traceroute, radio and field utilities
- **SETTINGS** — application, connection, radio, privacy, and appearance controls

## Development Roadmap

### 1. Foundation

- Android Flutter application foundation
- Bastion branding and visual system
- Core navigation and UI shell
- BLE device discovery
- Continuous integration and automated checks

### 2. Meshtastic Protocol

- Meshtastic ToRadio / FromRadio protobuf integration
- BLE radio session
- Configuration download
- Node database
- Connection state and recovery handling

### 3. Messaging

- Direct messages
- Channel messaging
- Message history
- Delivery state
- Notifications
- Field-friendly conversation interface

### 4. Field Intelligence

- Live node information
- GPS and map integration
- Telemetry
- Traceroute
- Signal and route diagnostics
- Offline maps
- Coverage and field-test sessions

### 5. Device & Network Tools

- Supported USB and TCP transports
- Radio settings
- Device diagnostics
- Network diagnostics
- Optional MQTT integration
- Troubleshooting utilities

### 6. Release Readiness

- Automated testing
- Physical hardware testing
- Device compatibility testing
- Privacy review
- License review
- Release documentation
- Dedicated Bastion Meshtastic signing credentials

## Local Development

### Requirements

- Flutter 3.41.5
- Java 17
- Android SDK

Clone the repository:

```sh
git clone https://github.com/BastionMeshApp/Bastion-Meshtastic.git
cd Bastion-Meshtastic
```

Prepare and run the project:

```sh
flutter create --platforms=android --org app.bastion --project-name bastion_meshtastic .
python3 scripts/prepare_android.py
flutter pub get
dart run flutter_launcher_icons
flutter analyze
flutter test
flutter run
```

## Android Application

Application ID:

```text
app.bastion.bastion_meshtastic
```

The approved Bastion application icon belongs at:

```text
branding/bastion-icon.png
```

Bastion Meshtastic must use its own release-signing credentials. **Do not reuse the MeshCore Bastion release keystore for this application.**

## Building

During development, a debug APK can be produced with:

```sh
flutter build apk --debug
```

When release signing and release QA are complete, the Android release build can be produced with:

```sh
flutter build apk --release
```

A release build should not be distributed as production-ready until hardware testing, signing, licensing, and required QA have been completed.

## Safety & Field Use

Bastion is intended to become useful for backcountry and emergency communications, but software alone should never be treated as a guaranteed emergency lifeline.

During the current development stage, do not rely on Bastion Meshtastic as the sole method of emergency communication. Users should maintain appropriate backup communications and safety plans for their environment.

## Meshtastic Compatibility & Attribution

Bastion Meshtastic is an **independent project** and is not the official Meshtastic application.

Meshtastic is an open-source ecosystem. Components incorporated from Meshtastic projects must retain their applicable licenses, notices, attribution, and source-distribution requirements.

Official Meshtastic resources:

- [Meshtastic](https://meshtastic.org/)
- [Meshtastic GitHub organization](https://github.com/meshtastic)

The official Meshtastic Android application and relevant upstream components have their own licensing requirements. Review and preserve the applicable upstream licenses before incorporating or distributing upstream code.

## Contributing

Contributions, testing, bug reports, hardware compatibility reports, and feature ideas are welcome.

Use the repository's [GitHub Issues](https://github.com/BastionMeshApp/Bastion-Meshtastic/issues) section for:

- Bug reports
- Feature requests
- Hardware compatibility findings
- UI and usability suggestions
- Meshtastic protocol issues
- Field-test observations

## BackCountrySignal

Bastion Meshtastic is developed as part of the **BackCountrySignal** project.

Visit [backcountrysignal.org](https://backcountrysignal.org/) for project information, mesh resources, tools, and future Bastion updates.

## License

Review the license files included in this repository before using, modifying, or distributing the software.

Any incorporated upstream Meshtastic code, protobuf definitions, libraries, assets, trademarks, or other third-party material remains subject to its respective license and usage requirements.

## Build validation

Pull requests and pushes are validated by the Android CI workflow with Flutter analysis, tests, an ARM64 release APK build, and a retained APK artifact.
