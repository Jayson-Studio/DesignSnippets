import Foundation

struct UpdateConfiguration {
    static func isValid(feed: String?, publicKey: String?) -> Bool {
        guard let feed, let url = URLComponents(string: feed), url.scheme == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.fragment == nil, let publicKey, Data(base64Encoded: publicKey)?.count == 32 else { return false }
        return true
    }
}
