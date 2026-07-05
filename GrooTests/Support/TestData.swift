//
//  TestData.swift
//  GrooTests
//
//  Shared fixture helpers.
//

import Foundation

extension Data {
    /// Build Data from a hex string like "55ac046e...". Returns nil on odd length / bad chars.
    init?(hexString: String) {
        let chars = Array(hexString)
        guard chars.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(chars.count / 2)
        for i in stride(from: 0, to: chars.count, by: 2) {
            guard let byte = UInt8(String(chars[i...i+1]), radix: 16) else { return nil }
            bytes.append(byte)
        }
        self.init(bytes)
    }
}
