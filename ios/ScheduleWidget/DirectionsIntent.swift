// DirectionsIntent is the Live Activity button that opens Apple Maps driving
// directions to the card's address. It's the primary action during travel,
// and the secondary one once on-site (see JobLiveActivity.swift).
//
// No auth, no network, no Firebase — it just builds a URL and hands it off
// to the system via `OpenURLIntent`, so it's safe to run entirely inside the
// widget extension.
//
// `OpenURLIntent` requires a universal (https) link, so custom schemes are
// rejected — that's why "Complete" stays a plain SwiftUI `Link` at its call
// site instead of an App Intent (see JobLiveActivity.swift).
//
// This deliberately uses `daddr=` plus `dirflg=d` for turn-by-turn driving
// directions, not the `q=` "show a pin" form that `AddressMapLauncher` uses
// elsewhere for browsing.

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

    /// Builds an Apple Maps universal link with driving directions to
    /// `address`. Falls back to a bare Maps launch rather than crash on an
    /// empty or unencodable address.
    static func mapsURL(for address: String) -> URL {
        var components = URLComponents(string: "https://maps.apple.com/")!
        components.queryItems = [
            URLQueryItem(name: "daddr", value: address),
            URLQueryItem(name: "dirflg", value: "d"),
        ]
        return components.url ?? URL(string: "https://maps.apple.com/")!
    }
}
