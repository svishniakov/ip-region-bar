# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.3]

### Fixed
- Надёжное обновление региона при смене сети и VPN. Раньше статус-бар не обновлялся или обновлялся с задержкой при включении/выключении/смене VPN.
  - `NetworkMonitor` теперь строит сигнатуру сети по именам интерфейсов (`en0`, `utun4`, …), а не только по типам — появление или смена VPN-интерфейса ловится надёжно.
  - Обновление запускается на любое `.satisfied`-событие сети с debounce (1с при явной смене интерфейса, 3с в остальных случаях), а не только при смене интерфейса.
  - Периодический таймер переведён в `.common` run-loop mode — больше не замерзает при открытом меню или окне настроек.
- Добавлены юнит-тесты для детектирования смены интерфейсов (`NetworkMonitorTests`).

## [Unreleased]

### Changed
- Migrated app architecture to PRD v2 (DB-IP Lite, zero onboarding).
- Replaced MaxMind license-key flow with manual first-run DB-IP download flow.
- Reworked preferences Database tab for DB version/update/attribution.
- Added About menu with required DB-IP attribution.
- Switched Homebrew cask source to `Casks/ipregionbar.rb` for tap compatibility.
- Updated release pipeline to build universal app (`arm64 + x86_64`) and auto-bump cask version/sha256.
- Simplified release pipeline to operate without paid Apple Developer signing/notarization.
- Removed bundled DB files from repository/build/release artifacts.
- Moved Homebrew tap publishing to dedicated repository `svishniakov/homebrew-ip-region-bar` for short `brew tap svishniakov/ip-region-bar` installs.

### Removed
- Onboarding window and Keychain-based license key flow.
