// Signs release DMGs so Tethera's updater can tell a real update from anything else.
// Ed25519 via CryptoKit; the app embeds the public key (Tethera/App/Updater.swift).
//
//   swift scripts/sign_update.swift keygen <private-key-file>   new key pair; prints the public key
//   swift scripts/sign_update.swift sign <file> [key-file]      prints the base64 signature
//                                                              (key from the file, or $TETHERA_UPDATE_KEY)
//   swift scripts/sign_update.swift verify <file> <signature> <public-key>

import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("sign_update: \(message)\n".utf8))
    exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "keygen":
    guard arguments.count == 2 else { fail("usage: keygen <private-key-file>") }
    let path = arguments[1]
    guard !FileManager.default.fileExists(atPath: path) else { fail("\(path) exists; refusing to overwrite a signing key") }
    let key = Curve25519.Signing.PrivateKey()
    let created = FileManager.default.createFile(atPath: path, contents: Data(key.rawRepresentation.base64EncodedString().utf8),
                                                 attributes: [.posixPermissions: 0o600])
    guard created else { fail("couldn't write \(path)") }
    print(key.publicKey.rawRepresentation.base64EncodedString())

case "sign":
    guard arguments.count >= 2, let data = FileManager.default.contents(atPath: arguments[1]) else { fail("usage: sign <file> [key-file]") }
    let encoded: String
    if arguments.count > 2 {
        guard let text = try? String(contentsOfFile: arguments[2], encoding: .utf8) else { fail("can't read \(arguments[2])") }
        encoded = text
    } else if let fromEnvironment = ProcessInfo.processInfo.environment["TETHERA_UPDATE_KEY"], !fromEnvironment.isEmpty {
        encoded = fromEnvironment
    } else {
        fail("no key: pass a key file or set TETHERA_UPDATE_KEY")
    }
    guard let raw = Data(base64Encoded: encoded.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else { fail("not an Ed25519 private key") }
    guard let signature = try? key.signature(for: data) else { fail("signing failed") }
    print(signature.base64EncodedString())

case "verify":
    guard arguments.count == 4, let data = FileManager.default.contents(atPath: arguments[1]),
          let signature = Data(base64Encoded: arguments[2]), let raw = Data(base64Encoded: arguments[3]),
          let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw) else { fail("usage: verify <file> <signature> <public-key>") }
    if key.isValidSignature(signature, for: data) { print("valid") } else { fail("INVALID signature") }

default:
    fail("usage: keygen <key-file> | sign <file> [key-file] | verify <file> <signature> <public-key>")
}
