import Foundation

public struct UpdateConfiguration: Equatable, Sendable {
    public static let placeholderPublicKey = "REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY"

    public let feedURL: String?
    public let publicKey: String?

    public init(feedURL: String?, publicKey: String?) {
        self.feedURL = feedURL
        self.publicKey = publicKey
    }

    public var isConfigured: Bool {
        guard let publicKey, !publicKey.isEmpty, publicKey != Self.placeholderPublicKey else { return false }
        guard let feedURL, let url = URL(string: feedURL), url.scheme == "https", url.host != nil else { return false }
        return true
    }
}
