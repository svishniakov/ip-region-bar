# PRD: IP Region Bar
**macOS Menu Bar Application**

Version: 2.0  
Status: Draft  
Target: Claude Code / Codex implementation  
License: MIT  
Distribution: GitHub + Homebrew Cask

---

## 1. Overview

IP Region Bar — нативное macOS-приложение без окна и Dock-иконки, которое живёт исключительно в системном menu bar и показывает геолокацию текущего внешнего IP-адреса машины.

### Goals
- Пользователь всегда видит, из какой страны/города выглядит его трафик
- Автоматическое обновление при смене сети (в том числе при подключении/отключении VPN)
- Минимальный footprint: нет окон, нет Dock-иконки, <15 МБ RAM в покое
- **Zero onboarding** — работает сразу после установки, не требует аккаунтов и ключей
- **Минимальная зависимость от сети** — геолокация резолвится локально по базе DB-IP
- **Privacy-first** — внешний IP не отправляется на сторонние геолокационные серверы
- **Offline-ready** — при отсутствии интернета геолокация продолжает работать локально

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
| Геолокация | DB-IP Lite City (`dbip-city-lite-YYYY-MM.mmdb`) |
| Парсер .mmdb | `MaxMind-DB-Reader-swift` (Swift Package, совместим с DB-IP) |
| Определение внешнего IP | `https://api64.ipify.org` (только IP, IPv4/IPv6) |
| Хранилище настроек | `UserDefaults` |
| Автозапуск | `SMAppService` (macOS 13+) |
| Минимальная версия macOS | 13.0 Ventura |
| Архитектура | Universal Binary (arm64 + x86_64) |
| Сборка | Xcode project + Swift Package Manager |

### Почему DB-IP Lite

| | DB-IP Lite | MaxMind GeoLite2 |
|---|---|---|
| Регистрация | ❌ не нужна | ✅ нужна |
| License Key | ❌ не нужен | ✅ нужен |
| Онбординг | ❌ не нужен | ✅ нужен |
| Бандл в .app | ✅ да (~30 МБ gz) | ⚠️ технически можно |
| Формат | `.mmdb` | `.mmdb` |
| Обновление | раз в месяц | раз в неделю |
| Лицензия | CC BY 4.0 | CC BY-SA 4.0 |

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
│   │   ├── DBIPDatabase.swift         # бандл базы, проверка обновлений, замена
│   │   ├── IPGeolocationService.swift # резолв IP через локальную .mmdb
│   │   └── NetworkMonitor.swift       # NWPathMonitor wrapper
│   ├── Models/
│   │   ├── IPInfo.swift               # результирующая структура данных
│   │   └── DatabaseStatus.swift       # состояние базы
│   ├── UI/
│   │   ├── StatusBarController.swift  # управление NSStatusItem
│   │   ├── MenuBuilder.swift          # построение NSMenu
│   │   └── PreferencesWindow.swift    # окно настроек
│   ├── Helpers/
│   │   ├── FlagEmoji.swift            # ISO код → флаг emoji
│   │   └── LaunchAtLogin.swift        # SMAppService wrapper
│   └── Resources/
│       ├── Assets.xcassets
│       └── dbip-city-lite.mmdb        # ← база бандлится в приложение
├── scripts/
│   └── update-dbip.sh                 # скрипт обновления базы для CI
├── .github/
│   └── workflows/
│       ├── build.yml                  # CI: сборка + lint на каждый PR
│       ├── update-db.yml              # Cron: обновление базы раз в месяц
│       └── release.yml                # CD: GitHub Release + .dmg
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

    var flagEmoji: String {
        FlagEmoji.from(countryCode: countryCode)
    }
}

// Models/DatabaseStatus.swift

enum DatabaseStatus {
    case bundled(month: String)           // база из бандла приложения, напр. "2025-01"
    case updated(month: String)           // пользователь получил свежую базу
    case updating                         // идёт фоновое обновление
    case updateFailed                     // ошибка обновления, используется текущая база
}

enum AppState {
    case loading
    case loaded(IPInfo)
    case offline(last: IPInfo?)
    case error(String)
}
```

---

## 5. Геолокация: DB-IP Lite + ipify

Архитектура разделена на два полностью независимых шага:

```
Запрос A  →  api64.ipify.org     →  текущий внешний IP (строка, ~50мс)
Запрос B  →  локальная .mmdb     →  геолокация по IP (мгновенно, без сети)
Фоново    →  github.com/sapics    →  ежемесячное обновление базы (CI или в-app)
```

### 5.1 Получение внешнего IP — ipify

```
GET https://api64.ipify.org?format=json
Response: {"ip": "185.220.101.42"}
```

- Бесплатно, без ключа, без лимитов
- Поддерживает IPv4 и IPv6 (api64 выбирает автоматически)
- Возвращает **только IP** — никакой геолокации, никаких логов пользователя

**Fallback** при недоступности ipify:
```
GET https://checkip.amazonaws.com
Response: 185.220.101.42\n
```

### 5.2 База данных — DB-IP Lite City

**Источник:** [https://db-ip.com/db/download/ip-to-city-lite](https://db-ip.com/db/download/ip-to-city-lite)

**Прямая ссылка для скачивания (без авторизации):**
```
https://download.db-ip.com/free/dbip-city-lite-{YYYY-MM}.mmdb.gz
```
Пример:
```
https://download.db-ip.com/free/dbip-city-lite-2025-01.mmdb.gz
```

**Характеристики базы:**
- Формат: `.mmdb` — тот же формат что MaxMind, читается тем же Swift-ридером
- Размер: ~40 МБ gzip, ~90 МБ распакованная
- Обновляется: 1-го числа каждого месяца
- Лицензия: [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) — требует attribution в README и About

**Attribution (обязательно по лицензии):**
```
This product includes IP geolocation data created by DB-IP.com,
available from https://db-ip.com
```
Добавить в README, About-меню и Preferences.

**Swift-библиотека (та же, что для MaxMind):**
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

### 5.3 Стратегия хранения и обновления базы

База хранится в **двух местах одновременно**:

| Копия | Путь | Назначение |
|---|---|---|
| Бандл | `IPRegionBar.app/Contents/Resources/dbip-city-lite.mmdb` | Гарантированно работает сразу после установки |
| Пользовательская | `~/Library/Application Support/IPRegionBar/dbip-city-lite.mmdb` | Более свежая версия, если обновлялась |

Логика выбора базы при запуске:
1. Проверить наличие пользовательской копии
2. Если есть — использовать её (она новее бандла)
3. Если нет — использовать бандл

### 5.4 DBIPDatabase — сервис обновления

```swift
// Services/DBIPDatabase.swift

actor DBIPDatabase {

    static let shared = DBIPDatabase()

    private let userDBURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("IPRegionBar/dbip-city-lite.mmdb")

    private let bundleDBURL = Bundle.main
        .url(forResource: "dbip-city-lite", withExtension: "mmdb")!

    // Вернуть актуальный путь к базе
    var activeDatabaseURL: URL {
        FileManager.default.fileExists(atPath: userDBURL.path)
            ? userDBURL
            : bundleDBURL
    }

    // Скачать свежую базу за текущий месяц
    func updateIfNeeded() async {
        guard shouldUpdate() else { return }

        let yearMonth = currentYearMonth()   // "2025-01"
        let urlString = "https://download.db-ip.com/free/dbip-city-lite-\(yearMonth).mmdb.gz"
        guard let url = URL(string: urlString) else { return }

        do {
            // 1. Скачать .mmdb.gz во временную директорию
            let tempGZ  = FileManager.default.temporaryDirectory
                .appendingPathComponent("dbip-\(yearMonth).mmdb.gz")
            let (tempFile, _) = try await URLSession.shared.download(from: url)
            try FileManager.default.moveItem(at: tempFile, to: tempGZ)

            // 2. Распаковать через gunzip (Process)
            let tempMMDB = tempGZ.deletingPathExtension()
            let process  = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
            process.arguments     = ["-f", tempGZ.path]
            try process.run(); process.waitUntilExit()

            // 3. Переместить на место пользовательской базы
            try FileManager.default.createDirectory(
                at: userDBURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: userDBURL.path) {
                try FileManager.default.removeItem(at: userDBURL)
            }
            try FileManager.default.moveItem(at: tempMMDB, to: userDBURL)

            // 4. Сохранить дату обновления
            UserDefaults.standard.set(Date(), forKey: "dbLastUpdated")
            UserDefaults.standard.set(yearMonth, forKey: "dbMonth")

        } catch {
            // Тихо падаем — приложение продолжает работать со старой базой
            print("DB-IP update failed: \(error)")
        }
    }

    // Обновлять раз в месяц
    private func shouldUpdate() -> Bool {
        guard let lastUpdate = UserDefaults.standard.object(forKey: "dbLastUpdated") as? Date
        else { return true }
        return Date().timeIntervalSince(lastUpdate) > 30 * 24 * 3600
    }

    private func currentYearMonth() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM"
        return fmt.string(from: Date())
    }
}
```

### 5.5 Обновление базы через GitHub Actions (CI-подход)

Помимо in-app обновления, база обновляется **автоматически в репозитории** раз в месяц через GitHub Actions. Это означает, что каждый новый релиз уже содержит актуальную базу в бандле.

```yaml
# .github/workflows/update-db.yml

name: Update DB-IP Database

on:
  schedule:
    - cron: '0 6 2 * *'    # 2-го числа каждого месяца в 06:00 UTC
  workflow_dispatch:         # ручной запуск

jobs:
  update:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Download latest DB-IP Lite
        run: bash scripts/update-dbip.sh

      - name: Commit updated database
        uses: stefanzweifel/git-auto-commit-action@v5
        with:
          commit_message: "chore: update DB-IP Lite database"
          file_pattern: "IPRegionBar/Resources/dbip-city-lite.mmdb"
```

```bash
#!/bin/bash
# scripts/update-dbip.sh

YEAR_MONTH=$(date +%Y-%m)
URL="https://download.db-ip.com/free/dbip-city-lite-${YEAR_MONTH}.mmdb.gz"
DEST="IPRegionBar/Resources/dbip-city-lite.mmdb"

echo "Downloading DB-IP Lite for ${YEAR_MONTH}..."
curl -L "$URL" | gunzip > "$DEST"
echo "Done. Size: $(du -sh $DEST | cut -f1)"
```

---

## 6. Services

### 6.1 ExternalIPService

```swift
// Services/ExternalIPService.swift

actor ExternalIPService {

    static let shared = ExternalIPService()

    private let primaryURL  = URL(string: "https://api64.ipify.org?format=json")!
    private let fallbackURL = URL(string: "https://checkip.amazonaws.com")!
    private let timeout: TimeInterval = 5

    func fetchIP() async throws -> String {
        do {
            return try await fetchFromIpify()
        } catch {
            return try await fetchFromAmazon()
        }
    }

    private func fetchFromIpify() async throws -> String {
        var req = URLRequest(url: primaryURL, timeoutInterval: timeout)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = try JSONDecoder().decode([String: String].self, from: data)
        guard let ip = json["ip"] else { throw IPError.parseError }
        return ip
    }

    private func fetchFromAmazon() async throws -> String {
        var req = URLRequest(url: fallbackURL, timeoutInterval: timeout)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let ip = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        else { throw IPError.parseError }
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
        reader = try MaxMindDBReader(fileURL: DBIPDatabase.shared.activeDatabaseURL)
    }

    func reloadDatabase() throws {
        reader = nil
        try loadDatabase()
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
    private let queue   = DispatchQueue(label: "com.ipregionbar.netmonitor")

    var onPathChange: ((NWPath) -> Void)?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.onPathChange?(path)
        }
        monitor.start(queue: queue)
    }

    func stop() { monitor.cancel() }
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
База:      DB-IP Lite · янв 2025  ← месяц базы (серый, мелкий)
──────────────────────────────
Обновить                  ⌘R
──────────────────────────────
Настройки…
──────────────────────────────
About IP Region Bar
──────────────────────────────
Выйти                     ⌘Q
```

Строки IP, Страна, Город — кликабельны, копируют значение в буфер через `UNUserNotificationCenter`.

**About** показывает мини-окно с attribution для DB-IP (обязательно по CC BY 4.0):
```
IP Region Bar v1.0.0

Geolocation data: DB-IP.com (CC BY 4.0)
https://db-ip.com
```

### 7.3 Preferences Window

**General tab:**
- Display Mode: `Popup Button` с вариантами из 7.1
- Refresh Interval: `Popup Button` → 1 мин / 5 мин / 15 мин / 30 мин / Вручную
- Launch at Login: `NSButton` (checkbox)

**Database tab:**
- Версия базы: "DB-IP Lite · January 2025"
- Последнее обновление: дата
- Кнопка "Обновить базу сейчас" (фоновая загрузка свежего месяца)
- Автообновление: `NSButton` (checkbox) — включить/выключить ежемесячное обновление
- Attribution: "IP geolocation by DB-IP.com" (ссылка)

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
    ├─► IPGeolocationService.loadDatabase()   ← бандл или пользовательская копия
    ├─► fetchAndUpdate()
    └─► Task { await DBIPDatabase.shared.updateIfNeeded() }  ← фоново, раз в месяц

fetchAndUpdate():
    │
    ├─► ExternalIPService.fetchIP()
    │       ├── success → ip: String
    │       └── failure → AppState(.offline(last: currentInfo))
    │
    ├─► IPGeolocationService.lookup(ip:)       ← локально, ~0.1мс
    │       ├── success → AppState(.loaded(info))
    │       └── failure → AppState(.error("lookup failed"))
    │
    └─► Schedule next refresh via Timer

NetworkMonitor.onPathChange:
    ├─► .satisfied && interface changed → debounce 2s → fetchAndUpdate()
    └─► not .satisfied → AppState(.offline(last: currentInfo))

DBIPDatabase.updateIfNeeded():
    ├─► lastUpdate < 30 дней назад → пропустить
    └─► иначе → скачать, распаковать, заменить, перезагрузить reader
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
        let interval = UserDefaults.standard.double(forKey: "refreshInterval")
        guard interval > 0 else { return }  // "Вручную" → interval == 0
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.fetchAndUpdate() }
        }
    }

    func fetchAndUpdate() async {
        await MainActor.run { setLabel(for: .loading) }
        do {
            let ip   = try await ExternalIPService.shared.fetchIP()
            let info = try await IPGeolocationService.shared.lookup(ip: ip)
            currentInfo = info
            UserDefaults.standard.set(try JSONEncoder().encode(info), forKey: "lastKnownIPInfo")
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
| `refreshInterval` | `Double` | `300` (сек), `0` = вручную |
| `launchAtLogin` | `Bool` | `false` |
| `autoUpdateDB` | `Bool` | `true` |
| `dbLastUpdated` | `Date` | `nil` |
| `dbMonth` | `String` | `nil` (читается из бандла) |
| `ipProvider` | `String` | `"ipify"` |
| `requestTimeout` | `Double` | `5` |
| `lastKnownIPInfo` | `Data` (JSON) | `nil` |

---

## 12. Launch at Login

```swift
// Helpers/LaunchAtLogin.swift
import ServiceManagement

enum LaunchAtLogin {
    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else        { try SMAppService.mainApp.unregister() }
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
<plist version="1.0">
<dict>
    <!-- Исходящие запросы: ipify, amazon, db-ip.com -->
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
```

Нет keychain, нет лишних entitlements — максимально простой профиль.

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
<key>CFBundleShortVersionString</key>
<string>1.0.0</string>
```

---

## 15. Open Source & Distribution

### 15.1 License

Лицензия **MIT**. Файл `LICENSE` в корне репозитория.

Дополнительно — attribution для DB-IP в `README.md`, `CONTRIBUTING.md` и About-меню:
```
IP geolocation data provided by DB-IP.com (CC BY 4.0)
https://db-ip.com
```

### 15.2 GitHub Repository

**README.md** обязан содержать:
- Скриншот/GIF menu bar в действии
- Секцию Installation (через Homebrew — основной способ)
- Секцию Manual Installation (скачать .dmg с Releases)
- Секцию Build from Source
- Секцию Requirements (macOS 13+)
- DB-IP attribution (обязательно по лицензии)
- Badges: CI, License, macOS version

```markdown
[![CI](https://github.com/<user>/ipregionbar/actions/workflows/build.yml/badge.svg)](...)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)](...)
```

**CONTRIBUTING.md** содержит:
- Как форкнуть и собрать локально
- Как обновить DB-IP базу вручную (`bash scripts/update-dbip.sh`)
- Code style (SwiftLint конфиг)
- Как открывать issues и PR

**CHANGELOG.md** — формат [Keep a Changelog](https://keepachangelog.com/).

### 15.3 CI/CD — GitHub Actions

#### `.github/workflows/build.yml` — на каждый push и PR:

```yaml
name: Build & Test

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_15.app
      - name: Build Universal Binary
        run: |
          xcodebuild -project IPRegionBar.xcodeproj \
            -scheme IPRegionBar \
            -configuration Release \
            -arch arm64 -arch x86_64 \
            build
      - name: Lint
        run: swiftlint lint --strict
```

#### `.github/workflows/update-db.yml` — обновление базы раз в месяц:

```yaml
name: Update DB-IP Database

on:
  schedule:
    - cron: '0 6 2 * *'    # 2-го числа каждого месяца
  workflow_dispatch:

jobs:
  update:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Download latest DB-IP Lite
        run: bash scripts/update-dbip.sh

      - name: Commit if changed
        uses: stefanzweifel/git-auto-commit-action@v5
        with:
          commit_message: "chore: update DB-IP Lite to $(date +%Y-%m)"
          file_pattern: "IPRegionBar/Resources/dbip-city-lite.mmdb"
```

#### `.github/workflows/release.yml` — на тег `v*`:

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
      - name: Build + Notarize + DMG
        env:
          APPLE_ID:           ${{ secrets.APPLE_ID }}
          APPLE_TEAM_ID:      ${{ secrets.APPLE_TEAM_ID }}
          APPLE_APP_PASSWORD: ${{ secrets.APPLE_APP_PASSWORD }}
        run: make release
      - name: Upload DMG to GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          files: build/IPRegionBar.dmg
          generate_release_notes: true
```

#### `Makefile`:

```makefile
SCHEME    = IPRegionBar
PROJECT   = IPRegionBar.xcodeproj
BUILD_DIR = build
APP_NAME  = IPRegionBar
BUNDLE_ID = com.yourname.ipregionbar
VERSION   = $(shell /usr/libexec/PlistBuddy -c \
            "Print CFBundleShortVersionString" IPRegionBar/Info.plist)

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

update-db:
	bash scripts/update-dbip.sh

release: build dmg notarize
```

### 15.4 Code Signing & Notarization

1. **Developer ID Application** сертификат (Apple Developer Account, $99/год)
2. **Signing**: `CODE_SIGN_IDENTITY = "Developer ID Application: Name (TEAMID)"`
3. **Hardened Runtime** включён
4. **Notarization** через `notarytool`
5. **Stapling** в `.dmg`

GitHub Secrets:
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_PASSWORD`

### 15.5 Homebrew Cask

```ruby
# Casks/ipregionbar.rb

cask "ipregionbar" do
  version "1.0.0"
  sha256 "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"

  url "https://github.com/<user>/ipregionbar/releases/download/v#{version}/IPRegionBar.dmg"
  name "IP Region Bar"
  desc "macOS menu bar app showing your current external IP geolocation"
  homepage "https://github.com/<user>/ipregionbar"

  app "IPRegionBar.app"

  zap trash: [
    "~/Library/Preferences/com.yourname.ipregionbar.plist",
    "~/Library/Application Support/IPRegionBar",
  ]
end
```

Установка:
```bash
brew install --cask ipregionbar
```

Или через собственный tap:
```bash
brew tap <user>/ipregionbar
brew install --cask <user>/ipregionbar/ipregionbar
```

### 15.6 Versioning

Semantic Versioning (`MAJOR.MINOR.PATCH`). Единственный источник правды — `CFBundleShortVersionString` в `Info.plist`.

---

## 16. Implementation Steps (для агента)

Реализовывать в следующем порядке:

1. Создать Xcode project (macOS App, AppKit, без SwiftUI)
2. Добавить SPM-зависимость `MaxMind-DB-Reader-swift`
3. Настроить `Info.plist` (`LSUIElement`)
4. Настроить `Entitlements` (network.client, Hardened Runtime)
5. Добавить `dbip-city-lite.mmdb` в `Resources` (скачать актуальную версию через `scripts/update-dbip.sh`)
6. Реализовать `IPInfo` и `DatabaseStatus` models
7. Реализовать `FlagEmoji` helper
8. Реализовать `DBIPDatabase` (выбор базы бандл/пользовательская, ежемесячное обновление)
9. Реализовать `ExternalIPService` (ipify + amazon fallback)
10. Реализовать `IPGeolocationService` (MMDB reader wrapper)
11. Реализовать `NetworkMonitor`
12. Реализовать `StatusBarController` (NSStatusItem + label + menu)
13. Реализовать `MenuBuilder` (включая строку версии базы и About)
14. Реализовать `PreferencesWindow` (General + Database + Advanced)
15. Реализовать `LaunchAtLogin`
16. Связать всё в `AppDelegate`
17. Проверить сборку Universal Binary (arm64 + x86_64)
18. Написать `scripts/update-dbip.sh`
19. Добавить `.swiftlint.yml`
20. Создать `Makefile`
21. Создать `.github/workflows/build.yml`
22. Создать `.github/workflows/update-db.yml`
23. Создать `.github/workflows/release.yml`
24. Написать `README.md` (скриншот, Homebrew install, DB-IP attribution, badges)
25. Написать `CONTRIBUTING.md`
26. Создать `CHANGELOG.md`
27. Добавить `LICENSE` (MIT)
28. Подготовить Homebrew Cask формулу (`Casks/ipregionbar.rb`)

---

## 17. Acceptance Criteria

### База данных и геолокация
- [ ] База `dbip-city-lite.mmdb` бандлится в `.app` и работает без интернета сразу после установки
- [ ] При наличии пользовательской копии базы — используется она (новее)
- [ ] База автоматически обновляется если старше 30 дней (фоново, без блокировки UI)
- [ ] При ошибке обновления — приложение продолжает работу с текущей базой
- [ ] Версия/месяц базы отображается в меню и в Preferences
- [ ] DB-IP attribution присутствует в About, README и Preferences

### Функциональность
- [ ] Приложение запускается и не появляется в Dock
- [ ] В menu bar отображается флаг + город + страна
- [ ] По клику открывается меню с деталями IP
- [ ] Геолокация резолвится локально — IP не отправляется на геолокационные серверы
- [ ] При подключении VPN — автообновление в течение 5 секунд (debounce 2s)
- [ ] При отключении интернета — геолокация работает, показывает последний IP с `⚠️`
- [ ] Кнопка "Обновить" (⌘R) вручную запускает fetch
- [ ] Клик по строке IP/Страна/Город копирует значение в буфер
- [ ] Настройки сохраняются между перезапусками
- [ ] "Launch at Login" работает корректно
- [ ] Потребление RAM в покое < 15 МБ
- [ ] Нет утечек памяти (Instruments)

### Open Source & Distribution
- [ ] Репозиторий содержит LICENSE (MIT), README, CONTRIBUTING, CHANGELOG
- [ ] GitHub Actions обновляет базу в репозитории раз в месяц автоматически
- [ ] CI проходит на каждый PR (сборка + SwiftLint)
- [ ] GitHub Actions создаёт нотаризированный `.dmg` при пуше тега `v*`
- [ ] `.dmg` подписан Developer ID и нотаризирован Apple (stapled)
- [ ] `brew install --cask ipregionbar` работает end-to-end
- [ ] `zap` в Cask удаляет все настройки и пользовательскую базу
