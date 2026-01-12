//
//  APIClient.swift
//  Groo
//
//  HTTP client for Groo APIs using URLSession.
//

import Foundation

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
    private let keychain: KeychainService
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: URL, keychain: KeychainService = KeychainService()) {
        self.baseURL = baseURL
        self.keychain = keychain
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    // MARK: - PAT Token

    private func getPatToken() -> String? {
        try? keychain.loadString(for: KeychainService.Key.patToken)
    }

    // MARK: - Request Building

    private func buildRequest(
        path: String,
        method: String,
        body: Data? = nil,
        contentType: String = "application/json"
    ) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Add PAT token as cookie (pad API expects session cookie)
        if let token = getPatToken() {
            request.setValue("session=\(token)", forHTTPHeaderField: "Cookie")
        }

        request.httpBody = body
        return request
    }

    // MARK: - HTTP Methods

    func get<T: Decodable>(_ path: String) async throws -> T {
        let request = try buildRequest(path: path, method: "GET")
        return try await perform(request)
    }

    func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        let bodyData = try encoder.encode(body)
        let request = try buildRequest(path: path, method: "POST", body: bodyData)
        print("[API] POST \(request.url?.absoluteString ?? "nil")")
        return try await perform(request)
    }

    func post(_ path: String) async throws {
        let request = try buildRequest(path: path, method: "POST")
        try await performVoid(request)
    }

    func put<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        let bodyData = try encoder.encode(body)
        let request = try buildRequest(path: path, method: "PUT", body: bodyData)
        return try await perform(request)
    }

    func delete(_ path: String) async throws {
        let request = try buildRequest(path: path, method: "DELETE")
        try await performVoid(request)
    }

    // MARK: - File Operations

    func uploadFile(_ data: Data, to path: String) async throws -> FileUploadResponse {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        // Multipart form data
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        if let token = getPatToken() {
            request.setValue("session=\(token)", forHTTPHeaderField: "Cookie")
        }

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"encrypted\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body
        return try await perform(request)
    }

    func downloadFile(from path: String) async throws -> Data {
        let request = try buildRequest(path: path, method: "GET")
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

        static func file(_ key: String) -> String {
            "/v1/files/\(key)"
        }

        static func listItem(_ id: String) -> String {
            "/v1/list/\(id)"
        }
    }
}

// MARK: - Additional Response Types

struct AddItemResponse: Decodable {
    let success: Bool
}
