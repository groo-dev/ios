//
//  SharedTotp.swift
//  Groo
//
//  TOTP code generation (RFC 6238) for extensions.
//  Mirrors TotpService in the main app.
//

import CryptoKit
import Foundation

enum SharedTotp {
    /// Generate the current TOTP code, or nil if the secret is invalid
    static func generateCode(config: SharedPassTotpConfig, time: Date = Date()) -> String? {
        guard let secretData = base32Decode(config.secret) else {
            return nil
        }

        let counter = UInt64(time.timeIntervalSince1970) / UInt64(config.period)
        let counterBytes = withUnsafeBytes(of: counter.bigEndian) { Array($0) }

        let hmac: Data
        switch config.algorithm {
        case .sha1:
            hmac = Data(HMAC<Insecure.SHA1>.authenticationCode(for: counterBytes, using: SymmetricKey(data: secretData)))
        case .sha256:
            hmac = Data(HMAC<SHA256>.authenticationCode(for: counterBytes, using: SymmetricKey(data: secretData)))
        case .sha512:
            hmac = Data(HMAC<SHA512>.authenticationCode(for: counterBytes, using: SymmetricKey(data: secretData)))
        }

        // Dynamic truncation
        let offset = Int(hmac[hmac.count - 1] & 0x0f)
        let truncatedHash = hmac.subdata(in: offset..<(offset + 4))

        var code = truncatedHash.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        code &= 0x7fffffff  // Clear the MSB

        let modulo = UInt32(pow(10.0, Double(config.digits)))
        code %= modulo

        return String(format: "%0\(config.digits)d", code)
    }

    // MARK: - Base32 Decoding

    private static func base32Decode(_ input: String) -> Data? {
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        let normalized = input.uppercased().filter { alphabet.contains($0) }

        var output = Data()
        var buffer: UInt64 = 0
        var bitsInBuffer = 0

        for char in normalized {
            guard let index = alphabet.firstIndex(of: char) else { continue }
            let value = UInt64(alphabet.distance(from: alphabet.startIndex, to: index))

            buffer = (buffer << 5) | value
            bitsInBuffer += 5

            if bitsInBuffer >= 8 {
                bitsInBuffer -= 8
                output.append(UInt8((buffer >> bitsInBuffer) & 0xff))
            }
        }

        return output.isEmpty ? nil : output
    }
}
