import Foundation
import CryptoKit

// Verify with the public key installed users already trust, before publishing.
let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let signature = Data(base64Encoded: CommandLine.arguments[2])!
let config = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "desktop/updates.json"))) as! [String: Any]
let encodedKey = ProcessInfo.processInfo.environment["SEMANTIC_UPDATE_PUBLIC_KEY"] ?? config["publicKey"] as! String
let key = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: encodedKey)!)
guard key.isValidSignature(signature, for: archive) else {
    fputs("Update signature does not match the installed app's public key. Refusing publication.\n", stderr)
    exit(1)
}
print("Update signature verified against the configured public key.")
