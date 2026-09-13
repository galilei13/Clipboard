import Foundation
import CryptoKit

// Verification only: no Keychain access or private signing material is needed.
guard CommandLine.arguments.count == 4,
      let publicBytes = Data(base64Encoded: CommandLine.arguments[2]),
      let signature = Data(base64Encoded: CommandLine.arguments[3]) else {
    fatalError("Usage: verify-update.swift archive public-key signature")
}
let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicBytes)
let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
guard key.isValidSignature(signature, for: archive) else {
    fputs("Invalid Ed25519 update signature\n", stderr)
    exit(1)
}
print("Verified update archive against embedded public key")
