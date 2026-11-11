import SwiftUI
import CoreImage.CIFilterBuiltins

/// Enter an invite code to join a household or accept a sitter's care plan.
struct JoinCodeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var isWorking = false
    @FocusState private var focused: Bool

    private var cleaned: String { String(code.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6)) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "ticket.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 76, height: 76)
                    .background(Theme.primarySoft, in: Circle())
                    .padding(.top, 24)
                Text("Enter your invite code")
                    .font(.title2.weight(.bold))
                Text("The pet's owner can find this 6-character code in their Tandem app and send it to you.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)

                TextField("ABC123", text: $code)
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .padding(.vertical, 14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                    .onChange(of: code) { if code != cleaned { code = cleaned } }
                    .accessibilityLabel("Invite code")

                Button {
                    isWorking = true
                    Task {
                        let result = await store.redeem(code: cleaned)
                        isWorking = false
                        if result != nil { dismiss() }
                    }
                } label: {
                    if isWorking { ProgressView().tint(.white) } else { Text("Join") }
                }
                .buttonStyle(.primary)
                .disabled(cleaned.count < 6 || isWorking)

                Spacer()
            }
            .padding(.horizontal, 24)
            .screenBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear { focused = true }
        }
    }
}

/// Shows an invite code with ways to pass it on: copy, share sheet, QR.
struct InviteCodeCard: View {
    let code: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Text(code)
                .font(.system(size: 36, weight: .heavy, design: .monospaced))
                .tracking(6)
                .foregroundStyle(Theme.text)
                .textSelection(.enabled)
                .accessibilityLabel("Invite code \(code.map(String.init).joined(separator: " "))")

            if let qr = QRCode.image(for: Config.inviteURL(code: code).absoluteString) {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 132, height: 132)
                    .padding(10)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityLabel("QR code for this invite")
                Text("They can scan this with their camera once Tandem is installed.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = code
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.secondary)

                ShareLink(item: "\(message)\n\nInvite code: \(code)\n\(Config.inviteURL(code: code).absoluteString)") {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.primary)
            }
        }
        .frame(maxWidth: .infinity)
        .card()
    }
}

enum QRCode {
    static func image(for string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
