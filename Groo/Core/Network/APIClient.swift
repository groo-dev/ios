//
//  APIClient.swift
//  Groo
//
//  HTTP client for Groo APIs using URLSession.
//

import Foundation
import os

// MARK: - Types

enum APIError: Error {
    case invalidURL
    case noData
    case decodingFailed(Error)
    case httpError(statusCode: Int, message: String?)
    case networkError(Error)
    case unauthorized
}

struct APIResponse<T: Decodable>: Decodable {
    let data: T?
    let error: String?
}

// MARK: - APIClient

actor APIClient {
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let tokenProvider: @Sendable () async throws -> String
    private let forceRefresh: @Sendable () async throws -> String

    /// - Parameters:
    ///   - tokenProvider: Returns a valid OAuth access token, refreshing transparently
    ///     when needed. In production this is `authService.accessToken`.
    ///   - forceRefresh: Forces exactly one token refresh (bypassing any expiry check)
    ///     and returns the new token. Used once on a `401` before retrying. In
    ///     production this is `authService.forceRefresh`.
    init(
        baseURL: URL,
        tokenProvider: @escaping @Sendable () async throws -> String = { throw APIError.unauthorized },
        forceRefresh: @escaping @Sendable () async throws -> String = { throw APIError.unauthorized }
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.forceRefresh = forceRefresh
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    // MARK: - Request Building

    private func buildRequest(
        path: String,
        method: String,
        body: Data? = nil,
        contentType: String = "application/json"
    ) async throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
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
            Log.network.debug("POST \(request.url?.absoluteString ?? "nil", privacy: .public)")
            return try await perform(request)
        }
    }

    func post(_ path: String) async throws {
        try await withUnauthorizedRetry {
            let request = try await buildRequest(path: path, method: "POST")
            try await performVoid(request)
        }
    }

    func put<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        try await withUnauthorizedRetry {
            let bodyData = try encoder.encode(body)
            let request = try await buildRequest(path: path, method: "PUT", body: bodyData)
            return try await perform(request)
        }
    }

    func delete(_ path: String) async throws {
        try await withUnauthorizedRetry {
            let request = try await buildRequest(path: path, method: "DELETE")
            try await performVoid(request)
        }
    }

    // MARK: - File Operations

    func uploadFile(_ data: Data, to path: String) async throws -> FileUploadResponse {
        try await withUnauthorizedRetry {
            guard let url = URL(string: path, relativeTo: baseURL) else {
                throw APIError.invalidURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"

            // Multipart form data
            let boundary = UUID().uuidString
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

            let token = try await tokenProvider()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            var body = Data()
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"encrypted\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
            body.append(data)
            body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

            request.httpBody = body
            return try await perform(request)
        }
    }

    func downloadFile(from path: String) async throws -> Data {
        try await withUnauthorizedRetry {
            let request = try await buildRequest(path: path, method: "GET")
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.networkError(URLError(.badServerResponse))
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                if httpResponse.statusCode == 401 {
                    throw APIError.unauthorized
                }
                throw APIError.httpError(statusCode: httpResponse.statusCode, message: nil)
            }

            return data
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
            let message = try? decoder.decode([String: String].self, from: data)["error"]
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: message)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingFailed(error)
        }
    }

    private func performVoid(_ request: URLRequest) async throws {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            }
            let message = try? decoder.decode([String: String].self, from: data)["error"]
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: message)
        }
    }
}

// MARK: - Response Types

struct FileUploadResponse: Decodable {
    let id: String
    let size: Int
    let r2Key: String
}

// MARK: - API Endpoints

extension APIClient {
    enum Endpoint {
        static let state = "/v1/state"
        static let files = "/v1/files"
        static let list = "/v1/list"
        static let scratchpads = "/v1/scratchpads"

        static func file(_ key: String) -> String {
            "/v1/files/\(key)"
        }

        static func listItem(_ id: String) -> String {
            "/v1/list/\(id)"
        }

        static func scratchpad(_ id: String) -> String {
            "/v1/scratchpads/\(id)"
        }

        static func scratchpadFiles(_ id: String) -> String {
            "/v1/scratchpads/\(id)/files"
        }
    }
}

// MARK: - Additional Response Types

struct AddItemResponse: Decodable {
    let success: Bool
}
