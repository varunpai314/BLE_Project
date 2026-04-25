# Proximia (BLE Patient Tracking) — Project Handoff Document
*Updated: 2026-04-18 | For pasting at the start of a new chat session*

---

## WHO I AM
- Name: Pai
- Engineering student at NMAMIT (Nitte), Mangaluru
- Flutter developer, interning at a LegalTech company
- Development machine: Lenovo IdeaPad 3 (Windows 11, Flutter + Dart installed)
- Demo machine: Lenovo G50-45 (Linux Mint — apps deployed as binaries)
- Prefer `flutter pub add` / `dart pub add` over editing pubspec.yaml manually
- Prefer complete updated files over partial diffs
- AI assistant used: Antigravity (Google DeepMind)

---

## THE PROJECT

### Product Name: **Proximia**
A BLE-based indoor patient zone detection system for hospitals.
- Not tied to any specific hospital — generic, deployable anywhere
- Domain: `proximia.in` (available, not yet registered)

### Problem Statement
The Chief Quality Assurance Officer at Wenlock District Hospital, Milagres, Mangaluru
wants to automatically track inpatient locations — MRI, X-Ray, OT, etc. — without nurses
manually updating. This is the pilot deployment site. The product is hospital-agnostic.

### Solution Architecture
```
[ESP32 Beacon - wristband]
        ↓ BLE advertisement
[Android Gateway App - Flutter] (Dynamic fetching from server via SharedPreferences)
        ↓ HTTP POST over local WiFi
[Dart Server - headless, shelf]  ←→  [Flutter Web Dashboard - full-screen browser map]
        ↓ async 
[Firebase Firestore - cloud persistence]
        ↓
[Gemini 2.5 Flash API - AI anomaly alerts]  
        ↓ (planned)
[FCM Push - nurse phones]
```

---

## COMPETITION CONTEXT — CRITICAL

### Google Solution Challenge 2026 (Build with AI)
- **DEADLINE: April 28, 2026 11:59 PM IST** ← hard deadline
- Team registered: **Argus** (Team Vigil was taken)
- Strategic Framing Choice: **[Smart Resource Allocation] Open Innovation**
- Description: *"Engineering Student from NMAMIT, Mangaluru, building Proximia — a BLE-based indoor patient tracking system for hospitals. Powered by Flutter, Firebase & Gemini AI. Addressing UN SDG 3: Good Health and Well-being."*
- PPT template downloaded — Markdown script mapping generated previously (`proximia_pitch_deck.md`) for NotebookLM consumption.

### Google Technologies in Use / Planned
| Technology | Status |
|---|---|
| Flutter (gateway app + web dashboard) | ✅ Fully Working (Immersive Map Built) |
| Firebase Firestore (persistence) | ✅ Integrated (Server side) |
| Gemini API (AI anomaly detection) | ✅ Integrated (`2.5-flash` working with special key) |
| Firebase Cloud Messaging / FCM    | 🔲 Planned |

---

## CURRENT STATUS (as of 2026-04-18 END OF DAY)

### What's Working ✅
- ESP32 beacon broadcasting correct 8-byte payload.
- **Gateway App Dynamic Setup**: `shared_preferences` remembers the selected Gateway ID and Server IP. Fetches available zones via `GET /zones` endpoint seamlessly.
- Dart server processing RSSI, assigning zones, tracking patients.
- Gemini API successfully triggering AI anomaly checking in the background. End-to-end alert triggering tested using `GET /debug/trigger-alert`. API key configuration solved (currently using working `AQ...` key over standard AIza limit:0 key).
- **Immersive Web Dashboard**: 
  - `ZoneMap` is converted to a StatefulWidget full-screen map taking up the whole center.
  - Interactive pulsing layout using an `AnimationController` to flash border colors when patients are waiting inside a zone.
  - Clicking on a map room opens a sleek Material `AlertDialog` overlay showing the active patients inside that specific room.
  - Gateways perfectly match the Flutter map to Dart Server configurations (`GW_001` -> Entrance/OPD Waiting, `GW_002` -> MRI Room, etc).

---

## WHAT NEEDS TO BE DONE NEXT (PITCH PHASE)

### 🔴 Before April 28 (Competition Deadline)

#### 1. Finish the PPT via NotebookLM
- Take the `proximia_pitch_deck.md` script generated today and upload it alongside the generic PowerPoint template to Google NotebookLM. Let it compile the pitch content perfectly mapped to the structure.

#### 2. Demo Video Recording
- Use Windows Game Bar (`Win + G`) or OBS to capture a tight, 1-2 minute video of the full hardware → dashboard flow. Make sure to capture the visual pulsing animation of the map when a patient triggers an AI Alert!

#### 3. FCM Push Notifications (Secondary Priority)
- Only if time permits! If you need a breather, the existing Dashboard + AI pipeline is more than enough.
- To implement: Register FCM token in gateway mobile app `POST /register-fcm`. Server uses `firebase_admin_sdk` to push Gemini warnings directly to nurse phones.

#### 4. ble_dashboard — Firebase integration (Optional for Demo)
- Make the Flutter web dashboard tap into Firebase directly to pull historical alerts, rather than purely polling the current session `http://192.168.29.76:8080/events`.

---

## ENVIRONMENT & TECHNICAL DETAILS
- Flutter: stable | Dart: 3.10.8
- Dev OS: Windows 11
- Server IP (home WiFi): 192.168.29.76 (Use `--web-hostname=0.0.0.0 --web-port=3000` to run web server on LAN)
- Firebase project ID: `proximia-argus` (Region: asia-south1)
- Gemini model: `gemini-2.5-flash` (Using working `AQ.` API key to bypass the standard account limit:0 India free tier block).

## KNOWN ISSUES / GOTCHAS
- **New Account Gemini Keys**: New AI Studio projects generated in your region hit a `limit:0` block on free-tier for `gemini-2.0-flash` and 404 for `1.5-flash`. The provided `AQ...` key is hardcoded currently in `ble_server.dart` and works flawlessly.
- To access the dashboard over WiFi, DO NOT use `-d chrome`. Use `flutter run -d web-server --web-hostname=0.0.0.0` or Windows Firewall will block the debug websocket port.
- Port 8080 conflict on restart: kill with `Stop-Process -Id (Get-NetTCPConnection -LocalPort 8080).OwningProcess -Force`

---
*Paste this entire file at the start of a new chat to continue seamlessly.*
*Last updated: 2026-04-18 after Map UI Overhaul, Gateway Dynamic Configuration, and Pitch Setup.*
