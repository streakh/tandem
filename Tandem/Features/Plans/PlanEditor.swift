import SwiftUI

/// Builds a care plan from the routine that already exists, so the owner never retypes sitter instructions.
struct PlanEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var draft: PlanDraft
    var onSaved: (CarePlan) -> Void

    @State private var isSaving = false
    @State private var didSetDefaults = false

    private var householdPets: [Pet] { store.pets.filter { $0.householdId == draft.plan.householdId } }
    private var selectedPets: [Pet] { householdPets.filter { draft.petIds.contains($0.id) } }

    /// Categories that actually have tasks for the chosen pets.
    private var availableCategories: [CareCategory] {
        let routines = store.routines.filter { draft.petIds.contains($0.petId) && $0.active }
        return CareCategory.routineCases.filter { category in routines.contains { $0.category == category } }
    }

    private func taskCount(_ category: CareCategory) -> Int {
        store.routines.filter { draft.petIds.contains($0.petId) && $0.active && $0.category == category }.count
    }

    private var isValid: Bool {
        !draft.petIds.isEmpty && draft.plan.endDate >= draft.plan.startDate && !draft.plan.categories.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Their name, e.g. Fano", text: $draft.plan.caregiverLabel)
                        .textContentType(.givenName)
                } header: {
                    Text("Who's taking over?")
                } footer: {
                    Text("They'll get an invite code. No need for their email.")
                }

                if householdPets.count > 1 {
                    Section("Which pets?") {
                        ForEach(householdPets) { pet in
                            let isOn = draft.petIds.contains(pet.id)
                            Button {
                                if isOn { draft.petIds.remove(pet.id) } else { draft.petIds.insert(pet.id) }
                                syncCategories()
                            } label: {
                                HStack(spacing: 12) {
                                    PetAvatar(pet: pet, size: 36)
                                    Text(pet.name).foregroundStyle(Theme.text)
                                    Spacer()
                                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                        .font(.title3).foregroundStyle(isOn ? Theme.primary : Theme.separator)
                                }
                            }
                            .accessibilityAddTraits(isOn ? .isSelected : [])
                        }
                    }
                }

                Section {
                    DatePicker("From", selection: day(\.startDate), displayedComponents: .date)
                    DatePicker("Until", selection: day(\.endDate), in: draft.plan.startDate.date..., displayedComponents: .date)
                } header: {
                    Text("When?")
                } footer: {
                    Text("Their access ends automatically after the last day.")
                }

                Section {
                    if draft.petIds.isEmpty {
                        Text("Choose a pet first.").foregroundStyle(Theme.textSecondary)
                    } else if availableCategories.isEmpty {
                        Text("There's no routine set up yet. Add tasks on the Today tab first, and they'll appear here.")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    ForEach(availableCategories) { category in
                        Toggle(isOn: Binding(
                            get: { draft.plan.categories.contains(category) },
                            set: { on in
                                if on { draft.plan.categories.append(category) } else { draft.plan.categories.removeAll { $0 == category } }
                            })) {
                            HStack(spacing: 12) {
                                CategoryIcon(category: category, size: 34)
                                VStack(alignment: .leading) {
                                    Text(category.label)
                                    Text("\(taskCount(category)) \(taskCount(category) == 1 ? "task" : "tasks")")
                                        .font(.caption).foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("What should they handle?")
                } footer: {
                    Text("Taken from the routine you already set up. They always see allergies and your vet and emergency contacts; they never see vaccines, weight, documents or older history.")
                }

                Section {
                    TextField("House quirks, where things are kept, what to watch for…", text: $draft.plan.notes, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("Notes for \(draft.plan.caregiverLabel.isEmpty ? "the sitter" : draft.plan.caregiverLabel)")
                }

                Section {
                    TextField("Who to call, what counts as an emergency, how much they can spend at the vet…", text: $draft.plan.emergencyNotes, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("In an emergency")
                }
            }
            .themedForm()
            .navigationTitle(draft.isNew ? "New care plan" : "Edit care plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(draft.isNew ? "Create" : "Save", action: save).disabled(!isValid || isSaving)
                }
            }
            .onAppear {
                guard !didSetDefaults else { return }
                didSetDefaults = true
                if draft.isNew, draft.plan.categories.isEmpty { draft.plan.categories = availableCategories }
                if draft.isNew, draft.plan.emergencyNotes.isEmpty { draft.plan.emergencyNotes = defaultEmergencyNotes }
            }
            .onChange(of: draft.plan.startDate) { _, start in
                if draft.plan.endDate < start { draft.plan.endDate = start }
            }
        }
    }

    /// Keep the chosen categories limited to ones that exist; for a new plan, default to all of them.
    private func syncCategories() {
        let available = availableCategories
        if draft.isNew {
            draft.plan.categories = available
        } else {
            draft.plan.categories.removeAll { !available.contains($0) }
        }
    }

    private var defaultEmergencyNotes: String {
        var lines: [String] = []
        lines.append("Call me first: \(store.myName).")
        if let pet = selectedPets.first ?? householdPets.first {
            if pet.hasEmergencyInfo {
                lines.append("If you can't reach me: \([pet.emergencyName, pet.emergencyPhone].filter { !$0.isEmpty }.joined(separator: ", ")).")
            }
            if pet.hasVetInfo {
                lines.append("Vet: \([pet.vetClinic.isEmpty ? pet.vetName : pet.vetClinic, pet.vetPhone].filter { !$0.isEmpty }.joined(separator: ", ")).")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func day(_ keyPath: WritableKeyPath<CarePlan, Day>) -> Binding<Date> {
        Binding(get: { draft.plan[keyPath: keyPath].date }, set: { draft.plan[keyPath: keyPath] = Day($0) })
    }

    private func save() {
        isSaving = true
        draft.plan.caregiverLabel = draft.plan.caregiverLabel.trimmingCharacters(in: .whitespaces)
        let draft = draft
        Task {
            if let saved = await store.savePlan(draft.plan, petIds: draft.petIds, isNew: draft.isNew) {
                dismiss()
                onSaved(saved)
            }
            isSaving = false
        }
    }
}
