# NetScope for iPhone — Architecture

A SwiftUI app (iOS 16+) organised by feature. State lives in a handful of `@Observable`
models injected through the environment; views are thin.

## Tabs & entry
`App/NetScopeApp.swift` is the `@main` entry: it builds the `TabView` (Speed, Devices,
Connection, Learn) and installs the shared environment objects. Settings is reached from
a gear on the Speed tab.

## Modules

### Speed (`Features/Speed/`)
The core feature. `SpeedTest.swift` holds the data model (`SpeedResult`), the persistent
`HistoryStore`, and the measurement engine: a **Cloudflare** edge path by default, plus
optional **M-Lab/NDT7** servers discovered via the Locate API and driven over WebSockets
(ping/jitter, download, upload). History is saved locally and exports as an **Ookla-format
CSV** via the share sheet. `SpeedTestView.swift` is the animated gauge + results UI.

### Devices (`Features/Devices/`)
`DeviceBrowser` uses Bonjour/mDNS to find devices that advertise services (Apple TVs,
printers, Chromecasts, NAS…). iOS hides MAC addresses and blocks ARP/ping sweeps, so this
is intentionally narrower than the Mac scan, and the tab is hidden on cellular.

### Connection (`Features/Connection/`)
Watches the active `NWPath` (Wi-Fi vs cellular). On Wi-Fi: SSID/BSSID/signal (with the
entitlement), local IP, band reference, and an Apple Maps view. On cellular: generation,
Standalone vs Non-Standalone, radio type, carrier + public IP (via ipinfo.io).

### Learn (`Features/Learn/`)
Static educational content — Wi-Fi band / channel-width / speed explainers.

### Settings (`Features/Settings/`)
`SettingsView` — permission status, history count/export/clear, default-tab + auto-run
prefs, the **Pro** switch, and the optional enrichment endpoint/token. `Privacy.swift`
renders the in-app Privacy Policy and Terms.

### Pro (`Features/Pro/`)
- `Pro.swift` — `ProManager`, the single gate (`pro.isPro`) read by every Pro feature.
- `Coverage.swift` — bins each saved test's lat/lon into a grid and draws a colour-coded
  **coverage heatmap** on Apple Maps. Optionally POSTs tiles to a Mac "backbone" and merges
  the returned set: `POST <url>/coverage  {"tiles":[…]} → {"tiles":[…]}` (offline-safe;
  a failed sync is non-fatal).
- `Enrichment.swift` — models Ookla's `SubscriberServiceResponse` (Provider Enrichment API).
  That API is provider-side, so by default the app shows clearly-labelled **sample** data,
  with an optional client for a real endpoint if one is configured.

### Core (`Core/`)
- `Theme.swift` — the colour palette (mirrored from the Mac dashboard) and styling helpers.
- `Tools.swift` — reusable network diagnostics iOS allows without entitlements: timed-HTTPS
  latency, DNS via `getaddrinfo`, TCP reachability via `NWConnection`, IP detail from ipinfo.

## Data flow (a speed test)
1. User taps run → `SpeedTest` engine selects a server (Cloudflare or chosen M-Lab city).
2. Engine measures ping/jitter, then download, then upload.
3. Result (incl. lat/lon from `LocationProvider`) is appended to `HistoryStore` (persisted).
4. Pro: `Coverage` re-bins history into tiles; the map redraws. Export writes Ookla CSV.

## External services
Cloudflare (speed), M-Lab/NDT7 (speed, open data), ipinfo.io (IP/carrier), beaconDB is
**not** used here (that's TowerScope). No app servers, no analytics.
