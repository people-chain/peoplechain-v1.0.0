import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';

/// Requests runtime permissions needed for Bluetooth and Wi‑Fi Direct discovery on Android 12+.
Future<void> requestDiscoveryPermissionsIfNeeded() async {
  if (kIsWeb || !Platform.isAndroid) return;
  // Notification permission for foreground service on Android 13+
  if (await Permission.notification.isDenied) {
    await Permission.notification.request();
  }

  // Android 12+ Bluetooth permissions
  if (await Permission.bluetoothScan.isDenied) {
    await Permission.bluetoothScan.request();
  }
  if (await Permission.bluetoothConnect.isDenied) {
    await Permission.bluetoothConnect.request();
  }
  if (await Permission.bluetoothAdvertise.isDenied) {
    await Permission.bluetoothAdvertise.request();
  }

  // Location permission for pre-Android 13 Wi‑Fi discovery
  if (await Permission.locationWhenInUse.isDenied) {
    await Permission.locationWhenInUse.request();
  }

  // Android 13+: NEARBY_WIFI_DEVICES
  final nearbyWifi = Permission.nearbyWifiDevices; // available via permission_handler 12+
  if (await nearbyWifi.status.isDenied) {
    await nearbyWifi.request();
  }
}
