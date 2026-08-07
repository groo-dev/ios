//
//  SharedAPIError.swift
//  Groo
//
//  Moved out of Groo/Core/Network/APIClient.swift so the AutoFill extension can
//  use PassAPIClient. `APIError` keeps its name and cases so every existing
//  call site and test compiles unchanged.
//

import Foundation

enum APIError: Error {
    case invalidURL
    case noData
    case decodingFailed(Error)
    case httpError(statusCode: Int, message: String?)
    case networkError(Error)
    case unauthorized
    /// A per-record optimistic-lock failure, carrying the server's current copy
    /// so the caller can field-merge and retry without a second round trip.
    ///
    /// A distinct case rather than extra data on `httpError`: existing call
    /// sites pattern-match `httpError` with exactly two associated values.
    case recordConflict(current: SharedServerRecord)

    /// The server's error `code`, when it sent one.
    ///
    /// The per-item record API returns several distinct 409s — `RECORD_CONFLICT`,
    /// `CURSOR_TOO_OLD`, `NOT_CONVERTED`, `COUNT_MISMATCH` — which callers must
    /// tell apart. Treating every 409 as a version conflict (as this client used
    /// to) would make a stale cursor look like a lost write.
    var serverCode: String? {
        if case .httpError(_, let message) = self { return message }
        return nil
    }
}

/// The shape the Pass API uses for every error response. `current` is present
/// only on a RECORD_CONFLICT.
struct SharedAPIErrorBody: Decodable {
    let error: String?
    let code: String?
    let current: SharedServerRecord?
}
