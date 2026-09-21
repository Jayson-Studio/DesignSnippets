import Foundation
import Sparkle

@main struct UpdateTests {
    static func main() {
        let key = Data(repeating: 42, count: 32).base64EncodedString()
        precondition(UpdateConfiguration.isValid(feed: "https://updates.example.com/appcast.xml", publicKey: key))
        for feed in [nil, "", "http://updates.example.com/appcast.xml", "file:///tmp/appcast.xml", "https://user:password@example.com/feed", "https://example.com/feed#fragment"] {
            precondition(!UpdateConfiguration.isValid(feed: feed, publicKey: key))
        }
        for invalidKey in [nil, "", "bad-key", Data(repeating: 0, count: 31).base64EncodedString()] {
            precondition(!UpdateConfiguration.isValid(feed: "https://example.com/feed", publicKey: invalidKey))
        }
        precondition(SUStandardVersionComparator.default.compareVersion("7", toVersion: "8") == .orderedAscending)
        precondition(SUStandardVersionComparator.default.compareVersion("8", toVersion: "8") == .orderedSame)
        precondition(SUStandardVersionComparator.default.compareVersion("9", toVersion: "8") == .orderedDescending)
        print("Update configuration and Sparkle runtime/version tests passed")
    }
}
