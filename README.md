# NetScope for iPhone

A native SwiftUI iPhone app with the parts of NetScope that **can** exist on iOS.

> ✅ **Validation status.** This is **not** a port of the macOS NetScope (see why below). It **builds cleanly against the iOS 27 SDK (Debug, iOS Simulator) with zero errors and zero warnings**, and has been **launched and exercised on an iPhone simulator**: all four tabs render, the Bonjour finder discovered real devices, the connection map drew a live location, and a full speed test ran end-to-end (real ISP/IP/Cloudflare colo, ping+jitter, download, upload) and saved to history. The **M-Lab / NDT7** backbone was verified against live M-Lab servers (Locate API discovery + real WebSocket download/upload throughput) via a standalone harness mirroring the engine. The history **exports as an Ookla-format CSV** (verified byte-for-byte against a real Speedtest export) and the app now ships an **app icon**. Just open the project, set your signing **Team**, and Run on your device.

## Why it isn't a 1:1 port

The Mac app is a Python web server that shells out to `arp`, `ping`, `nmap`, `system_profiler`, etc. iOS allows **none** of that — no Python/subprocesses, no shell tools, no ARP/ping sweeps, no MAC addresses of other devices, and **no Wi-Fi scanning API** (an iPhone app cannot see nearby networks, bands, channels or signal). So those features have no iOS equivalent and were left out.

## What's in the app

| Tab | Works on iOS? | Notes |
|-----|---------------|-------|
| **Speed** | ✅ Fully | Animated gauge, live download/upload/ping, ISP + server, history saved forever, **Ookla-format CSV export** (Date, ConnType, Lat/Lon, Download/Upload in kbps, total bytes, Latency, ServerName, internal/external IP, VPN flag) via the share sheet. **Server/location picker** — choose between Cloudflare's nearest edge and several nearby **M-Lab / NDT7** cities (an open-source internet measurement network), each shown with its live TCP-connect ping. The first M-Lab run shows a one-time consent prompt, since M-Lab publishes its results (including your IP) as open data. |
| **Devices** | ⚠️ Partial | Bonjour/mDNS discovery — finds devices that advertise services (Apple TVs, printers, Chromecasts, HomePods, NAS…). Far fewer than the Mac scan; no MACs. **Auto-hidden on cellular** (nothing local to browse). |
| **Connection** | ✅ Adaptive | **On Wi-Fi:** SSID/BSSID/signal (with the capability below), local IP, the Wi-Fi band reference + a best-guess band from your last speed test, and an **Apple Maps** view of where you're connected. **On cellular:** generation (5G/LTE/…), **Standalone vs Non-Standalone**, radio type, carrier (from ipinfo), public IP, and the map. |
| **Learn** | ✅ | The band / width / speed explainers. |
| **Settings** | ✅ | Gear icon on the Speed tab. Permission status (Location / Local Network) with one-tap "Open Settings", history count + Export CSV + Clear, default-tab and auto-run preferences, the **Pro** switch, and links to the in-app **Privacy Policy** and **Terms of Use**. |

## NetScope Pro

A Pro tier gated behind a **switch in Settings**. A real paid unlock needs the Apple Developer Program + StoreKit + an App Store Connect product, which can't be tested without all of that — so today the switch is a **preview toggle** that unlocks the Pro features for evaluation. The gate is centralised in `ProManager` (`Pro.swift`); swapping the stored flag for a `Transaction.currentEntitlements` check is the only change needed to make it a real purchase — no feature code changes.

| Pro feature | What it does |
|-------------|--------------|
| **Coverage Map** | Every saved speed test already records lat/lon, so they're binned into a ~280 m grid and drawn as colour-coded tiles (red → teal by average download) on an Apple Maps overlay, with a legend and coverage stats. A personal speed heatmap. |
| **Mac backbone (optional)** | Point the Coverage Map at a Mac running NetScope and the phone POSTs its tiles and gets back the set merged across every device reporting in — one Mac becomes a shared coverage backbone. Contract: `POST <url>/coverage  {"tiles":[…]} → {"tiles":[…]}`. Entirely optional; the map works fully offline on local tiles, and a failed sync is non-fatal. |
| **ISP Service** | A card on the Connection tab modelled on Ookla's *Provider Enrichment* `SubscriberServiceResponse` — provisioned plan speed vs. your last test, connection technology (Fiber/DOCSIS/Satellite/Fixed-Wireless…), and a throttling flag. |

> **About the Ookla API (`openapi.json`).** That spec is the Speedtest **Provider Enrichment API** — a *provider-side* contract that an **ISP** implements and **Ookla** calls (Ookla signs the JWT, the ISP verifies it). It has one **GET** endpoint and no way to *upload* a test result, so a consumer app can't post speed tests to it. NetScope therefore models its response schema and shows clearly-labelled **sample** data in the ISP Service card, with an optional advanced field to point at a real enrichment endpoint + bearer token if you operate one.

## Open it in Xcode

**Option A — open the generated project (already done for you):**
```bash
open "NetScopeiOS/NetScope.xcodeproj"
```
If you ever change `project.yml` or add files, regenerate with `brew install xcodegen && cd NetScopeiOS && xcodegen generate`.

**Option B — no XcodeGen:**
1. Xcode → **File ▸ New ▸ Project… ▸ iOS ▸ App**. Name it `NetScope`, Interface **SwiftUI**, Language **Swift**.
2. Delete the template's `ContentView.swift` and the generated `NetScopeApp.swift`.
3. Drag everything in the `NetScope/` folder here into the project (check *Copy items if needed*).
4. In the target's **Info** tab, add the keys from `NetScope/Info.plist` (the `NSLocalNetworkUsageDescription`, `NSBonjourServices` list, and `NSLocationWhenInUseUsageDescription`).

Then pick your **Team** under *Signing & Capabilities*, choose your iPhone (or a simulator), and **Run**.

## Permissions & capabilities

- **Local Network** — the OS prompts on first device scan; tap *Allow* or nothing shows up.
- **SSID (network name)** is optional and needs more setup: add the **Access Wi-Fi Information** capability in *Signing & Capabilities* (requires a paid Apple Developer account) and grant Location. Without it the Connection tab just shows "Wi-Fi" instead of the network name — everything else still works.

## Requirements

- **Xcode 26+ and iOS 27** — the app targets iOS 27 and uses current SwiftUI: the `@Observable` (Observation) state model, the MapKit-SwiftUI `Map(position:)` API, **Swift Charts**, SF Symbol effects, `.sensoryFeedback`, and **Liquid Glass** (`glassEffect`). On a macOS beta you'll need the matching **Xcode beta** from developer.apple.com.
- A free Apple ID works for building to your own iPhone (7-day signing); the speed test and Bonjour discovery work on a free account. Only the SSID readout needs the paid capability.

## Optimisations baked in

- Speed test uses a **delegate-based `URLSession` with 4 concurrent streams**, counting bytes live (`didReceive` / `didSendBodyData`) on a serial delegate queue — efficient and lock-light, the same design as the tuned macOS version.
- **Steady-state throughput:** the streams ramp through TCP/TLS slow-start for a short warm-up, then the counter resets and only the steady window is measured — the way Ookla/Cloudflare avoid under-reporting fast links. 4 MB upload bodies cut relaunch overhead.
- **Two open backbones + a location picker.** Cloudflare (anycast — always the nearest edge) and **M-Lab / NDT7**, the Apache-licensed open-source internet measurement network (the NDT protocol; NetScope has no affiliation with any search provider). M-Lab's public **Locate API v2** (`locate.measurementlab.net/v2/nearest/ndt/ndt7`) returns several nearby city servers with pre-signed, access-token'd WebSocket URLs; the app pings each with a **TCP-connect RTT** and lets you pick the location to test against. NDT7 runs over a single `URLSessionWebSocketTask` (subprotocol `net.measurementlab.ndt.v7`): downloads count received bytes for client-side goodput; uploads push 128 KB frames with completion-handler backpressure and report the **server's own `AppInfo` measurement** (the bytes it actually received) for the final figure. ⚠️ Note: tests run against M-Lab are **published by M-Lab as open data (incl. your IP)** — disclosed in the in-app Privacy Policy.
- The gauge **rescales per phase** so a fast download doesn't leave the upload arc looking empty; jitter is the mean consecutive-RTT difference (RFC 3550), and ping is the best (minimum) RTT.
- The CSV export matches the **Ookla Speedtest layout** and is **cached** (regenerated only when history changes, and re-checked for staleness/temp-purge before reuse). Each run also records lat/lon, total bytes, internal/external IP and a best-effort VPN flag. History rows are **capped on screen** (latest 40); the full set is always in the CSV.
- **Stable cellular detection:** the radio type is read from the *active data SIM* (`dataServiceIdentifier`), refreshed live on a polling task + RAT-change notification, with **anti-flicker hysteresis** (a brief NSA dip to LTE holds "5G · Non-Standalone" instead of bouncing the badge). Uses a monotonic clock so a system time change can't disturb the hold.
- **Phase-safe stream relaunch:** each speed-test stream is tagged with its direction, so a cancelled download stream can never relaunch as an upload stream — which previously over-saturated the upload phase and inflated the reported upload speed/bytes.
- The Bonjour finder **dedupes by device name** so an Apple TV advertising AirPlay + RAOP + companion-link shows once, with its most specific label.
- **Fluid motion, iOS-27 native:** the gauge animates on fluid springs (`.spring`/`.snappy`/`.smooth`); SF Symbols use live effects (the run-button speedometer pulses with `.variableColor` while testing, the connection icon swaps wifi↔antenna with `.contentTransition(.symbolEffect(.replace))`); haptics are declarative `.sensoryFeedback` keyed to the test phase; cards ease/scale in via `.scrollTransition`; empty states use `ContentUnavailableView`.
- **Modern state model:** all live models (`HistoryStore`, `SpeedTestEngine`, `ConnectionMonitor`, `LocationProvider`, `ProManager`, `DeviceBrowser`, …) use the `@Observable` Observation framework for finer-grained, faster view updates; the connection map uses the current `Map(position:)` MapKit-SwiftUI API. No deprecation warnings.
- **Liquid Glass:** the secondary actions (Import / Sync) use `glassEffect` capsules and the system tab/nav bars adopt the iOS-26/27 glass material.
- **Coverage Map (Pro):** native `Map` heatmap with a smooth interpolated colour ramp, confidence-scaled tile opacity, and tap-to-select tile details. **Import CSV** (`.fileImporter`) drops an Ookla-format export — this app's or a real Speedtest export — onto the map; the parser is header-driven and quote-aware (kbps→Mbps).
- **Speed history graph:** a **Swift Charts** download/upload trend line on the Speed tab once you have two or more saved tests.
- The `control` (ping/ISP) session has an **8 s request timeout** so a stalled link can't hang the latency phase for minutes.
- **App icon:** a speedometer mark generated at 1024² in `Assets.xcassets/AppIcon.appiconset`.
- **Launch arguments (optional, for Shortcuts/automation):** `-startTab <0–3>` opens a specific tab, `-autorun 1` runs a speed test on launch. Both are off by default.

The full-power scanner still lives on the Mac (`netscope.py` / `Launch NetScope.command`).
