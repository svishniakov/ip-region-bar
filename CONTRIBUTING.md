# Contributing

Thanks for contributing to IP Region Bar.

## Local Development

1. Fork and clone this repository.
2. Open the project in Xcode (or use CLI build).
3. Build locally:

```bash
make build
```

## GeoIP Runtime Setup

The app no longer ships with a bundled GeoIP database.
On first launch, install DB-IP Lite from inside the app using **Download database now**.

## Homebrew Cask

This repository is also a Homebrew tap. The cask file is:

- `Casks/ipregionbar.rb`

For local verification:

```bash
brew tap svishniakov/ip-region-bar https://github.com/svishniakov/ip-region-bar
brew audit --cask --strict ipregionbar
```

Release workflow updates `version` and `sha256` in `Casks/ipregionbar.rb` automatically after a tagged release (`v*`).

Current release workflow does not require Apple signing/notarization secrets.
It builds a universal app, creates DMG, uploads release asset, and auto-bumps cask `version` + `sha256`.

## Code Style

Run SwiftLint before opening a PR:

```bash
swiftlint lint --strict
```

## Issues and Pull Requests

When filing issues, include:

- macOS version
- app version
- clear reproduction steps
- expected vs actual behavior

Keep pull requests focused, with docs/changelog updates when behavior changes.

## Attribution Note

DB-IP attribution is required by license and must remain present in app/UI/docs.
