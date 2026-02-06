//
//  PassItemFormView.swift
//  Groo
//
//  Form for creating and editing vault items (passwords, cards, notes, bank accounts).
//

import SwiftUI

struct PassItemFormView: View {
    let passService: PassService
    let editingItem: PassVaultItem?
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var itemType: PassVaultItemType
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showPasswordGenerator = false

    // Common fields
    @State private var name = ""
    @State private var notes = ""
    @State private var folderId: String?

    // Password fields
    @State private var username = ""
    @State private var password = ""
    @State private var urls: [String] = [""]

    // Card fields
    @State private var cardholderName = ""
    @State private var cardNumber = ""
    @State private var expMonth = ""
    @State private var expYear = ""
    @State private var cvv = ""

    // Bank account fields
    @State private var bankName = ""
    @State private var accountType: PassBankAccountItem.PassBankAccountType = .checking
    @State private var accountNumber = ""
    @State private var routingNumber = ""
    @State private var iban = ""

    // Note field
    @State private var noteContent = ""

    private var isEditing: Bool { editingItem != nil }

    init(
        passService: PassService,
        editingItem: PassVaultItem? = nil,
        defaultType: PassVaultItemType = .password,
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.passService = passService
        self.editingItem = editingItem
        self.onSave = onSave
        self.onCancel = onCancel
        self._itemType = State(initialValue: editingItem?.type ?? defaultType)

        // Pre-populate fields if editing
        if let item = editingItem {
            switch item {
            case .password(let p):
                _name = State(initialValue: p.name)
                _username = State(initialValue: p.username)
                _password = State(initialValue: p.password)
                _urls = State(initialValue: p.urls.isEmpty ? [""] : p.urls)
                _notes = State(initialValue: p.notes ?? "")
                _folderId = State(initialValue: p.folderId)

            case .card(let c):
                _name = State(initialValue: c.name)
                _cardholderName = State(initialValue: c.cardholderName)
                _cardNumber = State(initialValue: c.number)
                _expMonth = State(initialValue: c.expMonth)
                _expYear = State(initialValue: c.expYear)
                _cvv = State(initialValue: c.cvv)
                _notes = State(initialValue: c.notes ?? "")
                _folderId = State(initialValue: c.folderId)

            case .bankAccount(let b):
                _name = State(initialValue: b.name)
                _bankName = State(initialValue: b.bankName)
                _accountType = State(initialValue: b.accountType)
                _accountNumber = State(initialValue: b.accountNumber)
                _routingNumber = State(initialValue: b.routingNumber ?? "")
                _iban = State(initialValue: b.iban ?? "")
                _notes = State(initialValue: b.notes ?? "")
                _folderId = State(initialValue: b.folderId)

            case .note(let n):
                _name = State(initialValue: n.name)
                _noteContent = State(initialValue: n.content)
                _folderId = State(initialValue: n.folderId)

            case .passkey, .file, .cryptoWallet, .corrupted:
                // Passkeys, files, crypto wallets, and corrupted items are not editable via form
                _name = State(initialValue: item.name)
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // Item type picker (only for new items)
                if !isEditing {
                    Section {
                        Picker("Type", selection: $itemType) {
                            ForEach(editableTypes, id: \.self) { type in
                                Label(type.label, systemImage: type.icon)
                                    .tag(type)
                            }
                        }
                    }
                }

                // Name field (common to all)
                Section {
                    TextField("Name", text: $name)
                }

                // Type-specific fields
                switch itemType {
                case .password:
                    passwordFields
                case .card:
                    cardFields
                case .bankAccount:
                    bankAccountFields
                case .note:
                    noteFields
                case .passkey, .file, .cryptoWallet:
                    EmptyView()
                }

                // Folder picker
                if !passService.folders.isEmpty {
                    Section("Folder") {
                        Picker("Folder", selection: $folderId) {
                            Text("None").tag(nil as String?)
                            ForEach(passService.folders) { folder in
                                Text(folder.name).tag(folder.id as String?)
                            }
                        }
                    }
                }

                // Notes (for non-note types)
                if itemType != .note {
                    Section("Notes") {
                        TextEditor(text: $notes)
                            .frame(minHeight: 80)
                    }
                }

                // Error message
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Item" : "New Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveItem()
                    }
                    .disabled(!isValid || isSaving)
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showPasswordGenerator) {
                PasswordGeneratorView { generatedPassword in
                    password = generatedPassword
                }
            }
        }
    }

    // MARK: - Editable Types

    private var editableTypes: [PassVaultItemType] {
        [.password, .card, .bankAccount, .note]
    }

    // MARK: - Password Fields

    private var passwordFields: some View {
        Group {
            Section("Login") {
                TextField("Username", text: $username)
                    .textContentType(.username)
                    .autocapitalization(.none)

                HStack {
                    SecureField("Password", text: $password)
                        .textContentType(.password)

                    Button {
                        showPasswordGenerator = true
                    } label: {
                        Image(systemName: "wand.and.stars")
                            .foregroundStyle(Theme.Brand.primary)
                    }
                }
            }

            Section("Websites") {
                ForEach(urls.indices, id: \.self) { index in
                    HStack {
                        TextField("URL", text: $urls[index])
                            .textContentType(.URL)
                            .autocapitalization(.none)
                            .keyboardType(.URL)

                        if urls.count > 1 {
                            Button {
                                urls.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }

                Button {
                    urls.append("")
                } label: {
                    Label("Add URL", systemImage: "plus")
                }
            }
        }
    }

    // MARK: - Card Fields

    private var cardFields: some View {
        Group {
            Section("Card Details") {
                TextField("Cardholder Name", text: $cardholderName)
                    .textContentType(.name)

                TextField("Card Number", text: $cardNumber)
                    .textContentType(.creditCardNumber)
                    .keyboardType(.numberPad)

                HStack {
                    TextField("MM", text: $expMonth)
                        .keyboardType(.numberPad)
                        .frame(width: 50)

                    Text("/")
                        .foregroundStyle(.secondary)

                    TextField("YY", text: $expYear)
                        .keyboardType(.numberPad)
                        .frame(width: 50)

                    Spacer()

                    SecureField("CVV", text: $cvv)
                        .keyboardType(.numberPad)
                        .frame(width: 80)
                }
            }
        }
    }

    // MARK: - Bank Account Fields

    private var bankAccountFields: some View {
        Group {
            Section("Bank Details") {
                TextField("Bank Name", text: $bankName)

                Picker("Account Type", selection: $accountType) {
                    Text("Checking").tag(PassBankAccountItem.PassBankAccountType.checking)
                    Text("Savings").tag(PassBankAccountItem.PassBankAccountType.savings)
                    Text("Other").tag(PassBankAccountItem.PassBankAccountType.other)
                }

                SecureField("Account Number", text: $accountNumber)
                    .keyboardType(.numberPad)

                TextField("Routing Number", text: $routingNumber)
                    .keyboardType(.numberPad)

                TextField("IBAN", text: $iban)
                    .autocapitalization(.allCharacters)
            }
        }
    }

    // MARK: - Note Fields

    private var noteFields: some View {
        Section("Content") {
            TextEditor(text: $noteContent)
                .frame(minHeight: 200)
        }
    }

    // MARK: - Validation

    private var isValid: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            return false
        }

        switch itemType {
        case .password:
            return true // Password and username can be empty
        case .card:
            return !cardNumber.isEmpty
        case .bankAccount:
            return !bankName.isEmpty && !accountNumber.isEmpty
        case .note:
            return !noteContent.trimmingCharacters(in: .whitespaces).isEmpty
        case .passkey, .file, .cryptoWallet:
            return false
        }
    }

    // MARK: - Save

    private func saveItem() {
        guard isValid else { return }

        isSaving = true
        errorMessage = nil

        Task {
            do {
                let item = buildItem()

                if isEditing {
                    try await passService.updateItem(item)
                } else {
                    try await passService.addItem(item)
                }

                await MainActor.run {
                    onSave()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }

    private func buildItem() -> PassVaultItem {
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespaces)
        let notesValue = trimmedNotes.isEmpty ? nil : trimmedNotes

        switch itemType {
        case .password:
            let filteredUrls = urls.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

            if let existing = editingItem, case .password(var item) = existing {
                item.name = trimmedName
                item.username = username
                item.password = password
                item.urls = filteredUrls
                item.notes = notesValue
                item.folderId = folderId
                item.updatedAt = now
                return .password(item)
            }

            return .password(PassPasswordItem(
                id: UUID().uuidString.lowercased(),
                type: .password,
                name: trimmedName,
                username: username,
                password: password,
                urls: filteredUrls,
                notes: notesValue,
                totp: nil,
                folderId: folderId,
                favorite: false,
                createdAt: now,
                updatedAt: now
            ))

        case .card:
            if let existing = editingItem, case .card(var item) = existing {
                item.name = trimmedName
                item.cardholderName = cardholderName
                item.number = cardNumber
                item.expMonth = expMonth
                item.expYear = expYear
                item.cvv = cvv
                item.notes = notesValue
                item.folderId = folderId
                item.updatedAt = now
                return .card(item)
            }

            return .card(PassCardItem(
                id: UUID().uuidString.lowercased(),
                type: .card,
                name: trimmedName,
                cardholderName: cardholderName,
                number: cardNumber,
                expMonth: expMonth,
                expYear: expYear,
                cvv: cvv,
                brand: nil,
                notes: notesValue,
                folderId: folderId,
                favorite: false,
                createdAt: now,
                updatedAt: now
            ))

        case .bankAccount:
            let routingValue = routingNumber.isEmpty ? nil : routingNumber
            let ibanValue = iban.isEmpty ? nil : iban

            if let existing = editingItem, case .bankAccount(var item) = existing {
                item.name = trimmedName
                item.bankName = bankName
                item.accountType = accountType
                item.accountNumber = accountNumber
                item.routingNumber = routingValue
                item.iban = ibanValue
                item.notes = notesValue
                item.folderId = folderId
                item.updatedAt = now
                return .bankAccount(item)
            }

            return .bankAccount(PassBankAccountItem(
                id: UUID().uuidString.lowercased(),
                type: .bankAccount,
                name: trimmedName,
                bankName: bankName,
                accountType: accountType,
                accountNumber: accountNumber,
                routingNumber: routingValue,
                iban: ibanValue,
                swiftBic: nil,
                notes: notesValue,
                folderId: folderId,
                favorite: false,
                createdAt: now,
                updatedAt: now
            ))

        case .note:
            if let existing = editingItem, case .note(var item) = existing {
                item.name = trimmedName
                item.content = noteContent
                item.folderId = folderId
                item.updatedAt = now
                return .note(item)
            }

            return .note(PassNoteItem(
                id: UUID().uuidString.lowercased(),
                type: .note,
                name: trimmedName,
                content: noteContent,
                folderId: folderId,
                favorite: false,
                createdAt: now,
                updatedAt: now
            ))

        case .passkey, .file, .cryptoWallet:
            fatalError("Passkeys, files, and crypto wallets cannot be created via form")
        }
    }
}

#Preview {
    PassItemFormView(
        passService: PassService(),
        onSave: {},
        onCancel: {}
    )
}
