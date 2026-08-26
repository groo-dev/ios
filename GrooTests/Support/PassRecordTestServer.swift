//
//  PassRecordTestServer.swift
//  GrooTests
//
//  An in-memory stand-in for the per-item record endpoints, wired into
//  StubURLProtocol's dynamic handler.
//
//  The canned FIFO queues cannot serve these: a record PUT goes to
//  /v1/vault/records/<id> with a per-record optimistic lock, so the response
//  depends on what was written before it. This keeps that state, which lets a
//  test assert on the vault the service actually persisted rather than on the
//  bytes of one request.
//

import CryptoKit
import Foundation
@testable import Groo

final class PassRecordTestServer: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [String: SharedServerRecord] = [:]
    private var changeSeq = 0
    private let keyInfoJSON: String
    private let privateKeyJSON: String?

    /// Set to fail the next single-record write with this status and code.
    nonisolated(unsafe) var failNextWrite: (status: Int, code: String)?

    init(keyInfoJSON: String, privateKeyJSON: String? = nil) {
        self.keyInfoJSON = keyInfoJSON
        self.privateKeyJSON = privateKeyJSON
    }

    /// Seed a record as though the server already held it.
    func seed(id: String, kind: SharedRecordKind, payload: Data, vaultKey: SymmetricKey) throws {
        let enc = try SharedRecordCrypto.encryptRecord(
            id: id, kind: kind, payload: payload, vaultKey: vaultKey)
        lock.lock(); defer { lock.unlock() }
        changeSeq += 1
        records[id] = SharedServerRecord(
            id: id,
            encryptedData: enc.encryptedData, iv: enc.iv,
            wrappedRecordKey: enc.wrappedRecordKey, wrapIv: enc.wrapIv,
            version: 1, seq: changeSeq, isDeleted: false, createdAt: 1, updatedAt: 1)
    }

    /// Every live record, decrypted, as the vault the service has persisted.
    func assembledVault(vaultKey: SymmetricKey) throws -> PassVault {
        lock.lock()
        let live = records.values.filter { !$0.isDeleted }.sorted { $0.seq < $1.seq }
        lock.unlock()

        var items: [PassVaultItem] = []
        var folders: [PassFolder] = []
        for record in live {
            guard let decoded = try SharedRecordCrypto.decryptRecord(record, vaultKey: vaultKey)
            else { continue }
            switch decoded.kind {
            case .item: items.append(try JSONDecoder().decode(PassVaultItem.self, from: decoded.data))
            case .folder: folders.append(try JSONDecoder().decode(PassFolder.self, from: decoded.data))
            }
        }
        return PassVault(version: 1, items: items, folders: folders, lastModified: 1_700_000_000_000)
    }

    func install() {
        StubURLProtocol.handler = { [weak self] request in self?.respond(to: request) }
    }

    private func respond(to request: URLRequest) -> StubURLProtocol.Response? {
        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? "GET"

        if method == "GET", path.hasSuffix("/v1/vault/key-info") {
            return .success(status: 200, body: Data(keyInfoJSON.utf8))
        }
        if method == "GET", path.hasSuffix("/v1/vault/private-key") {
            guard let privateKeyJSON else {
                return .success(status: 404, body: Data(#"{"code":"PRIVATE_KEY_NOT_SET"}"#.utf8))
            }
            return .success(status: 200, body: Data(privateKeyJSON.utf8))
        }
        if method == "GET", path.hasSuffix("/v1/vault/records") {
            let since = Int(URLComponents(string: request.url?.absoluteString ?? "")?
                .queryItems?.first { $0.name == "since" }?.value ?? "0") ?? 0
            lock.lock()
            let page = records.values.filter { $0.seq > since }.sorted { $0.seq < $1.seq }
            lock.unlock()
            let body = SharedRecordsResponse(
                records: page, nextSeq: page.last?.seq ?? since, hasMore: false)
            return .success(status: 200, body: (try? JSONEncoder().encode(body)) ?? Data())
        }
        if method == "POST", path.hasSuffix("/v1/vault/records") {
            return write(request, expectExisting: false)
        }
        if path.contains("/v1/vault/records/") {
            if method == "PUT" { return write(request, expectExisting: true) }
            if method == "DELETE" {
                let id = String(path.split(separator: "/").last ?? "").removingPercentEncoding ?? ""
                lock.lock(); defer { lock.unlock() }
                guard let existing = records[id] else {
                    return .success(status: 404, body: Data(#"{"code":"RECORD_NOT_FOUND"}"#.utf8))
                }
                changeSeq += 1
                records[id] = SharedServerRecord(
                    id: id, encryptedData: nil, iv: nil, wrappedRecordKey: nil, wrapIv: nil,
                    version: existing.version + 1, seq: changeSeq, isDeleted: true,
                    createdAt: existing.createdAt, updatedAt: 1)
                let body = SharedRecordDeleteResponse(id: id, seq: changeSeq)
                return .success(status: 200, body: (try? JSONEncoder().encode(body)) ?? Data())
            }
        }
        return nil
    }

    private func write(_ request: URLRequest, expectExisting: Bool) -> StubURLProtocol.Response {
        if let failure = failNextWrite {
            failNextWrite = nil
            return .success(
                status: failure.status, body: Data(#"{"code":"\#(failure.code)"}"#.utf8))
        }
        guard let body = request.bodyData,
              let write = try? JSONDecoder().decode(SharedRecordWriteRequest.self, from: body) else {
            return .success(status: 400, body: Data(#"{"code":"INVALID_REQUEST"}"#.utf8))
        }
        lock.lock(); defer { lock.unlock() }
        let existing = records[write.id]
        if expectExisting {
            guard let existing else {
                return .success(status: 404, body: Data(#"{"code":"RECORD_NOT_FOUND"}"#.utf8))
            }
            guard write.expectedVersion == existing.version else {
                return .success(status: 409, body: Data(#"{"code":"RECORD_CONFLICT"}"#.utf8))
            }
        } else if existing != nil {
            return .success(status: 409, body: Data(#"{"code":"RECORD_EXISTS"}"#.utf8))
        }
        changeSeq += 1
        let stored = SharedServerRecord(
            id: write.id,
            encryptedData: write.encryptedData, iv: write.iv,
            wrappedRecordKey: write.wrappedRecordKey, wrapIv: write.wrapIv,
            version: (existing?.version ?? 0) + 1, seq: changeSeq, isDeleted: false,
            createdAt: existing?.createdAt ?? 1, updatedAt: 1)
        records[write.id] = stored
        let response = SharedRecordWriteResponse(
            id: stored.id, seq: stored.seq, version: stored.version)
        return .success(status: 200, body: (try? JSONEncoder().encode(response)) ?? Data())
    }
}
