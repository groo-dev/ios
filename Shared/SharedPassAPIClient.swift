//
//  SharedPassAPIClient.swift
//  Groo
//
//  Moved out of PassService.swift so the AutoFill extension can push a passkey
//  during the registration ceremony. Already token-source-agnostic via its
//  tokenProvider/forceRefresh closures, so the move is mechanical.
//
//  Also removes ~130 lines from PassService.swift, which held both the service
//  and its HTTP client.
//

import Foundation

// MARK: - PassAPIClient

/// Dedicated API client for Pass service
actor PassAPIClient {
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let tokenProvider: @Sendable () async throws -> String
    private let forceRefresh: @Sendable () async throws -> String

    init(
        tokenProvider: @escaping @Sendable () async throws -> String = { throw APIError.unauthorized },
        forceRefresh: @escaping @Sendable () async throws -> String = { throw APIError.unauthorized },
        sessionConfiguration: URLSessionConfiguration = .default
    ) {
        self.baseURL = SharedConfig.passAPIBaseURL
        self.tokenProvider = tokenProvider
        self.forceRefresh = forceRefresh
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()

        let config = sessionConfiguration
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    // MARK: - Request Building

    private func buildRequest(
        path: String,
        method: String,
        body: Data? = nil
    ) async throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let token = try await tokenProvider()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        request.httpBody = body
        return request
    }

    /// Runs `operation` once; on `APIError.unauthorized` forces exactly one token
    /// refresh and retries `operation` once more. A second `401` (or any other
    /// error from the retry) propagates as-is — no further retries.
    private func withUnauthorizedRetry<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch APIError.unauthorized {
            _ = try await forceRefresh()
            return try await operation()
        }
    }

    // MARK: - HTTP Methods

    func get<T: Decodable>(_ path: String) async throws -> T {
        try await withUnauthorizedRetry {
            let request = try await buildRequest(path: path, method: "GET")
            return try await perform(request)
        }
    }

    func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        try await withUnauthorizedRetry {
            let bodyData = try encoder.encode(body)
            let request = try await buildRequest(path: path, method: "POST", body: bodyData)
            return try await perform(request)
        }
    }

    func put<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        try await withUnauthorizedRetry {
            let bodyData = try encoder.encode(body)
            let request = try await buildRequest(path: path, method: "PUT", body: bodyData)
            return try await perform(request)
        }
    }

    func delete<T: Decodable>(_ path: String) async throws -> T {
        try await withUnauthorizedRetry {
            let request = try await buildRequest(path: path, method: "DELETE")
            return try await perform(request)
        }
    }


    // MARK: - Request Execution

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            }
            let body = try? decoder.decode(SharedAPIErrorBody.self, from: data)

            // A record conflict becomes a typed error carrying the server's
            // copy, so the caller can field-merge without refetching.
            if let current = body?.current, body?.code == "RECORD_CONFLICT" {
                throw APIError.recordConflict(current: current)
            }

            // Carry the server's `code` rather than assuming. A 409 used to be
            // hardcoded as VERSION_CONFLICT, which is wrong now that the record
            // API also returns CURSOR_TOO_OLD, NOT_CONVERTED and COUNT_MISMATCH
            // with the same status.
            let code = body?.code
                ?? (httpResponse.statusCode == 409 ? "VERSION_CONFLICT" : body?.error)
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: code)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingFailed(error)
        }
    }

    // MARK: - Endpoints

    enum Endpoint {
        static let keyInfo = "/v1/vault/key-info"
        static let vault = "/v1/vault"
        static let vaultSetup = "/v1/vault/setup"
        static let vaultVersion = "/v1/vault/version"
        static let files = "/v1/files"
        static let audit = "/v1/audit"

        static func file(_ fileId: String) -> String {
            "/v1/files/\(fileId)"
        }

        // MARK: Per-item records
        //
        // Deliberately no `convert/commit`: only the web app converts a vault,
        // so exposing it here would invite a call that must never happen from
        // iOS.

        static let records = "/v1/vault/records"
        static let recordsBulk = "/v1/vault/records/bulk"
        static let privateKey = "/v1/vault/private-key"

        static func record(_ id: String) -> String {
            let escaped = id.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed
            ) ?? id
            return "/v1/vault/records/\(escaped)"
        }

        static func recordsSince(_ since: Int, limit: Int? = nil) -> String {
            var path = "/v1/vault/records?since=\(since)"
            if let limit { path += "&limit=\(limit)" }
            return path
        }
    }
}
