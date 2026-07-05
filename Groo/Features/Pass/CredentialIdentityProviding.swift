//
//  CredentialIdentityProviding.swift
//  Groo
//
//  Seam over CredentialIdentityService so tests don't hit the real
//  ASCredentialIdentityStore.
//

protocol CredentialIdentityProviding {
    func updateCredentialIdentities(from items: [PassVaultItem]) async
    func clearCredentialIdentities() async -> Bool
}
