import 'package:flutter/foundation.dart';

/// Global switch to enable the in-app Testing Dashboard on Web.
/// Defaults to false and must be toggled explicitly from UI.
class WebTestMode {
  static final ValueNotifier<bool> isActive = ValueNotifier<bool>(false);

  static void activate() => isActive.value = true;
  static void deactivate() => isActive.value = false;
}
