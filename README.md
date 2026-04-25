<div align="center">

<img src="docs/assets/proximia_product_logo_v1.png" alt="Proximia Logo" width="180"/>

# Proximia
### BLE-Based Indoor Patient Zone Tracking for Hospitals

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=flat-square&logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.10-0175C2?style=flat-square&logo=dart)](https://dart.dev)
[![Firebase](https://img.shields.io/badge/Firebase-Firestore-FFCA28?style=flat-square&logo=firebase)](https://firebase.google.com)
[![Gemini](https://img.shields.io/badge/Gemini-2.5%20Flash-4285F4?style=flat-square&logo=google)](https://ai.google.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)

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
[Android Gateway App - Flutter]     ← one phone per ward zone
        │ HTTP POST /beacon  (local WiFi, ~200ms latency)
        ▼
[Dart Server - shelf, headless]  ◄──► [Flutter Web Dashboard]
        │ RSSI triangulation             live animated zone map
        │ zone assignment
        ▼
[Firebase Firestore]                ← cloud persistence (asia-south1)
        ▼
[Gemini 2.5 Flash API]              ← AI anomaly detection
        │ fires when patient exceeds zone threshold
        ▼
  [Nurse Alert → Dashboard]         (FCM push — planned)
```

---

## Features

| Feature | Status |
|---|---|
| ESP32 BLE beacon firmware (8-byte custom payload) | ✅ Working |
| Flutter Android gateway app — dynamic server IP + zone selection | ✅ Working |
| Dart/shelf BLE processing server with RSSI zone logic | ✅ Working |
| Animated Flutter Web dashboard with interactive hospital map | ✅ Working |
| Firebase Firestore — patient, event & alert persistence | ✅ Working |
| Gemini 2.5 Flash AI anomaly detection + human-readable alerts | ✅ Working |
| Firebase Hosting — live public dashboard | ✅ Deployed |
| FCM push notifications to nurse phones | 🔲 Planned |

---

## Google Technology Stack

| Technology | Role |
|---|---|
| **Flutter** | Android gateway app + Flutter Web dashboard |
| **Firebase Firestore** | Cloud persistence for patients, events, alerts |
| **Firebase Hosting** | Live public dashboard (`proximia-argus.web.app`) |
| **Gemini 2.5 Flash API** | Real-time AI anomaly detection & alert generation |

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

Gemini fires when a patient **exceeds the threshold** for their current zone, generating a one-sentence, plain-English nursing alert. Alerts are deduplicated with a 30-minute cooldown per patient.

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

MIT License — see [LICENSE](LICENSE) for details.
