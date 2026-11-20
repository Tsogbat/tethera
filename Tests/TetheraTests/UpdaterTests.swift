import CryptoKit
import XCTest
@testable import Tethera

final class UpdaterTests: XCTestCase {
    func testVersionsCompareNumerically() {
        XCTAssertTrue(Updater.isNewer("0.6.1", than: "0.6.0"))
        XCTAssertTrue(Updater.isNewer("0.10.0", than: "0.9.3"))
        XCTAssertTrue(Updater.isNewer("1.0", than: "0.99.99"))
        XCTAssertFalse(Updater.isNewer("0.6.0", than: "0.6.0"))
        XCTAssertFalse(Updater.isNewer("0.6", than: "0.6.0"))
        XCTAssertFalse(Updater.isNewer("0.5.9", than: "0.6.0"))
        XCTAssertFalse(Updater.isNewer("0.7.0-beta", than: "0.7.0"))
    }

    func testOnlySignedReleasesAreOffered() throws {
        func release(_ assets: [String]) -> Data {
            let list = assets.map { #"{"name":"\#($0)","browser_download_url":"https://example.com/\#($0)"}"# }.joined(separator: ",")
            return Data(#"{"tag_name":"v0.7.0","html_url":"https://github.com/x","body":"Notes","assets":[\#(list)]}"#.utf8)
        }
        let signed = try XCTUnwrap(Updater.parse(release(["Tethera-macOS.dmg", "Tethera-macOS.dmg.sig"])))
        XCTAssertEqual(signed.version, "0.7.0")
        XCTAssertEqual(signed.dmg.lastPathComponent, "Tethera-macOS.dmg")
        XCTAssertEqual(signed.notes, "Notes")
        XCTAssertNil(try Updater.parse(release(["Tethera-macOS.dmg"])), "not offered until its signature is uploaded")
        XCTAssertThrowsError(try Updater.parse(Data("{}".utf8)))
    }

    func testSignaturesMustMatchTheKey() throws {
        let key = Curve25519.Signing.PrivateKey()
        let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
        let dmg = Data("pretend this is a disk image".utf8)
        let signature = try key.signature(for: dmg)
        XCTAssertTrue(Updater.verify(dmg, signature: signature, publicKey: publicKey))
        XCTAssertFalse(Updater.verify(dmg + Data([0]), signature: signature, publicKey: publicKey), "tampered download")
        XCTAssertFalse(Updater.verify(dmg, signature: signature), "signed by some other key than Tethera's")
        XCTAssertNotNil(Data(base64Encoded: Updater.publicKey).flatMap { try? Curve25519.Signing.PublicKey(rawRepresentation: $0) },
                        "the embedded public key is a valid Ed25519 key")
    }
}
