# PRD: IP Region Bar
**macOS Menu Bar Application**

Version: 1.2  
Status: Draft  
Target: Claude Code / Codex implementation  
License: MIT  
Distribution: GitHub + Homebrew Cask

---

## 1. Overview

IP Region Bar — нативное macOS-приложение без окна и Dock-иконки, которое живёт исключительно в системном menu bar и в режиме реального времени показывает геолокацию текущего внешнего IP-адреса машины.

### Goals
- Пользователь всегда видит, из какой страны/города выглядит его трафик
- Автоматическое обновление при смене сети (в том числе при подключении/отключении VPN)
- Минимальный footprint: нет окон, нет Dock-иконки, <15 МБ RAM в покое
- **Минимальная зависимость от сети** — геолокация резолвится локально по базе MaxMind
- **Privacy-first** — внешний IP не отправляется на сторонние геолокационные серверы

### Non-Goals
- Не является VPN-клиентом
- Не управляет сетевыми соединениями
- Не хранит историю IP

---

## 2. Tech Stack

| Компонент | Решение |
|---|---|
| Язык | Swift 5.9+ |
| UI | AppKit (`NSStatusItem`, `NSMenu`) |
| Сеть | `URLSession` (async/await) |
| Мониторинг сети | `Network.framework` → `NWPathMonitor` |
| Геолокация | MaxMind GeoLite2-City (локальная `.mmdb` база) |
| Парсер .mmdb | `MaxMind-DB-Reader-swift` (Swift Package) |
| Определение внешнего IP | `https://api64.ipify.org` (возвращает только IP, IPv4/IPv6) |
| Хранилище настроек | `UserDefaults` |
| Автозапуск | `SMAppService` (macOS 13+) |
| Минимальная версия macOS | 13.0 Ventura |
| Архитектура | Universal Binary (arm64 + x86_64) |
| Сборка | Xcode project + Swift Package Manager |

---

## 3. Project Structure

```
IPRegionBar/
├── IPRegionBar.xcodeproj
├── Package.swift                      # SPM: MaxMind-DB-Reader-swift
├── IPRegionBar/
│   ├── App/
│   │   ├── AppDelegate.swift          # точка входа, NSStatusItem
│   │   └── Info.plist                 # LSUIElement = YES
│   ├── Services/
│   │   ├── ExternalIPService.swift    # GET api64.ipify.org → String (IP)
│   │   ├── GeoLiteDatabase.swift      # загрузка, хранение, обновление .mmdb
│   │   ├── IPGeolocationService.swift # резолв IP через локальную базу MaxMind
│   │   └── NetworkMonitor.swift       # NWPathMonitor wrapper
│   ├── Models/
│   │   ├── IPInfo.swift               # результирующая структура данных
│   │   └── DatabaseStatus.swift       # состояние базы: актуальна / устарела / отсутствует
│   ├── UI/
│   │   ├── StatusBarController.swift  # управление NSStatusItem
│   │   ├── MenuBuilder.swift          # построение NSMenu
│   │   ├── PreferencesWindow.swift    # окно настроек
│   │   └── OnboardingWindow.swift     # первый запуск: ввод MaxMind License Key
│   ├── Helpers/
│   │   ├── FlagEmoji.swift            # ISO код → флаг emoji
│   │   └── LaunchAtLogin.swift        # SMAppService wrapper
│   └── Resources/
│       └── Assets.xcassets
├── .github/
│   └── workflows/
│       ├── build.yml
│       └── release.yml
├── Makefile
├── LICENSE
├── CHANGELOG.md
├── CONTRIBUTING.md
└── README.md
```

---

## 4. Data Model

```swift
// Models/IPInfo.swift

struct IPInfo: Codable {
    let ip: String
    let countryCode: String      // "DE"
    let countryName: String      // "Germany"
    let city: String             // "Frankfurt"
    let region: String           // "Hesse"
    let timezone: String         // "Europe/Berlin"
    // ISP недоступен в GeoLite2-City, только в платной GeoIP2-City
    // можно добавить в будущем через ASN базу (GeoLite2-ASN)

    var flagEmoji: String {
        FlagEmoji.from(countryCode: countryCode)
    }
}

// Models/DatabaseStatus.swift

enum DatabaseStatus {
    case missing                          // .mmdb файл не найден, нужен онбординг
    case downloading(progress: Double)    // идёт первая загрузка
    case ready(updatedAt: Date)           // база готова к использованию
    case outdated(updatedAt: Date)        // >7 дней, обновление на фоне
    case updateFailed(error: Error)       // ошибка обновления, старая база используется
}

enum AppState {
    case onboarding                       // нет License Key
    case loading
    case loaded(IPInfo)
    case offline(last: IPInfo?)
    case error(String)
}
```

---

## 5. Геолокация: MaxMind GeoLite2 + ipify

Архитектура разделена на два независимых запроса:

```
Запрос A  →  api64.ipify.org   →  текущий внешний IP (строка)
Запрос B  →  локальная .mmdb   →  геолокация по IP (мгновенно, без сети)
Фоново    →  MaxMind серверы   →  еженедельное обновление базы
```

### 5.1 Получение внешнего IP — ipify

```
GET https://api64.ipify.org?format=json
Response: {"ip": "185.220.101.42"}
```

- Бесплатно, без ключа, без лимитов
- Поддерживает IPv4 и IPv6 (api64 выбирает автоматически)
- Возвращает **только IP** — никакой геолокации, никаких логов

Fallback при недоступности ipify:
```
GET https://checkip.amazonaws.com
Response: 185.220.101.42\n
```

### 5.2 Геолокация — MaxMind GeoLite2-City

**База данных:**
- Формат: `.mmdb` (MaxMind DB binary format)
- Файл: `GeoLite2-City.mmdb` (~70 МБ распакованная)
- Хранится в: `~/Library/Application Support/IPRegionBar/GeoLite2-City.mmdb`
- Обновляется MaxMind каждый вторник

**Получение базы:**
- Требуется бесплатный аккаунт на maxmind.com
- После регистрации — License Key (бесплатно)
- URL загрузки:
```
https://download.maxmind.com/app/geoip_download
  ?edition_id=GeoLite2-City
  &license_key=YOUR_KEY
  &suffix=tar.gz
```

**Swift-библиотека:**
```swift
// Package.swift
dependencies: [
    .package(
        url: "https://github.com/maxmind/MaxMind-DB-Reader-swift.git",
        from: "1.0.0"
    )
]
```

**Резолв IP по базе:**
```swift
import MaxMindDBReader

let reader = try MaxMindDBReader(fileURL: databaseURL)
let record = try reader.lookup(ipAddress: "185.220.101.42")

let city       = record["city"]["names"]["en"].string ?? ""
let country    = record["country"]["names"]["en"].string ?? ""
let countryISO = record["country"]["iso_code"].string ?? ""
let region     = record["subdivisions"][0]["names"]["en"].string ?? ""
let timezone   = record["location"]["time_zone"].string ?? ""
```

### 5.3 GeoLiteDatabase — логика обновления

```swift
// Services/GeoLiteDatabase.swift

actor GeoLiteDatabase {

    static let shared = GeoLiteDatabase()

    private let dbPath = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("IPRegionBar/GeoLite2-City.mmdb")

    // Скачать или обновить базу
    func downloadOrUpdate(licenseKey: String) async throws {
        let url = URL(string: "https://download.maxmind.com/app/geoip_download"
            + "?edition_id=GeoLite2-City&license_key=\(licenseKey)&suffix=tar.gz")!
        // 1. Скачать .tar.gz во временную директорию
        // 2. Распаковать (Process + tar)
        // 3. Переместить .mmdb на место, заменив старую
        // 4. Сохранить дату обновления в UserDefaults
    }

    // Проверить актуальность: если >7 дней → обновить в фоне
    func checkAndUpdateIfNeeded(licenseKey: String) async {
        let lastUpdate = UserDefaults.standard.object(forKey: "dbLastUpdated") as? Date
        guard let lastUpdate else {
            try? await downloadOrUpdate(licenseKey: licenseKey)
            return
        }
        if Date().timeIntervalSince(lastUpdate) > 7 * 24 * 3600 {
            try? await downloadOrUpdate(licenseKey: licenseKey)
        }
    }

    var isReady: Bool {
        FileManager.default.fileExists(atPath: dbPath.path)
    }
}
```

**Распаковка tar.gz** — через `Process`:
```swift
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
process.arguments = ["-xzf", tarPath, "-C", tempDir, "--strip-components=1"]
try process.run()
process.waitUntilExit()
```

### 5.4 App Transport Security

Оба внешних хоста используют HTTPS — исключений в ATS не требуется.

---

---

## 6. Services

### 6.1 ExternalIPService

```swift
// Services/ExternalIPService.swift

actor ExternalIPService {

    static let shared = ExternalIPService()

    private let primaryURL   = URL(string: "https://api64.ipify.org?format=json")!
    private let fallbackURL  = URL(string: "https://checkip.amazonaws.com")!
    private let timeout: TimeInterval = 5

    func fetchIP() async throws -> String {
        do {
            return try await fetchFromIpify()
        } catch {
            return try await fetchFromAmazon()
        }
    }

    private func fetchFromIpify() async throws -> String {
        let (data, _) = try await URLSession.shared.data(from: primaryURL)
        let json = try JSONDecoder().decode([String: String].self, from: data)
        guard let ip = json["ip"] else { throw IPError.parseError }
        return ip
    }

    private func fetchFromAmazon() async throws -> String {
        let (data, _) = try await URLSession.shared.data(from: fallbackURL)
        let ip = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let ip else { throw IPError.parseError }
        return ip
    }
}
```

### 6.2 IPGeolocationService

```swift
// Services/IPGeolocationService.swift

actor IPGeolocationService {

    static let shared = IPGeolocationService()
    private var reader: MaxMindDBReader?

    func loadDatabase() throws {
        let dbURL = GeoLiteDatabase.shared.databaseURL
        reader = try MaxMindDBReader(fileURL: dbURL)
    }

    func lookup(ip: String) throws -> IPInfo {
        guard let reader else { throw GeoError.databaseNotLoaded }
        let record = try reader.lookup(ipAddress: ip)

        return IPInfo(
            ip:          ip,
            countryCode: record["country"]["iso_code"].string ?? "",
            countryName: record["country"]["names"]["en"].string ?? "",
            city:        record["city"]["names"]["en"].string ?? "",
            region:      record["subdivisions"][0]["names"]["en"].string ?? "",
            timezone:    record["location"]["time_zone"].string ?? ""
        )
    }
}
```

### 6.3 NetworkMonitor

```swift
// Services/NetworkMonitor.swift

final class NetworkMonitor {

    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.ipregionbar.netmonitor")

    var onPathChange: ((NWPath) -> Void)?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.onPathChange?(path)
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }
}
```

---

## 7. UI Specification

### 7.1 Menu Bar Label

Формат определяется настройкой `DisplayMode`:

| Режим | Пример |
|---|---|
| `flagCityCountry` (default) | `🇩🇪 Frankfurt, Germany` |
| `flagCountry` | `🇩🇪 Germany` |
| `flagOnly` | `🇩🇪` |
| `ipOnly` | `185.220.101.42` |

Состояния:

| AppState | Отображение |
|---|---|
| `.onboarding` | `🌐 Setup…` |
| `.loading` | `🌐 …` |
| `.loaded` | по DisplayMode |
| `.offline(last: nil)` | `🌐 —` |
| `.offline(last: info)` | `🇩🇪 Frankfurt ⚠️` |
| `.error` | `⚠️ Error` |

### 7.2 Dropdown Menu

```
🇩🇪 Frankfurt, Germany          ← заголовок (disabled, bold)
──────────────────────────────
IP:        185.220.101.42
Страна:    Germany
Город:     Frankfurt
Регион:    Hesse
Timezone:  Europe/Berlin
──────────────────────────────
База:      обновлена 2 дня назад  ← статус .mmdb (серый, мелкий)
──────────────────────────────
Обновить                  ⌘R
──────────────────────────────
Настройки…
──────────────────────────────
Выйти                     ⌘Q
```

Строки IP, Страна, Город — кликабельны: копируют значение в буфер обмена с уведомлением через `UNUserNotificationCenter`.

### 7.3 Onboarding Window (первый запуск)

Показывается при первом запуске, пока нет License Key и базы данных:

```
┌─────────────────────────────────────────┐
│           IP Region Bar Setup           │
│                                         │
│  Для работы приложения нужна бесплатная │
│  база данных MaxMind GeoLite2.          │
│                                         │
│  1. Зарегистрируйтесь на maxmind.com    │
│     [Открыть maxmind.com →]             │
│                                         │
│  2. Вставьте License Key:               │
│  ┌─────────────────────────────────┐    │
│  │ xxxxxxxxxxxxxxxx                │    │
│  └─────────────────────────────────┘    │
│                                         │
│  [Отмена]          [Скачать базу →]     │
└─────────────────────────────────────────┘
```

После нажатия "Скачать базу":
- Показывается прогресс-бар загрузки (~70 МБ)
- По завершении окно закрывается, приложение готово к работе
- License Key сохраняется в Keychain (не в UserDefaults)

### 7.4 Preferences Window

**General tab:**
- Display Mode: `Popup Button` с вариантами из 7.1
- Refresh Interval: `Popup Button` → 1 мин / 5 мин / 15 мин / 30 мин / Вручную
- Launch at Login: `NSButton` (checkbox)

**Database tab:**
- License Key: `NSSecureTextField` + кнопка "Показать" (читается из Keychain)
- Статус базы: дата последнего обновления
- Кнопка "Обновить базу сейчас" (запускает фоновую загрузку)
- Автообновление: `NSButton` (checkbox) — включить/выключить еженедельное обновление

**Advanced tab:**
- IP-провайдер: `ipify.org` / `checkip.amazonaws.com`
- Request timeout: `NSTextField` (секунды)
- Кнопка "Reset to Defaults"

---

## 8. Core Logic Flow

```
App Launch
    │
    ├─► Hide from Dock (LSUIElement = YES)
    ├─► Init NSStatusItem → label = "🌐 …"
    ├─► Start NetworkMonitor
    │
    ├─► GeoLiteDatabase.isReady?
    │       ├── NO  → AppState(.onboarding) → показать OnboardingWindow
    │       └── YES → IPGeolocationService.loadDatabase()
    │                       └─► fetchAndUpdate()
    │
    └─► GeoLiteDatabase.checkAndUpdateIfNeeded()  ← фоновая задача

fetchAndUpdate():
    │
    ├─► ExternalIPService.fetchIP()
    │       ├── success → ip: String
    │       └── failure → AppState(.offline(last: currentInfo))
    │
    ├─► IPGeolocationService.lookup(ip:)   ← локально, мгновенно
    │       ├── success → AppState(.loaded(info))
    │       └── failure → AppState(.error("DB lookup failed"))
    │
    └─► Schedule next refresh via Timer

NetworkMonitor.onPathChange:
    │
    ├─► .satisfied && interface changed
    │       └─► debounce 2s → fetchAndUpdate()
    │
    └─► not .satisfied
            └─► AppState(.offline(last: currentInfo))

GeoLiteDatabase.checkAndUpdateIfNeeded():
    │
    ├─► lastUpdated > 7 дней назад (или nil)
    │       └─► downloadOrUpdate(licenseKey:)
    │               ├── success → reload reader, сохранить дату
    │               └── failure → DatabaseStatus(.updateFailed), продолжать со старой базой
    │
    └─► актуальна → ничего не делать
```

---

## 9. Refresh Logic

```swift
// StatusBarController.swift

final class StatusBarController {

    private var refreshTimer: Timer?
    private var currentInfo: IPInfo?

    func scheduleRefresh() {
        refreshTimer?.invalidate()
        let interval = UserDefaults.standard.double(forKey: "refreshInterval")  // default 300s
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.fetchAndUpdate() }
        }
    }

    func fetchAndUpdate() async {
        await MainActor.run { setLabel(for: .loading) }
        do {
            let ip   = try await ExternalIPService.shared.fetchIP()
            let info = try IPGeolocationService.shared.lookup(ip: ip)
            currentInfo = info
            await MainActor.run { setLabel(for: .loaded(info)); rebuildMenu(info) }
        } catch {
            let state: AppState = currentInfo.map { .offline(last: $0) } ?? .error(error.localizedDescription)
            await MainActor.run { setLabel(for: state) }
        }
    }
}
```

---

## 10. FlagEmoji Helper

```swift
// Helpers/FlagEmoji.swift

enum FlagEmoji {
    static func from(countryCode: String) -> String {
        guard countryCode.count == 2 else { return "🌐" }
        let base: UInt32 = 127397
        return countryCode.uppercased().unicodeScalars.compactMap {
            Unicode.Scalar(base + $0.value)
        }.reduce("") { $0 + String($1) }
    }
}
```

---

## 11. UserDefaults Keys

| Ключ | Тип | Default |
|---|---|---|
| `displayMode` | `String` | `"flagCityCountry"` |
| `refreshInterval` | `Double` | `300` (сек) |
| `launchAtLogin` | `Bool` | `false` |
| `autoUpdateDB` | `Bool` | `true` |
| `dbLastUpdated` | `Date` | `nil` |
| `ipProvider` | `String` | `"ipify"` |
| `requestTimeout` | `Double` | `5` |
| `lastKnownIPInfo` | `Data` (JSON) | `nil` |

**MaxMind License Key** хранится в **Keychain** (не UserDefaults):
```swift
// Keychain service: "com.yourname.ipregionbar"
// Keychain account: "maxmind-license-key"
```

`lastKnownIPInfo` — сохраняется при каждом успешном lookup, используется для offline-режима.

---

## 12. Launch at Login

```swift
// Helpers/LaunchAtLogin.swift
import ServiceManagement

enum LaunchAtLogin {
    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("LaunchAtLogin error: \(error)")
        }
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
```

---

## 13. Entitlements & Capabilities

Файл `IPRegionBar.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" ...>
<plist version="1.0">
<dict>
    <!-- Исходящие сетевые запросы (ipify, MaxMind download) -->
    <key>com.apple.security.network.client</key>
    <true/>
    <!-- Хранение License Key -->
    <key>keychain-access-groups</key>
    <array>
        <string>$(AppIdentifierPrefix)com.yourname.ipregionbar</string>
    </array>
</dict>
</plist>
```

---

## 14. Info.plist Keys

```xml
<!-- Скрыть из Dock -->
<key>LSUIElement</key>
<true/>

<!-- Минимальная версия -->
<key>LSMinimumSystemVersion</key>
<string>13.0</string>

<!-- Bundle info -->
<key>CFBundleIdentifier</key>
<string>com.yourname.ipregionbar</string>
<key>CFBundleName</key>
<string>IP Region Bar</string>
```

---

## 15. Open Source & Distribution

### 15.1 License

Лицензия **MIT**. Файл `LICENSE` в корне репозитория:

```
MIT License

Copyright (c) 2024 <author>

Permission is hereby granted, free of charge, to any person obtaining a copy ...
```

### 15.2 GitHub Repository

Структура репозитория должна соответствовать стандартам open source проекта:

**README.md** обязан содержать:
- Скриншот/GIF menu bar в действии
- Секцию Installation (через Homebrew — основной способ)
- Секцию Manual Installation (скачать .dmg с Releases)
- Секцию Build from Source
- Секцию Requirements (macOS 13+)
- Секцию Contributing
- Badge: CI status, License, macOS version, Homebrew

```markdown
[![CI](https://github.com/<user>/ipregionbar/actions/workflows/build.yml/badge.svg)](...)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)](...)
```

**CONTRIBUTING.md** содержит:
- Как форкнуть и собрать локально
- Code style (SwiftLint конфиг)
- Как открывать issues и PR
- Как предложить новый API-провайдер

**CHANGELOG.md** — ведётся в формате [Keep a Changelog](https://keepachangelog.com/).

### 15.3 CI/CD — GitHub Actions

#### `.github/workflows/build.yml` — на каждый push и PR в `main`:

```yaml
name: Build & Test

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: macos-14          # Apple Silicon runner
    steps:
      - uses: actions/checkout@v4
      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_15.app
      - name: Build
        run: xcodebuild -project IPRegionBar.xcodeproj \
             -scheme IPRegionBar \
             -configuration Release \
             -arch arm64 -arch x86_64 \
             build
      - name: Lint
        run: swiftlint lint --strict
```

#### `.github/workflows/release.yml` — на создание тега `v*`:

```yaml
name: Release

on:
  push:
    tags: ['v*']

jobs:
  release:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Build Universal Binary
        run: make build
      - name: Notarize
        env:
          APPLE_ID: ${{ secrets.APPLE_ID }}
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
          APPLE_APP_PASSWORD: ${{ secrets.APPLE_APP_PASSWORD }}
        run: make notarize
      - name: Create DMG
        run: make dmg
      - name: Upload Release Asset
        uses: softprops/action-gh-release@v2
        with:
          files: build/IPRegionBar.dmg
          generate_release_notes: true
```

#### `Makefile`:

```makefile
SCHEME       = IPRegionBar
PROJECT      = IPRegionBar.xcodeproj
BUILD_DIR    = build
APP_NAME     = IPRegionBar
BUNDLE_ID    = com.yourname.ipregionbar
VERSION      = $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" \
               IPRegionBar/Info.plist)

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
	  -configuration Release \
	  -arch arm64 -arch x86_64 \
	  -derivedDataPath $(BUILD_DIR) \
	  CONFIGURATION_BUILD_DIR=$(BUILD_DIR)

dmg:
	hdiutil create -volname "$(APP_NAME)" \
	  -srcfolder "$(BUILD_DIR)/$(APP_NAME).app" \
	  -ov -format UDZO \
	  "$(BUILD_DIR)/$(APP_NAME).dmg"

notarize:
	xcrun notarytool submit "$(BUILD_DIR)/$(APP_NAME).dmg" \
	  --apple-id "$(APPLE_ID)" \
	  --team-id "$(APPLE_TEAM_ID)" \
	  --password "$(APPLE_APP_PASSWORD)" \
	  --wait
	xcrun stapler staple "$(BUILD_DIR)/$(APP_NAME).dmg"

release: build dmg notarize
```

### 15.4 Code Signing & Notarization

Для распространения вне Mac App Store требуется:

1. **Developer ID Application** сертификат (платный Apple Developer Account, $99/год)
2. **Signing** в Xcode: `CODE_SIGN_IDENTITY = "Developer ID Application: Name (TEAMID)"`
3. **Hardened Runtime** включён (обязательно для notarization)
4. **Notarization** через `notarytool` — Apple проверяет бинарь и ставит штамп
5. **Stapling** — штамп вшивается в `.dmg` чтобы работало offline

Секреты для CI хранятся в GitHub Secrets:
- `APPLE_ID` — email аккаунта Apple Developer
- `APPLE_TEAM_ID` — Team ID из Developer Portal
- `APPLE_APP_PASSWORD` — App-specific password

### 15.5 Homebrew Cask

После публикации первого релиза на GitHub — создать формулу в `homebrew-cask`.

#### Файл `Formula/ipregionbar.rb` (или PR в `homebrew/homebrew-cask`):

```ruby
cask "ipregionbar" do
  version "1.0.0"
  sha256 "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"

  url "https://github.com/<user>/ipregionbar/releases/download/v#{version}/IPRegionBar.dmg"
  name "IP Region Bar"
  desc "macOS menu bar app showing current external IP geolocation"
  homepage "https://github.com/<user>/ipregionbar"

  app "IPRegionBar.app"

  zap trash: [
    "~/Library/Preferences/com.yourname.ipregionbar.plist",
    "~/Library/Application Support/IPRegionBar",
  ]
end
```

#### Процесс публикации в Homebrew:
1. Собрать и нотаризировать `.dmg`
2. Вычислить SHA256: `shasum -a 256 IPRegionBar.dmg`
3. Обновить `sha256` в формуле
4. Открыть PR в `homebrew/homebrew-cask` репозиторий
5. После мержа пользователи могут устанавливать через:

```bash
brew install --cask ipregionbar
```

#### Обновление версий (после каждого релиза):
- Обновить `version` и `sha256` в cask-формуле
- Открыть PR в homebrew-cask с описанием изменений
- Или вести собственный tap для быстрых обновлений:

```bash
# Собственный tap (альтернатива ожиданию PR в homebrew-cask)
brew tap <user>/ipregionbar
brew install --cask <user>/ipregionbar/ipregionbar
```

Для собственного тапа создать репозиторий `homebrew-ipregionbar` с файлом `Casks/ipregionbar.rb`.

### 15.6 Versioning

Используется **Semantic Versioning** (`MAJOR.MINOR.PATCH`):
- `PATCH` — bugfix, обновление API URL
- `MINOR` — новая функция (новый display mode, новый API-провайдер)
- `MAJOR` — breaking change (смена минимальной версии macOS, переписывание)

Версия хранится в `CFBundleShortVersionString` в `Info.plist` и является единственным источником правды. CI читает версию из plist при сборке релиза.

---

## 16. Implementation Steps (для агента)

Реализовывать в следующем порядке:

1. Создать Xcode project (macOS App, AppKit, без SwiftUI)
2. Добавить SPM-зависимость `MaxMind-DB-Reader-swift`
3. Настроить `Info.plist` (`LSUIElement`)
4. Настроить `Entitlements` (network.client, keychain, Hardened Runtime)
5. Реализовать `IPInfo` и `DatabaseStatus` models
6. Реализовать `FlagEmoji` helper
7. Реализовать `KeychainHelper` (сохранение/чтение License Key)
8. Реализовать `GeoLiteDatabase` (загрузка, распаковка, обновление `.mmdb`)
9. Реализовать `ExternalIPService` (ipify + amazon fallback)
10. Реализовать `IPGeolocationService` (MaxMind reader wrapper)
11. Реализовать `NetworkMonitor`
12. Реализовать `OnboardingWindow` (ввод ключа + прогресс загрузки базы)
13. Реализовать `StatusBarController` (NSStatusItem + label + menu)
14. Реализовать `MenuBuilder` (включая строку статуса базы)
15. Реализовать `PreferencesWindow` (General + Database + Advanced tabs)
16. Реализовать `LaunchAtLogin`
17. Связать всё в `AppDelegate`
18. Проверить сборку Universal Binary (arm64 + x86_64)
19. Добавить `.swiftlint.yml`
20. Создать `Makefile` (build / dmg / notarize / release)
21. Создать `.github/workflows/build.yml`
22. Создать `.github/workflows/release.yml`
23. Написать `README.md` (скриншот, Homebrew install, MaxMind setup, badges)
24. Написать `CONTRIBUTING.md`
25. Создать `CHANGELOG.md`
26. Добавить `LICENSE` (MIT)
27. Подготовить Homebrew Cask формулу

---

## 17. Acceptance Criteria

### Онбординг и база данных
- [ ] При первом запуске показывается OnboardingWindow
- [ ] По невалидному License Key — показывается ошибка, база не скачивается
- [ ] После ввода корректного ключа — база скачивается с прогресс-баром
- [ ] License Key хранится в Keychain, не в UserDefaults / Info.plist
- [ ] База автоматически обновляется если старше 7 дней
- [ ] При ошибке обновления — приложение продолжает работу со старой базой
- [ ] Статус базы (дата обновления) отображается в меню и в Preferences

### Функциональность
- [ ] Приложение запускается и не появляется в Dock
- [ ] В menu bar отображается флаг + город + страна
- [ ] По клику открывается меню с деталями IP
- [ ] Геолокация резолвится локально — без отправки IP на сторонние серверы
- [ ] При подключении VPN — автообновление в течение 5 секунд
- [ ] При отключении интернета — показывает последний регион с `⚠️` (геолокация всё ещё работает локально, нет только IP)
- [ ] Кнопка "Обновить" (⌘R) вручную запускает fetch
- [ ] Клик по строке с IP копирует значение в буфер
- [ ] Настройки сохраняются между перезапусками
- [ ] "Launch at Login" работает корректно
- [ ] Потребление RAM в покое < 15 МБ (база не держится в памяти целиком)
- [ ] Нет утечек памяти (проверено через Instruments)

### Open Source & Distribution
- [ ] Репозиторий содержит LICENSE (MIT), README, CONTRIBUTING, CHANGELOG
- [ ] README содержит секцию "MaxMind Setup" с инструкцией по получению License Key
- [ ] README содержит секцию установки через Homebrew как основной способ
- [ ] CI проходит на каждый PR (сборка + SwiftLint)
- [ ] GitHub Actions создаёт нотаризированный `.dmg` при пуше тега `v*`
- [ ] `.dmg` подписан Developer ID и нотаризирован Apple (stapled)
- [ ] Homebrew Cask формула корректно устанавливает и удаляет приложение
- [ ] `brew install --cask ipregionbar` работает end-to-end
- [ ] `zap` в формуле удаляет все настройки и базу данных пользователя
