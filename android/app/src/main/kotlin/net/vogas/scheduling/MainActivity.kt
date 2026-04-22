package net.vogas.scheduling

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (not FlutterActivity) is required by local_auth,
// which presents the biometric prompt from a FragmentActivity.
class MainActivity : FlutterFragmentActivity()
