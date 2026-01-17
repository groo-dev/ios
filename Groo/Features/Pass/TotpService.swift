//
//  TotpService.swift
//  Groo
//
//  TOTP (Time-based One-Time Password) generation service following RFC 6238.
//

import Foundation
import CryptoKit

enum TotpService {
    /// Generate a TOTP code from the given configuration
    static func generateCode(config: PassTotpConfig, time: Date = Date()) -> String {
        guard let secretData = base32Decode(config.secret) else {
            return "------"
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

    /// Calculate seconds remaining until the current code expires
    static func secondsRemaining(period: Int, time: Date = Date()) -> Int {
        let elapsed = Int(time.timeIntervalSince1970) % period
        return period - elapsed
    }

    /// Progress percentage (0.0 to 1.0) through the current period
    static func progress(period: Int, time: Date = Date()) -> Double {
        let elapsed = Int(time.timeIntervalSince1970) % period
        return Double(elapsed) / Double(period)
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

// MARK: - TOTP URI Parsing

extension TotpService {
    /// Parse an otpauth:// URI into a TotpConfig
    static func parseUri(_ uri: String) -> PassTotpConfig? {
        guard let url = URL(string: uri),
              url.scheme == "otpauth",
              url.host == "totp" else {
            return nil
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return nil
        }

        var secret: String?
        var algorithm: PassTotpConfig.PassTotpAlgorithm = .sha1
        var digits = 6
        var period = 30

        for item in queryItems {
            switch item.name.lowercased() {
            case "secret":
                secret = item.value
            case "algorithm":
                if let value = item.value?.uppercased() {
                    switch value {
                    case "SHA1": algorithm = .sha1
                    case "SHA256": algorithm = .sha256
                    case "SHA512": algorithm = .sha512
                    default: break
                    }
                }
            case "digits":
                if let value = item.value, let d = Int(value) {
                    digits = d
                }
            case "period":
                if let value = item.value, let p = Int(value) {
                    period = p
                }
            default:
                break
            }
        }

        guard let secretValue = secret, !secretValue.isEmpty else {
            return nil
        }

        return PassTotpConfig(
            secret: secretValue,
            algorithm: algorithm,
            digits: digits,
            period: period
        )
    }
}
