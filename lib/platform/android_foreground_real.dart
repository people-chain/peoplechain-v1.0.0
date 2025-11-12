import 'dart:io' show Platform;
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';

Future<void> startAndroidForegroundService() async {
  if (!Platform.isAndroid) return;
  WidgetsFlutterBinding.ensureInitialized();

  // On Android 13+ the plugin can hit strict FGS timeouts on some devices.
  // Parse OS string like: "Android 14 (UP1A...)" and skip starting FGS.
  final os = Platform.operatingSystemVersion;
  final match = RegExp(r'Android\s+(\d+)').firstMatch(os);
  final major = match != null ? int.tryParse(match.group(1) ?? '') ?? 0 : 0;
  if (major >= 13) {
    return; // No-op on Android 13+
  }

  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: _onStart,
      // Avoid background auto-restarts; we'll start explicitly.
      autoStart: false,
      isForegroundMode: true,
      // Avoid background auto-restarts that are disallowed on Android 12+
      autoStartOnBoot: false,
      notificationChannelId: 'peoplechain_node',
      initialNotificationTitle: 'PeopleChain running',
      initialNotificationContent: 'Peer discovery and sync are active',
      foregroundServiceNotificationId: 101,
    ),
    iosConfiguration: IosConfiguration(autoStart: false),
  );
  try {
    await service.startService();
  } catch (_) {
    // Swallow to avoid crash loops; details available via device logs.
  }
}

@pragma('vm:entry-point')
void _onStart(ServiceInstance service) async {
  if (service is AndroidServiceInstance) {
    await service.setAsForegroundService();
  }
  // Keepalive heartbeat; actual node runs in main isolate. No-op here.
}
