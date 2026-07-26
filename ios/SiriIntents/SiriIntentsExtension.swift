// SiriIntentsExtension — the ExtensionKit entry point for the App Intents
// extension.
//
// An App Intents extension (`com.apple.appintents-extension`) is an
// ExtensionKit extension needing a `@main` type conforming to
// `AppIntentsExtension`, or the built `.appex` has no `__swift5_entry`
// section and App Store validation rejects it (409, "Invalid Mach-O header
// … __swift5_entry section is missing").
//
// The intents and AppShortcutsProvider are discovered through
// compiler-generated App Intents metadata, not referenced here — this type
// stays empty.
//
// This file is compiled only on macOS/Xcode.

import AppIntents

@available(iOS 16.0, *)
@main
struct SiriIntentsExtension: AppIntentsExtension {}
