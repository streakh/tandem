import SwiftUI
import UIKit

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }

    /// A color that adapts to light and dark mode.
    init(light: UInt, dark: UInt) {
        self.init(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

/// Warm cream and teal, carried over from the wireframes and tuned for contrast and dark mode.
enum Theme {
    static let background = Color(light: 0xF7F2E8, dark: 0x121514)
    static let surface = Color(light: 0xFFFFFF, dark: 0x1D2221)
    static let surfaceMuted = Color(light: 0xEFE8DA, dark: 0x282E2C)
    static let primary = Color(light: 0x2A867A, dark: 0x5EC4B4)
    static let primarySoft = Color(light: 0xDCEFEB, dark: 0x1D3A36)
    /// Text and icons that sit on top of `primary` or `success` fills.
    static let onPrimary = Color(light: 0xFFFFFF, dark: 0x0C211E)
    static let sun = Color(light: 0xE9BF45, dark: 0xE9C75A)
    static let sunSoft = Color(light: 0xFBF0CC, dark: 0x38311B)
    static let success = Color(light: 0x3A9460, dark: 0x5FC088)
    static let successSoft = Color(light: 0xDFF1E5, dark: 0x1C3626)
    static let warning = Color(light: 0xC97A1E, dark: 0xE9A24E)
    static let warningSoft = Color(light: 0xFBEBD5, dark: 0x3A2C17)
    static let danger = Color(light: 0xC04A35, dark: 0xEE7C66)
    static let dangerSoft = Color(light: 0xFADFD9, dark: 0x3D1F19)
    static let text = Color(light: 0x1F2B28, dark: 0xEEF2F0)
    static let textSecondary = Color(light: 0x66726E, dark: 0x9DA9A5)
    static let separator = Color(light: 0xE6DFD0, dark: 0x2F3634)

    static let cornerRadius: CGFloat = 18
    static let spacing: CGFloat = 16
}

// MARK: - Surfaces

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16
    var fill: Color = Theme.surface

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

extension View {
    func card(padding: CGFloat = 16, fill: Color = Theme.surface) -> some View {
        modifier(CardModifier(padding: padding, fill: fill))
    }

    /// Standard page: cream background, scrolling content with comfortable margins.
    func screenBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
            .presentationBackground(Theme.background)
    }

    /// Makes a native `Form` sit on the app's cream background.
    func themedForm() -> some View {
        scrollContentBackground(.hidden).background(Theme.background.ignoresSafeArea())
            .presentationBackground(Theme.background)
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.primary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.onPrimary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(tint.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Theme.primarySoft.opacity(configuration.isPressed ? 0.6 : 1),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

// MARK: - Small pieces

struct CategoryIcon: View {
    let category: CareCategory
    var size: CGFloat = 44
    var dimmed = false

    var body: some View {
        Image(systemName: category.icon)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(dimmed ? Theme.textSecondary : category.tint)
            .frame(width: size, height: size)
            .background((dimmed ? Theme.textSecondary : category.tint).opacity(0.14),
                        in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct Pill: View {
    let text: String
    var icon: String?
    var color: Color = Theme.primary
    var soft: Color = Theme.primarySoft

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.caption2.weight(.bold)) }
            Text(text).font(.caption.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(soft, in: Capsule())
    }
}

struct SectionTitle<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            trailing()
        }
        .padding(.top, 8)
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.primary)
                .frame(width: 76, height: 76)
                .background(Theme.primarySoft, in: Circle())
            Text(title).font(.title3.weight(.bold)).foregroundStyle(Theme.text)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.primary)
                    .padding(.top, 6)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

/// A pet's photo, or its species emoji on a soft circle when there's no photo.
struct PetAvatar: View {
    @Environment(AppStore.self) private var store
    let pet: Pet
    var size: CGFloat = 56
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Circle().fill(Theme.sunSoft)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(pet.species.emoji).font(.system(size: size * 0.5))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: pet.photoPath) {
            guard let path = pet.photoPath else { image = nil; return }
            image = await store.image(at: path)
        }
        .accessibilityLabel(pet.name)
    }
}

struct InitialsAvatar: View {
    let name: String
    var size: CGFloat = 40
    var color: Color = Theme.primary

    var body: some View {
        Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.15), in: Circle())
            .accessibilityHidden(true)
    }
}

struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(toast.isError ? Theme.danger : Theme.success)
            Text(toast.message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, 16)
    }
}

/// A labelled row for read-only details ("Clinic — Shadyside Vet").
struct DetailRow: View {
    let label: String
    let value: String
    var icon: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let icon {
                Image(systemName: icon).foregroundStyle(Theme.primary).frame(width: 22)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(Theme.textSecondary)
                Text(value).font(.body).foregroundStyle(Theme.text)
            }
            Spacer(minLength: 0)
        }
    }
}
