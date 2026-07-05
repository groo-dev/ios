# iOS Test Suite — Phase 2 (Wallet) + Phase 1 Fast-Follows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Test the crypto-wallet layer (APICache, EthereumService, CoinGeckoService, WalletManager) and close the Phase 1 review's deferred gaps in PassService integration coverage (folders, per-type lifecycle, toggleFavorite, biometric-offline proof).

**Architecture:** Same retrofit pattern as Phase 1: default-parameter injection seams (session configuration, cache instance, sleep function, UserDefaults), stubbed network via the existing `StubURLProtocol`, and reuse of the Task-10 `PassServiceIntegrationTests.makeEnv` environment for anything needing an unlocked vault. All suites touching `StubURLProtocol` nest under the `NetworkStubbedSuites` serialized umbrella.

**Tech Stack:** Swift Testing; web3swift/BigInt (already SPM dependencies of the app — tests exercise our usage, not the library); `xcodebuild` via `scripts/test.sh`.

**Spec:** `docs/superpowers/specs/2026-07-05-ios-test-suite-design.md` (Phase 2 section + Phase 1 leftovers listed in the final Phase 1 review).

## Global Constraints

- Working directory: `/Users/groo/work/gr/ios`. Test runner: `bash scripts/test.sh --unit` → `** TEST SUCCEEDED **`.
- GrooTests uses synchronized folders — new `.swift` files under `GrooTests/` compile automatically; never edit the pbxproj.
- Every production change is a default-parameter injection seam; default value must preserve current behavior byte-for-byte. No other production edits.
- Suites that use `StubURLProtocol` MUST be declared inside `extension NetworkStubbedSuites { ... }` (see `GrooTests/Support/NetworkStubbedSuites.swift`) and call `StubURLProtocol.reset()` first in each test — cross-suite races otherwise.
- No sleeps in tests. `CoinGeckoService`'s retry sleep is made injectable for exactly this reason.
- Never use production KDF iterations in tests (existing `makeEnv` already uses 1,000).
- Third-party code (web3swift, BigInt) is not under test — we test our usage of it. BIP39/address vectors: compare addresses case-insensitively (`lowercased()`) to stay independent of EIP-55 checksum casing.
- UserDefaults in tests: use `UserDefaults(suiteName:)` instances wiped with `removePersistentDomain(forName:)` — never `UserDefaults.standard`.
- Before each commit: `bash scripts/test.sh --unit` green AND app builds.

---

### Task 1: APICache session seam + cache-semantics tests

**Files:**
- Modify: `Groo/Core/Network/APICache.swift:37-42` (init)
- Test: `GrooTests/Core/Network/APICacheTests.swift`

**Interfaces:**
- Consumes: `StubURLProtocol` (`.reset()`, `.enqueue(method:pathSuffix:status:json:)`, `.enqueue(method:pathSuffix:error:)`, `.recordedRequests`, `.stubbedConfiguration()`); `APICacheError.httpError(statusCode:data:)`.
- Produces: `APICache.init(sessionConfiguration: URLSessionConfiguration = .default)` — Task 3 constructs `APICache(sessionConfiguration: StubURLProtocol.stubbedConfiguration())`.

**Spec note:** the spec's Phase 2 bullet "API-down fallback to cache" does not exist in production — `APICache.fetch` throws on failure and never serves a stale entry. The `httpErrorSurfacesAndIsNotCached` test documents the actual semantics. Building stale-fallback would be a product change, out of scope for a test retrofit; flag it to the user in the final report rather than testing behavior that isn't there.

- [ ] **Step 1: Write the failing tests**

`GrooTests/Core/Network/APICacheTests.swift`:

```swift
//
//  APICacheTests.swift
//  GrooTests
//
//  Cache hit/expiry, forceRefresh, in-flight dedup, error-not-cached, clear.
//  Uses fresh APICache instances (never .shared) against StubURLProtocol.
//

import Foundation
import Testing
@testable import Groo

extension NetworkStubbedSuites {
@Suite(.serialized)
struct APICacheTests {
    static let url = URL(string: "https://api.test/prices/eth")!

    static func makeCache() -> APICache {
        APICache(sessionConfiguration: StubURLProtocol.stubbedConfiguration())
    }

    @Test func cacheHitWithinTtlSkipsNetwork() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/prices/eth", json: #"{"v":1}"#)
        let cache = Self.makeCache()

        let first = try await cache.fetch(Self.url, ttl: 300)
        let second = try await cache.fetch(Self.url, ttl: 300)

        #expect(first == second)
        #expect(StubURLProtocol.recordedRequests.count == 1)
    }

    @Test func zeroTtlAlwaysRefetches() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/prices/eth", json: #"{"v":1}"#)
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/prices/eth", json: #"{"v":2}"#)
        let cache = Self.makeCache()

        let first = try await cache.fetch(Self.url, ttl: 0)
        let second = try await cache.fetch(Self.url, ttl: 0)

        #expect(first != second)
        #expect(StubURLProtocol.recordedRequests.count == 2)
    }

    @Test func forceRefreshBypassesFreshCache() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/prices/eth", json: #"{"v":1}"#)
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/prices/eth", json: #"{"v":2}"#)
        let cache = Self.makeCache()

        _ = try await cache.fetch(Self.url, ttl: 300)
        let refreshed = try await cache.fetch(Self.url, ttl: 300, forceRefresh: true)

        #expect(refreshed == Data(#"{"v":2}"#.utf8))
        #expect(StubURLProtocol.recordedRequests.count == 2)
    }

    @Test func concurrentFetchesShareOneRequest() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/prices/eth", json: #"{"v":1}"#)
        let cache = Self.makeCache()

        async let a = cache.fetch(Self.url, ttl: 300)
        async let b = cache.fetch(Self.url, ttl: 300)
        let (ra, rb) = try await (a, b)

        #expect(ra == rb)
        // In-flight dedup (or cache hit if the first finished first) — never 2 requests.
        #expect(StubURLProtocol.recordedRequests.count == 1)
    }

    @Test func httpErrorSurfacesAndIsNotCached() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/prices/eth", status: 500, json: #"{"err":true}"#)
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/prices/eth", json: #"{"v":1}"#)
        let cache = Self.makeCache()

        await #expect {
            _ = try await cache.fetch(Self.url, ttl: 300)
        } throws: { error in
            guard case APICacheError.httpError(let status, _) = error else { return false }
            return status == 500
        }

        // Failure was not cached — next fetch goes to network and succeeds
        let recovered = try await cache.fetch(Self.url, ttl: 300)
        #expect(recovered == Data(#"{"v":1}"#.utf8))
        #expect(StubURLProtocol.recordedRequests.count == 2)
    }

    @Test func transportErrorPropagates() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/prices/eth", error: URLError(.timedOut))
        let cache = Self.makeCache()
        await #expect(throws: (any Error).self) { _ = try await cache.fetch(Self.url, ttl: 300) }
    }

    @Test func clearAllEvictsEverything() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/prices/eth", json: #"{"v":1}"#)
        let cache = Self.makeCache()

        _ = try await cache.fetch(Self.url, ttl: 300)
        await cache.clearAll()
        _ = try await cache.fetch(Self.url, ttl: 300)

        #expect(StubURLProtocol.recordedRequests.count == 2)
    }

    @Test func clearMatchingEvictsSelectively() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/prices/eth", json: #"{"v":1}"#)
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/prices/btc", json: #"{"v":9}"#)
        let btcURL = URL(string: "https://api.test/prices/btc")!
        let cache = Self.makeCache()

        _ = try await cache.fetch(Self.url, ttl: 300)
        _ = try await cache.fetch(btcURL, ttl: 300)
        await cache.clear { $0.contains("eth") }
        _ = try await cache.fetch(btcURL, ttl: 300)   // still cached — no request
        _ = try await cache.fetch(Self.url, ttl: 300) // evicted — refetches

        #expect(StubURLProtocol.recordedRequests.count == 3)
    }
}
}
```

- [ ] **Step 2: Run to verify failure**

Run: `bash scripts/test.sh --unit 2>&1 | tail -20`
Expected: BUILD FAILURE — `argument passed to call that takes no arguments` (APICache has no `sessionConfiguration` init param yet).

- [ ] **Step 3: Add the seam**

In `Groo/Core/Network/APICache.swift`, replace the init (lines 37–42) with:

```swift
    init(sessionConfiguration: URLSessionConfiguration = .default) {
        let config = sessionConfiguration
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config)
    }
```

- [ ] **Step 4: Run to verify pass**

Run: `bash scripts/test.sh --unit 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Groo/Core/Network/APICache.swift GrooTests
git commit -m "test: APICache suite (hit/expiry/dedup/error-not-cached); inject session configuration"
```

---

### Task 2: EthereumService session seam + stubbed-RPC tests

**Files:**
- Modify: `Groo/Features/Crypto/Services/EthereumService.swift:21-28` (init)
- Test: `GrooTests/Features/Crypto/EthereumServiceTests.swift`

**Interfaces:**
- Consumes: `StubURLProtocol` + `URLRequest.bodyData`; `EthereumError`; `BlockscoutTokenBalance`.
- Produces: `EthereumService.init(sessionConfiguration: URLSessionConfiguration = .default)`.

**Note:** all JSON-RPC calls POST to `Config.ethereumRPCURL` (path `""`), so RPC stubs use `pathSuffix: ""`. Blockscout calls GET `…/api`, so those use `pathSuffix: "/api"`. To assert which RPC method was sent, decode the recorded request body.

- [ ] **Step 1: Write the failing tests**

`GrooTests/Features/Crypto/EthereumServiceTests.swift`:

```swift
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
        let request = try #require(StubURLProtocol.recordedRequests.last { $0.httpMethod == "POST" })
        let data = try #require(request.bodyData)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
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
```

- [ ] **Step 2: Run to verify failure**

Run: `bash scripts/test.sh --unit 2>&1 | tail -20`
Expected: BUILD FAILURE — EthereumService has no `sessionConfiguration` init param.

- [ ] **Step 3: Add the seam**

In `Groo/Features/Crypto/Services/EthereumService.swift`, replace the init (lines 21–28) with:

```swift
    init(sessionConfiguration: URLSessionConfiguration = .default) {
        let config = sessionConfiguration
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }
```

- [ ] **Step 4: Run to verify pass**

Run: `bash scripts/test.sh --unit 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Groo/Features/Crypto/Services/EthereumService.swift GrooTests
git commit -m "test: EthereumService stubbed-RPC suite (hex parsing, error matrix, Blockscout filter); inject session"
```

---

### Task 3: CoinGeckoService cache + sleep seams, retry/backoff tests

**Files:**
- Modify: `Groo/Features/Crypto/Services/CoinGeckoService.swift:21-23` (init), `:34,40` (sleep call sites), `:62,83,107,148` (`APICache.shared` → `cache`)
- Test: `GrooTests/Features/Crypto/CoinGeckoServiceTests.swift`

**Interfaces:**
- Consumes: `APICache(sessionConfiguration:)` from Task 1; `StubURLProtocol`; `CoinGeckoError`; `PricePoint`, `CoinGeckoSimplePrice`, `TokenPriceResult`.
- Produces: `CoinGeckoService.init(cache: APICache = .shared, sleep: @escaping @Sendable (Double) async throws -> Void = { try await Task.sleep(for: .seconds($0)) })`.

- [ ] **Step 1: Add the seams**

In `Groo/Features/Crypto/Services/CoinGeckoService.swift`:

Replace the stored properties + init (lines 12–23 region) so the actor holds the injected dependencies:

```swift
actor CoinGeckoService {
    private let logger = Logger(subsystem: "dev.groo.ios", category: "CoinGeckoService")
    private let decoder: JSONDecoder
    private let cache: APICache
    private let sleep: @Sendable (Double) async throws -> Void

    private let baseURL = URL(string: "https://api.coingecko.com/api/v3")!

    private let priceTTL: TimeInterval = 300    // 5 minutes
    private let chartTTL: TimeInterval = 900    // 15 minutes

    init(
        cache: APICache = .shared,
        sleep: @escaping @Sendable (Double) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    ) {
        self.decoder = JSONDecoder()
        self.cache = cache
        self.sleep = sleep
    }
```

In `withRetry`, replace both `try await Task.sleep(for: .seconds(delay))` lines with:

```swift
                try await sleep(delay)
```

Replace all four `APICache.shared.fetch(` call sites with `self.cache.fetch(`.

- [ ] **Step 2: Verify the app still builds (behavior-preserving check)**

Run: `xcodebuild build -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Write the tests**

`GrooTests/Features/Crypto/CoinGeckoServiceTests.swift`:

```swift
//
//  CoinGeckoServiceTests.swift
//  GrooTests
//
//  Retry/backoff (recorded, not slept), 429 mapping, decode, partial failure.
//

import Foundation
import Testing
@testable import Groo

extension NetworkStubbedSuites {
@Suite(.serialized)
struct CoinGeckoServiceTests {

    /// Records backoff delays instead of sleeping — the no-sleeps rule.
    final class SleepRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _delays: [Double] = []
        var delays: [Double] { lock.lock(); defer { lock.unlock() }; return _delays }
        func record(_ delay: Double) { lock.lock(); defer { lock.unlock() }; _delays.append(delay) }
    }

    static func makeService() -> (service: CoinGeckoService, sleeps: SleepRecorder) {
        let recorder = SleepRecorder()
        let cache = APICache(sessionConfiguration: StubURLProtocol.stubbedConfiguration())
        let service = CoinGeckoService(cache: cache) { recorder.record($0) }
        return (service, recorder)
    }

    static let ethPriceJSON = #"{"ethereum":{"usd":2000.5,"usd_24h_change":-1.2}}"#

    // MARK: - Happy-path decoding

    @Test func ethPriceDecodes() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/simple/price", json: Self.ethPriceJSON)
        let (service, sleeps) = Self.makeService()

        let price = try await service.getEthPrice()

        #expect(price.usd == 2000.5)
        #expect(price.usd_24h_change == -1.2)
        #expect(sleeps.delays.isEmpty)
    }

    @Test func marketChartMapsTimestampsAndPrices() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/market_chart",
                                json: #"{"prices":[[1700000000000,2000.5],[1700000060000,2001.0]]}"#)
        let (service, _) = Self.makeService()

        let points = try await service.getMarketChart(coinId: "ethereum", days: 1)

        #expect(points.count == 2)
        #expect(points[0].timestamp == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(points[0].price == 2000.5)
        #expect(points[1].price == 2001.0)
    }

    @Test func missingEthereumKeyThrowsInvalidResponse() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/simple/price", json: "{}")
        let (service, _) = Self.makeService()
        await #expect {
            _ = try await service.getEthPrice()
        } throws: { error in
            guard case CoinGeckoError.invalidResponse = error else { return false }
            return true
        }
    }

    // MARK: - Retry / backoff on 429

    @Test func rateLimitRetriesWithExponentialBackoffThenThrows() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/simple/price", status: 429, json: "{}")
        // last-response-repeats: every attempt sees 429
        let (service, sleeps) = Self.makeService()

        await #expect {
            _ = try await service.getEthPrice()
        } throws: { error in
            guard case CoinGeckoError.rateLimited = error else { return false }
            return true
        }

        #expect(sleeps.delays == [1.0, 2.0])                  // 2^0, 2^1 between 3 attempts
        #expect(StubURLProtocol.recordedRequests.count == 3)  // maxAttempts
    }

    @Test func rateLimitRecoversOnLaterAttempt() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/simple/price", status: 429, json: "{}")
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/simple/price", json: Self.ethPriceJSON)
        let (service, sleeps) = Self.makeService()

        let price = try await service.getEthPrice()

        #expect(price.usd == 2000.5)
        #expect(sleeps.delays == [1.0])
    }

    @Test func non429HttpErrorDoesNotRetry() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/simple/price", status: 500, json: "{}")
        let (service, sleeps) = Self.makeService()

        await #expect {
            _ = try await service.getEthPrice()
        } throws: { error in
            guard case CoinGeckoError.httpError(500) = error else { return false }
            return true
        }

        #expect(sleeps.delays.isEmpty)
        #expect(StubURLProtocol.recordedRequests.count == 1)
    }

    // MARK: - Batch token prices

    @Test func emptyContractListIsCompleteWithoutRequests() async {
        StubURLProtocol.reset()
        let (service, _) = Self.makeService()
        let result = await service.getTokenPrices(contracts: [])
        #expect(result.isComplete)
        #expect(result.prices.isEmpty)
        #expect(StubURLProtocol.recordedRequests.isEmpty)
    }

    @Test func partialFailureReportsFailedContracts() async {
        StubURLProtocol.reset()
        // Contracts fetched sequentially → FIFO: first succeeds, second 500s
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/simple/token_price/ethereum",
                                json: #"{"0xaaa":{"usd":5.0,"usd_24h_change":0.1}}"#)
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/simple/token_price/ethereum",
                                status: 500, json: "{}")
        let (service, _) = Self.makeService()

        let result = await service.getTokenPrices(contracts: ["0xAAA", "0xBBB"])

        #expect(result.prices["0xaaa"]?.usd == 5.0)
        #expect(result.isComplete == false)
        #expect(result.failedContracts == ["0xbbb"])
        #expect(result.failureReason != nil)
    }

    @Test func rateLimitShortCircuitsRemainingContracts() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(method: "GET", pathSuffix: "/simple/token_price/ethereum",
                                status: 429, json: "{}")
        // repeats: contract A exhausts 3 attempts; B and C must be skipped entirely
        let (service, sleeps) = Self.makeService()

        let result = await service.getTokenPrices(contracts: ["0xA", "0xB", "0xC"])

        #expect(result.isComplete == false)
        #expect(result.failedContracts == ["0xa", "0xb", "0xc"])
        #expect(StubURLProtocol.recordedRequests.count == 3)  // only contract A's attempts
        #expect(sleeps.delays == [1.0, 2.0])
    }
}
}
```

- [ ] **Step 4: Run to verify pass**

Run: `bash scripts/test.sh --unit 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Groo/Features/Crypto/Services/CoinGeckoService.swift GrooTests
git commit -m "test: CoinGeckoService retry/backoff + decode suite; inject cache and sleep"
```

---

### Task 4: WalletManager UserDefaults seam + wallet tests

**Files:**
- Modify: `Groo/Features/Crypto/Services/WalletManager.swift:21,30-34,38,42,82,87` (defaults injection)
- Test: `GrooTests/Features/Crypto/WalletManagerTests.swift`

**Interfaces:**
- Consumes: `NetworkStubbedSuites.PassServiceIntegrationTests.makeEnv(items:)` + `.stubVaultPut(version:)` + `Env` (from Task 10 of Phase 1 — static, reachable within GrooTests); `WalletError`; `PassCryptoWalletItem`.
- Produces: `WalletManager.init(passService: PassService, defaults: UserDefaults = .standard)`.

**Known BIP39/key vectors used (assert with `.lowercased()` — EIP-55 checksum casing must not matter):**
- Mnemonic `abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about` → first address `0x9858effd232b4033e47d90003d41ec34ecaeda94` (m/44'/60'/0'/0/0, empty passphrase).
- Private key `4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318` → address `0x2c7536e3605d9c16a7a3d7b1898e529396a65c23`.

If a vector assertion fails, print the actual derived address in the failure message and STOP — do not adjust the constant to match; the discrepancy means our derivation-path assumption is wrong and must be reported (this is a crypto wallet; a wrong address constant hides a wrong derivation).

- [ ] **Step 1: Add the seam**

In `Groo/Features/Crypto/Services/WalletManager.swift`:

```swift
    private let passService: PassService
    private let defaults: UserDefaults
```

```swift
    init(passService: PassService, defaults: UserDefaults = .standard) {
        self.passService = passService
        self.defaults = defaults
        loadCachedAddresses()
        resolveActiveAddress()
    }
```

Then replace the four `UserDefaults.standard` usages inside the class (`setActiveAddress`, `resolveActiveAddress`, `loadCachedAddresses`, `saveCachedAddresses`) with `defaults`.

Verify build: `xcodebuild build -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3` → `** BUILD SUCCEEDED **`

- [ ] **Step 2: Write the tests**

`GrooTests/Features/Crypto/WalletManagerTests.swift`:

```swift
//
//  WalletManagerTests.swift
//  GrooTests
//
//  BIP39 import vectors, wallet lifecycle against an unlocked stubbed vault.
//  Vector failures mean a derivation regression — never adjust the constants.
//

import BigInt
import Foundation
import Testing
@testable import Groo

extension NetworkStubbedSuites {
@MainActor
@Suite(.serialized)
struct WalletManagerTests {
    static let vectorMnemonic = "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about"
    static let vectorMnemonicAddress = "0x9858effd232b4033e47d90003d41ec34ecaeda94"
    static let vectorPrivateKey = "4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318"
    static let vectorPrivateKeyAddress = "0x2c7536e3605d9c16a7a3d7b1898e529396a65c23"

    struct WalletEnv {
        let manager: WalletManager
        let env: PassServiceIntegrationTests.Env
        let defaults: UserDefaults
        let suiteName: String
    }

    /// Unlocked PassService (stubbed network) + WalletManager on isolated UserDefaults.
    static func makeWalletEnv() async throws -> WalletEnv {
        let env = try PassServiceIntegrationTests.makeEnv(items: [])
        _ = try await env.service.unlock(password: PassServiceIntegrationTests.password)
        PassServiceIntegrationTests.stubVaultPut(version: 4)

        let suiteName = "WalletManagerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let manager = WalletManager(passService: env.service, defaults: defaults)
        return WalletEnv(manager: manager, env: env, defaults: defaults, suiteName: suiteName)
    }

    static func tearDown(_ walletEnv: WalletEnv) {
        walletEnv.defaults.removePersistentDomain(forName: walletEnv.suiteName)
        try? FileManager.default.removeItem(at: walletEnv.env.tempDir)
    }

    // MARK: - Import vectors

    @Test func importSeedPhraseDerivesKnownAddress() async throws {
        let walletEnv = try await Self.makeWalletEnv()
        defer { Self.tearDown(walletEnv) }

        let address = try await walletEnv.manager.importWallet(seedPhrase: Self.vectorMnemonic)

        #expect(address.lowercased() == Self.vectorMnemonicAddress,
                "BIP39 vector mismatch — derived \(address); derivation path assumption is wrong, STOP and report")
        #expect(walletEnv.manager.walletAddresses.map { $0.lowercased() } == [Self.vectorMnemonicAddress])
        #expect(walletEnv.manager.hasWallets)

        // Vault item stored with the seed phrase and a private key
        let items = walletEnv.manager.getWalletItems()
        #expect(items.count == 1)
        #expect(items.first?.seedPhrase == Self.vectorMnemonic)
        #expect(items.first?.privateKey?.isEmpty == false)
    }

    @Test func importSeedPhraseNormalizesWhitespace() async throws {
        let walletEnv = try await Self.makeWalletEnv()
        defer { Self.tearDown(walletEnv) }

        let messy = "  abandon abandon  abandon\nabandon abandon abandon abandon abandon abandon abandon abandon   about  "
        let address = try await walletEnv.manager.importWallet(seedPhrase: messy)

        #expect(address.lowercased() == Self.vectorMnemonicAddress)
    }

    @Test func importInvalidSeedPhraseThrows() async throws {
        let walletEnv = try await Self.makeWalletEnv()
        defer { Self.tearDown(walletEnv) }
        await #expect(throws: (any Error).self) {
            _ = try await walletEnv.manager.importWallet(seedPhrase: "definitely not a valid mnemonic phrase at all twelve")
        }
        #expect(!walletEnv.manager.hasWallets)
    }

    @Test func importPrivateKeyDerivesKnownAddress() async throws {
        let walletEnv = try await Self.makeWalletEnv()
        defer { Self.tearDown(walletEnv) }

        let address = try await walletEnv.manager.importWallet(privateKey: "0x" + Self.vectorPrivateKey)

        #expect(address.lowercased() == Self.vectorPrivateKeyAddress,
                "private-key vector mismatch — derived \(address); STOP and report")
        // 0x prefix stripped before storage
        #expect(walletEnv.manager.getPrivateKey(for: address) == Self.vectorPrivateKey)
    }

    @Test func importInvalidPrivateKeyThrows() async throws {
        let walletEnv = try await Self.makeWalletEnv()
        defer { Self.tearDown(walletEnv) }
        await #expect {
            _ = try await walletEnv.manager.importWallet(privateKey: "zz-not-hex")
        } throws: { error in
            guard case WalletError.invalidPrivateKey = error else { return false }
            return true
        }
    }

    // MARK: - Create

    @Test func createWalletProducesReimportableMnemonic() async throws {
        let walletEnv = try await Self.makeWalletEnv()
        defer { Self.tearDown(walletEnv) }

        let (mnemonic, address) = try await walletEnv.manager.createWallet()

        #expect(mnemonic.split(separator: " ").count == 12)   // 128 bits of entropy
        #expect(address.hasPrefix("0x") && address.count == 42)
        #expect(walletEnv.manager.activeAddress == address)

        // Determinism roundtrip: re-importing the mnemonic derives the same address
        let walletEnv2 = try await Self.makeWalletEnv()
        defer { Self.tearDown(walletEnv2) }
        let reimported = try await walletEnv2.manager.importWallet(seedPhrase: mnemonic)
        #expect(reimported.lowercased() == address.lowercased())
    }

    // MARK: - Address cache & active address

    @Test func addressesPersistAcrossManagerInstances() async throws {
        let walletEnv = try await Self.makeWalletEnv()
        defer { Self.tearDown(walletEnv) }
        _ = try await walletEnv.manager.importWallet(seedPhrase: Self.vectorMnemonic)

        // New manager over the same defaults sees the cached address without vault access
        let reborn = WalletManager(passService: walletEnv.env.service, defaults: walletEnv.defaults)
        #expect(reborn.walletAddresses.map { $0.lowercased() } == [Self.vectorMnemonicAddress])
        #expect(reborn.activeAddress?.lowercased() == Self.vectorMnemonicAddress)
    }

    @Test func setActiveAddressPersists() async throws {
        let walletEnv = try await Self.makeWalletEnv()
        defer { Self.tearDown(walletEnv) }
        _ = try await walletEnv.manager.importWallet(seedPhrase: Self.vectorMnemonic)
        _ = try await walletEnv.manager.importWallet(privateKey: Self.vectorPrivateKey)

        walletEnv.manager.setActiveAddress(Self.vectorPrivateKeyAddress)

        let reborn = WalletManager(passService: walletEnv.env.service, defaults: walletEnv.defaults)
        #expect(reborn.activeAddress == Self.vectorPrivateKeyAddress)
    }

    // MARK: - Signing

    @Test func signTransactionProducesRlpEncodedBytes() async throws {
        let walletEnv = try await Self.makeWalletEnv()
        defer { Self.tearDown(walletEnv) }
        _ = try await walletEnv.manager.importWallet(privateKey: Self.vectorPrivateKey)

        let signed = try walletEnv.manager.signTransaction(
            to: "0x3535353535353535353535353535353535353535",
            value: BigUInt(1_000_000_000_000_000_000),
            nonce: BigUInt(9),
            gasPrice: BigUInt(20_000_000_000),
            gasLimit: BigUInt(21_000),
            fromAddress: Self.vectorPrivateKeyAddress
        )

        #expect(!signed.isEmpty)
        #expect(signed.first == 0xf8)  // RLP list prefix for a legacy signed tx of this size
    }

    @Test func signTransactionWithoutKeyThrows() async throws {
        let walletEnv = try await Self.makeWalletEnv()
        defer { Self.tearDown(walletEnv) }
        #expect {
            _ = try walletEnv.manager.signTransaction(
                to: "0x3535353535353535353535353535353535353535",
                value: BigUInt(1), nonce: BigUInt(0),
                gasPrice: BigUInt(1), gasLimit: BigUInt(21_000),
                fromAddress: "0x0000000000000000000000000000000000000001")
        } throws: { error in
            guard case WalletError.privateKeyNotFound = error else { return false }
            return true
        }
    }

    @Test func signTransactionRejectsInvalidRecipient() async throws {
        let walletEnv = try await Self.makeWalletEnv()
        defer { Self.tearDown(walletEnv) }
        _ = try await walletEnv.manager.importWallet(privateKey: Self.vectorPrivateKey)
        #expect {
            _ = try walletEnv.manager.signTransaction(
                to: "not-an-address",
                value: BigUInt(1), nonce: BigUInt(0),
                gasPrice: BigUInt(1), gasLimit: BigUInt(21_000),
                fromAddress: Self.vectorPrivateKeyAddress)
        } throws: { error in
            guard case WalletError.invalidRecipient = error else { return false }
            return true
        }
    }

    // MARK: - Rename / delete

    @Test func renameWalletUpdatesVaultItem() async throws {
        let walletEnv = try await Self.makeWalletEnv()
        defer { Self.tearDown(walletEnv) }
        let address = try await walletEnv.manager.importWallet(seedPhrase: Self.vectorMnemonic)

        try await walletEnv.manager.renameWallet(address: address.uppercased(), newName: "Cold Storage")

        #expect(walletEnv.manager.getWalletItems().first?.name == "Cold Storage")
    }

    @Test func renameUnknownWalletThrows() async throws {
        let walletEnv = try await Self.makeWalletEnv()
        defer { Self.tearDown(walletEnv) }
        await #expect {
            try await walletEnv.manager.renameWallet(address: "0xdead", newName: "x")
        } throws: { error in
            guard case WalletError.walletNotFound = error else { return false }
            return true
        }
    }

    @Test func deleteWalletRemovesItemCacheAndReassignsActive() async throws {
        let walletEnv = try await Self.makeWalletEnv()
        defer { Self.tearDown(walletEnv) }
        let first = try await walletEnv.manager.importWallet(seedPhrase: Self.vectorMnemonic)
        let second = try await walletEnv.manager.importWallet(privateKey: Self.vectorPrivateKey)
        walletEnv.manager.setActiveAddress(first)

        try await walletEnv.manager.deleteWallet(address: first)

        #expect(walletEnv.manager.walletAddresses.map { $0.lowercased() } == [second.lowercased()])
        #expect(walletEnv.manager.activeAddress?.lowercased() == second.lowercased())
        #expect(walletEnv.manager.getWalletItems().count == 1)
    }
}
}
```

- [ ] **Step 3: Run to verify pass**

Run: `bash scripts/test.sh --unit 2>&1 | tail -30`
Expected: PASS. If a BIP39/private-key vector fails: report BLOCKED with the actual derived address — do NOT change the constant.

If `import BigInt` fails to resolve in the test target (module not visible to GrooTests), add the package products to the test target via the xcodeproj gem — run this once:

```ruby
# scripts/one-off, run with: ruby -e "$(cat)" <<'EOF'
require 'xcodeproj'
project = Xcodeproj::Project.open('Groo.xcodeproj')
tests = project.targets.find { |t| t.name == 'GrooTests' }
app = project.targets.find { |t| t.name == 'Groo' }
%w[BigInt].each do |name|
  dep = app.package_product_dependencies.find { |d| d.product_name == name }
  abort "#{name} not found on app target" unless dep
  new_dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  new_dep.product_name = name
  new_dep.package = dep.package
  tests.package_product_dependencies << new_dep
end
project.save
puts 'OK'
EOF
```

- [ ] **Step 4: Commit**

```bash
git add Groo/Features/Crypto/Services/WalletManager.swift GrooTests
git commit -m "test: WalletManager suite (BIP39 vectors, signing, lifecycle); inject UserDefaults"
```

---

### Task 5: PassService fast-follows (folders, per-type lifecycle, favorites, biometric-offline)

**Files:**
- Modify: `GrooTests/Features/Pass/PassServiceIntegrationTests.swift` (extend `makeEnv` with `folders:` param; strengthen biometric test; add tests)

**Interfaces:**
- Consumes: existing `makeEnv`/`stubVaultPut`/`decodeUploadedVault` helpers; `VaultItemFixtures.allItemJSONs`; `PassFolder(id:name:)`.
- Produces: `makeEnv(items:folders:vaultVersion:)` — `folders: [PassFolder] = []` added (existing call sites unchanged).

No production code changes in this task.

- [ ] **Step 1: Extend makeEnv with folders**

In `makeEnv`, change the signature and the vault construction:

```swift
    static func makeEnv(items: [PassVaultItem], folders: [PassFolder] = [], vaultVersion: Int = 3) throws -> Env {
```

```swift
        let vault = PassVault(version: 1, items: items, folders: folders, lastModified: 1_700_000_000_000)
```

- [ ] **Step 2: Strengthen the biometric test**

Replace `biometricUnlockUsesLocalCacheWithoutNetwork` with:

```swift
    @Test func biometricUnlockSucceedsWithZeroNetwork() async throws {
        let item = PassVaultItem.password(VaultItemFixtures.samplePasswordItem())
        let env = try Self.makeEnv(items: [item])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }

        // First unlock populates keychain + vault cache
        _ = try await env.service.unlock(password: Self.password)
        env.service.lock()

        // Remove ALL stubs: any network dependency now fails loudly.
        // (Background sync will fail and log — by design; the unlock itself
        // must succeed purely from the local cache + keychain.)
        StubURLProtocol.reset()

        let unlocked = try await env.service.unlockWithBiometric(context: nil)

        #expect(unlocked)
        #expect(env.service.getItems().map(\.id) == ["pw-1"])
    }
```

- [ ] **Step 3: Add the new tests (same suite)**

```swift
    // MARK: - Folders

    @Test func folderLifecycleRoundtripsThroughEncryption() async throws {
        let env = try Self.makeEnv(items: [])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }
        _ = try await env.service.unlock(password: Self.password)

        Self.stubVaultPut(version: 4)
        try await env.service.addFolder(PassFolder(id: "f-1", name: "Work"))
        #expect(env.service.getFolders().map(\.name) == ["Work"])
        var uploaded = try Self.decodeUploadedVault(key: env.key)
        #expect(uploaded.vault.folders.map(\.id) == ["f-1"])

        Self.stubVaultPut(version: 5)
        try await env.service.updateFolder(PassFolder(id: "f-1", name: "Work Renamed"))
        uploaded = try Self.decodeUploadedVault(key: env.key)
        #expect(uploaded.vault.folders.map(\.name) == ["Work Renamed"])
    }

    @Test func deleteFolderMovesItemsToRoot() async throws {
        var item = VaultItemFixtures.samplePasswordItem()
        item.folderId = "f-1"
        let env = try Self.makeEnv(items: [.password(item)], folders: [PassFolder(id: "f-1", name: "Work")])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }
        _ = try await env.service.unlock(password: Self.password)
        #expect(env.service.getItemsInFolder("f-1").map(\.id) == ["pw-1"])

        Self.stubVaultPut(version: 4)
        try await env.service.deleteFolder(PassFolder(id: "f-1", name: "Work"))

        #expect(env.service.getFolders().isEmpty)
        #expect(env.service.getItemsInFolder("f-1").isEmpty)
        let uploaded = try Self.decodeUploadedVault(key: env.key)
        #expect(uploaded.vault.folders.isEmpty)
        guard case .password(let survivor) = uploaded.vault.items.first else {
            Issue.record("expected surviving password item"); return
        }
        #expect(survivor.folderId == nil)   // item moved to root, not deleted
    }

    // MARK: - Favorites

    @Test func toggleFavoriteRoundtripsThroughEncryption() async throws {
        let env = try Self.makeEnv(items: [.password(VaultItemFixtures.samplePasswordItem())])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }
        _ = try await env.service.unlock(password: Self.password)
        let item = try #require(env.service.getItem(id: "pw-1"))

        Self.stubVaultPut(version: 4)
        try await env.service.toggleFavorite(item)
        #expect(env.service.getFavorites().map(\.id) == ["pw-1"])
        var uploaded = try Self.decodeUploadedVault(key: env.key)
        guard case .password(let fav) = uploaded.vault.items.first else {
            Issue.record("expected password item"); return
        }
        #expect(fav.favorite == true)

        Self.stubVaultPut(version: 5)
        try await env.service.toggleFavorite(try #require(env.service.getItem(id: "pw-1")))
        #expect(env.service.getFavorites().isEmpty)
    }

    // MARK: - Per-type lifecycle (guards the multi-file type switches)

    @Test func everyItemTypeSurvivesAddDeleteRestore() async throws {
        let env = try Self.makeEnv(items: [])
        defer { try? FileManager.default.removeItem(at: env.tempDir) }
        _ = try await env.service.unlock(password: Self.password)
        Self.stubVaultPut(version: 4)

        let decoder = JSONDecoder()
        let allItems = try VaultItemFixtures.allItemJSONs.map {
            try decoder.decode(PassVaultItem.self, from: Data($0.utf8))
        }

        // Add one of each type
        for item in allItems {
            try await env.service.addItem(item)
        }
        #expect(env.service.getItems().count == allItems.count)
        var uploaded = try Self.decodeUploadedVault(key: env.key)
        #expect(Set(uploaded.vault.items.map(\.type)) == Set(PassVaultItemType.allCases))

        // Tombstone every type (exercises the per-type deletedAt switch)
        for item in env.service.getItems() {
            try await env.service.deleteItem(item)
        }
        #expect(env.service.getItems().isEmpty)
        #expect(env.service.getTrashItems().count == allItems.count)
        uploaded = try Self.decodeUploadedVault(key: env.key)
        #expect(uploaded.vault.items.allSatisfy { $0.deletedAt != nil })

        // Restore every type
        for item in env.service.getTrashItems() {
            try await env.service.restoreItem(item)
        }
        #expect(env.service.getItems().count == allItems.count)
        #expect(env.service.getTrashItems().isEmpty)
        uploaded = try Self.decodeUploadedVault(key: env.key)
        #expect(uploaded.vault.items.allSatisfy { $0.deletedAt == nil })
    }
```

Note: `PassVaultItem` must expose `deletedAt` and `folderId` as computed vars for `allSatisfy`/filter use — they do (used by `getItems`/`deleteFolder` in production). If the compiler disagrees, match on the concrete cases instead; do not add production accessors.

- [ ] **Step 4: Run to verify pass**

Run: `bash scripts/test.sh --unit 2>&1 | tail -30`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add GrooTests
git commit -m "test: PassService folders, per-type lifecycle, favorites, biometric-offline proof"
```

---

### Task 6: Full verification + docs + coverage snapshot

**Files:**
- Modify: `README.md` (Testing section: one line on wallet coverage)

- [ ] **Step 1: Full suite twice**

Run: `bash scripts/test.sh --all 2>&1 | tail -5 && bash scripts/test.sh --all 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **` twice.

- [ ] **Step 2: App builds**

Run: `xcodebuild build -project Groo.xcodeproj -scheme Groo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Coverage snapshot**

Run: `bash scripts/test.sh --unit --coverage 2>&1 | tail -45`
Record in the task report: coverage for `WalletManager.swift`, `EthereumService.swift`, `CoinGeckoService.swift`, `APICache.swift` (expected: each well above 60%; WalletManager and EthereumService above 80%).

- [ ] **Step 4: README line**

In `README.md`'s Testing conventions list, append:

```markdown
- Wallet tests use real BIP39 derivation vectors (constants in `WalletManagerTests`) — a vector failure is a derivation regression, never a fixture to update.
```

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: note wallet test vectors in README"
```

---

## Post-plan

Remaining spec phases: 3 (sync & offline), 4 (extensions & remaining features), 5 (UI tests), 6 (edge-case sweep) — each gets its own plan.
