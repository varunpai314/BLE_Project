import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_admin_sdk/firebase_admin_sdk.dart';
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

// Deduplication: beaconId → last time an alert was sent for that patient
final Map<int, DateTime> _lastAlertSentAt = {};

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
Future<void> _checkAnomalies() async {
  if (_patients.isEmpty) return;
  print('[GEMINI]  Running anomaly check on ${_patients.length} patient(s)...');

  final now = DateTime.now();

  for (final patient in _patients.values) {
    final thresholdMin = zoneAlertThresholds[patient.currentZone];
    if (thresholdMin == null) continue; // zone not in threshold map

    final durationMin = now.difference(patient.zoneEntryTime).inMinutes;
    if (durationMin < thresholdMin) continue; // under threshold, all good

    // Check deduplication cooldown
    final lastAlert = _lastAlertSentAt[patient.beaconId];
    if (lastAlert != null &&
        now.difference(lastAlert).inMinutes < alertCooldownMinutes) {
      continue; // still within cooldown window
    }

    // Threshold exceeded + cooldown cleared → call Gemini
    print(
      '[GEMINI]  ⚠ P-${patient.beaconId} in ${patient.currentZone} '
      'for ${durationMin}min (threshold: ${thresholdMin}min) — calling Gemini...',
    );

    final alertMessage = await _callGeminiForAlert(patient, durationMin, thresholdMin);
    if (alertMessage != null) {
      _recordAlert(patient, durationMin, alertMessage.trim());
    }
  }
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

/// Records a confirmed Gemini alert in memory and Firestore.
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

  print('');
  print('╔══════════════════════════════════════════╗');
  print('║   Proximia BLE Tracking Server           ║');
  print('╠══════════════════════════════════════════╣');
  print('║   IP      : http://$localIp:$serverPort    ║');
  print('║   POST    : /beacon                      ║');
  print('║   GET     : /patients                    ║');
  print('║   GET     : /events                      ║');
  print('║   GET     : /alerts   ← NEW              ║');
  print('║   GET     : /status                      ║');
  print('╠══════════════════════════════════════════╣');
  print('║   Gemini  : $geminiStatus                ║');
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
