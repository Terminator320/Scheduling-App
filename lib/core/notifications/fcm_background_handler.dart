import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';

import 'package:scheduling/features/home_widget/application/widget_sync_service.dart';

/// Background FCM handler that rewrites the home-screen widget; must stay top-level with @pragma and dependency-light (home_widget only, no Firebase/Riverpod).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Only iOS ships the home-screen widget.
  if (!Platform.isIOS) return;
  final payload = message.data['widgetPayload'];
  if (payload is! String || payload.isEmpty) return;
  // Fresh isolate; init the binding for the method channel.
  WidgetsFlutterBinding.ensureInitialized();
  await writeWidgetPayloadJson(payload);
}
