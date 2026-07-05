//
//  WebSocketService.swift
//  Groo
//
//  WebSocket connection for real-time scratchpad sync.
//  Handles connection, reconnection, and incoming updates.
//  The socket and timers sit behind seams (WebSocketConnection,
//  WebSocketTimerFactory) so tests can drive the state machine with a
//  scripted fake and fire backoff timers manually.
//

import Foundation
import os

// MARK: - WebSocket Message Types

enum WebSocketMessageType: String, Codable {
    case scratchpadUpdated = "scratchpad_updated"
    case scratchpadCreated = "scratchpad_created"
    case scratchpadDeleted = "scratchpad_deleted"
    case ping = "ping"
    case pong = "pong"
}

struct WebSocketMessage: Codable {
    let type: WebSocketMessageType
    let scratchpadId: String?
    let timestamp: Int?
}

// MARK: - Seams

/// The slice of AuthService the WebSocket layer needs (mirrors the
/// KeychainServicing extraction). Tests inject a fake token provider.
@MainActor
protocol WebSocketTokenProviding: AnyObject {
    func accessToken() async throws -> String
    func forceRefresh() async throws -> String
}

extension AuthService: WebSocketTokenProviding {}

/// One WebSocket connection attempt. Production wraps a
/// URLSession + URLSessionWebSocketTask pair; tests use a scripted fake.
@MainActor
protocol WebSocketConnection: AnyObject {
    /// Fired when the WebSocket handshake completes.
    var onOpen: (() -> Void)? { get set }
    /// Fired when the socket closes after having opened.
    var onClose: ((URLSessionWebSocketTask.CloseCode, Data?) -> Void)? { get set }
    /// Fired when the connection attempt errors out before any
    /// WebSocket-specific callback (e.g. the server rejected the upgrade).
    /// `statusCode` is the handshake's HTTP status when known.
    var onHandshakeFailure: ((_ statusCode: Int?, _ error: any Error) -> Void)? { get set }

    func resume()
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
    func send(_ text: String, completion: @escaping @Sendable ((any Error)?) -> Void)
    func receive(completion: @escaping @Sendable (Result<URLSessionWebSocketTask.Message, any Error>) -> Void)
}

/// Creates a scheduled timer. Injected so tests can record (interval,
/// repeats, block) and fire manually instead of waiting (no-sleeps rule).
typealias WebSocketTimerFactory = @MainActor (
    _ interval: TimeInterval,
    _ repeats: Bool,
    _ block: @escaping @MainActor () -> Void
) -> Timer

/// Production connection: owns a URLSession + URLSessionWebSocketTask pair
/// and forwards the delegate callbacks that used to live on WebSocketService.
@MainActor
final class URLSessionWebSocketConnection: NSObject, WebSocketConnection {
    var onOpen: (() -> Void)?
    var onClose: ((URLSessionWebSocketTask.CloseCode, Data?) -> Void)?
    var onHandshakeFailure: ((Int?, any Error) -> Void)?

    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private let request: URLRequest

    init(request: URLRequest) {
        self.request = request
        super.init()
    }

    func resume() {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()
    }

    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        task?.cancel(with: closeCode, reason: reason)
        task = nil
        session = nil
    }

    func send(_ text: String, completion: @escaping @Sendable ((any Error)?) -> Void) {
        task?.send(.string(text), completionHandler: completion)
    }

    func receive(completion: @escaping @Sendable (Result<URLSessionWebSocketTask.Message, any Error>) -> Void) {
        task?.receive(completionHandler: completion)
    }
}

extension URLSessionWebSocketConnection: URLSessionWebSocketDelegate {
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        Task { @MainActor in
            self.onOpen?()
        }
    }

    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task { @MainActor in
            self.onClose?(closeCode, reason)
        }
    }

    /// A failed handshake (before any WebSocket-specific delegate callback
    /// fires) surfaces here — e.g. the server rejected the upgrade with 401.
    /// Successful completions (error == nil) are not forwarded; the close
    /// path and receive's failure branch drive the normal disconnect flow.
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let statusCode = (task.response as? HTTPURLResponse)?.statusCode
        Task { @MainActor in
            self.onHandshakeFailure?(statusCode, error)
        }
    }
}

// MARK: - WebSocket Service

@MainActor
@Observable
class WebSocketService {
    // Callbacks for events
    var onScratchpadUpdated: ((String) -> Void)?
    var onScratchpadCreated: ((String) -> Void)?
    var onScratchpadDeleted: ((String) -> Void)?
    var onConnected: (() -> Void)?
    var onDisconnected: ((Error?) -> Void)?

    private var connection: (any WebSocketConnection)?
    private let authService: any WebSocketTokenProviding
    private let makeConnection: @MainActor (URLRequest) -> any WebSocketConnection
    private let makeTimer: WebSocketTimerFactory

    private(set) var isConnected = false
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    private var reconnectTimer: Timer?
    private var pingTimer: Timer?

    /// Guards against retrying the forced-refresh more than once per connection
    /// attempt: reset when a fresh `connect()` starts or the socket opens.
    private var didRetryAfterUnauthorized = false

    // Connection URL
    private var webSocketURL: URL? {
        // Convert HTTP URL to WebSocket URL
        var components = URLComponents(url: Config.padAPIBaseURL, resolvingAgainstBaseURL: false)
        components?.scheme = Config.padAPIBaseURL.scheme == "https" ? "wss" : "ws"
        components?.path = "/v1/ws"
        return components?.url
    }

    init(
        authService: any WebSocketTokenProviding,
        makeConnection: @escaping @MainActor (URLRequest) -> any WebSocketConnection = { URLSessionWebSocketConnection(request: $0) },
        makeTimer: @escaping WebSocketTimerFactory = { interval, repeats, block in
            Timer.scheduledTimer(withTimeInterval: interval, repeats: repeats) { _ in
                Task { @MainActor in
                    block()
                }
            }
        }
    ) {
        self.authService = authService
        self.makeConnection = makeConnection
        self.makeTimer = makeTimer
    }

    // MARK: - Connection Management

    func connect() async {
        // Fresh connect: reset the reconnect backoff
        reconnectAttempts = 0
        didRetryAfterUnauthorized = false
        stopReconnectTimer()
        await openConnection()
    }

    private func openConnection() async {
        guard !isConnected, connection == nil else { return }
        guard let url = webSocketURL else {
            Log.sync.error("WebSocket connect failed: invalid URL")
            isConnected = false
            return
        }

        // Get auth token (Pad's /v1/ws accepts a Bearer token on the upgrade request)
        let token: String
        do {
            token = try await authService.accessToken()
        } catch {
            Log.sync.error("WebSocket connect failed: couldn't get access token: \(String(describing: error), privacy: .public)")
            isConnected = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let connection = makeConnection(request)
        self.connection = connection

        connection.onOpen = { [weak self] in
            guard let self else { return }
            self.isConnected = true
            self.reconnectAttempts = 0
            self.didRetryAfterUnauthorized = false
            Log.sync.debug("WebSocket connected")
            self.onConnected?()
        }

        connection.onClose = { [weak self] closeCode, reason in
            let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "unknown"
            Log.sync.debug("WebSocket closed: \(closeCode.rawValue) - \(reasonString, privacy: .public)")
            self?.handleDisconnect(error: nil)
        }

        connection.onHandshakeFailure = { [weak self] statusCode, error in
            // Only the 401-retry-once behavior lives here; other errored
            // completions are handled by receive's failure branch / onClose.
            guard statusCode == 401 else { return }
            Task { @MainActor in
                await self?.handleUnauthorizedHandshake(error: error)
            }
        }

        connection.resume()
        receiveMessage()
        startPingTimer()

        Log.sync.debug("WebSocket connecting to \(url.absoluteString, privacy: .public)")
    }

    /// Handles a handshake that failed with HTTP 401: forces exactly one token
    /// refresh and retries the connection once. A second 401 (or a failed
    /// refresh) surfaces as a normal disconnect — no further retries here.
    private func handleUnauthorizedHandshake(error: any Error) async {
        connection = nil
        isConnected = false
        stopPingTimer()

        guard !didRetryAfterUnauthorized else {
            Log.sync.error("WebSocket handshake unauthorized again after refresh — giving up")
            onDisconnected?(error)
            return
        }
        didRetryAfterUnauthorized = true

        do {
            _ = try await authService.forceRefresh()
        } catch {
            Log.sync.error("WebSocket forced refresh failed: \(String(describing: error), privacy: .public)")
            onDisconnected?(error)
            return
        }
        await openConnection()
    }

    func disconnect() {
        stopPingTimer()
        stopReconnectTimer()
        connection?.cancel(with: .goingAway, reason: nil)
        connection = nil
        isConnected = false
        reconnectAttempts = 0
        Log.sync.debug("WebSocket disconnected")
    }

    // MARK: - Message Handling

    private func receiveMessage() {
        connection?.receive { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let message):
                    self?.handleMessage(message)
                    self?.receiveMessage() // Continue listening
                case .failure(let error):
                    Log.sync.error("WebSocket receive error: \(String(describing: error), privacy: .public)")
                    self?.handleDisconnect(error: error)
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            parseMessage(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                parseMessage(text)
            }
        @unknown default:
            break
        }
    }

    private func parseMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else {
            Log.sync.error("WebSocket message is not valid UTF-8")
            return
        }
        let message: WebSocketMessage
        do {
            message = try JSONDecoder().decode(WebSocketMessage.self, from: data)
        } catch {
            Log.sync.error("Failed to parse WebSocket message: \(String(describing: error), privacy: .public)")
            return
        }

        Log.sync.debug("WebSocket received: \(message.type.rawValue, privacy: .public)")

        switch message.type {
        case .scratchpadUpdated:
            if let id = message.scratchpadId {
                onScratchpadUpdated?(id)
            }
        case .scratchpadCreated:
            if let id = message.scratchpadId {
                onScratchpadCreated?(id)
            }
        case .scratchpadDeleted:
            if let id = message.scratchpadId {
                onScratchpadDeleted?(id)
            }
        case .ping:
            sendPong()
        case .pong:
            // Server responded to our ping
            break
        }
    }

    // MARK: - Ping/Pong

    private func startPingTimer() {
        pingTimer = makeTimer(30, true) { [weak self] in
            self?.sendPing()
        }
    }

    private func stopPingTimer() {
        pingTimer?.invalidate()
        pingTimer = nil
    }

    private func sendPing() {
        let message = WebSocketMessage(type: .ping, scratchpadId: nil, timestamp: Int(Date().timeIntervalSince1970 * 1000))
        send(message)
    }

    private func sendPong() {
        let message = WebSocketMessage(type: .pong, scratchpadId: nil, timestamp: Int(Date().timeIntervalSince1970 * 1000))
        send(message)
    }

    private func send(_ message: WebSocketMessage) {
        guard let data = try? JSONEncoder().encode(message),
              let text = String(data: data, encoding: .utf8) else { return }

        connection?.send(text) { error in
            if let error = error {
                Log.sync.error("WebSocket send error: \(String(describing: error), privacy: .public)")
            }
        }
    }

    // MARK: - Reconnection

    private func handleDisconnect(error: Error?) {
        isConnected = false
        connection = nil
        stopPingTimer()

        onDisconnected?(error)

        // Attempt to reconnect
        if reconnectAttempts < maxReconnectAttempts {
            scheduleReconnect()
        } else {
            Log.sync.error("WebSocket gave up after \(self.maxReconnectAttempts) reconnect attempts")
        }
    }

    private func scheduleReconnect() {
        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts)), 30) // Exponential backoff, max 30s

        Log.sync.debug("WebSocket reconnecting in \(delay)s (attempt \(self.reconnectAttempts)/\(self.maxReconnectAttempts))")

        reconnectTimer = makeTimer(delay, false) { [weak self] in
            Task { @MainActor in
                await self?.openConnection()
            }
        }
    }

    private func stopReconnectTimer() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }
}
