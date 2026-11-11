import SwiftUI

struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @State private var showSetup = false
    @State private var showJoin = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                AppMark(size: 72).padding(.top, 40)
                Text("Welcome, \(store.myName)")
                    .font(.largeTitle.weight(.heavy))
                    .foregroundStyle(Theme.text)
                Text("How are you starting out?")
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)

                choice(icon: "pawprint.fill", title: "Set up my pet",
                       detail: "Add your pet and their routine once. Then invite the people who help care for them.") {
                    showSetup = true
                }
                choice(icon: "ticket.fill", title: "I have an invite code",
                       detail: "Join a household you share a pet with, or open a care plan a pet owner sent you.") {
                    showJoin = true
                }

                Button("Sign out") { Task { await store.signOut() } }
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 12)
            }
            .padding(.horizontal, 24)
        }
        .screenBackground()
        .fullScreenCover(isPresented: $showSetup) { SetupFlow() }
        .sheet(isPresented: $showJoin) { JoinCodeView() }
    }

    private func choice(icon: String, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 56, height: 56)
                    .background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).foregroundStyle(Theme.text)
                    Text(detail).font(.subheadline).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Theme.textSecondary)
            }
            .card()
        }
        .buttonStyle(.plain)
    }
}

/// Three quick steps: household name, first pet, starter routine. Used at first launch and when adding another pet.
struct SetupFlow: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// When set, skips the household step and adds the pet to this household.
    var household: Household?

    @State private var step = 0
    @State private var householdName = ""
    @State private var petName = ""
    @State private var species: Species = .dog
    @State private var templates: [RoutineTemplate] = []
    @State private var chosen: Set<UUID> = []
    @State private var isSaving = false
    @FocusState private var focused: Bool

    private var firstStep: Int { household == nil ? 0 : 1 }
    private var trimmedPetName: String { petName.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step - firstStep + 1), total: Double(3 - firstStep))
                    .tint(Theme.primary)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch step {
                        case 0: householdStep
                        case 1: petStep
                        default: routineStep
                        }
                    }
                    .padding(24)
                }
                .scrollDismissesKeyboard(.interactively)

                Button(action: next) {
                    if isSaving { ProgressView().tint(.white) } else { Text(step == 2 ? "Finish" : "Continue") }
                }
                .buttonStyle(.primary)
                .disabled(!canContinue || isSaving)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .screenBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step > firstStep {
                        Button("Back") { withAnimation { step -= 1 } }
                    } else {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .onAppear {
                step = firstStep
                if householdName.isEmpty { householdName = "\(store.myName)'s household" }
            }
        }
    }

    private var canContinue: Bool {
        switch step {
        case 0: !householdName.trimmingCharacters(in: .whitespaces).isEmpty
        case 1: !trimmedPetName.isEmpty
        default: true
        }
    }

    private var householdStep: some View {
        Group {
            header("Name your household", "This is the group of people who share your pets day to day: roommates, partners, family.")
            TextField("Household name", text: $householdName)
                .font(.title3)
                .padding(16)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                .focused($focused)
        }
    }

    private var petStep: some View {
        Group {
            header("Who are we caring for?", "You can add a photo, health details and more pets later.")
            TextField("Pet's name", text: $petName)
                .font(.title3)
                .padding(16)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                .focused($focused)
            Text("Species").font(.headline).foregroundStyle(Theme.text)
            SpeciesGrid(selection: $species)
        }
    }

    private var routineStep: some View {
        Group {
            header("\(trimmedPetName)'s routine", "Pick what applies. You can change times, add amounts, and add more tasks any time.")
            VStack(spacing: 10) {
                ForEach(templates) { template in
                    let isOn = chosen.contains(template.id)
                    Button {
                        if isOn { chosen.remove(template.id) } else { chosen.insert(template.id) }
                    } label: {
                        HStack(spacing: 14) {
                            CategoryIcon(category: template.category, size: 40, dimmed: !isOn)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.title).font(.headline).foregroundStyle(Theme.text)
                                Text(template.routine(petId: UUID()).scheduleLabel)
                                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                .font(.title2)
                                .foregroundStyle(isOn ? Theme.primary : Theme.separator)
                        }
                        .card(padding: 12)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
    }

    private func header(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.title.weight(.heavy)).foregroundStyle(Theme.text)
            Text(subtitle).font(.body).foregroundStyle(Theme.textSecondary)
        }
    }

    private func next() {
        focused = false
        if step == 1 {
            templates = RoutineTemplate.suggestions(for: species)
            chosen = Set(templates.filter { $0.schedule == .daily }.map(\.id))
        }
        if step < 2 {
            withAnimation { step += 1 }
            return
        }
        isSaving = true
        Task {
            store.holdPhase = true
            defer { store.holdPhase = false; store.updatePhase() }
            var householdId = household?.id
            if householdId == nil {
                householdId = await store.createHousehold(name: householdName.trimmingCharacters(in: .whitespaces))
            }
            guard let householdId else { isSaving = false; return }
            let pet = Pet(householdId: householdId, name: trimmedPetName, species: species)
            guard await store.save(pet) else { isSaving = false; return }
            for template in templates where chosen.contains(template.id) {
                await store.save(template.routine(petId: pet.id))
            }
            store.selectPet(pet.id)
            store.track("pet_added", ["species": species.rawValue])
            await store.loadAll(quiet: true)
            isSaving = false
            dismiss()
        }
    }
}

struct SpeciesGrid: View {
    @Binding var selection: Species
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Species.allCases) { species in
                let isOn = selection == species
                Button {
                    selection = species
                } label: {
                    VStack(spacing: 6) {
                        Text(species.emoji).font(.system(size: 30))
                        Text(species.label).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    }
                    .frame(maxWidth: .infinity, minHeight: 84)
                    .background(isOn ? Theme.primarySoft : Theme.surface,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(isOn ? Theme.primary : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}
