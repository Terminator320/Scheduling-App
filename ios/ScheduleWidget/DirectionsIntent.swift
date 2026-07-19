// DirectionsIntent — Live Activity button App Intent that opens Apple Maps
// driving directions to the card's address. See JobLiveActivity.swift for
// where the button is placed (primary action during the travel phase,
// secondary once on-site).
//
// No auth, no network call, no Firebase — it only builds a URL and hands it
// to the system via `OpenURLIntent`. Safe to run entirely inside the widget
// extension process; it never needs to launch the Runner app.
//
// `OpenURLIntent` (AppIntents) requires a universal (https) link — custom URL
// schemes are rejected — so this always opens `https://maps.apple.com/…`.
// That is also why the "Complete" button is NOT built the same way: it deep-
// links into this app's own `esproschedule://appointment?id=…` scheme, which
// `OpenURLIntent` can't carry, so it stays a plain SwiftUI `Link` at the call
// site instead of an App Intent (see JobLiveActivity.swift). Note this is
// deliberately `daddr=`+`dirflg=d` (turn-by-turn driving directions), not the
// `q=` "show a pin" form `AddressMapLauncher` uses elsewhere in the app for
// browsing — a Live Activity button should start you moving, not open a map.

import AppIntents
import Foundation

@available(iOS 17.2, *)
struct DirectionsIntent: AppIntent {
    static var title: LocalizedStringResource = "Directions"
    static var description = IntentDescription(
        "Opens driving directions to the job address.")

    // The system opens the URL; the extension never launches the app itself.
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Address")
    var address: String

    init() {}

    init(address: String) {
        self.address = address
    }

    // The return type must name `OpensIntent`, or `.result(opensIntent:)`
    // does not typecheck.
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(Self.mapsURL(for: address)))
    }

    /// Apple Maps universal link requesting driving directions to `address`.
    /// Falls back to a bare Maps launch rather than crash if the address is
    /// ever empty or fails to encode.
    static func mapsURL(for address: String) -> URL {
        var components = URLComponents(string: "https://maps.apple.com/")!
        components.queryItems = [
            URLQueryItem(name: "daddr", value: address),
            URLQueryItem(name: "dirflg", value: "d"),
        ]
        return components.url ?? URL(string: "https://maps.apple.com/")!
    }
}
