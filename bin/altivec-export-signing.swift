#!/usr/bin/swift
// Run on the Mac host. Exports only the exact named Keychain identity.
import Foundation
import Security

var temporarySigningDirectory: URL?

func fail(_ message: String) -> Never {
  if let directory = temporarySigningDirectory {
    try? FileManager.default.removeItem(at: directory)
  }
  fputs(message + "\n", stderr)
  exit(1)
}
func check(_ status: OSStatus, _ action: String) {
  if status != errSecSuccess {
    let detail = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
    fail("\(action): \(detail) (\(status))")
  }
}
func run(_ tool: String, _ arguments: [String], input: URL? = nil) {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: tool)
  process.arguments = arguments
  var handle: FileHandle?
  if let input = input {
    do { handle = try FileHandle(forReadingFrom: input) }
    catch { fail("Cannot read signing PEM.") }
    process.standardInput = handle
  }
  defer { try? handle?.close() }
  do { try process.run(); process.waitUntilExit() }
  catch { fail("Cannot run \(tool): \(error.localizedDescription)") }
  if process.terminationStatus != 0 { fail("\(tool) failed; upload not confirmed.") }
}
let name = "Altivec Intelligence Local Code Signing"
let arguments = Array(CommandLine.arguments.dropFirst())
let localOnly = arguments.isEmpty || arguments == ["--local"]
if !localOnly && (arguments.count != 2 || arguments[0] != "--repo") {
  fail("Usage: swift altivec-export-signing.swift [--local | --repo OWNER/REPO]")
}
let repo = localOnly ? "" : arguments[1]
// Confirm GitHub access before requesting private-key access.
if !localOnly {
  run("/usr/bin/env", ["gh", "api", "repos/" + repo, "--silent"])
}
var result: CFTypeRef?
check(SecItemCopyMatching([
  kSecClass: kSecClassIdentity,
  kSecReturnRef: true,
  kSecMatchLimit: kSecMatchLimitAll
] as CFDictionary, &result), "Find Keychain identities")
let identities = result as! [SecIdentity]
let matches = identities.filter { identity in
  var certificate: SecCertificate?
  guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess,
        let certificate = certificate else { return false }
  var commonName: CFString?
  return SecCertificateCopyCommonName(certificate, &commonName) == errSecSuccess
    && commonName as String? == name
}
guard matches.count == 1 else {
  fail("Expected exactly one identity named '\(name)'; found \(matches.count).")
}
let directory = FileManager.default.temporaryDirectory
  .appendingPathComponent("altivec-signing-" + UUID().uuidString)
do {
  try FileManager.default.createDirectory(at: directory,
    withIntermediateDirectories: false,
    attributes: [.posixPermissions: 0o700])
} catch { fail("Cannot create private temporary directory.") }
temporarySigningDirectory = directory
defer { try? FileManager.default.removeItem(at: directory) }
var certificate: SecCertificate?
var privateKey: SecKey?
check(SecIdentityCopyCertificate(matches[0], &certificate),
      "Read signing certificate")
check(SecIdentityCopyPrivateKey(matches[0], &privateKey),
      "Read signing private key")
guard let certificate = certificate, let privateKey = privateKey else {
  fail("Keychain returned an incomplete identity.")
}
var certificateData: CFData?
var privateKeyData: CFData?
check(SecItemExport(certificate, .formatX509Cert, .pemArmour, nil,
                    &certificateData), "Export signing certificate")
var exportParameters = SecItemImportExportKeyParameters()
exportParameters.version = UInt32(SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION)
let exportPassphrase = UUID().uuidString as CFString
exportParameters.passphrase = Unmanaged.passUnretained(exportPassphrase)
check(SecItemExport(privateKey, .formatWrappedPKCS8, .pemArmour, &exportParameters,
                    &privateKeyData), "Export signing private key")
guard let certificateData = certificateData,
      let privateKeyData = privateKeyData else {
  fail("Keychain returned no identity data.")
}
let wrappedKey = directory.appendingPathComponent("wrapped-key.pem")
let passwordFile = directory.appendingPathComponent("export-password")
let plainKey = directory.appendingPathComponent("private-key.pem")
do {
  try (privateKeyData as Data).write(to: wrappedKey)
  try (exportPassphrase as String).write(to: passwordFile,
    atomically: false, encoding: .utf8)
} catch { fail("Cannot write temporary wrapped key.") }
run("/usr/bin/env", ["openssl", "pkey", "-in", wrappedKey.path,
  "-passin", "file:" + passwordFile.path, "-out", plainKey.path])
var exported = certificateData as Data
do { exported.append(try Data(contentsOf: plainKey)) }
catch { fail("Cannot read converted private key.") }
let pem = directory.appendingPathComponent("identity.pem")
do {
  try exported.write(to: pem)
  try FileManager.default.setAttributes([.posixPermissions: 0o600],
    ofItemAtPath: pem.path)
} catch { fail("Cannot write temporary signing PEM.") }
let validator = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
  .deletingLastPathComponent().appendingPathComponent("make/check-mac-signing.sh")
run("/bin/bash", [validator.path, pem.path])
if localOnly {
  let localDirectory = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".altivec/signing")
  let destination = localDirectory.appendingPathComponent("development.pem")
  do {
    try FileManager.default.createDirectory(at: localDirectory,
      withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try FileManager.default.setAttributes([.posixPermissions: 0o700],
      ofItemAtPath: localDirectory.path)
    // Copy refuses to overwrite any existing identity.
    try FileManager.default.copyItem(at: pem, to: destination)
    try FileManager.default.setAttributes([.posixPermissions: 0o600],
      ofItemAtPath: destination.path)
  } catch { fail("Cannot save local signing identity: \(error.localizedDescription)") }
  print("Saved validated identity to \(destination.path)")
} else {
  run("/usr/bin/env", ["gh", "secret", "set", "ALTIVEC_SIGNING_PEM",
    "--repo", repo], input: pem)
  run("/usr/bin/env", ["gh", "secret", "list", "--repo", repo])
  print("Uploaded ALTIVEC_SIGNING_PEM using '\(name)'.")
}
