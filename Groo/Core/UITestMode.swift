//
//  UITestMode.swift
//  Groo
//
//  Production seam for XCUITests. Every path in this file — and every branch
//  on UITestMode.isActive elsewhere — is inert unless the process was launched
//  with the "--uitest" argument (GrooUITests always passes it). Under --uitest
//  the app must never touch real local data or real APIs:
//    - UserDefaults: persistent domain wiped per launch (test independence),
//      overridable base URLs volatile-registered to an unroutable local port
//    - SwiftData: in-memory container (LocalStore.shared checks isActive)
//    - Keychain: in-process fake shared by ContentView/PadService/PassService
//    - Pass API: in-process URLProtocol stub with an in-memory vault, seeded
//      empty and encrypted under masterPassword (real PBKDF2 + AES-GCM)
//    - Pad/Sync/Accounts APIs: token provider always throws — requests die
//      before any network I/O
//  The seam swaps I/O boundaries only; all real crypto runs unmodified.
//

import CryptoKit
import Foundation
import LocalAuthentication
import SwiftData

enum UITestMode {
    /// The single fencing condition for every UI-test seam in the app.
    static let isActive = ProcessInfo.processInfo.arguments.contains("--uitest")

    /// Master password of the stub server's seeded vault. Mirrored as a
    /// constant in GrooUITests/UITestHelpers.swift — keep in sync.
    static let masterPassword = "uitest-master-1"

    /// Deterministic salt + low iteration count so unlock is near-instant in
    /// tests. kdfIterations is served by the stub exactly like the real
    /// server serves 600k — PassService's mechanism is identical either way.
    static let keySalt = Data(repeating: 0xAB, count: 16)
    static let kdfIterations = 10_000

    /// One shared in-process keychain so ContentView's global-lock check,
    /// PadService, and PassService all observe the same (empty-at-launch) state.
    static let keychain = UITestInMemoryKeychain()

    /// Called once from GrooApp.init, before any store/service singleton is
    /// first touched. (AuthService/GrooAuth are constructed before this runs
    /// but read only their own keychain storage, never UserDefaults.standard.)
    static func activateIfNeeded() {
        guard isActive else { return }

        // Fresh UserDefaults every launch: erases anything a previous UI-test
        // launch wrote (wallet address cache, selected tab) and detaches the
        // run from developer state on the same simulator.
        if let bundleId = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleId)
        }

        // Defense-in-depth: point every overridable base URL at an unroutable
        // local port so any request that escapes a stub fails fast without
        // leaving the machine. register(defaults:) is volatile — never persisted.
        let dead = "http://127.0.0.1:9"
        UserDefaults.standard.register(defaults: [
            "padAPIBaseURL": dead,
            "passAPIBaseURL": dead,
            "accountsAPIBaseURL": dead,
            "ethereumRPCURL": dead,
            "blockscoutBaseURL": dead,
            "coinGeckoBaseURL": dead,
        ])
    }

    /// In-memory SwiftData container; LocalStore.shared wraps this under
    /// --uitest so every LocalStore.shared caller (Home, Azan, Portfolio,
    /// Settings, Stocks) is isolated without threading a store through views.
    static func makeInMemoryModelContainer() -> ModelContainer {
        let config = ModelConfiguration(schema: LocalStore.schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: LocalStore.schema, configurations: [config])
        } catch {
            // UI-test-only path: crash loudly; a fallback would hide the break
            fatalError("UITestMode: in-memory ModelContainer creation failed: \(error)")
        }
    }

    /// PassService wired to the in-process stub API, the fake keychain, a
    /// per-launch temp-directory vault store (never the App Group), and a
    /// no-op credential-identity service (never ASCredentialIdentityStore).
    @MainActor
    static func makePassService() -> PassService {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [UITestPassAPIProtocol.self]
        let api = PassAPIClient(
            tokenProvider: { "uitest-token" },
            forceRefresh: { "uitest-token" },
            sessionConfiguration: sessionConfiguration
        )
        let vaultDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("uitest-vault-\(UUID().uuidString)", isDirectory: true)
        return PassService(
            api: api,
            keychain: keychain,
            vaultStore: PassVaultStore(directoryURL: vaultDirectory),
            credentialService: UITestNoopCredentialService()
        )
    }
}

// MARK: - In-memory keychain

/// Deterministic KeychainServicing fake for --uitest. Biometric items never
/// prompt. (Deliberate near-duplicate of GrooTests/Support/InMemoryKeychain —
/// test-target code cannot be compiled into the app target.)
final class UITestInMemoryKeychain: KeychainServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var plain: [String: Data] = [:]
    private var biometric: [String: Data] = [:]

    func save(_ value: String, for key: String) throws {
        try save(Data(value.utf8), for: key)
    }

    func loadString(for key: String) throws -> String {
        guard let string = String(data: try load(for: key), encoding: .utf8) else {
            throw KeychainError.encodingFailed
        }
        return string
    }

    func save(_ data: Data, for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        plain[key] = data
    }

    func load(for key: String) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        guard let data = plain[key] else { throw KeychainError.itemNotFound }
        return data
    }

    func delete(for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        plain[key] = nil
    }

    func exists(for key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return plain[key] != nil
    }

    func saveBiometricProtected(_ data: Data, for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        biometric[key] = data
    }

    func loadBiometricProtected(for key: String, prompt: String, context: LAContext?) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        guard let data = biometric[key] else { throw KeychainError.itemNotFound }
        return data
    }

    func deleteBiometricProtected(for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        biometric[key] = nil
    }

    func biometricProtectedKeyExists(for key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return biometric[key] != nil
    }
}

// MARK: - No-op credential identity service

/// Keeps --uitest runs out of the (global, entitlement-gated) system
/// ASCredentialIdentityStore.
final class UITestNoopCredentialService: CredentialIdentityProviding {
    func updateCredentialIdentities(from items: [PassVaultItem]) async {}
    func clearCredentialIdentities() async -> Bool { true }
}

// MARK: - In-process Pass API stub

/// In-memory Pass "server": GET /v1/vault/key-info, GET /v1/vault,
/// PUT /v1/vault with the real optimistic-locking contract (409 on a stale
/// expectedVersion). Seeded lazily with an empty vault encrypted — via the
/// app's own CryptoService — under UITestMode.masterPassword.
final class UITestVaultServer: @unchecked Sendable {
    static let shared = UITestVaultServer()

    private let lock = NSLock()
    private var encryptedData: String   // base64 (ciphertext+tag, no IV)
    private var iv: String              // base64 (12 bytes)
    private var version = 1
    private var updatedAt = Int(Date().timeIntervalSince1970 * 1000)

    private init() {
        let crypto = CryptoService()
        do {
            let key = try crypto.deriveKey(
                password: UITestMode.masterPassword,
                salt: UITestMode.keySalt,
                iterations: UInt32(UITestMode.kdfIterations)
            )
            let vaultJSON = try JSONEncoder().encode(PassVault.empty)
            // encryptData returns IV + ciphertext + tag; the API contract
            // splits the 12-byte IV out (mirrors PassService.saveVault)
            let combined = try crypto.encryptData(vaultJSON, using: key)
            self.iv = combined.prefix(12).base64EncodedString()
            self.encryptedData = combined.dropFirst(12).base64EncodedString()
        } catch {
            fatalError("UITestVaultServer: vault seeding failed: \(error)")
        }
    }

    func response(for request: URLRequest) -> (status: Int, body: Data) {
        lock.lock(); defer { lock.unlock() }
        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? "GET"

        switch (method, path) {
        case ("GET", "/v1/vault/key-info"):
            return (200, encode(PassKeyInfo(
                keySalt: UITestMode.keySalt.base64EncodedString(),
                kdfIterations: UITestMode.kdfIterations
            )))
        case ("GET", "/v1/vault"):
            return (200, encode(PassVaultResponse(
                encryptedData: encryptedData, iv: iv, version: version, updatedAt: updatedAt
            )))
        case ("PUT", "/v1/vault"):
            guard let body = request.uitestBodyData,
                  let update = try? JSONDecoder().decode(PassVaultUpdateRequest.self, from: body) else {
                return (400, Data(#"{"error":"bad request"}"#.utf8))
            }
            guard update.expectedVersion == version else {
                return (409, Data(#"{"error":"VERSION_CONFLICT"}"#.utf8))
            }
            encryptedData = update.encryptedData
            iv = update.iv
            version += 1
            updatedAt = Int(Date().timeIntervalSince1970 * 1000)
            return (200, encode(PassVaultResponse(
                encryptedData: encryptedData, iv: iv, version: version, updatedAt: updatedAt
            )))
        default:
            return (404, Data(#"{"error":"not found"}"#.utf8))
        }
    }

    private func encode<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }
}

/// Installed only on the PassAPIClient session UITestMode.makePassService
/// builds — it intercepts every request on that session and answers from
/// UITestVaultServer. No other session in the app sees this class.
final class UITestPassAPIProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (status, body) = UITestVaultServer.shared.response(for: request)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "http://uitest.invalid")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension URLRequest {
    /// URLSession hands URLProtocol the body as a stream, not httpBody.
    var uitestBodyData: Data? {
        if let body = httpBody { return body }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
