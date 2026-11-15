import Darwin
import Foundation
import Security

@main
@available(macOS, deprecated: 10.10)
struct InstallerImport {
  private struct Identity: Encodable {
    let der: [UInt8]
    let subject: String
    let privateKey: Bool
  }

  private struct Report: Encodable {
    let status: OSStatus
    let identities: [Identity?]?
  }

  private struct SecurityFailure: Error {
    let status: OSStatus
  }

  static func main() {
    let report: Report
    do {
      report = Report(status: errSecSuccess, identities: try run())
    } catch {
      let status = (error as? SecurityFailure)?.status ?? errSecInternalComponent
      report = Report(status: status, identities: nil)
    }
    let output = (try? JSONEncoder().encode(report)) ?? Data("{\"status\":-2070}".utf8)
    FileHandle.standardOutput.write(output)
    exit(report.status == errSecSuccess ? EXIT_SUCCESS : EXIT_FAILURE)
  }

  private static func check(_ status: OSStatus) throws {
    guard status == errSecSuccess else { throw SecurityFailure(status: status) }
  }

  private static func run() throws -> [Identity?] {
    let arguments = CommandLine.arguments
    let environment = ProcessInfo.processInfo.environment
    guard arguments.count == 3,
      let encoded = environment["GYMEMO_PKCS12_BASE64"],
      let data = Data(base64Encoded: encoded),
      let password = environment["GYMEMO_PKCS12_PASSWORD"]
    else { throw SecurityFailure(status: errSecParam) }
    var previous = DarwinBoolean(true)
    try check(SecKeychainGetUserInteractionAllowed(&previous))
    try check(SecKeychainSetUserInteractionAllowed(false))
    do {
      let identities = try importIdentity(
        data: data, password: password, keychainPath: arguments[1], toolPath: arguments[2])
      try check(SecKeychainSetUserInteractionAllowed(previous.boolValue))
      return identities
    } catch {
      try check(SecKeychainSetUserInteractionAllowed(previous.boolValue))
      throw error
    }
  }

  private static func importIdentity(
    data: Data, password: String, keychainPath: String, toolPath: String
  ) throws -> [Identity?] {
    var opened: SecKeychain?
    try check(SecKeychainOpen(keychainPath, &opened))
    guard let keychain = opened else { throw SecurityFailure(status: errSecInvalidKeychain) }
    var trusted: SecTrustedApplication?
    try check(SecTrustedApplicationCreateFromPath(toolPath, &trusted))
    guard let trusted else { throw SecurityFailure(status: errSecParam) }
    var created: SecAccess?
    try check(
      SecAccessCreate("Gymemo installer identity" as CFString, [trusted] as CFArray, &created))
    guard let access = created else { throw SecurityFailure(status: errSecParam) }
    let options: [String: Any] = [
      kSecImportExportPassphrase as String: password,
      kSecImportExportKeychain as String: keychain,
      kSecImportExportAccess as String: access,
    ]
    var imported: CFArray?
    try check(SecPKCS12Import(data as CFData, options as CFDictionary, &imported))
    guard let items = imported as? [[String: Any]] else {
      throw SecurityFailure(status: errSecDecode)
    }
    return try items.map { item -> Identity? in
      if item[kSecImportItemIdentity as String] == nil { return nil }
      guard let chain = item[kSecImportItemCertChain as String] as? [SecCertificate],
        let certificate = chain.first
      else { throw SecurityFailure(status: errSecDecode) }
      var matched: SecIdentity?
      try check(SecIdentityCreateWithCertificate(keychain, certificate, &matched))
      guard let identity = matched else { throw SecurityFailure(status: errSecDecode) }
      var privateKey: SecKey?
      let privateKeyStatus = SecIdentityCopyPrivateKey(identity, &privateKey)
      return Identity(
        der: [UInt8](SecCertificateCopyData(certificate) as Data),
        subject: SecCertificateCopySubjectSummary(certificate) as String? ?? "",
        privateKey: privateKeyStatus == errSecSuccess && privateKey != nil)
    }
  }
}
