import 'dart:convert';
import 'dart:io';
import 'package:googleapis_auth/auth_io.dart';

void main() async {
  final file = File('service-account.json');
  if (!file.existsSync()) {
    print('No service-account.json');
    return;
  }
  
  final creds = ServiceAccountCredentials.fromJson(file.readAsStringSync());
  
  final client = await clientViaServiceAccount(creds, ['https://www.googleapis.com/auth/firebase.messaging']);
  final token = client.credentials.accessToken.data;
  print('Token: $token');
  client.close();
}
