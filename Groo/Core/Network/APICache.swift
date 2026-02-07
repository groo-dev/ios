//
//  APICache.swift
//  Groo
//
//  Shared URL-level cache for third-party API responses.
//  Deduplicates in-flight requests and supports configurable TTL.
//

import Foundation
import os

// MARK: - Errors

enum APICacheError: Error {
    case httpError(statusCode: Int, data: Data)
}

// MARK: - APICache

actor APICache {
    static let shared = APICache()

    private var cache: [String: Entry] = [:]
    private var inFlight: [String: Task<Data, Error>] = [:]
    private let session: URLSession
    private let logger = Logger(subsystem: "dev.groo.ios", category: "APICache")

    struct Entry {
        let data: Data
        let timestamp: Date

        func isValid(ttl: TimeInterval) -> Bool {
            Date().timeIntervalSince(timestamp) < ttl
        }
    }

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config)
    }

    func fetch(_ url: URL, ttl: TimeInterval, forceRefresh: Bool = false) async throws -> Data {
        let key = url.absoluteString

        // 1. Cache check
        if !forceRefresh, let entry = cache[key], entry.isValid(ttl: ttl) {
            return entry.data
        }

        // 2. Request deduplication — await existing in-flight task
        if let existing = inFlight[key] {
            return try await existing.value
        }

        // 3. Network call
        let task = Task<Data, Error> {
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw APICacheError.httpError(statusCode: statusCode, data: data)
            }

            return data
        }

        inFlight[key] = task

        do {
            let data = try await task.value
            // 4. Store result
            cache[key] = Entry(data: data, timestamp: Date())
            inFlight[key] = nil
            return data
        } catch {
            // 5. Error handling — don't cache errors
            inFlight[key] = nil
            throw error
        }
    }

    func clearAll() {
        cache.removeAll()
    }

    func clear(matching predicate: (String) -> Bool) {
        for key in cache.keys where predicate(key) {
            cache.removeValue(forKey: key)
        }
    }
}
