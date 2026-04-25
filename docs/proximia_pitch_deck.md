# Proximia: Solution Challenge Pitch Deck Content

> **Note for NotebookLM:** 
> Please use the contents below to fill out the structure found in the "[EXT] Solution Challenge 2026 - Prototype PPT Template.pptx" document. It maps our technical implementation and problem statement perfectly to the Google Solution Challenge judging criteria.

---

## Slide 1: Title 
- **Project Name:** Proximia
- **Tagline:** Offline-first BLE patient tracking and AI anomaly detection for overburdened public hospitals.
- **Target Audience/Partner:** Wenlock District Hospital (and similar high-volume medical facilities).

---

## Slide 2: The Problem & UN SDG
- **Target UN SDG:** Goal 3: Good Health and Well-being.
- **The Problem:** Government hospitals face overwhelming patient volumes. Nursing staff lack real-time visibility into patient flow across various diagnostic zones (MRI, X-Ray, General Ward). This results in unknown wait-time bottlenecks, patient neglect, and significantly degraded emergency responsiveness.
- **The Gap:** Existing tracking solutions require expensive active RFID or heavy cloud reliance, which rural/public hospitals cannot afford or support due to spotty internet.

---

## Slide 3: Our Solution
- **The Concept:** A hyper-affordable, modular tracking ecosystem combining simple Bluetooth Low Energy (BLE) beacons with cutting-edge AI.
- **How it Works:** 
  1. Patients are given an ultra-cheap BLE beacon upon admission.
  2. Standard Android devices act as "Gateways" stationed in hospital rooms.
  3. A robust digital twin (Dashboard) maps the hospital in real-time, instantly visually pulsing when rooms are occupied.
  4. Google Gemini automatically flags when a patient has been waiting too long without receiving care.

---

## Slide 4: Google Technology Architecture
*(Visual: Add a clean block diagram showing the flow of data)*
- **Flutter:** Used uniquely to build *both* the Android Gateway scanner app and the highly immersive, visually mapped Web Dashboard.
- **Dart (Backend):** Powers a blazing fast, standalone local HTTP server. This establishes an "Offline-First" architecture that processes high-velocity BLE pings without needing internet connectivity.
- **Google Gemini API (2.5 Flash):** Acts as an automated nursing assistant. A background worker periodically checks patient wait durations against configurable thresholds and asks Gemini to generate professional, context-aware safety alerts.
- **Firebase Firestore:** Syncs critical events from the local server to the cloud natively, enabling persistent anomaly history and future analytics.

---

## Slide 5: The Demo Video
*(Visual: Insert 1-to-2 minute Screen Recording here)*
- **Demo Script Outline:**
  1. Show the physical setup: Bring a BLE beacon near an Android Gateway device.
  2. Switch to the Flutter Web Dashboard: Highlight how the immersive "Live Zone Map" smoothly pulses when the patient enters the "MRI Room".
  3. Wait/Simulate a timeout: Show the background process catching the wait limit.
  4. Show the AI Alert magically populating in the "AI Alerts" tab, showcasing the generated message from Gemini 2.5 Flash.

---

## Slide 6: Feedback & Next Steps
- **Current Achievements:** Successfully built a fully operational, end-to-end prototype from the hardware layer up to the AI layer, mapped directly to a hospital's specific floor plan logic.
- **Future Roadmap:**
  - **FCM Integration:** Automatically push the Gemini AI alerts directly to the smartwatches or mobile phones of on-call nurses using Firebase Cloud Messaging.
  - **Predictive Analytics:** Use historical Firestore data to train models that predict daily hospital bottlenecks before they happen.
  - **Asset Tracking:** Expand the BLE network to track expensive, frequently lost mobile hospital equipment (IV pumps, wheelchairs).
