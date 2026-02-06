//
//  EthereumService.swift
//  Groo
//
//  Ethereum on-chain data via public RPC + Blockscout block explorer API.
//  No API keys or signups needed.
//
//  - Public RPC (Cloudflare): standard JSON-RPC (balances, gas, send tx)
//  - Blockscout: token discovery (all ERC-20 balances for an address)
//

import Foundation
import os

actor EthereumService {
    private let logger = Logger(subsystem: "dev.groo.ios", category: "EthereumService")
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }

    // MARK: - ETH Balance (Public RPC)

    /// Get ETH balance for an address
    func getEthBalance(address: String) async throws -> Double {
        let request = EthRPCRequest(method: "eth_getBalance", params: [address, "latest"])
        let response: EthRPCResponse = try await performRPC(request)

        if let error = response.error {
            logger.error("eth_getBalance RPC error: \(error.message)")
            throw EthereumError.rpcError(error.message)
        }

        guard let hexBalance = response.result else {
            throw EthereumError.invalidResponse
        }

        return hexToEth(hexBalance)
    }

    // MARK: - Token Balances (Blockscout)

    /// Get all ERC-20 token balances for an address via Blockscout
    func getTokenBalances(address: String) async throws -> [BlockscoutTokenBalance] {
        var components = URLComponents(url: Config.blockscoutBaseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "module", value: "account"),
            URLQueryItem(name: "action", value: "tokenlist"),
            URLQueryItem(name: "address", value: address),
        ]

        let (data, response) = try await session.data(from: components.url!)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            logger.error("Blockscout request failed with HTTP \(statusCode)")
            throw EthereumError.httpError
        }

        let result = try decoder.decode(BlockscoutResponse<[BlockscoutTokenBalance]>.self, from: data)

        // Filter to ERC-20 tokens with non-zero balance
        return result.result.filter { token in
            token.type == "ERC-20" && token.balance != "0"
        }
    }

    // MARK: - Transaction (Public RPC)

    /// Send a signed raw transaction
    func sendRawTransaction(signedTx: String) async throws -> String {
        let hex = signedTx.hasPrefix("0x") ? signedTx : "0x" + signedTx
        let request = EthRPCRequest(method: "eth_sendRawTransaction", params: [hex])
        let response: EthRPCResponse = try await performRPC(request)

        if let error = response.error {
            throw EthereumError.rpcError(error.message)
        }

        guard let txHash = response.result else {
            throw EthereumError.invalidResponse
        }

        return txHash
    }

    // MARK: - Gas (Public RPC)

    /// Estimate gas for a transaction
    func estimateGas(from: String, to: String, value: String, data: String = "0x") async throws -> String {
        let params: [String: String] = ["from": from, "to": to, "value": value, "data": data]
        let request = EthRPCRequest(method: "eth_estimateGas", params: [params])
        let response: EthRPCResponse = try await performRPC(request)

        if let error = response.error {
            throw EthereumError.rpcError(error.message)
        }

        guard let gas = response.result else {
            throw EthereumError.invalidResponse
        }

        return gas
    }

    /// Get current gas price
    func getGasPrice() async throws -> String {
        let request = EthRPCRequest(method: "eth_gasPrice", params: [])
        let response: EthRPCResponse = try await performRPC(request)

        if let error = response.error {
            throw EthereumError.rpcError(error.message)
        }

        guard let gasPrice = response.result else {
            throw EthereumError.invalidResponse
        }

        return gasPrice
    }

    /// Get transaction count (nonce) for an address
    func getTransactionCount(address: String) async throws -> String {
        let request = EthRPCRequest(method: "eth_getTransactionCount", params: [address, "latest"])
        let response: EthRPCResponse = try await performRPC(request)

        if let error = response.error {
            throw EthereumError.rpcError(error.message)
        }

        guard let count = response.result else {
            throw EthereumError.invalidResponse
        }

        return count
    }

    // MARK: - Private

    private func performRPC<T: Decodable>(_ rpcRequest: EthRPCRequest) async throws -> T {
        var urlRequest = URLRequest(url: Config.ethereumRPCURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try encoder.encode(rpcRequest)

        logger.debug("RPC \(rpcRequest.method) → \(Config.ethereumRPCURL)")

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            logger.error("RPC \(rpcRequest.method) HTTP \(statusCode): \(body)")
            throw EthereumError.httpError
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            logger.error("RPC \(rpcRequest.method) decode failed: \(error.localizedDescription) body: \(body)")
            throw error
        }
    }

    private func hexToEth(_ hex: String) -> Double {
        let cleanHex = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        guard !cleanHex.isEmpty else { return 0 }
        // Parse hex digit by digit into Decimal to avoid UInt64 overflow (>18.4 ETH)
        var wei = Decimal(0)
        for char in cleanHex {
            guard let digit = UInt8(String(char), radix: 16) else { return 0 }
            wei = wei * 16 + Decimal(digit)
        }
        let eth = wei / Decimal(sign: .plus, exponent: 18, significand: 1)
        return NSDecimalNumber(decimal: eth).doubleValue
    }
}

// MARK: - Errors

enum EthereumError: Error, LocalizedError {
    case invalidResponse
    case httpError
    case rpcError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Invalid RPC response"
        case .httpError: "Network error"
        case .rpcError(let msg): "RPC error: \(msg)"
        }
    }
}
