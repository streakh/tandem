import SwiftUI

struct AuthView: View {
    @Environment(AppStore.self) private var store
    @State private var isCreating = true
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @FocusState private var focus: Field?
    @State private var showReset = false

    private enum Field { case name, email, password }

    private var canSubmit: Bool {
        email.contains("@") && password.count >= 6 && (!isCreating || !name.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    AppMark(size: 88)
                    Text("Tandem")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.text)
                    Text("Everyone who cares for your pet,\non the same page.")
                        .font(.body)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 48)

                if store.pendingInviteCode != nil {
                    Label("You've been invited. Sign in or create an account to join.", systemImage: "envelope.open.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.primary)
                        .card(fill: Theme.primarySoft)
                }

                Picker("Mode", selection: $isCreating) {
                    Text("Create account").tag(true)
                    Text("Sign in").tag(false)
                }
                .pickerStyle(.segmented)

                VStack(spacing: 0) {
                    if isCreating {
                        field("Your first name", text: $name, icon: "person.fill")
                            .textContentType(.givenName)
                            .focused($focus, equals: .name)
                            .submitLabel(.next)
                            .onSubmit { focus = .email }
                        Divider().padding(.leading, 48)
                    }
                    field("Email", text: $email, icon: "envelope.fill")
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                    Divider().padding(.leading, 48)
                    HStack(spacing: 12) {
                        Image(systemName: "lock.fill").foregroundStyle(Theme.textSecondary).frame(width: 24)
                        SecureField(isCreating ? "Password (6+ characters)" : "Password", text: $password)
                            .textContentType(isCreating ? .newPassword : .password)
                            .focused($focus, equals: .password)
                            .submitLabel(.go)
                            .onSubmit { submit() }
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 54)
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(action: submit) {
                    if isWorking { ProgressView().tint(.white) } else { Text(isCreating ? "Create account" : "Sign in") }
                }
                .buttonStyle(.primary)
                .disabled(!canSubmit || isWorking)

                if !isCreating {
                    Button("Forgot password?") { showReset = true }
                        .font(.subheadline.weight(.semibold))
                }

                if isCreating {
                    Text("Your name is what other caregivers see when you log something, like \u{201C}Done by \(name.isEmpty ? "Alex" : name)\u{201D}.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .animation(.default, value: isCreating)
        .onChange(of: isCreating) { errorMessage = nil }
        .sheet(isPresented: $showReset) {
            ResetPasswordSheet(email: email.trimmingCharacters(in: .whitespaces).lowercased())
                .presentationDetents([.medium])
        }
    }

    private func field(_ title: String, text: Binding<String>, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Theme.textSecondary).frame(width: 24)
            TextField(title, text: text)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 54)
    }

    private func submit() {
        guard canSubmit, !isWorking else { return }
        focus = nil
        isWorking = true
        errorMessage = nil
        Task {
            let cleanEmail = email.trimmingCharacters(in: .whitespaces).lowercased()
            if isCreating {
                errorMessage = await store.signUp(name: name.trimmingCharacters(in: .whitespaces), email: cleanEmail, password: password)
            } else {
                errorMessage = await store.signIn(email: cleanEmail, password: password)
            }
            isWorking = false
        }
    }
}

/// Asks for the account's email and sends a reset link.
struct ResetPasswordSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var email: String
    @State private var isWorking = false
    @State private var sent = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if sent {
                    Label("Check your email", systemImage: "envelope.badge.fill")
                        .font(.title2.weight(.bold)).foregroundStyle(Theme.text)
                    Text("If there's a Tandem account for \(email), we've sent it a link. Open the link on this phone to choose a new password.")
                        .font(.body).foregroundStyle(Theme.textSecondary)
                    Button("Done") { dismiss() }.buttonStyle(.primary)
                } else {
                    Text("Reset your password").font(.title2.weight(.bold)).foregroundStyle(Theme.text)
                    Text("Enter the email you signed up with and we'll send you a link to choose a new password.")
                        .font(.subheadline).foregroundStyle(Theme.textSecondary)
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(16)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.subheadline).foregroundStyle(Theme.danger)
                    }
                    Button {
                        isWorking = true
                        errorMessage = nil
                        Task {
                            errorMessage = await store.sendPasswordReset(email: email.trimmingCharacters(in: .whitespaces).lowercased())
                            sent = errorMessage == nil
                            isWorking = false
                        }
                    } label: {
                        if isWorking { ProgressView().tint(.white) } else { Text("Send reset link") }
                    }
                    .buttonStyle(.primary)
                    .disabled(!email.contains("@") || isWorking)
                }
                Spacer(minLength: 0)
            }
            .padding(24)
            .screenBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

/// Shown after opening a reset link: choose the new password.
struct NewPasswordView: View {
    @Environment(AppStore.self) private var store
    @State private var password = ""
    @State private var confirm = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var isValid: Bool { password.count >= 6 && password == confirm }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Choose a new password").font(.title.weight(.heavy)).foregroundStyle(Theme.text)
                Text("At least 6 characters.").font(.subheadline).foregroundStyle(Theme.textSecondary)
                VStack(spacing: 0) {
                    SecureField("New password", text: $password)
                        .textContentType(.newPassword)
                        .padding(.horizontal, 16).frame(minHeight: 54)
                    Divider().padding(.leading, 16)
                    SecureField("Type it again", text: $confirm)
                        .textContentType(.newPassword)
                        .padding(.horizontal, 16).frame(minHeight: 54)
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))

                if !confirm.isEmpty, password != confirm {
                    Text("Those don't match yet.").font(.subheadline).foregroundStyle(Theme.warning)
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                        .font(.subheadline).foregroundStyle(Theme.danger)
                }
                Button {
                    isWorking = true
                    Task {
                        errorMessage = await store.setNewPassword(password)
                        isWorking = false
                    }
                } label: {
                    if isWorking { ProgressView().tint(.white) } else { Text("Save password") }
                }
                .buttonStyle(.primary)
                .disabled(!isValid || isWorking)
                Spacer(minLength: 0)
            }
            .padding(24)
            .screenBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Not now") { store.needsNewPassword = false } }
            }
        }
    }
}
