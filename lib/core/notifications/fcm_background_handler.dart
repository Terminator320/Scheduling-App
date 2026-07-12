import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';

import 'package:scheduling/features/home_widget/application/widget_sync_service.dart';

/// Background / terminated FCM handler.
///
/// Change-driven pushes (assigned / rescheduled / cancelled / removed) carry a
/// freshly-rebuilt `widgetPayload` and `content-available`, so iOS wakes the
/// app briefly here — with the app closed or backgrounded — and we rewrite the
/// home-screen widget from that payload. Without this, the widget only updated
/// while the app was actually running (its live appointment stream), so an
/// employee assigned a job could glance at the widget and still see the stale
/// pre-assignment schedule.
///
/// Registered via `FirebaseMessaging.onBackgroundMessage` in `main()`. It MUST
/// be a top-level (or static) function annotated `@pragma('vm:entry-point')`:
/// the OS spawns a fresh isolate to run it, and the annotation keeps it from
/// being tree-shaken out of release builds. Deliberately dependency-light — it
/// touches only the `home_widget` plugin (no Firebase/Firestore/Riverpod), so
/// no `Firebase.initializeApp` is required in the isolate.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Only iOS ships the home-screen widget; Android is the dev harness.
  if (!Platform.isIOS) return;
  final payload = message.data['widgetPayload'];
  if (payload is! String || payload.isEmpty) return;
  // The OS spawns a fresh isolate for this handler with no plugins registered;
  // initialize the binding so the home_widget method channel is available.
  WidgetsFlutterBinding.ensureInitialized();
  await writeWidgetPayloadJson(payload);
}
