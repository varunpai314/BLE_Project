class BeaconData {
  final int companyIdLsb; // Byte 0
  final int companyIdMsb; // Byte 1
  final int version; // Byte 2
  final int deviceType; // Byte 3
  final int deviceId; // Bytes 4-5 combined
  final int flags; // Byte 6
  final int battery; // Byte 7
  final int rssi;

  BeaconData({
    required this.companyIdLsb,
    required this.companyIdMsb,
    required this.version,
    required this.deviceType,
    required this.deviceId,
    required this.flags,
    required this.battery,
    required this.rssi,
  });

  // Returns null if this is not our beacon
  static BeaconData? parse(List<int> mfgData, int rssi) {
    if (mfgData.length < 8) return null;
    if (mfgData[0] != 0xFF || mfgData[1] != 0xFF) return null;
    if (mfgData[2] != 0x01) return null; // Version check
    if (mfgData[3] != 0x01) return null; // Device type check

    final deviceId = (mfgData[4] << 8) | mfgData[5];

    return BeaconData(
      companyIdLsb: mfgData[0],
      companyIdMsb: mfgData[1],
      version: mfgData[2],
      deviceType: mfgData[3],
      deviceId: deviceId,
      flags: mfgData[6],
      battery: mfgData[7],
      rssi: rssi,
    );
  }

  @override
  String toString() =>
      'BeaconData(id: $deviceId, rssi: $rssi, battery: $battery)';
}
