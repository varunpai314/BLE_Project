import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'beacon_parser.dart';

// ─────────────────────────────────────────
//  CONFIG
// ─────────────────────────────────────────
const int serverPort = 8080;
const int rssiThreshold = -85; // Ignore beacons weaker than this
// ─────────────────────────────────────────

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final savedGatewayId = prefs.getString('gatewayId');
  final savedServerIp = prefs.getString('serverIp');

  runApp(GatewayApp(
    initialGatewayId: savedGatewayId,
    initialServerIp: savedServerIp,
  ));
}

class GatewayApp extends StatelessWidget {
  final String? initialGatewayId;
  final String? initialServerIp;

  const GatewayApp({super.key, this.initialGatewayId, this.initialServerIp});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Gateway',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: (initialGatewayId != null && initialServerIp != null)
          ? GatewayScreen(gatewayId: initialGatewayId!, serverIp: initialServerIp!)
          : SetupScreen(initialServerIp: initialServerIp ?? '192.168.29.76'),
    );
  }
}

// ─────────────────────────────────────────
//  Setup Screen
// ─────────────────────────────────────────
class SetupScreen extends StatefulWidget {
  final String initialServerIp;
  const SetupScreen({super.key, required this.initialServerIp});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late TextEditingController _ipController;
  List<Map<String, dynamic>> _zones = [];
  String? _selectedGatewayId;
  bool _isLoading = false;
  String _errorMsg = '';

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController(text: widget.initialServerIp);
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _fetchZones() async {
    setState(() {
      _isLoading = true;
      _errorMsg = '';
      _zones = [];
      _selectedGatewayId = null;
    });

    final ip = _ipController.text.trim();
    if (ip.isEmpty) {
      setState(() {
        _errorMsg = 'Please enter Server IP';
        _isLoading = false;
      });
      return;
    }

    try {
      final response = await http
          .get(Uri.parse('http://$ip:$serverPort/zones'))
          .timeout(const Duration(seconds: 4));
          
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> zonesData = data['zones'] ?? [];
        if (zonesData.isEmpty) {
          _errorMsg = 'No zones returned by server.';
        } else {
          _zones = List<Map<String, dynamic>>.from(zonesData);
          _selectedGatewayId = _zones.first['gatewayId'];
        }
      } else {
        _errorMsg = 'Server error: ${response.statusCode}';
      }
    } catch (e) {
      _errorMsg = 'Failed to fetch zones. Is server running?';
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveAndContinue() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty || _selectedGatewayId == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('serverIp', ip);
    await prefs.setString('gatewayId', _selectedGatewayId!);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => GatewayScreen(gatewayId: _selectedGatewayId!, serverIp: ip),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gateway Setup', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.teal,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Configure Gateway', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            TextField(
              controller: _ipController,
              decoration: const InputDecoration(
                labelText: 'Server IP Address',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.wifi),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _fetchZones,
              icon: _isLoading 
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) 
                : const Icon(Icons.cloud_download),
              label: Text(_isLoading ? 'Fetching...' : 'Fetch Zones from Server'),
            ),
            if (_errorMsg.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(_errorMsg, style: const TextStyle(color: Colors.red)),
            ],
            if (_zones.isNotEmpty) ...[
              const SizedBox(height: 32),
              const Text('Select Zone', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _selectedGatewayId,
                    items: _zones.map((z) {
                      return DropdownMenuItem<String>(
                        value: z['gatewayId'],
                        child: Text('${z['zoneName']} (${z['gatewayId']})'),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedGatewayId = val);
                    },
                  ),
                ),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: _saveAndContinue,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Start Scanning', style: TextStyle(color: Colors.white, fontSize: 18)),
              ),
            ] else const Spacer(),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────
//  Gateway Scanner Screen
// ─────────────────────────────────────────
class GatewayScreen extends StatefulWidget {
  final String gatewayId;
  final String serverIp;

  const GatewayScreen({super.key, required this.gatewayId, required this.serverIp});

  @override
  State<GatewayScreen> createState() => _GatewayScreenState();
}

class _GatewayScreenState extends State<GatewayScreen> {
  // ── State ──
  bool _isScanning = false;
  bool _permissionsOk = false;
  String _statusMessage = 'Initialising...';
  final List<String> _log = [];

  // Detected beacons: deviceId → latest BeaconData
  final Map<int, BeaconData> _detectedBeacons = {};
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> _init() async {
    await _requestPermissions();
    if (_permissionsOk) {
      _addLog('Permissions granted. Ready to scan.');
      await _startScan();
    }
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      if (await Permission.bluetoothScan.isGranted == false) {
        final status = await Permission.bluetoothScan.request();
        if (!status.isGranted) {
          setState(() => _statusMessage = 'Bluetooth scan permission denied.');
          return;
        }
      }
      if (await Permission.bluetoothConnect.isGranted == false) {
        await Permission.bluetoothConnect.request();
      }
    } else {
      final status = await Permission.location.request();
      if (!status.isGranted) {
        setState(() => _statusMessage = 'Location permission denied.');
        return;
      }
    }
    setState(() => _permissionsOk = true);
    _addLog('Permissions granted.');
  }

  Future<void> _startScan() async {
    if (_isScanning) return;

    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      setState(() => _statusMessage = 'Bluetooth is OFF. Please turn it on.');
      return;
    }

    setState(() {
      _isScanning = true;
      _statusMessage = 'Scanning for beacons...';
    });

    _addLog('Scan started — Gateway: ${widget.gatewayId}');

    _scanSubscription = FlutterBluePlus.onScanResults.listen((results) {
      for (final result in results) {
        final mfgData = result.advertisementData.manufacturerData;
        if (mfgData.isEmpty) continue;

        for (final entry in mfgData.entries) {
          final companyIdLsb = entry.key & 0xFF;
          final companyIdMsb = (entry.key >> 8) & 0xFF;
          final rest = entry.value;

          final fullPayload = [companyIdLsb, companyIdMsb, ...rest];
          final beacon = BeaconData.parse(fullPayload, result.rssi);
          if (beacon == null) continue;
          if (beacon.rssi < rssiThreshold) continue;

          setState(() => _detectedBeacons[beacon.deviceId] = beacon);
          _sendToServer(beacon);
        }
      }
    });

    await FlutterBluePlus.startScan(
      continuousUpdates: true,
      removeIfGone: const Duration(seconds: 5),
    );
  }

  Future<void> _stopScan() async {
    await _scanSubscription?.cancel();
    await FlutterBluePlus.stopScan();
    setState(() {
      _isScanning = false;
      _statusMessage = 'Scan stopped.';
    });
    _addLog('Scan stopped.');
  }

  Future<void> _sendToServer(BeaconData beacon) async {
    final url = Uri.parse('http://${widget.serverIp}:$serverPort/beacon');
    final payload = {
      'gateway_id': widget.gatewayId,
      'beacon_id': beacon.deviceId,
      'rssi': beacon.rssi,
      'battery': beacon.battery,
      'timestamp': DateTime.now().toIso8601String(),
    };

    try {
      final response = await http
          .post(url, headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        _addLog('✓ Beacon ${beacon.deviceId} → ${widget.gatewayId} (RSSI: ${beacon.rssi})');
      } else {
        _addLog('✗ Server error ${response.statusCode} for beacon ${beacon.deviceId}');
      }
    } on SocketException {
      _addLog('✗ Cannot reach server at ${widget.serverIp}:$serverPort');
    } on TimeoutException {
      _addLog('✗ Server timeout for beacon ${beacon.deviceId}');
    } catch (e) {
      _addLog('✗ Error: $e');
    }
  }

  void _addLog(String message) {
    if (!mounted) return;
    final time = TimeOfDay.now().format(context);
    setState(() {
      _log.insert(0, '[$time] $message');
      if (_log.length > 100) _log.removeLast();
    });
  }

  void _openSetup() async {
    await _stopScan();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => SetupScreen(initialServerIp: widget.serverIp)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.teal,
        title: const Text('BLE Gateway', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: _openSetup,
            tooltip: 'Settings',
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Icon(
              _isScanning ? Icons.bluetooth_searching : Icons.bluetooth_disabled,
              color: Colors.white,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner
          Container(
            width: double.infinity,
            color: _isScanning ? Colors.teal.shade50 : Colors.grey.shade200,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(
                  _isScanning ? Icons.sensors : Icons.sensors_off,
                  color: _isScanning ? Colors.teal : Colors.grey,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _statusMessage,
                    style: TextStyle(
                      color: _isScanning ? Colors.teal.shade800 : Colors.grey.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Info
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _infoChip(Icons.router, 'Gateway: ${widget.gatewayId}'),
                const SizedBox(width: 8),
                _infoChip(Icons.wifi, '${widget.serverIp}:$serverPort'),
              ],
            ),
          ),

          // Beacons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Text('Detected Beacons', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: Colors.teal, borderRadius: BorderRadius.circular(12)),
                  child: Text('${_detectedBeacons.length}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 120,
            child: _detectedBeacons.isEmpty
                ? Center(child: Text('No beacons detected yet', style: TextStyle(color: Colors.grey.shade500)))
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    scrollDirection: Axis.horizontal,
                    children: _detectedBeacons.values.map((b) => _beaconCard(b)).toList(),
                  ),
          ),

          const Divider(height: 20),

          // Log
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Text('Event Log', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _log.clear()),
                  child: const Text('Clear', style: TextStyle(color: Colors.teal)),
                ),
              ],
            ),
          ),

          Expanded(
            child: _log.isEmpty
                ? Center(child: Text('Log is empty', style: TextStyle(color: Colors.grey.shade400)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _log.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        _log[index],
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: _log[index].contains('✗') ? Colors.red.shade700 : Colors.grey.shade800,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),

      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _isScanning ? Colors.red : Colors.teal,
        onPressed: _isScanning ? _stopScan : _startScan,
        icon: Icon(_isScanning ? Icons.stop : Icons.play_arrow, color: Colors.white),
        label: Text(_isScanning ? 'Stop' : 'Start', style: const TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _beaconCard(BeaconData beacon) {
    return Container(
      width: 110,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.teal.shade100),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.person_pin, color: Colors.teal, size: 28),
          const SizedBox(height: 4),
          Text('P-${beacon.deviceId}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          Text('${beacon.rssi} dBm', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          Text('Bat: ${beacon.battery == 0xFF ? "?" : "${beacon.battery}%"}', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.teal.shade100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.teal),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.teal)),
        ],
      ),
    );
  }
}
