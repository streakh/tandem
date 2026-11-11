import SwiftUI
import PhotosUI

struct PetEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var pet: Pet
    @State private var hasBirthday = false
    @State private var weightText = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var newPhoto: UIImage?
    @State private var confirmDelete = false
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            VStack(spacing: 8) {
                                if let newPhoto {
                                    Image(uiImage: newPhoto).resizable().scaledToFill()
                                        .frame(width: 96, height: 96).clipShape(Circle())
                                } else {
                                    PetAvatar(pet: pet, size: 96)
                                }
                                Text(pet.photoPath == nil && newPhoto == nil ? "Add photo" : "Change photo")
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.primary)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section("About") {
                    TextField("Name", text: $pet.name)
                    Picker("Species", selection: $pet.species) {
                        ForEach(Species.allCases) { Text("\($0.emoji)  \($0.label)").tag($0) }
                    }
                    TextField("Breed (optional)", text: $pet.breed)
                    Picker("Sex", selection: $pet.sex) {
                        Text("Not set").tag("")
                        Text("Female").tag("Female")
                        Text("Male").tag("Male")
                    }
                    Toggle("Birthday", isOn: $hasBirthday)
                    if hasBirthday {
                        DatePicker("Born", selection: Binding(
                            get: { (pet.birthdate ?? Day.today.adding(-365)).date },
                            set: { pet.birthdate = Day($0) }), in: ...Date.now, displayedComponents: .date)
                    }
                    HStack {
                        TextField("Weight", text: $weightText).keyboardType(.decimalPad)
                        Picker("Unit", selection: $pet.weightUnit) {
                            Text("lb").tag("lb")
                            Text("kg").tag("kg")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 110)
                    }
                    TextField("Microchip number (optional)", text: $pet.microchip)
                }

                Section {
                    TextField("Behavior, quirks, what \u{201C}normal\u{201D} looks like, house rules…", text: $pet.notes, axis: .vertical)
                        .lineLimit(3...8)
                } header: {
                    Text("Good to know")
                } footer: {
                    Text("Shown to everyone who cares for \(pet.name.isEmpty ? "this pet" : pet.name), including sitters.")
                }

                Section("Veterinarian") {
                    TextField("Vet's name", text: $pet.vetName)
                    TextField("Clinic", text: $pet.vetClinic)
                    TextField("Phone", text: $pet.vetPhone).keyboardType(.phonePad)
                    TextField("Address", text: $pet.vetAddress)
                }

                Section {
                    TextField("Name", text: $pet.emergencyName)
                    TextField("Phone", text: $pet.emergencyPhone).keyboardType(.phonePad)
                } header: {
                    Text("Emergency contact")
                } footer: {
                    Text("Who a sitter should call if they can't reach you.")
                }

                Section {
                    Button("Remove \(pet.name)", role: .destructive) { confirmDelete = true }
                }
            }
            .themedForm()
            .navigationTitle("Edit \(pet.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(pet.name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear {
                hasBirthday = pet.birthdate != nil
                weightText = pet.weight.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? ""
            }
            .onChange(of: photoItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) { newPhoto = UIImage(data: data) }
                }
            }
            .alert("Remove \(pet.name)?", isPresented: $confirmDelete) {
                Button("Remove pet and all records", role: .destructive) {
                    Task { await store.delete(pet); await store.loadAll(quiet: true); dismiss() }
                Button("Cancel", role: .cancel) {}
                }
            } message: {
                Text("This deletes their routine, history and health records for everyone. It can't be undone.")
            }
        }
    }

    private func save() {
        isSaving = true
        pet.name = pet.name.trimmingCharacters(in: .whitespaces)
        if !hasBirthday { pet.birthdate = nil }
        pet.weight = Double(weightText.replacingOccurrences(of: ",", with: "."))
        let pet = pet
        Task {
            if await store.save(pet) {
                if let newPhoto { await store.setPhoto(newPhoto, for: pet) }
                dismiss()
            }
            isSaving = false
        }
    }
}

/// Shared chrome for the small health-record editors.
private struct EditorSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let canSave: Bool
    let onSave: () async -> Bool
    var onDelete: (() async -> Void)?
    @ViewBuilder var content: () -> Content

    var body: some View {
        NavigationStack {
            Form {
                content()
                if let onDelete {
                    Section {
                        Button("Delete", role: .destructive) { Task { await onDelete(); dismiss() } }
                    }
                }
            }
            .themedForm()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { if await onSave() { dismiss() } } }.disabled(!canSave)
                }
            }
        }
    }
}

struct AllergyEditor: View {
    @Environment(AppStore.self) private var store
    @State var allergy: Allergy

    private var isNew: Bool { !store.allergies.contains { $0.id == allergy.id } }

    var body: some View {
        EditorSheet(title: isNew ? "New allergy" : "Allergy",
                    canSave: !allergy.name.trimmingCharacters(in: .whitespaces).isEmpty,
                    onSave: { await store.save(allergy) },
                    onDelete: isNew ? nil : { await store.delete(allergy) }) {
            Section {
                TextField("Allergic to, e.g. Chicken", text: $allergy.name)
                Picker("Severity", selection: $allergy.severity) {
                    Text("Not set").tag("")
                    Text("Mild").tag("Mild")
                    Text("Moderate").tag("Moderate")
                    Text("Severe").tag("Severe")
                }
                TextField("What happens, what to do (optional)", text: $allergy.notes, axis: .vertical).lineLimit(2...5)
            } footer: {
                Text("Allergies are shown on the Today screen for every caregiver, including sitters.")
            }
        }
    }
}

struct MedicationEditor: View {
    @Environment(AppStore.self) private var store
    @State var medication: Medication
    @State private var addToRoutine = true
    @State private var time = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: .now) ?? .now

    private var isNew: Bool { !store.medications.contains { $0.id == medication.id } }

    var body: some View {
        EditorSheet(title: isNew ? "New medication" : "Medication",
                    canSave: !medication.name.trimmingCharacters(in: .whitespaces).isEmpty,
                    onSave: save,
                    onDelete: isNew ? nil : { await store.delete(medication) }) {
            Section {
                TextField("Name, e.g. Thyroid pill", text: $medication.name)
                TextField("Dose, e.g. 1 tablet", text: $medication.dose)
                TextField("How often, e.g. twice daily", text: $medication.frequency)
                TextField("How to give it (optional)", text: $medication.instructions, axis: .vertical).lineLimit(2...5)
                if !isNew { Toggle("Currently taking", isOn: $medication.active) }
            }
            if isNew {
                Section {
                    Toggle("Add a daily dose to the routine", isOn: $addToRoutine)
                    if addToRoutine { DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute) }
                } footer: {
                    Text("This puts the dose on the Today checklist so nobody gives it twice or misses it. You can add more doses in the routine.")
                }
            }
        }
    }

    private func save() async -> Bool {
        let wasNew = isNew
        medication.name = medication.name.trimmingCharacters(in: .whitespaces)
        guard await store.save(medication) else { return false }
        if wasNew, addToRoutine {
            await store.save(Routine(petId: medication.petId, category: .medication, title: medication.name,
                                     amount: medication.dose, timeOfDay: ClockTime(time), medicationId: medication.id))
        }
        return true
    }
}

struct VaccineEditor: View {
    @Environment(AppStore.self) private var store
    @State var vaccine: Vaccine
    @State private var hasGiven = false
    @State private var hasDue = false

    private var isNew: Bool { !store.vaccines.contains { $0.id == vaccine.id } }

    var body: some View {
        EditorSheet(title: isNew ? "New vaccine" : "Vaccine",
                    canSave: !vaccine.name.trimmingCharacters(in: .whitespaces).isEmpty,
                    onSave: {
                        if !hasGiven { vaccine.dateGiven = nil }
                        if !hasDue { vaccine.dueDate = nil }
                        return await store.save(vaccine)
                    },
                    onDelete: isNew ? nil : { await store.delete(vaccine) }) {
            Section {
                TextField("Vaccine, e.g. Rabies", text: $vaccine.name)
                Toggle("Date given", isOn: $hasGiven)
                if hasGiven {
                    DatePicker("Given", selection: Binding(get: { (vaccine.dateGiven ?? .today).date }, set: { vaccine.dateGiven = Day($0) }),
                               in: ...Date.now, displayedComponents: .date)
                }
                Toggle("Next due", isOn: $hasDue)
                if hasDue {
                    DatePicker("Due", selection: Binding(get: { (vaccine.dueDate ?? Day.today.adding(365)).date }, set: { vaccine.dueDate = Day($0) }),
                               displayedComponents: .date)
                }
                TextField("Notes (optional)", text: $vaccine.notes, axis: .vertical).lineLimit(1...4)
            }
        }
        .onAppear {
            hasGiven = vaccine.dateGiven != nil
            hasDue = vaccine.dueDate != nil
        }
    }
}

struct WeightEditor: View {
    @Environment(AppStore.self) private var store
    let pet: Pet
    @State private var text = ""
    @State private var date = Date.now

    private var value: Double? { Double(text.replacingOccurrences(of: ",", with: ".")) }

    var body: some View {
        EditorSheet(title: "Log weight", canSave: (value ?? 0) > 0, onSave: {
            guard let value else { return false }
            guard await store.save(WeightEntry(petId: pet.id, weight: value, unit: pet.weightUnit, measuredOn: Day(date))) else { return false }
            // Keep the profile's headline weight in step with the latest weigh-in.
            let latest = store.weights.filter { $0.petId == pet.id }.max { $0.measuredOn < $1.measuredOn }
            if var updated = store.pets.first(where: { $0.id == pet.id }), let latest {
                updated.weight = latest.weight
                await store.save(updated)
            }
            return true
        }) {
            Section {
                HStack {
                    TextField("Weight", text: $text).keyboardType(.decimalPad)
                    Text(pet.weightUnit).foregroundStyle(Theme.textSecondary)
                }
                DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
            }
        }
    }
}

// MARK: - Documents

struct DocumentsSection: View {
    @Environment(AppStore.self) private var store
    let pet: Pet
    @State private var photoItem: PhotosPickerItem?
    @State private var pending: UIImage?
    @State private var title = ""
    @State private var viewing: PetDocument?
    @State private var isUploading = false

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 10)]

    var body: some View {
        let documents = store.documents.filter { $0.petId == pet.id }
        VStack(alignment: .leading, spacing: 14) {
        SectionTitle("Documents") {
            PhotosPicker(selection: $photoItem, matching: .images) {
                if isUploading { ProgressView() } else { Image(systemName: "plus.circle.fill").font(.title3) }
            }
            .accessibilityLabel("Add a document photo")
        }
        if documents.isEmpty {
            Text("Keep photos of vaccine certificates, prescriptions and vet paperwork here so they're easy to find.")
                .font(.subheadline).foregroundStyle(Theme.textSecondary).card()
        } else {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(documents) { document in
                    Button { viewing = document } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            StorageImage(path: document.storagePath)
                                .frame(height: 96)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Text(document.title).font(.caption.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .card(padding: 12)
        }
        }
            .onChange(of: photoItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        title = ""
                        pending = image
                    }
                    photoItem = nil
                }
            }
            .alert("Name this document", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
                TextField("e.g. Rabies certificate", text: $title)
                Button("Save") {
                    guard let image = pending else { return }
                    isUploading = true
                    Task {
                        _ = await store.addDocument(image, title: title.isEmpty ? "Document" : title, kind: "", for: pet)
                        isUploading = false
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(item: $viewing) { document in
                NavigationStack {
                    ScrollView {
                        StorageImage(path: document.storagePath, fill: false)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(16)
                    }
                    .screenBackground()
                    .navigationTitle(document.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Close") { viewing = nil } }
                        ToolbarItem(placement: .destructiveAction) {
                            Button("Delete", role: .destructive) {
                                Task { await store.deleteDocument(document); viewing = nil }
                            }
                            .tint(Theme.danger)
                        }
                    }
                }
            }
    }
}

/// An image stored privately in Supabase Storage, downloaded with the signed-in user's access.
struct StorageImage: View {
    @Environment(AppStore.self) private var store
    let path: String
    var fill = true
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                if fill {
                    Color.clear.overlay(Image(uiImage: image).resizable().scaledToFill()).clipped()
                } else {
                    Image(uiImage: image).resizable().scaledToFit()
                }
            } else {
                Theme.surfaceMuted.overlay(ProgressView()).frame(minHeight: fill ? 0 : 260)
            }
        }
        .task(id: path) { image = await store.image(at: path) }
    }
}
