//
//  SharedNewLoginDraft.swift
//  Groo
//
//  The new-login form's pure logic. Lives in Shared/ rather than in
//  GrooAutoFill so GrooTests can reach it: the test bundle hosts the app, so
//  nothing declared in the extension target is testable.
//

import Foundation

struct SharedNewLoginDraft {
    var name: String
    var username: String
    var password: String
    /// The site as typed or prefilled — a bare host, or a full URL.
    var site: String

    init(name: String = "", username: String = "", password: String = "", site: String = "") {
        self.name = name
        self.username = username
        self.password = password
        self.site = site
    }

    /// Default item name for the host of the request being filled.
    ///
    /// Only a leading `www.` is stripped. Deeper subdomains are kept:
    /// `accounts.google.com` is a different service from `google.com`, and
    /// collapsing it files the item under a name the user did not mean.
    static func defaultName(forHost host: String?) -> String {
        guard let host, !host.trimmingCharacters(in: .whitespaces).isEmpty else {
            return "New Login"
        }
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("www.") ? String(trimmed.dropFirst(4)) : trimmed
    }

    /// Force a scheme so the stored URL parses. Saved URLs may be bare domains;
    /// `URL(string:)` yields no host for those, which is what
    /// `AutoFillService.updateQuickTypeIdentities` already works around.
    static func normalizedURL(_ site: String) -> String? {
        let trimmed = site.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.contains("://") ? trimmed : "https://\(trimmed)"
    }

    /// A password is the one thing that cannot be filled in later — a username
    /// often is, on the screen after the one being filled.
    var isSaveable: Bool {
        !password.isEmpty
    }

    func pendingItem(id: String, now: Int) -> SharedPendingPasswordItem {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty
            ? Self.defaultName(forHost: site.trimmingCharacters(in: .whitespaces).isEmpty ? nil : site)
            : trimmedName

        return SharedPendingPasswordItem(
            item: SharedPassPasswordItem(
                id: id,
                name: resolvedName,
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                urls: Self.normalizedURL(site).map { [$0] } ?? []
            ),
            createdAt: now,
            updatedAt: now
        )
    }
}
