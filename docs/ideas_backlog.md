# Ideas Backlog
*Running log of ideas — not scheduled, not forgotten*
*Update this file whenever a new idea comes up mid-conversation*

---

## Firebase / Cloud
- [ ] Zone-specific nurse assignment — nurse gets FCM alerts only for their ward's patients
- [ ] Nurse vicinity detection — FCM alert priority based on which zone the nurse is physically near
- [ ] Firebase Remote Config — change zone thresholds (OT: 3h, MRI: 45min) without redeploying server

## AI / Gemini
- [ ] Kannada language support in NL query assistant
- [ ] Gemini analyzing historical Firestore data to predict congestion ("OPD usually crowded at 10am")
- [ ] Patient risk scoring ("P-3 has been in 4 zones in 2 hours — possible wandering/confusion")
- [ ] Nurse workload balancing ("Zone A has 3 patients, Zone B has 0 — reassign?")

## Hardware
- [ ] ESP32 gateway firmware (replace Android phones with ESP32s at zone entrances)
- [ ] Custom PCB for wristband beacon (ESP32-WROOM-32 module, smaller form factor)
- [ ] Real battery ADC reading in beacon firmware (currently hardcoded 0xFF)
- [ ] Powerbank that doesn't auto-shutoff with low BLE draw (research models)

## Dashboard
- [ ] Patient name mapping on dashboard (beacon_id → name/bed number)
- [ ] Summary stats bar (total patients, active zones count)
- [ ] Mobile responsive layout
- [ ] Animated LIVE badge (subtle pulse)
- [ ] Role-based views (nurse vs. admin vs. CQA officer)

## Gateway App
- [ ] Foreground service — keeps BLE scanning alive when screen off
- [ ] App survives phone reboot (boot receiver)

## Business / Funding
- [ ] Apply to KDEM (Karnataka Digital Economy Mission)
- [ ] Google Solution Challenge 2026 submission (deadline: last week of June 2026)
- [ ] Confirm Pai's GDSC membership at NMAMIT
- [ ] Domain registration (zonepulse.in?)
- [ ] Hospital pitch deck for Wenlock demo

## Future / Post-Demo
- [ ] Patient data persistence (server currently in-memory only — Firestore will fix this)
- [ ] Multi-hospital deployment support (tenant isolation in Firestore)
- [ ] iOS gateway app support
- [ ] Startup company/product name finalized
