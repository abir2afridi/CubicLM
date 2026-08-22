/// Web device info — no RAM detection, use generous defaults.
Future<Map<String, dynamic>> getDeviceInfo() async {
  return {
    'totalRamGB': 8.0,
    'availableRamGB': 4.0,
    'isTensorSoC': 0.0,
    'socFamily': 8, // unknown
    'socHardware': '',
  };
}
