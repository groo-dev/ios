//
//  AutoFillCapabilitiesTests.swift
//  GrooTests
//
//  Pins the GrooAutoFill extension's declared credential capabilities.
//
//  iOS only reads ASCredentialProviderExtensionCapabilities from
//  NSExtension > NSExtensionAttributes. Declaring it one level up — directly
//  under NSExtension — is silently ignored: password AutoFill keeps working
//  (that is a credential provider's default), but the extension is never
//  offered for passkeys, so "Save in Groo" is missing from the registration
//  sheet and stored passkeys can't be used for assertions.
//

import Foundation
import Testing

struct AutoFillCapabilitiesTests {

    /// The built GrooAutoFill.appex embedded in the test host app.
    private func autoFillInfoPlist() throws -> [String: Any] {
        let plugIns = try #require(
            Bundle.main.builtInPlugInsURL,
            "test host has no PlugIns directory"
        )
        let infoURL = plugIns
            .appendingPathComponent("GrooAutoFill.appex")
            .appendingPathComponent("Info.plist")

        let data = try Data(contentsOf: infoURL)
        let plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        return try #require(plist as? [String: Any], "Info.plist is not a dictionary")
    }

    private func nsExtension() throws -> [String: Any] {
        let info = try autoFillInfoPlist()
        return try #require(info["NSExtension"] as? [String: Any], "missing NSExtension")
    }

    @Test func declaresPasskeyAndPasswordCapabilities() throws {
        let nsExtension = try nsExtension()

        let attributes = try #require(
            nsExtension["NSExtensionAttributes"] as? [String: Any],
            "missing NSExtension > NSExtensionAttributes"
        )
        let capabilities = try #require(
            attributes["ASCredentialProviderExtensionCapabilities"] as? [String: Any],
            "missing ASCredentialProviderExtensionCapabilities under NSExtensionAttributes"
        )

        #expect(capabilities["ProvidesPasskeys"] as? Bool == true)
        #expect(capabilities["ProvidesPasswords"] as? Bool == true)
    }

    /// The misplacement is invisible at build time and only shows up as
    /// "Groo isn't offered when creating a passkey", so pin it explicitly.
    @Test func capabilitiesAreNotDeclaredDirectlyUnderNSExtension() throws {
        let nsExtension = try nsExtension()

        #expect(
            nsExtension["ASCredentialProviderExtensionCapabilities"] == nil,
            "capabilities must live under NSExtensionAttributes, where iOS reads them"
        )
    }

    @Test func isACredentialProviderExtension() throws {
        let nsExtension = try nsExtension()

        #expect(
            nsExtension["NSExtensionPointIdentifier"] as? String
                == "com.apple.authentication-services-credential-provider-ui"
        )
    }
}
