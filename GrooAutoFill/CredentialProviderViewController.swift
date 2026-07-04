//
//  CredentialProviderViewController.swift
//  GrooAutoFill
//
//  AutoFill Credential Provider for Groo Pass.
//  Provides password and passkey credentials to apps and Safari.
//

import AuthenticationServices
import CryptoKit
import SwiftUI
import UniformTypeIdentifiers
import os

class CredentialProviderViewController: ASCredentialProviderViewController {

    private let service = AutoFillService()
    private var hostingController: UIHostingController<AnyView>?
    private var currentServiceIdentifiers: [ASCredentialServiceIdentifier] = []
    private var passkeyRequestParameters: Any? // ASPasskeyCredentialRequestParameters (iOS 17+)
    private var pendingRegistrationRequest: Any? // ASPasskeyCredentialRequest (iOS 17+)

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        if hostingController == nil {
            setupUI(rootView: AnyView(makeCredentialListView(serviceIdentifiers: currentServiceIdentifiers)))
        }
    }

    private func setupUI(rootView: AnyView) {
        let hostingController = UIHostingController(rootView: rootView)
        self.hostingController = hostingController

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        hostingController.didMove(toParent: self)
    }

    private func show(rootView: AnyView) {
        loadViewIfNeeded()
        if let hostingController {
            hostingController.rootView = rootView
        } else {
            setupUI(rootView: rootView)
        }
    }

    private func updateServiceIdentifiers(_ identifiers: [ASCredentialServiceIdentifier]) {
        currentServiceIdentifiers = identifiers
        show(rootView: AnyView(makeCredentialListView(serviceIdentifiers: identifiers)))
    }

    private var currentRpId: String? {
        if #available(iOS 17.0, *),
           let params = passkeyRequestParameters as? ASPasskeyCredentialRequestParameters {
            return params.relyingPartyIdentifier
        }
        return nil
    }

    private var currentAllowedCredentialIds: [Data] {
        if #available(iOS 17.0, *),
           let params = passkeyRequestParameters as? ASPasskeyCredentialRequestParameters {
            return params.allowedCredentials
        }
        return []
    }

    private func makeCredentialListView(serviceIdentifiers: [ASCredentialServiceIdentifier]) -> AutoFillCredentialListView {
        AutoFillCredentialListView(
            service: service,
            serviceIdentifiers: serviceIdentifiers,
            rpId: currentRpId,
            allowedCredentialIds: currentAllowedCredentialIds,
            onSelect: { [weak self] credential in
                self?.selectCredential(credential)
            },
            onSelectPasskey: { [weak self] passkey in
                self?.selectPasskey(passkey)
            },
            onCancel: { [weak self] in
                self?.cancel()
            }
        )
    }

    // MARK: - Credential Provider Methods

    /// Called when the user selects "Groo" from the password list in QuickType bar
    /// This is for quickly providing a credential without showing UI
    override func provideCredentialWithoutUserInteraction(for credentialIdentity: ASPasswordCredentialIdentity) {
        // We always require user interaction (biometric auth)
        self.extensionContext.cancelRequest(
            withError: NSError(
                domain: ASExtensionErrorDomain,
                code: ASExtensionError.userInteractionRequired.rawValue
            )
        )
    }

    /// Called when UI is needed to authenticate before providing credential
    override func prepareInterfaceToProvideCredential(for credentialIdentity: ASPasswordCredentialIdentity) {
        // The credential identity contains the record identifier we stored
        // We need to find and return this credential after biometric auth
        handlePasswordRequest(credentialIdentity)
    }

    /// Called to prepare UI for credential selection
    /// The serviceIdentifiers describe the service the user is logging into
    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        updateServiceIdentifiers(serviceIdentifiers)

        // Auto-unlock if possible
        if service.hasVault {
            Task {
                do {
                    try await service.unlock()
                } catch {
                    // User can still tap the unlock button; keep the cause visible
                    Log.autofill.error("Auto-unlock failed: \(String(describing: error), privacy: .public)")
                }
            }
        }
    }

    /// Called to prepare UI for passkey credential selection (iOS 17+)
    @available(iOS 17.0, *)
    override func prepareCredentialList(
        for serviceIdentifiers: [ASCredentialServiceIdentifier],
        requestParameters: ASPasskeyCredentialRequestParameters
    ) {
        self.passkeyRequestParameters = requestParameters
        updateServiceIdentifiers(serviceIdentifiers)

        // Auto-unlock if possible
        if service.hasVault {
            Task {
                do {
                    try await service.unlock()
                } catch {
                    // User can still tap the unlock button; keep the cause visible
                    Log.autofill.error("Auto-unlock failed: \(String(describing: error), privacy: .public)")
                }
            }
        }
    }

    // MARK: - iOS 17+ Passkey Methods

    /// Called for credential requests (iOS 17+) - handles both passwords and passkeys
    @available(iOS 17.0, *)
    override func provideCredentialWithoutUserInteraction(for credentialRequest: ASCredentialRequest) {
        // We always require user interaction (biometric auth)
        extensionContext.cancelRequest(
            withError: NSError(
                domain: ASExtensionErrorDomain,
                code: ASExtensionError.userInteractionRequired.rawValue
            )
        )
    }

    /// Called when UI is needed to authenticate before providing credential (iOS 17+)
    @available(iOS 17.0, *)
    override func prepareInterfaceToProvideCredential(for credentialRequest: ASCredentialRequest) {
        if let passkeyRequest = credentialRequest as? ASPasskeyCredentialRequest {
            handlePasskeyAssertion(passkeyRequest)
        } else if let passwordRequest = credentialRequest as? ASPasswordCredentialRequest,
                  let passwordIdentity = passwordRequest.credentialIdentity as? ASPasswordCredentialIdentity {
            // Delegate to existing password handling
            handlePasswordRequest(passwordIdentity)
        }
    }

    /// Handle password credential request
    private func handlePasswordRequest(_ credentialIdentity: ASPasswordCredentialIdentity) {
        Task {
            do {
                try await service.unlock()

                // Find the credential by ID
                if let credential = service.credentials.first(where: { $0.id == credentialIdentity.recordIdentifier }) {
                    selectCredential(credential)
                } else {
                    Log.autofill.error("Credential \(credentialIdentity.recordIdentifier ?? "?", privacy: .public) not found in vault; showing list")
                    updateServiceIdentifiers([credentialIdentity.serviceIdentifier])
                }
            } catch {
                // Leave the user on the unlock screen with the actual cause
                Log.autofill.error("Unlock for QuickType request failed: \(String(describing: error), privacy: .public)")
                service.error = error.localizedDescription
                updateServiceIdentifiers([credentialIdentity.serviceIdentifier])
            }
        }
    }

    /// Handle passkey assertion request (iOS 17+)
    @available(iOS 17.0, *)
    private func handlePasskeyAssertion(_ request: ASPasskeyCredentialRequest) {
        Task {
            do {
                try await service.unlock()

                // Find the passkey by credential ID
                guard let passkeyIdentity = request.credentialIdentity as? ASPasskeyCredentialIdentity,
                      let passkey = service.findPasskey(credentialId: passkeyIdentity.credentialID) else {
                    extensionContext.cancelRequest(
                        withError: NSError(
                            domain: ASExtensionErrorDomain,
                            code: ASExtensionError.credentialIdentityNotFound.rawValue
                        )
                    )
                    return
                }

                // Synced credentials must report a constant sign count of 0 —
                // an unpersisted increment trips relying parties' clone detection
                let authenticatorData = SharedPasskeyCrypto.buildAuthenticatorData(
                    rpId: passkey.rpId,
                    signCount: 0
                )

                // Sign the assertion
                let signature = try SharedPasskeyCrypto.signAssertion(
                    privateKeyBase64: passkey.privateKey,
                    authenticatorData: authenticatorData,
                    clientDataHash: request.clientDataHash
                )

                // Decode credential ID and user handle from base64url
                guard let credentialIdData = Data(base64URLEncoded: passkey.credentialId),
                      let userHandleData = Data(base64URLEncoded: passkey.userHandle) else {
                    throw AutoFillError.decryptionFailed
                }

                // Create passkey assertion credential
                let credential = ASPasskeyAssertionCredential(
                    userHandle: userHandleData,
                    relyingParty: passkey.rpId,
                    signature: signature,
                    clientDataHash: request.clientDataHash,
                    authenticatorData: authenticatorData,
                    credentialID: credentialIdData
                )

                // Complete the request
                await extensionContext.completeAssertionRequest(using: credential)

            } catch {
                extensionContext.cancelRequest(
                    withError: NSError(
                        domain: ASExtensionErrorDomain,
                        code: ASExtensionError.failed.rawValue,
                        userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]
                    )
                )
            }
        }
    }

    // MARK: - Passkey Registration (iOS 17+)

    /// Called when a website or app wants to create a new passkey
    @available(iOS 17.0, *)
    override func prepareInterface(forPasskeyRegistration registrationRequest: ASCredentialRequest) {
        guard let request = registrationRequest as? ASPasskeyCredentialRequest,
              let identity = request.credentialIdentity as? ASPasskeyCredentialIdentity,
              request.supportedAlgorithms.contains(ASCOSEAlgorithmIdentifier.ES256) else {
            extensionContext.cancelRequest(
                withError: NSError(
                    domain: ASExtensionErrorDomain,
                    code: ASExtensionError.failed.rawValue,
                    userInfo: [NSLocalizedDescriptionKey: "Unsupported passkey registration request"]
                )
            )
            return
        }

        pendingRegistrationRequest = request

        show(rootView: AnyView(RegisterPasskeyView(
            service: service,
            rpId: identity.relyingPartyIdentifier,
            userName: identity.userName,
            onConfirm: { [weak self] in
                self?.completePasskeyRegistration()
            },
            onCancel: { [weak self] in
                self?.cancel()
            }
        )))
    }

    @available(iOS 17.0, *)
    private func completePasskeyRegistration() {
        guard let request = pendingRegistrationRequest as? ASPasskeyCredentialRequest,
              let identity = request.credentialIdentity as? ASPasskeyCredentialIdentity else {
            // Internal state bug — report as failure, not as the user backing out
            Log.autofill.error("Registration confirmed but pending request is missing/mistyped")
            extensionContext.cancelRequest(
                withError: NSError(
                    domain: ASExtensionErrorDomain,
                    code: ASExtensionError.failed.rawValue,
                    userInfo: [NSLocalizedDescriptionKey: "Registration request lost"]
                )
            )
            return
        }

        Task {
            do {
                if !service.isUnlocked {
                    try await service.unlock()
                }

                let rpId = identity.relyingPartyIdentifier

                // The relying party may exclude credentials it already has (iOS 18+)
                if #available(iOS 18.0, *) {
                    let excludedIds = Set((request.excludedCredentials ?? []).map(\.credentialID))
                    let hasExcluded = service.passkeys.contains { passkey in
                        passkey.rpId == rpId &&
                        Data(base64URLEncoded: passkey.credentialId).map { excludedIds.contains($0) } == true
                    }
                    if hasExcluded {
                        extensionContext.cancelRequest(
                            withError: NSError(
                                domain: ASExtensionErrorDomain,
                                code: ASExtensionError.matchedExcludedCredential.rawValue
                            )
                        )
                        return
                    }
                }

                let registration = try SharedPasskeyCrypto.createRegistration(rpId: rpId)

                // Persist before completing so we never hand out a credential we didn't save
                let item = SharedPassPasskeyItem(
                    id: UUID().uuidString.lowercased(),
                    name: rpId,
                    rpId: rpId,
                    rpName: rpId,
                    credentialId: registration.credentialId.base64URLEncodedString,
                    publicKey: registration.publicKeyBase64,
                    privateKey: registration.privateKeyBase64,
                    userHandle: identity.userHandle.base64URLEncodedString,
                    userName: identity.userName,
                    signCount: 0
                )
                try service.savePendingPasskey(item)

                // Make the new passkey show up in QuickType immediately
                let passkeyIdentity = ASPasskeyCredentialIdentity(
                    relyingPartyIdentifier: rpId,
                    userName: identity.userName,
                    credentialID: registration.credentialId,
                    userHandle: identity.userHandle,
                    recordIdentifier: item.id
                )
                try? await ASCredentialIdentityStore.shared.saveCredentialIdentities([passkeyIdentity])

                let credential = ASPasskeyRegistrationCredential(
                    relyingParty: rpId,
                    clientDataHash: request.clientDataHash,
                    credentialID: registration.credentialId,
                    attestationObject: registration.attestationObject
                )

                await extensionContext.completeRegistrationRequest(using: credential)

            } catch AutoFillError.vaultLocked {
                // Face ID failed or was cancelled — let the user retry
                service.error = "Couldn't unlock. Try again."
            } catch {
                extensionContext.cancelRequest(
                    withError: NSError(
                        domain: ASExtensionErrorDomain,
                        code: ASExtensionError.failed.rawValue,
                        userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]
                    )
                )
            }
        }
    }

    // MARK: - Actions

    private func selectCredential(_ credential: SharedPassPasswordItem) {
        // Copy the current TOTP code so the user can paste it on the next screen
        // (matches Bitwarden behavior). Local-only, expires after 60 seconds.
        if let totp = credential.totp,
           let code = SharedTotp.generateCode(config: totp) {
            UIPasteboard.general.setItems(
                [[UTType.utf8PlainText.identifier: code]],
                options: [
                    .localOnly: true,
                    .expirationDate: Date().addingTimeInterval(60),
                ]
            )
        }

        let passwordCredential = ASPasswordCredential(
            user: credential.username,
            password: credential.password
        )

        extensionContext.completeRequest(
            withSelectedCredential: passwordCredential,
            completionHandler: nil
        )
    }

    private func selectPasskey(_ passkey: SharedPassPasskeyItem) {
        guard #available(iOS 17.0, *),
              let params = passkeyRequestParameters as? ASPasskeyCredentialRequestParameters else {
            // Passkey rows are only shown for passkey requests; if this is ever
            // hit, fail loudly instead of a dead tap
            Log.autofill.error("Passkey selected without passkey request parameters")
            extensionContext.cancelRequest(
                withError: NSError(
                    domain: ASExtensionErrorDomain,
                    code: ASExtensionError.failed.rawValue,
                    userInfo: [NSLocalizedDescriptionKey: "No passkey request in progress"]
                )
            )
            return
        }

        Task {
            do {
                // Synced credentials must report a constant sign count of 0 —
                // an unpersisted increment trips relying parties' clone detection
                let authenticatorData = SharedPasskeyCrypto.buildAuthenticatorData(
                    rpId: passkey.rpId,
                    signCount: 0
                )

                // Sign the assertion
                let signature = try SharedPasskeyCrypto.signAssertion(
                    privateKeyBase64: passkey.privateKey,
                    authenticatorData: authenticatorData,
                    clientDataHash: params.clientDataHash
                )

                // Decode credential ID and user handle from base64url
                guard let credentialIdData = Data(base64URLEncoded: passkey.credentialId),
                      let userHandleData = Data(base64URLEncoded: passkey.userHandle) else {
                    throw AutoFillError.decryptionFailed
                }

                // Create passkey assertion credential
                let credential = ASPasskeyAssertionCredential(
                    userHandle: userHandleData,
                    relyingParty: passkey.rpId,
                    signature: signature,
                    clientDataHash: params.clientDataHash,
                    authenticatorData: authenticatorData,
                    credentialID: credentialIdData
                )

                // Complete the request
                await extensionContext.completeAssertionRequest(using: credential)

            } catch {
                extensionContext.cancelRequest(
                    withError: NSError(
                        domain: ASExtensionErrorDomain,
                        code: ASExtensionError.failed.rawValue,
                        userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]
                    )
                )
            }
        }
    }

    private func cancel() {
        extensionContext.cancelRequest(
            withError: NSError(
                domain: ASExtensionErrorDomain,
                code: ASExtensionError.userCanceled.rawValue
            )
        )
    }
}
