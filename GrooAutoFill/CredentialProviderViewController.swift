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

class CredentialProviderViewController: ASCredentialProviderViewController {

    private let service = AutoFillService()
    private var hostingController: UIHostingController<AutoFillCredentialListView>?
    private var currentServiceIdentifiers: [ASCredentialServiceIdentifier] = []
    private var passkeyRequestParameters: Any? // ASPasskeyCredentialRequestParameters (iOS 17+)

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    private func setupUI() {
        let contentView = makeCredentialListView(serviceIdentifiers: currentServiceIdentifiers)

        let hostingController = UIHostingController(rootView: contentView)
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

    private func updateServiceIdentifiers(_ identifiers: [ASCredentialServiceIdentifier]) {
        currentServiceIdentifiers = identifiers

        // Update the SwiftUI view with new identifiers
        if hostingController != nil {
            let contentView = makeCredentialListView(serviceIdentifiers: identifiers)
            hostingController?.rootView = contentView
        }
    }

    private var currentRpId: String? {
        if #available(iOS 17.0, *),
           let params = passkeyRequestParameters as? ASPasskeyCredentialRequestParameters {
            return params.relyingPartyIdentifier
        }
        return nil
    }

    private func makeCredentialListView(serviceIdentifiers: [ASCredentialServiceIdentifier]) -> AutoFillCredentialListView {
        AutoFillCredentialListView(
            service: service,
            serviceIdentifiers: serviceIdentifiers,
            rpId: currentRpId,
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
                    // User will need to tap unlock button
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
                    // User will need to tap unlock button
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
                    // Credential not found, show the list
                    updateServiceIdentifiers([credentialIdentity.serviceIdentifier])
                }
            } catch {
                // Show unlock UI
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
                let passkeyIdentity = request.credentialIdentity as! ASPasskeyCredentialIdentity
                guard let passkey = service.findPasskey(credentialId: passkeyIdentity.credentialID) else {
                    extensionContext.cancelRequest(
                        withError: NSError(
                            domain: ASExtensionErrorDomain,
                            code: ASExtensionError.credentialIdentityNotFound.rawValue
                        )
                    )
                    return
                }

                // Build authenticator data with incremented sign count
                let authenticatorData = SharedPasskeyCrypto.buildAuthenticatorData(
                    rpId: passkey.rpId,
                    signCount: passkey.signCount + 1
                )

                // Sign the assertion
                let signature = try SharedPasskeyCrypto.signAssertion(
                    privateKeyBase64: passkey.privateKey,
                    authenticatorData: authenticatorData,
                    clientDataHash: request.clientDataHash
                )

                // Decode credential ID and user handle from base64
                guard let credentialIdData = Data(base64Encoded: passkey.credentialId),
                      let userHandleData = Data(base64Encoded: passkey.userHandle) else {
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

    // MARK: - Actions

    private func selectCredential(_ credential: SharedPassPasswordItem) {
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
            return
        }

        Task {
            do {
                // Build authenticator data with incremented sign count
                let authenticatorData = SharedPasskeyCrypto.buildAuthenticatorData(
                    rpId: passkey.rpId,
                    signCount: passkey.signCount + 1
                )

                // Sign the assertion
                let signature = try SharedPasskeyCrypto.signAssertion(
                    privateKeyBase64: passkey.privateKey,
                    authenticatorData: authenticatorData,
                    clientDataHash: params.clientDataHash
                )

                // Decode credential ID and user handle from base64
                guard let credentialIdData = Data(base64Encoded: passkey.credentialId),
                      let userHandleData = Data(base64Encoded: passkey.userHandle) else {
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
