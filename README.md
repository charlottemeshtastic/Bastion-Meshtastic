# Bastion

**Bastion** is an independent Android field-mesh application developed by **BackCountrySignal**. It interoperates with devices running Meshtastic® firmware while maintaining its own name, icon, interface, and project identity.

> **Independent project:** Bastion is not affiliated with, sponsored by, endorsed by, or an official application of Meshtastic LLC.

## Development status

Bastion is under active development. BLE transport, PhoneAPI synchronization, NodeDB, channel/direct messaging, offline queueing, and field tooling are being developed and tested. Do not rely on a development build as the sole method of emergency communication.

## Mission

Bastion is designed for backcountry users, community mesh networks, radio enthusiasts, preparedness, field deployments, and emergency-communications support. The project emphasizes reliable offline operation, field-friendly controls, radio diagnostics, network visibility, privacy-conscious operation, and useful automation.

## Interface

Bastion uses its own black/charcoal field-oriented identity with restrained signal accents. Primary navigation is:

- **NODES** — discovered radios, nodes, status, telemetry, signal information, and network intelligence
- **CHATS** — direct and channel communications
- **MAP** — node locations, field information, coverage, and offline mapping
- **TOOLS** — diagnostics, traceroute, radio, and field utilities
- **SETTINGS** — application, connection, radio, privacy, appearance, and legal notices

## Compatibility

Bastion implements interoperability with the public protocol used by Meshtastic® firmware. Technical references to Meshtastic® in source code and documentation describe compatibility or protocol behavior; they are not Bastion product branding.

Bastion does not use “Meshtastic” in its primary or secondary software product name. The official Meshtastic logo is not used as the Bastion application icon or primary branding.

## Trademark and licensing notice

Meshtastic® is a registered trademark of Meshtastic LLC. Meshtastic software components are released under various licenses, see GitHub for details. No warranty is provided - use at your own risk.

Bastion is independently developed and is not affiliated with, sponsored by, or endorsed by Meshtastic LLC. All Meshtastic® trademarks remain the property of Meshtastic LLC.

Official policy and project information:

- Licensing and trademark rules: https://meshtastic.org/docs/legal/licensing-and-trademark/
- Official website: https://meshtastic.org/
- Official GitHub organization: https://github.com/meshtastic

See [TRADEMARKS.md](TRADEMARKS.md) for Bastion's trademark-use rules.

## Upstream software and third-party licenses

Meshtastic software components are released under various licenses. Bastion must preserve all applicable license notices, attribution, source-distribution obligations, and other requirements for any upstream component that is actually incorporated into the project.

Bastion's current protocol codec is independently implemented for interoperability rather than copied generated protobuf source. Before any future upstream source, generated code, library, or asset is incorporated, its license must be reviewed and its obligations documented.

Third-party Flutter/Dart dependencies remain subject to their respective licenses.

## Android application

Bastion's Android display name is **Bastion**. CI generates the Android project using the Dart project name `bastion` and organization `org.backcountrysignal`.

The Bastion application icon is located at:

```text
branding/bastion-icon.png
```

The icon and Bastion visual identity are independent artwork and must not incorporate the official Meshtastic logo unless a future use is separately authorized and complies with the then-current trademark rules.

## Local development

Requirements:

- Flutter 3.41.5
- Java 17
- Android SDK

After cloning this repository:

```sh
flutter create --platforms=android --org org.backcountrysignal --project-name bastion .
python3 scripts/prepare_android.py
flutter pub get
dart run flutter_launcher_icons
flutter analyze
flutter test
flutter run
```

## Build validation

Pull requests and pushes are validated by the Android CI workflow with Flutter analysis, tests, an ARM64 release APK build, and a retained APK artifact.

A build should not be represented as production-ready until hardware testing, release signing, dependency/license review, privacy review, and release QA are complete.

## Safety

Bastion may support field and emergency-communications workflows, but software and mesh radio links are not guaranteed emergency lifelines. Maintain appropriate backup communications and safety plans for the environment in which Bastion is used.

## Contributing

Testing, bug reports, hardware compatibility reports, and feature ideas are welcome. Contributions must preserve Bastion's independent branding and comply with [TRADEMARKS.md](TRADEMARKS.md) and all applicable third-party licenses.
