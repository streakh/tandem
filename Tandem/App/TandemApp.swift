import SwiftUI

@main
struct TandemApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .fontDesign(.rounded)
                .tint(Theme.primary)
                .task { await store.start() }
                .onOpenURL { url in handle(url) }
        }
    }

    /// tandem://join?code=ABC123
    private func handle(_ url: URL) {
        guard url.scheme == Config.urlScheme,
              let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value, !code.isEmpty else { return }
        if store.userId == nil {
            store.pendingInviteCode = code
        } else {
            Task { await store.redeem(code: code) }
        }
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch store.phase {
            case .launching:
                ZStack {
                    Theme.background.ignoresSafeArea()
                    VStack(spacing: 16) {
                        AppMark(size: 84)
                        ProgressView()
                    }
                }
            case .signedOut:
                AuthView()
            case .onboarding:
                OnboardingView()
            case .ready:
                MainTabView()
            }
        }
        .animation(.default, value: store.phase)
        .overlay(alignment: .top) {
            if let toast = store.toast {
                ToastView(toast: toast)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { store.toast = nil }
                    .task(id: toast.id) {
                        try? await Task.sleep(for: .seconds(toast.isError ? 4.5 : 2.5))
                        if store.toast?.id == toast.id { store.toast = nil }
                    }
            }
        }
        .animation(.spring(duration: 0.35), value: store.toast)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, store.userId != nil { store.scheduleRefresh() }
        }
    }
}

/// The app's mark: two overlapping circles (two caregivers) around a paw.
struct AppMark: View {
    var size: CGFloat = 72

    var body: some View {
        ZStack {
            Circle().fill(Theme.sun).frame(width: size * 0.74, height: size * 0.74).offset(x: size * 0.16)
            Circle().fill(Theme.primary).frame(width: size * 0.74, height: size * 0.74).offset(x: -size * 0.16)
            Image(systemName: "pawprint.fill")
                .font(.system(size: size * 0.34, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size * 1.1, height: size)
        .accessibilityHidden(true)
    }
}

struct MainTabView: View {
    @Environment(AppStore.self) private var store
    @State private var tab = UserDefaults.standard.integer(forKey: "startTab")

    var body: some View {
        TabView(selection: $tab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "checklist") }.tag(0)
            PetProfileView()
                .tabItem { Label("Health", systemImage: "heart.text.square.fill") }.tag(1)
            PlansView()
                .tabItem { Label("Care plans", systemImage: "arrow.left.arrow.right.circle.fill") }.tag(2)
            HouseholdView()
                .tabItem { Label("Household", systemImage: "person.2.fill") }.tag(3)
        }
    }
}
