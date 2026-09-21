import Foundation
import CryptoKit

// Only the public key is printed. Never put a private seed in arguments, logs, or git.
let directory = URL(fileURLWithPath: "desktop/.secrets", isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
let file = directory.appendingPathComponent("sparkle-private-key")
let key: Curve25519.Signing.PrivateKey
if FileManager.default.fileExists(atPath: file.path) {
    guard let seed = Data(base64Encoded: try String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)) else { fatalError("Invalid saved signing key") }
    key = try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
} else {
    key = Curve25519.Signing.PrivateKey()
    try Data(key.rawRepresentation.base64EncodedString().utf8).write(to: file, options: .atomic)
}
try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
let configURL = URL(fileURLWithPath: "desktop/updates.json")
var config = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as! [String: String]
let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
if let existing = config["publicKey"], !existing.isEmpty, existing != publicKey {
    fatalError("Configured public key differs from saved signing key. Restore the original key; do not rotate it silently.")
}
config["publicKey"] = publicKey
try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: configURL, options: .atomic)
print("Update public key configured. Back up desktop/.secrets/sparkle-private-key securely; it is required for future releases.")
