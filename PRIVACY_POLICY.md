# NetScope Privacy Policy

**Last updated: June 16, 2026**

NetScope ("the App") is a free network diagnostic tool for iPhone. This policy explains what information the App accesses and stores, and how it is used.

---

## Summary

> **NetScope does not collect, transmit, or sell your data. Everything stays on your device.**

---

## Information the App stores on your device

| Data | Description |
|------|-------------|
| **Speed test results** | Download/upload speeds, ping, jitter, timestamp, and network type. Kept until you clear them via Settings. |
| **Location** *(optional)* | GPS coordinates stamped on test results, only if you grant Location permission. Stored locally; never sent to the developer. |
| **Network details** | Wi-Fi name (SSID), router identifier (BSSID), signal strength, cellular carrier, and generation (5G/LTE/etc.). |
| **IP addresses** | Your public IP address (returned by Cloudflare during a test) and your local network IP. Stored in test history on your device only. |
| **ISP info** | Internet Service Provider name and approximate city, resolved from your IP by ipinfo.io. Stored locally. |

---

## Third-party services

Two external services are contacted **only when you run a speed test**. Neither service receives your name, GPS coordinates, device ID, or test history.

| Service | Purpose | Data sent |
|---------|---------|-----------|
| **Cloudflare** (`speed.cloudflare.com`) | Speed test measurement | Your IP address; network traffic during the test |
| **ipinfo.io** | ISP name and city lookup | Your IP address |

- Cloudflare Privacy Policy: https://www.cloudflare.com/privacypolicy/
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
| IP address | Yes (stored locally) | No | No |
| Other network info | Yes (stored locally) | No | No |

All data collected is stored locally on the user's device and is not linked to identity or used for tracking.
