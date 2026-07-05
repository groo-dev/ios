//
//  StubURLProtocol.swift
//  GrooTests
//
//  Intercepts every request on a stubbed URLSession and serves canned
//  responses. FIFO per (method, path suffix); last response repeats.
//  Static state ⇒ consuming suites MUST be @Suite(.serialized) and reset().
//

import Foundation

final class StubURLProtocol: URLProtocol {
    enum Response {
        case success(status: Int, body: Data)
        case failure(any Error)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var queues: [String: [Response]] = [:]
    nonisolated(unsafe) private static var recorded: [URLRequest] = []

    private static func key(_ method: String, _ pathSuffix: String) -> String {
        "\(method.uppercased()) \(pathSuffix)"
    }

    static func enqueue(method: String, pathSuffix: String, status: Int = 200, json: String) {
        lock.lock(); defer { lock.unlock() }
        queues[key(method, pathSuffix), default: []].append(.success(status: status, body: Data(json.utf8)))
    }

    static func enqueue(method: String, pathSuffix: String, error: any Error) {
        lock.lock(); defer { lock.unlock() }
        queues[key(method, pathSuffix), default: []].append(.failure(error))
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        queues = [:]
        recorded = []
    }

    static var recordedRequests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    /// Session configuration routing ALL traffic through this stub.
    static func stubbedConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return config
    }

    private static func dequeue(for request: URLRequest) -> Response? {
        lock.lock(); defer { lock.unlock() }
        recorded.append(request)
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? ""
        guard let matchKey = queues.keys.first(where: { key in
            let parts = key.split(separator: " ", maxSplits: 1)
            return parts[0] == method.uppercased() && path.hasSuffix(parts[1])
        }), var queue = queues[matchKey], !queue.isEmpty else {
            return nil
        }
        let response = queue.removeFirst()
        // Last response for a key repeats: only consume while more remain.
        queues[matchKey] = queue.isEmpty ? [response] : queue
        return response
    }

    // MARK: URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let response = Self.dequeue(for: request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL,
                userInfo: [NSLocalizedDescriptionKey: "No stub for \(request.httpMethod ?? "?") \(request.url?.path ?? "?")"]))
            return
        }
        switch response {
        case .success(let status, let body):
            let http = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}

extension URLRequest {
    /// URLSession delivers bodies to URLProtocol as a stream — read it back.
    var bodyData: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
