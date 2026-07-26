// DirectionsIntent — Live Activity button App Intent that opens Apple Maps
// driving directions to the card's address (primary action during the travel
// phase, secondary once on-site; see JobLiveActivity.swift).
//
// No auth, no network, no Firebase — just builds a URL and hands it to the
// system via `OpenURLIntent`, safe entirely inside the widget extension.
//
// `OpenURLIntent` requires a universal (https) link, so custom schemes are
// rejected — that's why "Complete" stays a plain SwiftUI `Link` at its call
// site instead of an App Intent (see JobLiveActivity.swift).
//
// Deliberately `daddr=`+`dirflg=d` (turn-by-turn driving directions), not the
// `q=` "show a pin" form `AddressMapLauncher` uses elsewhere for browsing.

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

    /// Apple Maps universal link requesting driving directions to `address`;
    /// falls back to a bare Maps launch rather than crash on an
    /// empty/unencodable address.
    static func mapsURL(for address: String) -> URL {
        var components = URLComponents(string: "https://maps.apple.com/")!
        components.queryItems = [
            URLQueryItem(name: "daddr", value: address),
            URLQueryItem(name: "dirflg", value: "d"),
        ]
        return components.url ?? URL(string: "https://maps.apple.com/")!
    }
}
