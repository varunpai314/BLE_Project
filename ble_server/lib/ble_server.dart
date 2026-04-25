import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_admin_sdk/firebase_admin_sdk.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http_pkg;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:dotenv/dotenv.dart';

// ─────────────────────────────────────────
//  CONFIG — update before demo
// ─────────────────────────────────────────
const int serverPort = 8080;
const String firebaseProjectId = 'proximia-argus';

// Gemini API key — fetched from lib/.env at runtime
String geminiApiKey = '';

const Map<String, String> gatewayZoneMap = {
  'GW_001': 'OPD Waiting',
  'GW_002': 'MRI Room',
  'GW_003': 'Operation Theater',
  'GW_004': 'X-Ray Room',
  'GW_005': 'General Ward',
};

// Zone alert thresholds (in minutes)
// Gemini fires when a patient exceeds these limits
const Map<String, int> zoneAlertThresholds = {
  'OPD Waiting':        120,  // 2 hours
  'MRI Room':            45,  // 45 minutes
  'Operation Theater':  180,  // 3 hours
  'X-Ray Room':          30,  // 30 minutes
  'General Ward':       360,  // 6 hours
};

// Re-alert cooldown per patient (minutes)
const int alertCooldownMinutes = 30;

// Gemini model to use
const String geminiModel = 'gemini-2.5-flash';
// ─────────────────────────────────────────

// Inverse map: zone name → gateway ID (used for FCM routing)
// Built as a const since gatewayZoneMap is const.
const Map<String, String> zoneToGatewayMap = {
  'OPD Waiting':       'GW_001',
  'MRI Room':          'GW_002',
  'Operation Theater': 'GW_003',
  'X-Ray Room':        'GW_004',
  'General Ward':      'GW_005',
};


// ─────────────────────────────────────────
//  Firebase — initialized lazily
// ─────────────────────────────────────────
FirebaseApp? _firebaseApp;
dynamic _firestore; // null = offline mode

Future<void> _initFirebase() async {
  const serviceAccountPath = 'service-account.json';
  final file = File(serviceAccountPath);

  if (!file.existsSync()) {
    print('[FIREBASE] service-account.json not found → Firestore sync DISABLED');
    print('[FIREBASE] Server runs normally. Add service-account.json to enable cloud sync.');
    return;
  }

  try {
    _firebaseApp = FirebaseApp.initializeApp(
      options: AppOptions(
        credential: Credential.fromServiceAccount(file),
        projectId: firebaseProjectId,
      ),
    );
    _firestore = _firebaseApp!.firestore();
    print('[FIREBASE] ✓ Firestore connected — cloud sync ENABLED');
  } catch (e) {
    print('[FIREBASE] Init failed → Firestore sync DISABLED: $e');
  }
}

// ─────────────────────────────────────────
//  Firestore Sync Helpers (fire-and-forget)
// ─────────────────────────────────────────
void _syncPatientToFirestore(PatientState patient) {
  if (_firestore == null) return;
  final data = patient.toJson();
  Future.delayed(Duration.zero, () {
    _firestore!
        .collection('patients')
        .doc('${patient.beaconId}')
        .set(data)
        .catchError((e) => print('[FIREBASE] Patient sync error: $e'));
  });
}

void _logEventToFirestore(ZoneEvent event) {
  if (_firestore == null) return;
  final data = event.toJson();
  Future.delayed(Duration.zero, () {
    _firestore!
        .collection('events')
        .doc()
        .set(data)
        .catchError((e) => print('[FIREBASE] Event log error: $e'));
  });
}

void _syncAlertToFirestore(PatientAlert alert) {
  if (_firestore == null) return;
  final data = alert.toJson();
  Future.delayed(Duration.zero, () {
    _firestore!
        .collection('alerts')
        .doc()
        .set(data)
        .catchError((e) => print('[FIREBASE] Alert sync error: $e'));
  });
}

// ─────────────────────────────────────────
//  Nurse FCM Registry
// ─────────────────────────────────────────
class NurseRegistration {
  final String gatewayId;
  final String nurseName;
  final String fcmToken;
  final DateTime registeredAt;

  NurseRegistration({
    required this.gatewayId,
    required this.nurseName,
    required this.fcmToken,
    required this.registeredAt,
  });
}

/// gatewayId → nurse currently assigned to that phone
final Map<String, NurseRegistration> _nurseRegistry = {};

/// Send an FCM push to the nurse in the patient's zone using HTTP v1 API.
Future<void> _sendFcmAlert(PatientAlert alert) async {
  final gatewayId = zoneToGatewayMap[alert.zone];
  if (gatewayId == null) return;

  final nurse = _nurseRegistry[gatewayId];
  if (nurse == null) {
    print('[FCM]     No nurse registered for $gatewayId (${alert.zone}) — skipping push');
    return;
  }

  final file = File('service-account.json');
  if (!file.existsSync()) {
    print('[FCM]     service-account.json not found — cannot authenticate FCM HTTP v1.');
    return;
  }

  try {
    final creds = ServiceAccountCredentials.fromJson(file.readAsStringSync());
    final client = await clientViaServiceAccount(creds, ['https://www.googleapis.com/auth/firebase.messaging']);
    final token = client.credentials.accessToken.data;

    final uri = Uri.parse('https://fcm.googleapis.com/v1/projects/$firebaseProjectId/messages:send');
    final body = jsonEncode({
      'message': {
        'token': nurse.fcmToken,
        'notification': {
          'title': '🚨 Proximia Alert — ${alert.zone}',
          'body': alert.message,
        },
        'data': {
          'beacon_id': '${alert.beaconId}',
          'zone': alert.zone,
          'duration_minutes': '${alert.durationMinutes}',
        },
        'android': {
          'priority': 'HIGH',
          'notification': {
            'sound': 'default',
          }
        }
      }
    });

    final response = await client
        .post(uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: body)
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      print('[FCM]     ✓ Push sent to ${nurse.nurseName} (${nurse.gatewayId})');
    } else {
      print('[FCM]     Push error ${response.statusCode}: ${response.body}');
    }
    client.close();
  } catch (e) {
    print('[FCM]     Push failed: $e');
  }
}

// ─────────────────────────────────────────
//  Models
// ─────────────────────────────────────────
class BeaconReading {
  final String gatewayId;
  final int beaconId;
  final int rssi;
  final int battery;
  final DateTime timestamp;

  BeaconReading({
    required this.gatewayId,
    required this.beaconId,
    required this.rssi,
    required this.battery,
    required this.timestamp,
  });

  factory BeaconReading.fromJson(Map<String, dynamic> json) {
    return BeaconReading(
      gatewayId: json['gateway_id'] as String,
      beaconId: json['beacon_id'] as int,
      rssi: json['rssi'] as int,
      battery: json['battery'] as int,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}

class PatientState {
  final int beaconId;
  String currentZone;
  String currentGateway;
  int currentRssi;
  DateTime lastSeen;
  DateTime zoneEntryTime;

  PatientState({
    required this.beaconId,
    required this.currentZone,
    required this.currentGateway,
    required this.currentRssi,
    required this.lastSeen,
    required this.zoneEntryTime,
  });

  Map<String, dynamic> toJson() => {
    'beacon_id': beaconId,
    'current_zone': currentZone,
    'gateway_id': currentGateway,
    'rssi': currentRssi,
    'last_seen': lastSeen.toIso8601String(),
    'zone_entry_time': zoneEntryTime.toIso8601String(),
    'duration_seconds': DateTime.now().difference(zoneEntryTime).inSeconds,
  };
}

class ZoneEvent {
  final int beaconId;
  final String zone;
  final String gatewayId;
  final DateTime timestamp;

  ZoneEvent({
    required this.beaconId,
    required this.zone,
    required this.gatewayId,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'beacon_id': beaconId,
    'zone': zone,
    'gateway_id': gatewayId,
    'timestamp': timestamp.toIso8601String(),
    'message': 'Patient P-$beaconId entered ${zone.toUpperCase()}',
  };
}

class PatientAlert {
  final int beaconId;
  final String zone;
  final int durationMinutes;
  final String message;      // Gemini-generated human-readable alert
  final DateTime timestamp;

  PatientAlert({
    required this.beaconId,
    required this.zone,
    required this.durationMinutes,
    required this.message,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'beacon_id': beaconId,
    'zone': zone,
    'duration_minutes': durationMinutes,
    'message': message,
    'timestamp': timestamp.toIso8601String(),
  };
}

// ─────────────────────────────────────────
//  In-Memory State (offline-first)
// ─────────────────────────────────────────
final Map<int, Map<String, BeaconReading>> _readings = {};
final Map<int, PatientState> _patients = {};
final List<ZoneEvent> _events = [];
final List<PatientAlert> _alerts = [];
final List<PatientAlert> _bottleneckAlerts = [];

// Deduplication: beaconId → last time an alert was sent for that patient
final Map<int, DateTime> _lastAlertSentAt = {};
// Bottleneck dedup: zone → last bottleneck alert time
final Map<String, DateTime> _lastBottleneckAlertAt = {};

// (FCM now uses service-account.json instead of .env server key)

// ─────────────────────────────────────────
//  Core Zone Logic
// ─────────────────────────────────────────
void processReading(BeaconReading reading) {
  _readings[reading.beaconId] ??= {};
  _readings[reading.beaconId]![reading.gatewayId] = reading;

  // Strongest RSSI among gateways that reported within last 10 seconds
  String? strongestGateway;
  int strongestRssi = -999;

  for (final entry in _readings[reading.beaconId]!.entries) {
    final age = DateTime.now().difference(entry.value.timestamp).inSeconds;
    if (age > 10) continue;
    if (entry.value.rssi > strongestRssi) {
      strongestRssi = entry.value.rssi;
      strongestGateway = entry.key;
    }
  }

  if (strongestGateway == null) return;

  final zone = gatewayZoneMap[strongestGateway] ?? 'Unknown Zone';
  final now = DateTime.now();

  if (!_patients.containsKey(reading.beaconId)) {
    final patient = PatientState(
      beaconId: reading.beaconId,
      currentZone: zone,
      currentGateway: strongestGateway,
      currentRssi: strongestRssi,
      lastSeen: now,
      zoneEntryTime: now,
    );
    _patients[reading.beaconId] = patient;
    _addEvent(reading.beaconId, zone, strongestGateway, now);
    _syncPatientToFirestore(patient);
    print('[NEW]     Patient P-${reading.beaconId} detected in $zone');
  } else {
    final patient = _patients[reading.beaconId]!;
    patient.lastSeen = now;
    patient.currentRssi = strongestRssi;

    if (patient.currentZone != zone) {
      print('[MOVED]   Patient P-${reading.beaconId}: ${patient.currentZone} → $zone');
      patient.currentZone = zone;
      patient.currentGateway = strongestGateway;
      patient.zoneEntryTime = now;
      // Reset alert cooldown on zone change so the new zone is checked fresh
      _lastAlertSentAt.remove(reading.beaconId);
      _addEvent(reading.beaconId, zone, strongestGateway, now);
      _syncPatientToFirestore(patient);
    } else {
      patient.currentGateway = strongestGateway;
    }
  }
}

void _addEvent(int beaconId, String zone, String gatewayId, DateTime time) {
  final event = ZoneEvent(
    beaconId: beaconId,
    zone: zone,
    gatewayId: gatewayId,
    timestamp: time,
  );
  _events.insert(0, event);
  if (_events.length > 200) _events.removeLast();
  _logEventToFirestore(event);
}

// ─────────────────────────────────────────
//  Gemini Anomaly Detection
// ─────────────────────────────────────────

/// Called on startup — runs every 60 seconds in the background.
void startAnomalyChecker() {
  // Run once after 60 seconds, then every minute
  Timer.periodic(const Duration(minutes: 1), (_) => _checkAnomalies());
  print('[GEMINI]  Anomaly checker started — scanning every 60 seconds');
}

/// Checks all tracked patients against zone thresholds.
/// Fires Gemini alert if threshold exceeded and cooldown has elapsed.
/// Also detects multi-patient bottlenecks in the same zone.
Future<void> _checkAnomalies() async {
  if (_patients.isEmpty) return;
  print('[GEMINI]  Running anomaly check on ${_patients.length} patient(s)...');

  final now = DateTime.now();
  // Track overdue patients per zone for bottleneck detection
  final Map<String, List<PatientState>> overdueByZone = {};

  for (final patient in _patients.values) {
    final thresholdMin = zoneAlertThresholds[patient.currentZone];
    if (thresholdMin == null) continue;

    final durationMin = now.difference(patient.zoneEntryTime).inMinutes;
    if (durationMin < thresholdMin) continue;

    // Record as overdue for bottleneck grouping
    overdueByZone.putIfAbsent(patient.currentZone, () => []).add(patient);

    // Per-patient cooldown check
    final lastAlert = _lastAlertSentAt[patient.beaconId];
    if (lastAlert != null &&
        now.difference(lastAlert).inMinutes < alertCooldownMinutes) {
      continue;
    }

    print(
      '[GEMINI]  ⚠ P-${patient.beaconId} in ${patient.currentZone} '
      'for ${durationMin}min (threshold: ${thresholdMin}min) — calling Gemini...',
    );

    final alertMessage = await _callGeminiForAlert(patient, durationMin, thresholdMin);
    if (alertMessage != null) {
      _recordAlert(patient, durationMin, alertMessage.trim());
    }
  }

  // ── Bottleneck detection: zones with ≥2 overdue patients ──
  await _checkBottlenecks(overdueByZone);
}

/// Calls Gemini Flash API and returns a plain-English alert string, or null on failure.
Future<String?> _callGeminiForAlert(
  PatientState patient,
  int durationMin,
  int thresholdMin,
) async {
  if (geminiApiKey == 'YOUR_GEMINI_API_KEY_HERE' || geminiApiKey.isEmpty) {
    print('[GEMINI]  ⚠ No API key set — skipping Gemini call');
    return null;
  }

  final prompt = '''
You are an AI alert assistant for Proximia, a hospital patient tracking system.
A patient has spent more time in a hospital zone than the recommended limit.

Patient Details:
- Patient ID: P-${patient.beaconId}
- Current Zone: ${patient.currentZone}
- Time in Zone: $durationMin minutes
- Recommended Maximum: $thresholdMin minutes
- Last Seen via Gateway: ${patient.currentGateway}

Write a single, clear, professional alert message (1-2 sentences only) for the nursing staff.
Do NOT include any preamble, labels, or formatting — just the alert message text itself.
''';

  try {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$geminiModel:generateContent?key=$geminiApiKey',
    );

    final response = await http_pkg
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {'text': prompt},
                ],
              },
            ],
            'generationConfig': {
              'temperature': 0.4,
              'maxOutputTokens': 100,
            },
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
      return text;
    } else {
      print('[GEMINI]  API error ${response.statusCode}: ${response.body}');
      return null;
    }
  } catch (e) {
    print('[GEMINI]  Call failed: $e');
    return null;
  }
}

/// Records a confirmed Gemini alert in memory, Firestore, and sends FCM push.
void _recordAlert(PatientState patient, int durationMin, String message) {
  final alert = PatientAlert(
    beaconId: patient.beaconId,
    zone: patient.currentZone,
    durationMinutes: durationMin,
    message: message,
    timestamp: DateTime.now(),
  );

  _alerts.insert(0, alert);
  if (_alerts.length > 100) _alerts.removeLast();
  _lastAlertSentAt[patient.beaconId] = DateTime.now();

  _syncAlertToFirestore(alert);
  _sendFcmAlert(alert); // fire-and-forget push to nurse in zone

  // Console print — clearly visible in server logs
  print('');
  print('╔══════════════════════════════════════════╗');
  print('║  🚨 GEMINI ALERT                         ║');
  print('╠══════════════════════════════════════════╣');
  print('║  Patient : P-${patient.beaconId}');
  print('║  Zone    : ${patient.currentZone}');
  print('║  Duration: ${durationMin}min');
  print('║  Message : $message');
  print('╚══════════════════════════════════════════╝');
  print('');
}

/// Bottleneck alert: fired when ≥2 patients are overdue in the same zone.
Future<void> _checkBottlenecks(Map<String, List<PatientState>> overdueByZone) async {
  final now = DateTime.now();
  for (final entry in overdueByZone.entries) {
    final zone = entry.key;
    final patients = entry.value;
    if (patients.length < 2) continue;

    final last = _lastBottleneckAlertAt[zone];
    if (last != null && now.difference(last).inMinutes < alertCooldownMinutes) continue;

    print('[GEMINI]  🚧 Bottleneck in $zone — ${patients.length} patients overdue. Calling Gemini...');
    final msg = await _callGeminiForBottleneckAlert(zone, patients);
    if (msg == null) continue;

    _lastBottleneckAlertAt[zone] = now;
    final alert = PatientAlert(
      beaconId: -1, // -1 = systemic alert, not a single patient
      zone: zone,
      durationMinutes: patients.map((p) => now.difference(p.zoneEntryTime).inMinutes).reduce((a, b) => a > b ? a : b),
      message: msg.trim(),
      timestamp: now,
    );
    _bottleneckAlerts.insert(0, alert);
    if (_bottleneckAlerts.length > 50) _bottleneckAlerts.removeLast();
    _syncAlertToFirestore(alert);

    print('');
    print('╔══════════════════════════════════════════╗');
    print('║  🚧 BOTTLENECK ALERT                     ║');
    print('╠══════════════════════════════════════════╣');
    print('║  Zone    : $zone');
    print('║  Patients: ${patients.length}');
    print('║  Message : ${msg.trim()}');
    print('╚══════════════════════════════════════════╝');
    print('');
  }
}

/// Calls Gemini to generate a systemic bottleneck alert for a zone.
Future<String?> _callGeminiForBottleneckAlert(
  String zone,
  List<PatientState> patients,
) async {
  if (geminiApiKey.isEmpty) return null;

  final patientLines = patients.map((p) {
    final dur = DateTime.now().difference(p.zoneEntryTime).inMinutes;
    return '  - Patient P-${p.beaconId}: ${dur}min in zone (threshold: ${zoneAlertThresholds[zone]}min)';
  }).join('\n');

  final prompt = '''
You are an AI alert assistant for Proximia, a hospital patient tracking system.
Multiple patients are backed up in the same zone beyond the safe wait time — this may indicate a systemic issue.

Zone: $zone
Overdue patients (${patients.length} total):
$patientLines

Write a single, concise, professional alert (1-2 sentences) for the charge nurse suggesting this may be a systemic bottleneck — possible equipment delay or staffing gap. No preamble, no labels, just the message.
''';

  try {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$geminiModel:generateContent?key=$geminiApiKey',
    );
    final response = await http_pkg
        .post(uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [{'text': prompt}]
                }
              ],
              'generationConfig': {'temperature': 0.4, 'maxOutputTokens': 120},
            }))
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
    }
  } catch (e) {
    print('[GEMINI]  Bottleneck call failed: $e');
  }
  return null;
}

// ─────────────────────────────────────────
//  Routes
// ─────────────────────────────────────────
Router buildRouter() {
  final router = Router();

  // Gateway phones POST beacon data here
  router.post('/beacon', (Request request) async {
    try {
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final reading = BeaconReading.fromJson(json);
      processReading(reading);
      return Response.ok('OK');
    } catch (e) {
      print('[ERROR]   /beacon → $e');
      return Response.badRequest(body: 'Invalid payload: $e');
    }
  });

  // Dashboard fetches current patient states
  router.get('/patients', (Request request) {
    final data = _patients.values.map((p) => p.toJson()).toList();
    return Response.ok(
      jsonEncode(data),
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
      },
    );
  });

  // App fetches zones
  router.get('/zones', (Request request) {
    final zones = gatewayZoneMap.entries.map((e) => {
      'gatewayId': e.key,
      'zoneName': e.value,
    }).toList();
    return Response.ok(
      jsonEncode({'zones': zones}),
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
      },
    );
  });

  // Dashboard fetches event log
  router.get('/events', (Request request) {
    final data = _events.map((e) => e.toJson()).toList();
    return Response.ok(
      jsonEncode(data),
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
      },
    );
  });

  // Dashboard fetches AI-generated alerts
  router.get('/alerts', (Request request) {
    final data = _alerts.map((a) => a.toJson()).toList();
    return Response.ok(
      jsonEncode(data),
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
      },
    );
  });

  // ── DEBUG: force an immediate Gemini alert (for testing / demo) ──
  // Usage: GET /debug/trigger-alert
  // Optional query param: ?beacon_id=1  (defaults to first patient, or dummy)
  router.get('/debug/trigger-alert', (Request request) async {
    final idParam = request.url.queryParameters['beacon_id'];
    final int? requestedId = idParam != null ? int.tryParse(idParam) : null;

    // Pick a real patient or synthesise a dummy
    PatientState? patient =
        (requestedId != null ? _patients[requestedId] : null) ??
        _patients.values.firstOrNull;

    final bool usedDummy = patient == null;
    if (usedDummy) {
      // No beacons tracked yet — create a synthetic patient for the demo
      patient = PatientState(
        beaconId: requestedId ?? 1,
        currentZone: 'MRI Room',
        currentGateway: 'GW_002',
        currentRssi: -72,
        lastSeen: DateTime.now(),
        zoneEntryTime: DateTime.now().subtract(const Duration(minutes: 52)),
      );
    }

    // Override duration so it looks like a real threshold breach
    final fakeZone = patient!.currentZone;
    final fakeThreshold = zoneAlertThresholds[fakeZone] ?? 45;
    final fakeDuration = fakeThreshold + 7; // always 7 minutes over threshold

    print('[DEBUG]   Forcing Gemini alert for P-${patient.beaconId} '
        'in $fakeZone (${fakeDuration}min)...');

    final msg = await _callGeminiForAlert(patient, fakeDuration, fakeThreshold);

    if (msg == null) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Gemini call failed — check API key and logs'}),
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      );
    }

    // Record normally so it appears in /alerts and Firestore
    _recordAlert(patient, fakeDuration, msg.trim());

    return Response.ok(
      jsonEncode({
        'triggered': true,
        'beacon_id': patient.beaconId,
        'zone': fakeZone,
        'duration_minutes': fakeDuration,
        'used_dummy_patient': usedDummy,
        'gemini_message': msg.trim(),
      }),
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
      },
    );
  });

  // Health check — includes Firestore + Gemini status
  router.get('/status', (Request request) {
    return Response.ok(
      jsonEncode({
        'running': true,
        'patients': _patients.length,
        'events': _events.length,
        'alerts': _alerts.length,
        'firestore_connected': _firestore != null,
        'gemini_configured': geminiApiKey != 'YOUR_GEMINI_API_KEY_HERE' && geminiApiKey.isNotEmpty,
      }),
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
      },
    );
  });

  // Nurse FCM registration — gateway app calls this on startup
  router.post('/register-nurse', (Request request) async {
    try {
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final gatewayId = json['gateway_id'] as String;
      final nurseName = json['nurse_name'] as String? ?? 'Unknown Nurse';
      final fcmToken = json['fcm_token'] as String;

      _nurseRegistry[gatewayId] = NurseRegistration(
        gatewayId: gatewayId,
        nurseName: nurseName,
        fcmToken: fcmToken,
        registeredAt: DateTime.now(),
      );

      print('[FCM]     Nurse registered: $nurseName @ $gatewayId');
      return Response.ok(
        jsonEncode({'registered': true, 'gateway_id': gatewayId, 'nurse_name': nurseName}),
        headers: {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
      );
    } catch (e) {
      return Response.badRequest(body: 'Invalid payload: $e');
    }
  });

  // Gemini shift summary — dashboard calls this on demand
  router.get('/summary', (Request request) async {
    if (geminiApiKey.isEmpty) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Gemini API key not configured'}),
        headers: {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
      );
    }

    final patientSummary = _patients.values.map((p) {
      final dur = DateTime.now().difference(p.zoneEntryTime).inMinutes;
      return 'Patient P-${p.beaconId}: currently in ${p.currentZone} for ${dur}min';
    }).join('\n');

    final alertSummary = _alerts.take(10).map((a) =>
      '[${a.timestamp.toLocal().toString().substring(11, 16)}] P-${a.beaconId} in ${a.zone}: ${a.message}'
    ).join('\n');

    final prompt = '''
You are summarising a hospital shift for handover in the Proximia patient tracking system.

Current patients tracked (${_patients.length} total):
${patientSummary.isEmpty ? 'None' : patientSummary}

Total zone transitions recorded: ${_events.length}
Total AI alerts generated this session: ${_alerts.length}

Recent alerts:
${alertSummary.isEmpty ? 'None' : alertSummary}

Write a professional, concise handover summary (3-5 sentences) that a nurse leaving their shift would hand to the incoming team. Include any patients still in zones, notable alerts, and overall system status. No bullet points, just plain prose.
''';

    try {
      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$geminiModel:generateContent?key=$geminiApiKey',
      );
      final response = await http_pkg
          .post(uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'contents': [
                  {
                    'parts': [{'text': prompt}]
                  }
                ],
                'generationConfig': {'temperature': 0.3, 'maxOutputTokens': 200},
              }))
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
        return Response.ok(
          jsonEncode({'summary': text?.trim() ?? 'No summary generated'}),
          headers: {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
        );
      } else {
        return Response.internalServerError(
          body: jsonEncode({'error': 'Gemini error ${response.statusCode}'}),
          headers: {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
        );
      }
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Summary failed: $e'}),
        headers: {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
      );
    }
  });

  return router;
}

// ─────────────────────────────────────────
//  Start Server
// ─────────────────────────────────────────
Future<void> startServer() async {
  // Load environment variables from lib/.env
  final env = DotEnv(includePlatformEnvironment: true)..load(['lib/.env']);
  geminiApiKey = env['GCP_API_KEY'] ?? '';
  if (geminiApiKey.isEmpty) {
    print('[CONFIG]  ⚠ GCP_API_KEY not found in lib/.env');
  } else {
    print('[CONFIG]  ✓ GCP_API_KEY loaded from lib/.env');
  }

  if (!File('service-account.json').existsSync()) {
    print('[CONFIG]  ⚠ service-account.json missing — Push notifications disabled.');
  } else {
    print('[CONFIG]  ✓ service-account.json found (FCM HTTP v1 ready)');
  }

  await _initFirebase();

  final router = buildRouter();
  final handler = Pipeline()
      .addMiddleware(_corsMiddleware())
      .addMiddleware(logRequests())
      .addHandler(router.call);

  await shelf_io.serve(handler, InternetAddress.anyIPv4, serverPort);

  // Auto-detect local IP for display
  final interfaces = await NetworkInterface.list();
  String localIp = 'unknown';
  for (final iface in interfaces) {
    if (iface.name.toLowerCase().contains('vethernet') ||
        iface.name.toLowerCase().contains('wsl') ||
        iface.name.toLowerCase().contains('hyper-v') ||
        iface.name.toLowerCase().contains('bluetooth')) {
      continue;
    }
    for (final addr in iface.addresses) {
      if (addr.type == InternetAddressType.IPv4 &&
          !addr.address.startsWith('127')) {
        localIp = addr.address;
        break;
      }
    }
  }

  final geminiStatus = (geminiApiKey != 'YOUR_GEMINI_API_KEY_HERE' && geminiApiKey.isNotEmpty)
      ? '✓ Key set ($geminiModel)'
      : '✗ Key missing';

  final fcmStatus = File('service-account.json').existsSync() ? '✓ Ready (HTTP v1)' : '✗ Missing service-account.json';

  print('');
  print('╔══════════════════════════════════════════╗');
  print('║   Proximia BLE Tracking Server           ║');
  print('╠══════════════════════════════════════════╣');
  print('║   IP      : http://$localIp:$serverPort    ║');
  print('║   POST    : /beacon                      ║');
  print('║   POST    : /register-nurse              ║');
  print('║   GET     : /patients                    ║');
  print('║   GET     : /events                      ║');
  print('║   GET     : /alerts                      ║');
  print('║   GET     : /summary                     ║');
  print('║   GET     : /status                      ║');
  print('╠══════════════════════════════════════════╣');
  print('║   Gemini  : $geminiStatus                ║');
  print('║   FCM     : $fcmStatus                   ║');
  print('╚══════════════════════════════════════════╝');
  print('');

  // Start the Gemini anomaly detection loop
  startAnomalyChecker();
}

// ─────────────────────────────────────────
//  CORS Middleware
// ─────────────────────────────────────────
Middleware _corsMiddleware() {
  return (Handler handler) {
    return (Request request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok(
          '',
          headers: {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type',
          },
        );
      }
      final response = await handler(request);
      return response.change(headers: {'Access-Control-Allow-Origin': '*'});
    };
  };
}
