import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';

import 'package:scheduling/features/home_widget/application/widget_sync_service.dart';

/// Background FCM handler that rewrites the home-screen widget. Needs to
/// stay a top-level function with @pragma, and dependency-light — home_widget
/// only, no Firebase or Riverpod.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!Platform.isIOS) return;
  final payload = message.data['widgetPayload'];
  if (payload is! String || payload.isEmpty) return;
  // Background isolates need a binding before method-channel calls.
  WidgetsFlutterBinding.ensureInitialized();
  await writeWidgetPayloadJson(payload);
}
