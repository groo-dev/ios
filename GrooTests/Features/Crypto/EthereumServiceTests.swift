//
//  EthereumServiceTests.swift
//  GrooTests
//
//  JSON-RPC parsing (incl. >UInt64 balances), error matrix, Blockscout filtering.
//

import Foundation
import Testing
@testable import Groo

extension NetworkStubbedSuites {
@Suite(.serialized)
struct EthereumServiceTests {
    static func makeService() -> EthereumService {
        EthereumService(sessionConfiguration: StubURLProtocol.stubbedConfiguration())
    }

    static func stubRPC(result: String?, error: (code: Int, message: String)? = nil) {
        var body = #"{"jsonrpc":"2.0","id":1"#
        if let result { body += #","result":"\#(result)""# }
        if let error { body += #","error":{"code":\#(error.code),"message":"\#(error.message)"}"# }
        body += "}"
        StubURLProtocol.enqueue(method: "POST", pathSuffix: "", json: body)
    }

    /// Decode the JSON-RPC body of the most recent recorded POST.
    static func lastRPCBody() throws -> [String: Any] {
        guard let request = StubURLProtocol.recordedRequests.last(where: { $0.httpMethod == "POST" }) else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "No POST request found"])
        }
        guard let data = request.bodyData else {
            throw NSError(domain: "test", code: 2, userInfo: [NSLocalizedDescriptionKey: "No request body"])
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "test", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON"])
        }
        return json
    }

    // MARK: - getEthBalance / hex parsing

    @Test func balanceParsesOneEth() async throws {
        StubURLProtocol.reset()
        Self.stubRPC(result: "0xde0b6b3a7640000")  // 10^18 wei
        let balance = try await Self.makeService().getEthBalance(address: "0xabc")
        #expect(balance == 1.0)
        let body = try Self.lastRPCBody()
        #expect(body["method"] as? String == "eth_getBalance")
        #expect((body["params"] as? [Any])?.first as? String == "0xabc")
    }

    @Test func balanceParsesZeroAndEmptyHex() async throws {
        StubURLProtocol.reset()
        Self.stubRPC(result: "0x0")
        #expect(try await Self.makeService().getEthBalance(address: "0xabc") == 0)

        StubURLProtocol.reset()
        Self.stubRPC(result: "0x")
        #expect(try await Self.makeService().getEthBalance(address: "0xabc") == 0)
    }

    /// 1000 ETH in wei = 10^21 — overflows UInt64; exercises the Decimal path.
    @Test func balanceParsesBeyondUInt64() async throws {
        StubURLProtocol.reset()
        Self.stubRPC(result: "0x3635c9adc5dea00000")
        let balance = try await Self.makeService().getEthBalance(address: "0xabc")
        #expect(abs(balance - 1000.0) < 0.0000001)
    }

    @Test func invalidHexBalanceThrowsInvalidResponse() async {
        StubURLProtocol.reset()
        Self.stubRPC(result: "0xNOTHEX")
        await #expect(throws: EthereumError.self) {
            _ = try await Self.makeService().getEthBalance(address: "0xabc")
        }
    }

    // MARK: - RPC error matrix

    @Test func rpcErrorObjectSurfacesMessage() async {
        StubURLProtocol.reset()
        Self.stubRPC(result: nil, error: (code: -32000, message: "insufficient funds"))
        await #expect {
            _ = try await Self.makeService().getEthBalance(address: "0xabc")
        } throws: { error in
            guard case EthereumError.rpcError(let message) = error else { return false }
            return message == "insufficient funds"
        }
    }

    @Test func missingResultThrowsInvalidResponse() async {
        StubURLProtocol.reset()
        Self.stubRPC(result: nil)
        await #expect {
            _ = try await Self.makeService().getEthBalance(address: "0xabc")
        } throws: { error in
            guard case EthereumError.invalidResponse = error else { return false }
            return true
        }
    }

    @Test func httpFailureThrowsHttpError() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "POST", pathSuffix: "", status: 503, json: "busy")
        await #expect {
            _ = try await Self.makeService().getEthBalance(address: "0xabc")
        } throws: { error in
            guard case EthereumError.httpError = error else { return false }
            return true
        }
    }

    @Test func malformedRPCJsonThrows() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "POST", pathSuffix: "", json: "not json")
        await #expect(throws: (any Error).self) {
            _ = try await Self.makeService().getEthBalance(address: "0xabc")
        }
    }

    // MARK: - Transactions / gas

    @Test func sendRawTransactionPrefixesHexAndReturnsHash() async throws {
        StubURLProtocol.reset()
        Self.stubRPC(result: "0xtxhash")
        let hash = try await Self.makeService().sendRawTransaction(signedTx: "f86c0a85...")
        #expect(hash == "0xtxhash")
        let body = try Self.lastRPCBody()
        #expect(body["method"] as? String == "eth_sendRawTransaction")
        #expect((body["params"] as? [Any])?.first as? String == "0xf86c0a85...")
    }

    @Test func sendRawTransactionKeepsExistingPrefix() async throws {
        StubURLProtocol.reset()
        Self.stubRPC(result: "0xtxhash")
        _ = try await Self.makeService().sendRawTransaction(signedTx: "0xf86c")
        let body = try Self.lastRPCBody()
        #expect((body["params"] as? [Any])?.first as? String == "0xf86c")
    }

    @Test func gasAndNonceCallsUseCorrectMethods() async throws {
        StubURLProtocol.reset()
        Self.stubRPC(result: "0x5208")
        #expect(try await Self.makeService().estimateGas(from: "0xa", to: "0xb", value: "0x0") == "0x5208")
        #expect(try Self.lastRPCBody()["method"] as? String == "eth_estimateGas")

        StubURLProtocol.reset()
        Self.stubRPC(result: "0x3b9aca00")
        #expect(try await Self.makeService().getGasPrice() == "0x3b9aca00")
        #expect(try Self.lastRPCBody()["method"] as? String == "eth_gasPrice")

        StubURLProtocol.reset()
        Self.stubRPC(result: "0x2a")
        #expect(try await Self.makeService().getTransactionCount(address: "0xa") == "0x2a")
        #expect(try Self.lastRPCBody()["method"] as? String == "eth_getTransactionCount")
    }

    // MARK: - Blockscout token discovery

    @Test func tokenBalancesFilterToNonZeroErc20() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/api", json: #"""
        {"message":"OK","status":"1","result":[
          {"balance":"1000","contractAddress":"0xaaa","decimals":"18","name":"TokenA","symbol":"TKA","type":"ERC-20"},
          {"balance":"0","contractAddress":"0xbbb","decimals":"18","name":"TokenB","symbol":"TKB","type":"ERC-20"},
          {"balance":"5","contractAddress":"0xccc","decimals":"0","name":"NFT","symbol":"NFT","type":"ERC-721"}
        ]}
        """#)

        let tokens = try await Self.makeService().getTokenBalances(address: "0xabc")

        #expect(tokens.map(\.contractAddress) == ["0xaaa"])
    }

    @Test func blockscoutHttpErrorThrows() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/api", status: 502, json: "")
        await #expect {
            _ = try await Self.makeService().getTokenBalances(address: "0xabc")
        } throws: { error in
            guard case EthereumError.httpError = error else { return false }
            return true
        }
    }
}
}
