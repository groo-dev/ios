//
//  CredentialProviderViewController.swift
//  GrooAutoFill
//
//  AutoFill Credential Provider for Groo Pass.
//  Provides password credentials to apps and Safari.
//

import AuthenticationServices
import SwiftUI

class CredentialProviderViewController: ASCredentialProviderViewController {

    private let service = AutoFillService()
    private var hostingController: UIHostingController<AutoFillCredentialListView>?
    private var currentServiceIdentifiers: [ASCredentialServiceIdentifier] = []

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    private func setupUI() {
        let contentView = AutoFillCredentialListView(
            service: service,
            serviceIdentifiers: currentServiceIdentifiers,
            onSelect: { [weak self] credential in
                self?.selectCredential(credential)
            },
            onCancel: { [weak self] in
                self?.cancel()
            }
        )

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
            let contentView = AutoFillCredentialListView(
                service: service,
                serviceIdentifiers: identifiers,
                onSelect: { [weak self] credential in
                    self?.selectCredential(credential)
                },
                onCancel: { [weak self] in
                    self?.cancel()
                }
            )
            hostingController?.rootView = contentView
        }
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

    private func cancel() {
        extensionContext.cancelRequest(
            withError: NSError(
                domain: ASExtensionErrorDomain,
                code: ASExtensionError.userCanceled.rawValue
            )
        )
    }
}
