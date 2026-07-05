//
//  WebSocketFakes.swift
//  GrooTests
//
//  Scriptable doubles for the WebSocketService seams: token provider,
//  connection, connection factory, and timer recorder. Timers are recorded
//  and fired manually — never waited on.
//

import Foundation
@testable import Groo

@MainActor
final class FakeTokenProvider: WebSocketTokenProviding {
    var currentToken = "tok-1"
    var refreshedToken = "tok-2"
    var accessTokenError: (any Error)?
    var forceRefreshError: (any Error)?
    private(set) var accessTokenCalls = 0
    private(set) var forceRefreshCalls = 0

    func accessToken() async throws -> String {
        accessTokenCalls += 1
        if let accessTokenError { throw accessTokenError }
        return currentToken
    }

    func forceRefresh() async throws -> String {
        forceRefreshCalls += 1
        if let forceRefreshError { throw forceRefreshError }
        currentToken = refreshedToken
        return currentToken
    }
}

@MainActor
final class FakeWebSocketConnection: WebSocketConnection {
    var onOpen: (() -> Void)?
    var onClose: ((URLSessionWebSocketTask.CloseCode, Data?) -> Void)?
    var onHandshakeFailure: ((Int?, any Error) -> Void)?

    private(set) var resumeCalls = 0
    private(set) var cancelledWith: URLSessionWebSocketTask.CloseCode?
    private(set) var sentTexts: [String] = []

    private var pendingReceives: [(Result<URLSessionWebSocketTask.Message, any Error>) -> Void] = []
    private var queuedResults: [Result<URLSessionWebSocketTask.Message, any Error>] = []

    func resume() { resumeCalls += 1 }

    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        cancelledWith = closeCode
    }

    func send(_ text: String, completion: @escaping @Sendable ((any Error)?) -> Void) {
        sentTexts.append(text)
        completion(nil)
    }

    func receive(completion: @escaping @Sendable (Result<URLSessionWebSocketTask.Message, any Error>) -> Void) {
        if queuedResults.isEmpty {
            pendingReceives.append(completion)
        } else {
            completion(queuedResults.removeFirst())
        }
    }

    // MARK: Test drivers

    /// Simulates the handshake completing.
    func open() { onOpen?() }

    /// Simulates the server closing the socket.
    func close(code: URLSessionWebSocketTask.CloseCode = .abnormalClosure) { onClose?(code, nil) }

    /// Simulates a failed upgrade (e.g. 401 before the socket opened).
    func failHandshake(statusCode: Int?, error: any Error = URLError(.userAuthenticationRequired)) {
        onHandshakeFailure?(statusCode, error)
    }

    /// Delivers a text frame to the service's receive loop. Frames delivered
    /// before the loop re-arms are buffered, preserving FIFO order.
    func deliver(_ text: String) { dispatch(.success(.string(text))) }

    /// Delivers a binary frame.
    func deliver(data: Data) { dispatch(.success(.data(data))) }

    /// Fails the receive loop (transport drop mid-stream).
    func failReceive(_ error: any Error) { dispatch(.failure(error)) }

    private func dispatch(_ result: Result<URLSessionWebSocketTask.Message, any Error>) {
        if pendingReceives.isEmpty {
            queuedResults.append(result)
        } else {
            pendingReceives.removeFirst()(result)
        }
    }
}

@MainActor
final class FakeConnectionFactory {
    private(set) var connections: [FakeWebSocketConnection] = []
    private(set) var requests: [URLRequest] = []
    var onCreate: ((FakeWebSocketConnection) -> Void)?

    func make(_ request: URLRequest) -> any WebSocketConnection {
        let connection = FakeWebSocketConnection()
        connections.append(connection)
        requests.append(request)
        onCreate?(connection)
        return connection
    }

    /// Runs `action`, then suspends until the factory creates the next
    /// connection (reconnects happen on a later main-actor turn).
    func connectionCreated(after action: @MainActor () -> Void) async -> FakeWebSocketConnection {
        await withCheckedContinuation { (continuation: CheckedContinuation<FakeWebSocketConnection, Never>) in
            onCreate = { [weak self] connection in
                self?.onCreate = nil
                continuation.resume(returning: connection)
            }
            action()
        }
    }
}

@MainActor
final class TimerRecorder {
    struct Entry {
        let interval: TimeInterval
        let repeats: Bool
        let block: @MainActor () -> Void
    }

    private(set) var entries: [Entry] = []

    /// Matches WebSocketTimerFactory. Returns an inert Timer (never added to
    /// a run loop): `invalidate()` is safe, and nothing ever fires on its own.
    func make(interval: TimeInterval, repeats: Bool, block: @escaping @MainActor () -> Void) -> Timer {
        entries.append(Entry(interval: interval, repeats: repeats, block: block))
        return Timer(timeInterval: interval, repeats: repeats) { _ in }
    }

    /// One-shot timers = the reconnect backoff schedule.
    var reconnectDelays: [TimeInterval] { entries.filter { !$0.repeats }.map(\.interval) }

    /// Repeating timers = the ping schedule.
    var pingIntervals: [TimeInterval] { entries.filter { $0.repeats }.map(\.interval) }

    func fireLastReconnect() {
        entries.last(where: { !$0.repeats })?.block()
    }

    func fireLastPing() {
        entries.last(where: { $0.repeats })?.block()
    }
}
