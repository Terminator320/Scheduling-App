// SiriIntentsExtension — the ExtensionKit entry point for the App Intents
// extension.
//
// An App Intents extension (`com.apple.appintents-extension`) is an ExtensionKit
// extension, which needs a `@main` type conforming to `AppIntentsExtension`.
// Without it the built `.appex` has no `__swift5_entry` section and App Store
// validation rejects it (409, "Invalid Mach-O header … __swift5_entry section
// is missing"). The old NSExtension form didn't need an explicit entry point,
// which is why this only surfaced after the ExtensionKit conversion.
//
// The intents (AppointmentCountIntent, …) and the AppShortcutsProvider
// (ESProShortcuts) are discovered through the App Intents metadata the compiler
// generates — they are NOT referenced here. This type stays empty.
//
// This file is compiled only on macOS/Xcode.

import AppIntents

@available(iOS 16.0, *)
@main
struct SiriIntentsExtension: AppIntentsExtension {}
