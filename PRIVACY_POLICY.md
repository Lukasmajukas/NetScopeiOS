# NetScope Privacy Policy

**Last updated: June 18, 2026**

NetScope ("the App") is a free network diagnostic tool for iPhone. This policy explains what information the App accesses and stores, and how it is used.

---

## Summary

> **NetScope has no servers and no analytics — the developer never receives, stores, or sells your data, and your results live on your device.** Running a speed test does send your IP address to the test backbone (Cloudflare by default, or M-Lab if you choose an M-Lab location) and to ipinfo.io, as any speed test must. **Important:** if you choose an **M-Lab** location, that test — your IP address, the time, and your measured speeds — is published publicly by M-Lab as open data under a CC0 license, and that cannot be undone. The app shows a one-time consent prompt before your first M-Lab test, and Cloudflare (not published) is always the default.

---

## Information the App stores on your device

| Data | Description |
|------|-------------|
| **Speed test results** | Download/upload speeds, ping, jitter, timestamp, and network type. Kept until you clear them via Settings. |
| **Location** *(optional)* | GPS coordinates stamped on test results, only if you grant Location permission. Stored locally; never sent to the developer. |
| **Network details** | Wi-Fi name (SSID), router identifier (BSSID), signal strength, cellular carrier, and generation (5G/LTE/etc.). |
| **IP addresses** | Your public IP address (from ipinfo.io and the test backbone) and your local network IP, stored in your on-device history. On the **M-Lab** path your public IP is also transmitted to and published by M-Lab — see Third-party services. |
| **ISP info** | Internet Service Provider name and approximate city, resolved from your IP by ipinfo.io. Stored locally. |

---

## Third-party services

External services are contacted when you open the Speed tab (to list nearby servers and measure their ping), pick a server, or run a test. None of them receives your name, GPS coordinates, device ID, or test history.

| Service | Purpose | Data sent |
|---------|---------|-----------|
| **Cloudflare** (`speed.cloudflare.com`) | Default speed-test backbone | Your IP address; network traffic during the test |
| **M-Lab / Measurement Lab** (`measurement-lab.org`) | Optional open-source backbone you can select | Your IP address and the test traffic. **M-Lab publishes every test run against it — your IP, the time, and your measured speeds — as an open public dataset under a CC0 license.** Only contacted when you list/select an M-Lab server or run a test against one. |
| **ipinfo.io** | ISP name and city lookup | Your IP address |

- Cloudflare Privacy Policy: https://www.cloudflare.com/privacypolicy/
- M-Lab Privacy Policy: https://www.measurementlab.net/privacy/
- ipinfo.io Privacy Policy: https://ipinfo.io/privacy

---

## Permissions

| Permission | Why it's requested | Without it |
|------------|-------------------|------------|
| **Location** (When In Use) | Stamp speed tests with GPS coordinates for the map and CSV export | Tests still run; lat/lon will be blank in exports and the map won't show your location |
| **Local Network** | Discover devices (printers, TVs, etc.) on your Wi-Fi in the Devices tab | The Devices tab won't find anything |

You can change permissions at any time in **iOS Settings → Privacy & Security → NetScope** (Location) or the main Settings app (Local Network).

---

## Data storage and retention

All test results are stored in your device's app container. They are:

- Not backed up to any developer-operated server
- Not synced across devices (no iCloud sync)
- Kept until you clear them via **Settings → Data → Clear History** or until you delete the app

If you export a CSV file, it is created in your device's temporary storage and shared only by your explicit action (AirDrop, Files, Mail, etc.). The developer never receives this file.

---

## What the app does NOT do

- Does not require an account or sign-in
- Does not send data to any server operated by the developer
- Does not use analytics or crash-reporting SDKs
- Does not serve advertising
- Does not track you across apps or websites

---

## Children

NetScope is not directed at children under 13 and does not knowingly collect personal information from children.

---

## Changes to this policy

If this policy changes materially, the updated policy will be available within the app. The "last updated" date at the top of this document will be revised.

---

## Contact

For privacy questions or requests:

**Email:** odonnelldigger1@gmail.com

---

## App Store privacy nutrition label

The following categories apply to NetScope for App Store Connect disclosure:

| Category | Collected | Linked to identity | Used for tracking |
|----------|-----------|--------------------|-------------------|
| Precise location | No | — | No |
| Coarse location | Yes (if granted) | No | No |
| IP address | Yes | No | No |
| Other network info | Yes | No | No |

NetScope itself has no servers, no analytics, no ads, and does not track you across apps or websites. On the default **Cloudflare** path, network/IP data is used only for the live test and stored on your device. If you choose an **M-Lab** location, your IP address, the test time, and your measured speeds are transmitted to M-Lab (a third party) and published by M-Lab as an open, CC0-licensed public dataset. Set the App Store Connect "App Privacy" answers to reflect that, on the M-Lab path, IP address and diagnostics are **collected by and shared with a third party**.
