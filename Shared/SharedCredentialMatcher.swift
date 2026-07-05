//
//  SharedCredentialMatcher.swift
//  Groo
//
//  Pure credential/passkey matching and search logic shared by the app and
//  the AutoFill extension. Extracted verbatim from AutoFillService so the
//  domain-matching semantics are testable from GrooTests (extension-target
//  files are not compiled into the test host).
//

import Foundation

enum SharedCredentialMatcher {
    /// Exact host or subdomain match: "accounts.google.com" matches a saved
    /// "google.com" (and vice versa), but "app.com" never matches "myapp.com"
    static func domainsMatch(_ a: String, _ b: String) -> Bool {
        a == b || a.hasSuffix(".\(b)") || b.hasSuffix(".\(a)")
    }

    /// Filter credentials that match any of the search domains (checks all
    /// saved URLs). An empty search-domain list means "no filter".
    static func credentials(
        _ credentials: [SharedPassPasswordItem],
        matchingDomains searchDomains: [String]
    ) -> [SharedPassPasswordItem] {
        guard !searchDomains.isEmpty else {
            return credentials
        }

        return credentials.filter { credential in
            let credentialDomains = credential.domains
            guard !credentialDomains.isEmpty else { return false }

            return searchDomains.contains { searchDomain in
                credentialDomains.contains { credDomain in
                    domainsMatch(credDomain, searchDomain)
                }
            }
        }
    }

    /// Case-insensitive search over name, username, and raw saved URLs.
    static func credentials(
        _ credentials: [SharedPassPasswordItem],
        matchingQuery query: String
    ) -> [SharedPassPasswordItem] {
        guard !query.isEmpty else {
            return credentials
        }

        let lowercasedQuery = query.lowercased()

        return credentials.filter { credential in
            credential.name.lowercased().contains(lowercasedQuery) ||
            credential.username.lowercased().contains(lowercasedQuery) ||
            credential.urls.contains { $0.lowercased().contains(lowercasedQuery) }
        }
    }

    /// Filter passkeys by relying party ID and the request's allow-list of
    /// base64url credential IDs. An empty allow-list means "any".
    static func passkeys(
        _ passkeys: [SharedPassPasskeyItem],
        forRpId rpId: String?,
        allowedCredentialIds allowed: Set<String>
    ) -> [SharedPassPasskeyItem] {
        guard let rpId = rpId else { return [] }

        return passkeys.filter { passkey in
            passkey.rpId == rpId && (allowed.isEmpty || allowed.contains(passkey.credentialId))
        }
    }

    /// Case-insensitive search over name, userName, and rpId.
    static func passkeys(
        _ passkeys: [SharedPassPasskeyItem],
        matchingQuery query: String
    ) -> [SharedPassPasskeyItem] {
        guard !query.isEmpty else {
            return passkeys
        }

        let lowercasedQuery = query.lowercased()

        return passkeys.filter { passkey in
            passkey.name.lowercased().contains(lowercasedQuery) ||
            passkey.userName.lowercased().contains(lowercasedQuery) ||
            passkey.rpId.lowercased().contains(lowercasedQuery)
        }
    }

    /// Find a passkey by its raw credential ID bytes (stored IDs are base64url).
    static func passkey(
        in passkeys: [SharedPassPasskeyItem],
        credentialId: Data
    ) -> SharedPassPasskeyItem? {
        let credentialIdBase64URL = credentialId.base64URLEncodedString
        return passkeys.first { $0.credentialId == credentialIdBase64URL }
    }

    /// Vault passkeys plus pending-queue passkeys, deduped by credentialId
    /// (the vault copy wins — the queue may lag behind a completed merge).
    static func mergingPendingPasskeys(
        vault: [SharedPassPasskeyItem],
        pending: [SharedPassPasskeyItem]
    ) -> [SharedPassPasskeyItem] {
        let knownCredentialIds = Set(vault.map(\.credentialId))
        return vault + pending.filter { !knownCredentialIds.contains($0.credentialId) }
    }
}
