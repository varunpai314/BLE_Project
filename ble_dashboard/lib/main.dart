import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import 'firebase_options.dart';
import 'widgets/zone_map.dart';

// ─────────────────────────────────────────
//  CONFIG — update before running
// ─────────────────────────────────────────
const String serverUrl = 'http://192.168.29.76:8080';
const int pollIntervalSeconds = 3;

// Patient name mapping: beacon_id → display name
// Update these to match your actual deployed patients
const Map<int, String> patientNames = {
  1: 'Ravi Kumar',
  2: 'Sita M. Hegde',
  3: 'Mohammed Arif',
  4: 'Priya Nair',
  5: "John D'Souza",
};

String _patientName(int beaconId) =>
    patientNames[beaconId] ?? 'Patient P-$beaconId';
// ─────────────────────────────────────────

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint("Firebase init error: $e");
  }
  runApp(const DashboardApp());
}

// ─────────────────────────────────────────
//  Models
// ─────────────────────────────────────────
class PatientState {
  final int beaconId;
  final String currentZone;
  final String gatewayId;
  final int rssi;
  final DateTime lastSeen;
  final DateTime zoneEntryTime;
  final int durationSeconds;

  PatientState({
    required this.beaconId,
    required this.currentZone,
    required this.gatewayId,
    required this.rssi,
    required this.lastSeen,
    required this.zoneEntryTime,
    required this.durationSeconds,
  });

  factory PatientState.fromJson(Map<String, dynamic> json) {
    return PatientState(
      beaconId: json['beacon_id'] as int,
      currentZone: json['current_zone'] as String,
      gatewayId: json['gateway_id'] as String,
      rssi: json['rssi'] as int,
      lastSeen: DateTime.parse(json['last_seen'] as String),
      zoneEntryTime: DateTime.parse(json['zone_entry_time'] as String),
      durationSeconds: json['duration_seconds'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'beacon_id': beaconId,
      'current_zone': currentZone,
      'gateway_id': gatewayId,
      'rssi': rssi,
      'last_seen': lastSeen.toIso8601String(),
      'zone_entry_time': zoneEntryTime.toIso8601String(),
      'duration_seconds': durationSeconds,
    };
  }
}

class ZoneEvent {
  final int beaconId;
  final String zone;
  final String gatewayId;
  final DateTime timestamp;
  final String message;

  ZoneEvent({
    required this.beaconId,
    required this.zone,
    required this.gatewayId,
    required this.timestamp,
    required this.message,
  });

  factory ZoneEvent.fromJson(Map<String, dynamic> json) {
    return ZoneEvent(
      beaconId: json['beacon_id'] as int,
      zone: json['zone'] as String,
      gatewayId: json['gateway_id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      message: json['message'] as String,
    );
  }
}

class PatientAlert {
  final int beaconId;
  final String zone;
  final int durationMinutes;
  final String message;
  final DateTime timestamp;

  PatientAlert({
    required this.beaconId,
    required this.zone,
    required this.durationMinutes,
    required this.message,
    required this.timestamp,
  });

  factory PatientAlert.fromJson(Map<String, dynamic> json) {
    return PatientAlert(
      beaconId: json['beacon_id'] as int,
      zone: json['zone'] as String,
      durationMinutes: json['duration_minutes'] as int,
      message: json['message'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}

// ─────────────────────────────────────────
//  App
// ─────────────────────────────────────────
class DashboardApp extends StatelessWidget {
  const DashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Proximia — Patient Tracking',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0D7377),
          brightness: Brightness.light,
        ),
        textTheme: GoogleFonts.interTextTheme(),
        useMaterial3: true,
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasData) {
            return const DashboardScreen();
          }
          return const SignInScreen();
        },
      ),
    );
  }
}

// ─────────────────────────────────────────
//  Sign-In Screen
// ─────────────────────────────────────────
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _signInAsGuest() async {
    setState(() { _loading = true; _error = null; });
    try {
      await FirebaseAuth.instance.signInAnonymously();
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() { _loading = true; _error = null; });
    try {
      if (kIsWeb) {
        await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
      } else {
        setState(() {
          _error = 'Google Auth popup is web-only. Please use "Demo Mode" below to view the system locally.';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D7377),
      body: Center(
        child: Container(
          width: 380,
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D7377).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.local_hospital_rounded,
                  color: Color(0xFF0D7377),
                  size: 40,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Proximia',
                style: GoogleFonts.inter(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0D7377),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Patient Tracking Dashboard',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Colors.grey.shade500,
                ),
              ),
              const SizedBox(height: 36),
              if (_error != null) ...[  
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : _signInWithGoogle,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D7377),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: _loading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.login_rounded),
                  label: Text(
                    _loading ? 'Signing in…' : 'Sign in with Google',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Demo Mode Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _signInAsGuest,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0D7377),
                    side: const BorderSide(color: Color(0xFF0D7377)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.visibility),
                  label: Text(
                    'Try Demo Mode',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Authorised hospital staff only',
                style: GoogleFonts.inter(fontSize: 11, color: Colors.grey.shade400),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
//  Dashboard Screen
// ─────────────────────────────────────────
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  // Data
  List<PatientState> _patients = [];
  List<ZoneEvent> _events = [];
  List<PatientAlert> _alerts = [];

  // Connection state
  bool _isConnected = false;
  String _lastUpdated = '--:--:--';
  Timer? _timer;
  
  // Firebase subscriptions
  StreamSubscription<QuerySnapshot>? _eventsSubscription;
  StreamSubscription<QuerySnapshot>? _alertsSubscription;

  // Animated LIVE badge
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Right-panel tab controller
  late TabController _tabController;

  @override
  void initState() {
    super.initState();

    // Pulse animation for LIVE badge
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.25, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Tab controller for right panel
    _tabController = TabController(length: 2, vsync: this);

    // Start polling/listening
    _fetchPatients();
    _listenToEvents();
    _listenToAlerts();
    _timer = Timer.periodic(
      const Duration(seconds: pollIntervalSeconds),
      (_) => _fetchPatients(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _eventsSubscription?.cancel();
    _alertsSubscription?.cancel();
    _pulseController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // ── Fetching HTTP (Patients Only) ──

  Future<void> _fetchPatients() async {
    try {
      final response = await http
          .get(Uri.parse('$serverUrl/patients'))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _patients = data.map((j) => PatientState.fromJson(j)).toList();
          _isConnected = true;
          _lastUpdated = _timeStr(DateTime.now());
        });
      }
    } catch (_) {
      setState(() => _isConnected = false);
    }
  }

  // ── Fetching Firebase Streams (Events & Alerts) ──

  void _listenToEvents() {
    try {
      _eventsSubscription = FirebaseFirestore.instance
          .collection('events')
          .orderBy('timestamp', descending: true)
          .limit(200)
          .snapshots()
          .listen((snapshot) {
        final fetched = snapshot.docs.map((doc) {
          final data = doc.data();
          return ZoneEvent.fromJson(data);
        }).toList();
        setState(() {
          _events = fetched;
        });
      }, onError: (e) {
        debugPrint("Error listening to events: $e");
      });
    } catch (e) {
      debugPrint("Firebase events listener error: $e");
    }
  }

  void _listenToAlerts() {
    try {
      _alertsSubscription = FirebaseFirestore.instance
          .collection('alerts')
          .orderBy('timestamp', descending: true)
          .limit(100)
          .snapshots()
          .listen((snapshot) {
        final fetched = snapshot.docs.map((doc) {
          final data = doc.data();
          return PatientAlert.fromJson(data);
        }).toList();

        // Switch to alerts tab automatically when a new alert appears
        if (fetched.length > _alerts.length && _tabController.index != 1) {
          _tabController.animateTo(1);
        }

        setState(() {
          _alerts = fetched;
        });
      }, onError: (e) {
        debugPrint("Error listening to alerts: $e");
      });
    } catch (e) {
      debugPrint("Firebase alerts listener error: $e");
    }
  }

  // ── Helpers ──

  String _timeStr(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}:'
      '${dt.second.toString().padLeft(2, '0')}';

  String _durationStr(int seconds) {
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) return '${seconds ~/ 60}m ${seconds % 60}s';
    return '${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}m';
  }

  int get _activeZoneCount => _patients.map((p) => p.currentZone).toSet().length;

  /// Calls GET /summary and shows Gemini shift summary in a dialog.
  Future<void> _generateShiftSummary() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Generating shift summary…'),
          ],
        ),
      ),
    );

    try {
      final response = await http
          .get(Uri.parse('$serverUrl/summary'))
          .timeout(const Duration(seconds: 25));

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // dismiss loading

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final summary = data['summary'] as String? ?? 'No summary generated.';

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.summarize_rounded, color: Color(0xFF0D7377)),
              const SizedBox(width: 8),
              Text('Shift Summary', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: Text(
              summary,
              style: GoogleFonts.inter(fontSize: 14, height: 1.6),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Summary failed: $e'), backgroundColor: Colors.red),
      );
    }
}

  Color _zoneColor(String zone) {
    switch (zone.toLowerCase()) {
      case 'mri room':           return const Color(0xFF2563EB);
      case 'operation theater':  return const Color(0xFFDC2626);
      case 'opd waiting':        return const Color(0xFF0D7377);
      case 'x-ray room':         return const Color(0xFFD97706);
      case 'general ward':       return const Color(0xFF16A34A);
      default:                   return const Color(0xFF6B7280);
    }
  }

  IconData _zoneIcon(String zone) {
    switch (zone.toLowerCase()) {
      case 'mri room':           return Icons.biotech_outlined;
      case 'operation theater':  return Icons.medical_services_outlined;
      case 'opd waiting':        return Icons.chair_outlined;
      case 'x-ray room':         return Icons.wb_sunny_outlined;
      case 'general ward':       return Icons.bed_outlined;
      default:                   return Icons.location_on_outlined;
    }
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      body: Column(
        children: [
          _buildHeader(),
          _buildStatsBar(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ZoneMap(
                      activePatients: _patients.map((p) => p.toJson()).toList(),
                      onZoneTap: _showPatientsInZone,
                    ),
                  ),
                  const SizedBox(width: 20),
                  SizedBox(
                    width: 380,
                    child: _buildRightPanel(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ──

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0D7377), Color(0xFF14919B)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x440D7377),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Logo / icon
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.local_hospital_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          // Title
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Proximia',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                'Patient Location Tracking · Wenlock District Hospital',
                style: GoogleFonts.inter(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Shift Summary button
          TextButton.icon(
            onPressed: _generateShiftSummary,
            icon: const Icon(Icons.summarize_rounded, color: Colors.white70, size: 16),
            label: Text(
              'Shift Summary',
              style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          // LIVE badge
          _buildLiveBadge(),
          const SizedBox(width: 16),
          // Last updated
          Text(
            'Updated $lastUpdated',
            style: GoogleFonts.inter(
              color: Colors.white.withOpacity(0.55),
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 12),
          // Sign out
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.white60, size: 18),
            tooltip: 'Sign out',
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
    );
  }

  String get lastUpdated => _lastUpdated;

  Widget _buildLiveBadge() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _isConnected
                ? Colors.white.withOpacity(0.15)
                : Colors.red.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _isConnected
                  ? Colors.white.withOpacity(0.4)
                  : Colors.red.shade300.withOpacity(0.6),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pulsing dot — only pulses when connected
              Opacity(
                opacity: _isConnected ? _pulseAnimation.value : 1.0,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: _isConnected
                        ? const Color(0xFF4ADE80)
                        : Colors.red.shade300,
                    shape: BoxShape.circle,
                    boxShadow: _isConnected
                        ? [
                            BoxShadow(
                              color: const Color(0xFF4ADE80)
                                  .withOpacity(_pulseAnimation.value * 0.7),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Text(
                _isConnected ? 'LIVE' : 'OFFLINE',
                style: GoogleFonts.inter(
                  color: _isConnected
                      ? const Color(0xFF4ADE80)
                      : Colors.red.shade300,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Stats Bar ──

  Widget _buildStatsBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
      child: Row(
        children: [
          _StatChip(
            icon: Icons.people_alt_rounded,
            label: 'Active Patients',
            value: '${_patients.length}',
            color: const Color(0xFF0D7377),
          ),
          const SizedBox(width: 12),
          _StatChip(
            icon: Icons.location_on_rounded,
            label: 'Zones Occupied',
            value: '$_activeZoneCount',
            color: const Color(0xFF2563EB),
          ),
          const SizedBox(width: 12),
          _StatChip(
            icon: Icons.smart_toy_rounded,
            label: 'AI Alerts',
            value: '${_alerts.length}',
            color: _alerts.isNotEmpty
                ? const Color(0xFFDC2626)
                : const Color(0xFF6B7280),
            highlight: _alerts.isNotEmpty,
          ),
          const Spacer(),
          // Powered by Gemini tag
          Row(
            children: [
              Icon(
                Icons.auto_awesome,
                size: 13,
                color: Colors.grey.shade400,
              ),
              const SizedBox(width: 4),
              Text(
                'Powered by Gemini AI',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: Colors.grey.shade400,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Patient Dialog Overlay ──

  void _showPatientsInZone(String zoneName, String? gatewayId) {
    final patientsInZone = _patients.where((p) => p.currentZone == zoneName).toList();
    
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: Text(
            '$zoneName Patients',
            style: GoogleFonts.inter(fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: 400,
            child: patientsInZone.isEmpty 
              ? const Text('No active patients in this zone.')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: patientsInZone.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (ctx, i) => _listTileForPatient(patientsInZone[i]),
              ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Close', style: TextStyle(color: Colors.teal.shade700)),
            ),
          ],
        );
      }
    );
  }

  Widget _listTileForPatient(PatientState patient) {
    final color = _zoneColor(patient.currentZone);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.1),
        child: Text(
          'P${patient.beaconId}',
          style: GoogleFonts.inter(color: color, fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ),
      title: Text(_patientName(patient.beaconId), style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('Wait time: ${_durationStr(patient.durationSeconds)}'),
      trailing: Text('${patient.rssi} dBm', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.sensors_off_rounded,
            size: 56,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 14),
          Text(
            _isConnected
                ? 'No beacons detected yet'
                : 'Cannot reach server\n$serverUrl',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: Colors.grey.shade400,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPatientCard(PatientState patient) {
    final color = _zoneColor(patient.currentZone);
    final name = _patientName(patient.beaconId);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: avatar + zone chip + active dot
          Row(
            children: [
              // Avatar
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    'P${patient.beaconId}',
                    style: GoogleFonts.inter(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                        color: const Color(0xFF1E293B),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      patient.gatewayId,
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ),
              // Active dot
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: const Color(0xFF4ADE80),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4ADE80).withOpacity(0.5),
                      blurRadius: 5,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Zone
          Row(
            children: [
              Icon(_zoneIcon(patient.currentZone), color: color, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  patient.currentZone,
                  style: GoogleFonts.inter(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Bottom row: duration + RSSI
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.timer_outlined,
                  size: 12,
                  color: Colors.grey.shade500,
                ),
                const SizedBox(width: 4),
                Text(
                  _durationStr(patient.durationSeconds),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.sensors_rounded,
                  size: 12,
                  color: Colors.grey.shade500,
                ),
                const SizedBox(width: 4),
                Text(
                  '${patient.rssi} dBm',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Right Panel (tabbed: Events | AI Alerts) ──

  Widget _buildRightPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Custom tab bar
          Container(
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFF0D7377),
              indicatorWeight: 2.5,
              labelColor: const Color(0xFF0D7377),
              unselectedLabelColor: const Color(0xFF94A3B8),
              labelStyle: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              unselectedLabelStyle: GoogleFonts.inter(
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
              tabs: [
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.history_rounded, size: 15),
                      const SizedBox(width: 6),
                      const Text('Event Log'),
                      const SizedBox(width: 6),
                      _TabBadge(
                        count: _events.length,
                        color: const Color(0xFF0D7377),
                      ),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.smart_toy_rounded, size: 15),
                      const SizedBox(width: 6),
                      const Text('AI Alerts'),
                      const SizedBox(width: 6),
                      _TabBadge(
                        count: _alerts.length,
                        color: _alerts.isNotEmpty
                            ? const Color(0xFFDC2626)
                            : const Color(0xFF94A3B8),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Tab views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildEventLogTab(),
                _buildAlertsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventLogTab() {
    if (_events.isEmpty) {
      return Center(
        child: Text(
          'No events yet',
          style: GoogleFonts.inter(color: Colors.grey.shade400, fontSize: 14),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _events.length,
      separatorBuilder: (_, __) => const Divider(
        height: 1,
        indent: 16,
        endIndent: 16,
        color: Color(0xFFF1F5F9),
      ),
      itemBuilder: (ctx, i) {
        final event = _events[i];
        final color = _zoneColor(event.zone);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 5),
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.message,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _timeStr(event.timestamp),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAlertsTab() {
    if (_alerts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              size: 48,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 12),
            Text(
              'No anomalies detected',
              style: GoogleFonts.inter(
                color: Colors.grey.shade400,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Gemini AI is monitoring all patients',
              style: GoogleFonts.inter(
                color: Colors.grey.shade300,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _alerts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) => _buildAlertCard(_alerts[i]),
    );
  }

  Widget _buildAlertCard(PatientAlert alert) {
    final name = _patientName(alert.beaconId);
    final zoneColor = _zoneColor(alert.zone);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5F5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFCA5A5), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.smart_toy_rounded,
                  size: 15,
                  color: Color(0xFFDC2626),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                  Row(
                    children: [
                      Icon(
                        _zoneIcon(alert.zone),
                        size: 11,
                        color: zoneColor,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${alert.zone} · ${alert.durationMinutes}min',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: zoneColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              Text(
                _timeStr(alert.timestamp),
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  color: Colors.grey.shade400,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Gemini message
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.format_quote_rounded,
                  size: 14,
                  color: Color(0xFFDC2626),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    alert.message,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      color: const Color(0xFF374151),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
//  Small Reusable Widgets
// ─────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool highlight;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: highlight ? color.withOpacity(0.08) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: highlight ? color.withOpacity(0.3) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 7),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 7),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              value,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabBadge extends StatelessWidget {
  final int count;
  final Color color;

  const _TabBadge({required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$count',
        style: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
