// Signs the Bible catalog for OpenBibleAI (Ed25519, CryptoKit — the same
// code the app verifies with). Run through catalog_key.sh, which compiles it.
//
//     Tools/BibleImport/catalog_key.sh generate
//         Creates the signing key, stores the private key in the login Keychain
//         ("OpenBibleAI catalog signing") and prints the public key for
//         BIBLE_CATALOG_PUBLIC_KEY in Config/Local.xcconfig. Refuses to replace
//         an existing key.
//     Tools/BibleImport/catalog_key.sh public-key
//     Tools/BibleImport/catalog_key.sh export-private | gh secret set CATALOG_SIGNING_KEY --env release
//         Prints the private key (base64) for the GitHub Actions secret and a
//         password-manager backup. Never paste it anywhere else.
//     Tools/BibleImport/catalog_key.sh sign <catalog.json>
//         Writes <catalog.json>.sig. Uses $CATALOG_SIGNING_KEY when set (CI),
//         otherwise the Keychain.
//     Tools/BibleImport/catalog_key.sh verify-assets <catalog.json>
//         Downloads every pinned asset from the release and checks its size and
//         SHA-256, and that the catalog's sequence is newer than the published one.

import CryptoKit
import Foundation

let service = "OpenBibleAI catalog signing"
let account = "catalog"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

@discardableResult
func security(_ arguments: [String]) -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    do { try process.run() } catch { fail("can't run security: \(error)") }
    process.waitUntilExit()
    let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    return (process.terminationStatus, output.trimmingCharacters(in: .whitespacesAndNewlines))
}

func keychainKey() -> String? {
    let result = security(["find-generic-password", "-s", service, "-a", account, "-w"])
    return result.status == 0 && !result.output.isEmpty ? result.output : nil
}

func privateKey() -> Curve25519.Signing.PrivateKey {
    let encoded = ProcessInfo.processInfo.environment["CATALOG_SIGNING_KEY"].flatMap { $0.isEmpty ? nil : $0 } ?? keychainKey()
    guard let encoded else { fail("no signing key: set CATALOG_SIGNING_KEY or run `generate`") }
    guard let data = Data(base64Encoded: encoded.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: data)
    else { fail("the signing key is not a base64 Ed25519 private key") }
    return key
}

/// The public key as BIBLE_CATALOG_PUBLIC_KEY expects it: hex (base64 can
/// contain "//", which starts a comment in an xcconfig file).
func hex(_ key: Curve25519.Signing.PublicKey) -> String {
    key.rawRepresentation.map { String(format: "%02x", $0) }.joined()
}

func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func verifyAssets(_ catalogURL: URL) async {
    guard let data = try? Data(contentsOf: catalogURL),
          let catalog = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let sequence = catalog["sequence"] as? Int,
          let entries = catalog["entries"] as? [[String: Any]]
    else { fail("\(catalogURL.path) is not a catalog") }

    var problems: [String] = []
    var publishedSequence: Int?
    for entry in entries {
        guard let manifest = entry["manifest"] as? [String: Any],
              let repository = manifest["repository"] as? String,
              let revision = manifest["revision"] as? String,
              let host = (manifest["host"] as? [String: Any])?["gitHubRelease"] as? [String: Any],
              let tag = host["tag"] as? String,
              let files = manifest["files"] as? [[String: Any]]
        else { fail("malformed entry \(entry)") }

        if publishedSequence == nil {
            let url = URL(string: "https://github.com/\(repository)/releases/download/\(tag)/catalog.json")!
            if let (published, response) = try? await URLSession.shared.data(from: url),
               (response as? HTTPURLResponse)?.statusCode == 200,
               let object = try? JSONSerialization.jsonObject(with: published) as? [String: Any] {
                publishedSequence = object["sequence"] as? Int ?? 0
            } else {
                publishedSequence = 0
            }
        }

        for file in files {
            guard let name = file["name"] as? String else { continue }
            let pinned = (file["archive"] as? [String: Any]) ?? file
            let asset = "\(revision)-\(name)\(file["archive"] == nil ? "" : ".zlib")"
            let url = URL(string: "https://github.com/\(repository)/releases/download/\(tag)/\(asset)")!
            guard let (bytes, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200
            else { problems.append("\(asset): not downloadable"); continue }
            if bytes.count != pinned["size"] as? Int || sha256(bytes) != pinned["sha256"] as? String {
                problems.append("\(asset): size or SHA-256 differs from the catalog")
            } else {
                print("ok \(asset)")
            }
        }
    }
    if let publishedSequence, sequence <= publishedSequence {
        problems.append("sequence \(sequence) is not newer than the published \(publishedSequence)")
    }
    if !problems.isEmpty { fail(problems.joined(separator: "\n")) }
    print("All assets match; sequence \(sequence) (published: \(publishedSequence ?? 0)).")
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "generate":
    guard keychainKey() == nil else { fail("a key already exists in the Keychain; replacing it would orphan every published catalog") }
    let key = Curve25519.Signing.PrivateKey()
    let stored = security(["add-generic-password", "-s", service, "-a", account, "-w", key.rawRepresentation.base64EncodedString()])
    guard stored.status == 0 else { fail("couldn't store the key in the Keychain") }
    print("Private key stored in the login Keychain (\(service)). Back it up with `export-private`.")
    print("BIBLE_CATALOG_PUBLIC_KEY = \(hex(key.publicKey))")
case "public-key":
    print(hex(privateKey().publicKey))
case "export-private":
    print(privateKey().rawRepresentation.base64EncodedString())
case "sign":
    guard arguments.count == 2 else { fail("usage: sign <catalog.json>") }
    let url = URL(fileURLWithPath: arguments[1])
    guard let data = try? Data(contentsOf: url) else { fail("can't read \(url.path)") }
    let key = privateKey()
    let signature = try key.signature(for: data)
    precondition(key.publicKey.isValidSignature(signature, for: data))
    try Data((signature.base64EncodedString() + "\n").utf8).write(to: url.appendingPathExtension("sig"))
    print("Signed \(url.lastPathComponent) with public key \(hex(key.publicKey))")
case "verify-assets":
    guard arguments.count == 2 else { fail("usage: verify-assets <catalog.json>") }
    await verifyAssets(URL(fileURLWithPath: arguments[1]))
default:
    fail("usage: catalog_key.swift generate | public-key | export-private | sign <catalog.json> | verify-assets <catalog.json>")
}
