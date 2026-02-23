# IP Region Bar

[![CI](https://github.com/<user>/ipregionbar/actions/workflows/build.yml/badge.svg)](https://github.com/<user>/ipregionbar/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)](https://support.apple.com/en-us/102861)
[![Homebrew](https://img.shields.io/badge/Homebrew-Cask-orange)](https://brew.sh)

IP Region Bar is a native macOS menu bar app (no Dock icon, no main window) that shows the geolocation of your current external IP in real time.

## Screenshot

![IP Region Bar menu screenshot](docs/assets/menu-screenshot.svg)

## Installation (Homebrew)

```bash
brew install --cask ipregionbar
```

## Manual Installation

1. Open [Releases](https://github.com/<user>/ipregionbar/releases).
2. Download `IPRegionBar.dmg`.
3. Drag `IPRegionBar.app` to `Applications`.
4. Launch the app.

## Build from Source

### Requirements

- macOS 13+
- Xcode 15 Command Line Tools
- SwiftLint (`brew install swiftlint`)

### Build

```bash
make build
```

### Package DMG

```bash
make dmg
```

## MaxMind Setup

IP geolocation is resolved locally from the GeoLite2-City database.

1. Register a free account at [maxmind.com](https://www.maxmind.com/).
2. Create a GeoLite2 License Key in your account.
3. On first app launch, paste the key into onboarding.
4. The app downloads `GeoLite2-City.mmdb` into:
   `~/Library/Application Support/IPRegionBar/GeoLite2-City.mmdb`

Your external IP is fetched from `api64.ipify.org` (or `checkip.amazonaws.com` fallback), and geolocation lookup is done locally.

## Requirements

- macOS 13.0 Ventura or newer

## Privacy

- External IP is fetched via HTTPS from IP-only providers.
- Geolocation lookup runs locally using MaxMind database.
- MaxMind License Key is stored in Keychain.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).
