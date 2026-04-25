import 'package:ble_server/ble_server.dart' as ble_server;

void main() async {
  await ble_server.startServer();

  // Keep server alive
  await Future.delayed(Duration(days: 365));
}
