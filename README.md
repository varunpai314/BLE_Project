<div align="center">

<img src="docs/assets/proximia_product_logo_v1.png" alt="Proximia Logo" width="180"/>

# Proximia
### BLE-Based Indoor Patient Zone Tracking for Hospitals

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=flat-square&logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.10-0175C2?style=flat-square&logo=dart)](https://dart.dev)
[![Firebase](https://img.shields.io/badge/Firebase-Firestore-FFCA28?style=flat-square&logo=firebase)](https://firebase.google.com)
[![Gemini](https://img.shields.io/badge/Gemini-2.5%20Flash-4285F4?style=flat-square&logo=google)](https://ai.google.dev)

**Google Solution Challenge 2026 · Team Argus · NMAMIT, Nitte**

[Live Dashboard →](https://proximia-argus.web.app) · [Demo Video →](#demo-video)

</div>

---

## What is Proximia?

Hospitals struggle with manually tracking inpatient locations — nurses call zones, check boards, and interrupt workflows just to know if a patient is in MRI or still in OPD Waiting. **Proximia automates this entirely using Bluetooth Low Energy (BLE).**

Patients wear a small ESP32 wristband beacon. Android phones placed at ward entry points act as gateways, picking up BLE signals and posting them to a local Dart server over WiFi. The server resolves patient locations in real time and drives a live, animated web dashboard — plus calls Gemini AI to alert staff when a patient has been waiting too long in any zone.

> **Pilot Site:** Wenlock District Hospital, Milagres, Mangaluru.
> **Design:** Hospital-agnostic — drop-in deployable at any facility.

---

## Architecture

```
[ESP32 Beacon - patient wristband]
        │ BLE advertisement (8-byte payload, 500ms interval)
        ▼
[Android Gateway App - Flutter]     ← nurse logs in, registers name
        │ HTTP POST /beacon  (local WiFi, ~200ms latency)
        │ POST /register-nurse (FCM token + gateway ID)
        ▼
[Dart Server - shelf, headless]  ◄──► [Flutter Web Dashboard - Firebase Hosted]
        │ Rule-based zone dwell detection         Google Sign-In auth gate
        │ zone assignment                         Shift Summary button
        ▼
[Firebase Firestore]                ← cloud persistence (asia-south1)
        ▼
[Gemini 2.5 Flash API]
        │  ├─ Per-patient alert (threshold breached)
        │  ├─ Bottleneck alert (≥2 patients overdue in same zone)
        │  └─ Shift summary (on-demand handover report)
        ▼
[FCM Push → nurse's phone in that zone]   ← proximity-aware delivery
```

---

## Features

| Feature | Status |
|---|---|
| ESP32 BLE beacon firmware (8-byte custom payload) | ✅ Working |
| Flutter Android gateway app — dynamic server IP + zone selection | ✅ Working |
| Nurse name registration at gateway setup | ✅ Working |
| Dart/shelf BLE processing server with RSSI zone logic | ✅ Working |
| Animated Flutter Web dashboard with interactive hospital map | ✅ Working |
| Firebase Firestore — patient, event & alert persistence | ✅ Working |
| Gemini 2.5 Flash — per-patient anomaly alert generation | ✅ Working |
| Gemini — multi-patient bottleneck detection (≥2 in same zone) | ✅ Working |
| Gemini — on-demand shift handover summary (GET /summary) | ✅ Working |
| FCM proximity alerts — push to nurse in patient's zone | ✅ Working |
| Google Sign-In auth gate on dashboard (Firebase Auth) | ✅ Working |
| Firebase Hosting — live public dashboard | ✅ Deployed |

---

## Google Technology Stack

| Technology | Role |
|---|---|
| **Flutter** | Android gateway app + Flutter Web dashboard |
| **Firebase Auth** | Google Sign-In gate for the dashboard |
| **Firebase Firestore** | Cloud persistence for patients, events, alerts |
| **Firebase Hosting** | Live public dashboard (`proximia-argus.web.app`) |
| **Firebase Cloud Messaging (FCM)** | Proximity-aware push alerts to nurses |
| **Gemini 2.5 Flash API** | Per-patient alerts, bottleneck detection, shift summaries |

---

## Repository Structure

```
Wenlock_BLE_Project/
├── ble_beacon/          # ESP32 Arduino firmware
├── ble_server/          # Dart/shelf backend server
│   ├── lib/
│   │   └── ble_server.dart    # Core server logic (BLE processing + Gemini)
│   └── bin/
│       └── ble_server.dart    # Entry point
├── ble_dashboard/       # Flutter Web dashboard (Firebase Hosted)
│   └── lib/
│       └── main.dart          # Animated zone map + live patient tracking
├── gateway_app/         # Flutter Android gateway app (submodule)
├── hospital_server/     # Companion web portal (WIP)
└── docs/                # Architecture, pitch deck, project docs
```

---

## Getting Started

### Prerequisites
- Flutter SDK (stable) · Dart ≥ 3.10
- Firebase CLI (`npm install -g firebase-tools`)
- A `service-account.json` for your Firebase project (not committed — see `.env` setup)

### 1. Run the BLE Server
```bash
cd ble_server
cp .env.example .env          # add your GCP_API_KEY
dart run bin/ble_server.dart
```
Server starts at `http://0.0.0.0:8080`.

### 2. Run the Dashboard (local dev)
```bash
cd ble_dashboard
flutter run -d web-server --web-hostname=0.0.0.0 --web-port=3000
```
Open `http://<your-local-ip>:3000` in any browser on the same network.

### 3. Live Dashboard
The dashboard is deployed publicly at:
**[https://proximia-argus.web.app](https://proximia-argus.web.app)**

> Note: Without the local BLE server running, the dashboard will show an empty state. This is expected — it polls `POST /beacon` data from the hardware in production.

### 4. Gateway App
Set up on Android — enter the server IP (`192.168.x.x:8080`) and select the Gateway ID for that zone. The app fetches available zones dynamically from `GET /zones`.

---

## Zones & AI Thresholds

| Zone | Gateway | Alert Threshold |
|---|---|---|
| OPD Waiting | GW_001 | 2 hours |
| MRI Room | GW_002 | 45 minutes |
| Operation Theater | GW_003 | 3 hours |
| X-Ray Room | GW_004 | 30 minutes |
| General Ward | GW_005 | 6 hours |

The server uses **rule-based threshold detection** — when a patient's dwell time in a zone exceeds the limit, three things happen:

1. **Per-patient alert** — Gemini generates a one-sentence clinical nursing alert with the patient's context
2. **Bottleneck alert** — if ≥2 patients are overdue in the *same zone*, Gemini generates a systemic bottleneck alert (e.g. equipment delay, staffing gap)
3. **FCM push** — the alert is routed to the nurse whose phone is registered on that gateway zone

All alerts are deduplicated with a 30-minute cooldown and stored in Firestore. The dashboard's "Shift Summary" button calls `GET /summary` to generate a Gemini-authored handover report for the entire session.

---

## Demo Video

*Coming soon — recording in progress.*

---

## Team

**Team Argus** · NMAMIT, Nitte (Deemed-to-be University), Mangaluru

| Role | Name |
|---|---|
| Lead Developer | Varun Pai ([@varunpai314](https://github.com/varunpai314)) |

---

## Competition

> **Google Solution Challenge 2026** — Build with AI
> Strategic Category: **Smart Resource Allocation · Open Innovation**
> UN SDG Alignment: **SDG 3 — Good Health and Well-being**

---

## License

© 2026 Varun Pai. All rights reserved.
This source code is made available for evaluation and demonstration purposes only. No license is granted for use, modification, or distribution without explicit written permission from the author.
