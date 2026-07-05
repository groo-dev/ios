//
//  WebSocketServiceTests.swift
//  GrooTests
//
//  Connect/drop/reconnect state machine over a scripted fake socket:
//  backoff schedule, give-up cap, 401 refresh-retry-once, ping/pong,
//  message dispatch. No real sockets, no waits — timers fire manually.
//

import Foundation
import Testing
@testable import Groo

@MainActor
struct WebSocketServiceTests {
    struct Env {
        let service: WebSocketService
        let auth: FakeTokenProvider
        let factory: FakeConnectionFactory
        let timers: TimerRecorder
    }

    static func makeEnv() -> Env {
        let auth = FakeTokenProvider()
        let factory = FakeConnectionFactory()
        let timers = TimerRecorder()
        let service = WebSocketService(
            authService: auth,
            makeConnection: { factory.make($0) },
            makeTimer: { timers.make(interval: $0, repeats: $1, block: $2) }
        )
        return Env(service: service, auth: auth, factory: factory, timers: timers)
    }

    /// connect() + complete the handshake on the first fake connection.
    static func makeConnectedEnv() async -> (Env, FakeWebSocketConnection) {
        let env = makeEnv()
        await env.service.connect()
        let connection = env.factory.connections[0]
        connection.open()
        return (env, connection)
    }

    // MARK: - Connect

    @Test func connectAttachesBearerTokenAndOpensToConnected() async {
        let env = Self.makeEnv()

        await env.service.connect()

        #expect(env.factory.requests.count == 1)
        #expect(env.factory.requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer tok-1")
        #expect(env.factory.requests[0].url?.path == "/v1/ws")
        #expect(env.factory.connections[0].resumeCalls == 1)
        #expect(!env.service.isConnected)   // handshake hasn't completed yet

        var connectedFired = false
        env.service.onConnected = { connectedFired = true }
        env.factory.connections[0].open()

        #expect(env.service.isConnected)
        #expect(connectedFired)
    }

    @Test func tokenFailureAbortsConnect() async {
        let env = Self.makeEnv()
        env.auth.accessTokenError = URLError(.userAuthenticationRequired)

        await env.service.connect()

        #expect(env.factory.connections.isEmpty)
        #expect(!env.service.isConnected)
    }

    // MARK: - Message dispatch

    @Test func scratchpadEventsInvokeCallbacksWithId() async {
        let (env, connection) = await Self.makeConnectedEnv()

        let updated = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            env.service.onScratchpadUpdated = { continuation.resume(returning: $0) }
            connection.deliver(#"{"type":"scratchpad_updated","scratchpadId":"sp-1","timestamp":1}"#)
        }
        #expect(updated == "sp-1")

        let created = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            env.service.onScratchpadCreated = { continuation.resume(returning: $0) }
            connection.deliver(#"{"type":"scratchpad_created","scratchpadId":"sp-2"}"#)
        }
        #expect(created == "sp-2")

        let deleted = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            env.service.onScratchpadDeleted = { continuation.resume(returning: $0) }
            connection.deliver(#"{"type":"scratchpad_deleted","scratchpadId":"sp-3"}"#)
        }
        #expect(deleted == "sp-3")
    }

    @Test func malformedAndBinaryFramesAreHandledSafely() async {
        let (env, connection) = await Self.makeConnectedEnv()

        var unexpectedCallbacks = 0
        env.service.onScratchpadUpdated = { _ in unexpectedCallbacks += 1 }
        env.service.onScratchpadDeleted = { _ in unexpectedCallbacks += 1 }

        connection.deliver("not json at all")
        connection.deliver(data: Data([0xFF, 0xFE]))   // invalid UTF-8

        // Binary frames containing valid JSON are parsed (the .data path).
        // Frames are FIFO: once this callback fires, the garbage frames above
        // have already been (safely) dropped.
        let created = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            env.service.onScratchpadCreated = { continuation.resume(returning: $0) }
            connection.deliver(data: Data(#"{"type":"scratchpad_created","scratchpadId":"sp-2"}"#.utf8))
        }

        #expect(created == "sp-2")
        #expect(unexpectedCallbacks == 0)
        #expect(env.service.isConnected)   // garbage frames don't drop the connection
    }

    // MARK: - Ping/pong

    @Test func serverPingIsAnsweredWithPong() async throws {
        let (env, connection) = await Self.makeConnectedEnv()

        connection.deliver(#"{"type":"ping","timestamp":1}"#)
        // Frames are processed FIFO on the main actor: once the follow-up
        // message's callback fires, the pong for the ping was already sent.
        _ = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            env.service.onScratchpadUpdated = { continuation.resume(returning: $0) }
            connection.deliver(#"{"type":"scratchpad_updated","scratchpadId":"sp-1"}"#)
        }

        let sent = try #require(connection.sentTexts.first)
        let message = try JSONDecoder().decode(WebSocketMessage.self, from: Data(sent.utf8))
        #expect(message.type == .pong)
    }

    @Test func pingTimerSendsPing() async throws {
        let (env, connection) = await Self.makeConnectedEnv()
        #expect(env.timers.pingIntervals == [30])

        env.timers.fireLastPing()

        let sent = try #require(connection.sentTexts.last)
        let message = try JSONDecoder().decode(WebSocketMessage.self, from: Data(sent.utf8))
        #expect(message.type == .ping)
    }

    // MARK: - Drop → reconnect

    @Test func dropSchedulesReconnectAndTimerFireReconnects() async {
        let (env, connection) = await Self.makeConnectedEnv()

        var disconnected = false
        env.service.onDisconnected = { _ in disconnected = true }
        connection.close()

        #expect(disconnected)
        #expect(!env.service.isConnected)
        #expect(env.timers.reconnectDelays == [2.0])   // 2^1 for attempt 1

        let second = await env.factory.connectionCreated {
            env.timers.fireLastReconnect()
        }
        #expect(second.resumeCalls == 1)

        second.open()
        #expect(env.service.isConnected)
    }

    @Test func receiveFailureAlsoTriggersReconnect() async {
        let (env, connection) = await Self.makeConnectedEnv()

        let error = await withCheckedContinuation { (continuation: CheckedContinuation<(any Error)?, Never>) in
            env.service.onDisconnected = { continuation.resume(returning: $0) }
            connection.failReceive(URLError(.networkConnectionLost))
        }

        #expect(error != nil)
        #expect(!env.service.isConnected)
        #expect(env.timers.reconnectDelays == [2.0])
    }

    @Test func backoffDoublesAndGivesUpAfterFiveAttempts() async {
        let (env, connection) = await Self.makeConnectedEnv()

        var latest = connection
        latest.close()
        for _ in 0..<5 {
            latest = await env.factory.connectionCreated {
                env.timers.fireLastReconnect()
            }
            latest.close()   // every attempt fails before opening
        }

        #expect(env.timers.reconnectDelays == [2.0, 4.0, 8.0, 16.0, 30.0])   // capped at 30s
        #expect(env.factory.connections.count == 6)   // initial + 5 attempts
        // After the 5th failed attempt the service gave up — no 6th timer
        #expect(env.timers.reconnectDelays.count == 5)
    }

    @Test func successfulReconnectResetsBackoff() async {
        let (env, connection) = await Self.makeConnectedEnv()

        connection.close()
        #expect(env.timers.reconnectDelays == [2.0])

        let second = await env.factory.connectionCreated {
            env.timers.fireLastReconnect()
        }
        second.open()   // resets reconnectAttempts

        second.close()
        #expect(env.timers.reconnectDelays == [2.0, 2.0])   // back to attempt 1
    }

    // MARK: - 401 handshake → refresh-retry-once

    @Test func handshake401ForcesOneRefreshAndRetries() async {
        let env = Self.makeEnv()
        await env.service.connect()

        let second = await env.factory.connectionCreated {
            env.factory.connections[0].failHandshake(statusCode: 401)
        }

        #expect(env.auth.forceRefreshCalls == 1)
        #expect(env.factory.requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer tok-2")

        second.open()
        #expect(env.service.isConnected)
    }

    @Test func second401GivesUpWithDisconnect() async {
        let env = Self.makeEnv()
        await env.service.connect()

        let second = await env.factory.connectionCreated {
            env.factory.connections[0].failHandshake(statusCode: 401)
        }

        let error = await withCheckedContinuation { (continuation: CheckedContinuation<(any Error)?, Never>) in
            env.service.onDisconnected = { continuation.resume(returning: $0) }
            second.failHandshake(statusCode: 401)
        }

        #expect(error != nil)
        #expect(env.auth.forceRefreshCalls == 1)          // refreshed exactly once
        #expect(env.factory.connections.count == 2)       // no third attempt
    }

    @Test func refreshFailureSurfacesAsDisconnect() async {
        let env = Self.makeEnv()
        env.auth.forceRefreshError = URLError(.badServerResponse)
        await env.service.connect()

        let error = await withCheckedContinuation { (continuation: CheckedContinuation<(any Error)?, Never>) in
            env.service.onDisconnected = { continuation.resume(returning: $0) }
            env.factory.connections[0].failHandshake(statusCode: 401)
        }

        #expect(error != nil)
        #expect(env.auth.forceRefreshCalls == 1)
        #expect(env.factory.connections.count == 1)   // no retry connection
    }

    @Test func non401HandshakeFailureDoesNotTriggerRefresh() async {
        let env = Self.makeEnv()
        await env.service.connect()

        env.factory.connections[0].failHandshake(statusCode: 503, error: URLError(.badServerResponse))

        // Non-401 completions are ignored by the handshake handler (the
        // receive-failure/close paths own normal reconnects) — synchronous
        // guard, so nothing is pending after this returns.
        #expect(env.auth.forceRefreshCalls == 0)
        #expect(env.factory.connections.count == 1)
    }

    // MARK: - Disconnect

    @Test func disconnectCancelsGoingAwayAndAllowsFreshConnect() async {
        let (env, connection) = await Self.makeConnectedEnv()

        env.service.disconnect()

        #expect(connection.cancelledWith == .goingAway)
        #expect(!env.service.isConnected)
        #expect(env.timers.reconnectDelays.isEmpty)   // clean disconnect never reconnects

        await env.service.connect()
        #expect(env.factory.connections.count == 2)
    }
}
