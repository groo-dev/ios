//
//  WebSocketService.swift
//  Groo
//
//  WebSocket connection for real-time scratchpad sync.
//  Handles connection, reconnection, and incoming updates.
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

// MARK: - WebSocket Service

@MainActor
@Observable
class WebSocketService: NSObject {
    // Callbacks for events
    var onScratchpadUpdated: ((String) -> Void)?
    var onScratchpadCreated: ((String) -> Void)?
    var onScratchpadDeleted: ((String) -> Void)?
    var onConnected: (() -> Void)?
    var onDisconnected: ((Error?) -> Void)?

    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private let authService: AuthService

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

    init(authService: AuthService) {
        self.authService = authService
        super.init()
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
        guard !isConnected, webSocket == nil else { return }
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

        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        webSocket = session?.webSocketTask(with: request)
        webSocket?.resume()

        receiveMessage()
        startPingTimer()

        Log.sync.debug("WebSocket connecting to \(url.absoluteString, privacy: .public)")
    }

    /// Handles a handshake that failed with HTTP 401: forces exactly one token
    /// refresh and retries the connection once. A second 401 (or a failed
    /// refresh) surfaces as a normal disconnect — no further retries here.
    private func handleUnauthorizedHandshake(error: Error) async {
        webSocket = nil
        session = nil
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
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        session = nil
        isConnected = false
        reconnectAttempts = 0
        Log.sync.debug("WebSocket disconnected")
    }

    // MARK: - Message Handling

    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
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
        pingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sendPing()
            }
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

        webSocket?.send(.string(text)) { error in
            if let error = error {
                Log.sync.error("WebSocket send error: \(String(describing: error), privacy: .public)")
            }
        }
    }

    // MARK: - Reconnection

    private func handleDisconnect(error: Error?) {
        isConnected = false
        webSocket = nil
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

        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
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

// MARK: - URLSessionWebSocketDelegate

extension WebSocketService: URLSessionWebSocketDelegate {
    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        Task { @MainActor in
            isConnected = true
            reconnectAttempts = 0
            didRetryAfterUnauthorized = false
            Log.sync.debug("WebSocket connected")
            onConnected?()
        }
    }

    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task { @MainActor in
            let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "unknown"
            Log.sync.debug("WebSocket closed: \(closeCode.rawValue) - \(reasonString, privacy: .public)")
            handleDisconnect(error: nil)
        }
    }

    /// A failed handshake (before any WebSocket-specific delegate callback fires)
    /// surfaces here — e.g. the server rejected the upgrade with 401. Other
    /// completions (including our own `disconnect()` cancelling the task) are left
    /// to `didCloseWith`/`receive`'s failure branch, which already drive the normal
    /// reconnect flow — this handler only adds the 401-retry-once behavior.
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, (task.response as? HTTPURLResponse)?.statusCode == 401 else { return }
        Task { @MainActor in
            await handleUnauthorizedHandshake(error: error)
        }
    }
}
