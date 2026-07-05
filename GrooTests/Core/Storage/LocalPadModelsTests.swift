//
//  LocalPadModelsTests.swift
//  GrooTests
//
//  LocalPadItem/LocalScratchpad JSON-accessor fallbacks and API-model
//  conversions (millisecond timestamps), plus DecryptedScratchpad title
//  derivation. Pure model logic — no container needed.
//

import Foundation
import Testing
@testable import Groo

struct LocalPadModelsTests {
    static let payload = PadEncryptedPayload(ciphertext: "Y2lwaGVy", iv: "aXZpdml2aXZpdg==", version: 1)

    @Test func garbageStoredJsonDegradesToNilPayloadAndEmptyFiles() {
        let item = LocalPadItem(id: "x", encryptedTextJSON: "garbage", createdAt: Date(timeIntervalSince1970: 1))
        item.filesJSON = Data("also garbage".utf8)

        #expect(item.encryptedText == nil)     // nil, never a wrong payload
        #expect(item.files.isEmpty)
        #expect(item.toPadListItem() == nil)   // unconvertible → skipped, not fabricated
    }

    @Test func padItemConvertsToAndFromApiModel() throws {
        let file = PadFileAttachment(id: "f-1", encryptedName: Self.payload, size: 9, encryptedType: Self.payload, r2Key: "r2/f-1")
        let apiItem = PadListItem(id: "item-1", encryptedText: Self.payload, files: [file], createdAt: 1_700_000_000_000)

        let local = try #require(LocalPadItem(from: apiItem))

        #expect(local.createdAt == Date(timeIntervalSince1970: 1_700_000_000))   // ms → Date
        #expect(local.toPadListItem() == apiItem)                                // …and back
    }

    @Test func scratchpadConvertsToAndFromApiModel() throws {
        let apiScratchpad = PadScratchpad(
            id: "sp-1", encryptedContent: Self.payload, files: [],
            createdAt: 1_700_000_000_000, updatedAt: 1_700_000_060_000
        )

        let local = try #require(LocalScratchpad(from: apiScratchpad))

        #expect(local.updatedAt == Date(timeIntervalSince1970: 1_700_000_060))
        #expect(local.toPadScratchpad() == apiScratchpad)
    }

    @Test func scratchpadTitleDerivesFromFirstLine() {
        func scratchpad(_ content: String) -> DecryptedScratchpad {
            DecryptedScratchpad(id: "sp", content: content, files: [], createdAt: 0, updatedAt: 0)
        }

        #expect(scratchpad("# Meeting Notes\nbody text").title == "Meeting Notes")
        #expect(scratchpad("plain first line\nsecond").title == "plain first line")
        #expect(scratchpad("###   ").title == "Untitled")
        #expect(scratchpad("").title == "Untitled")
    }
}
