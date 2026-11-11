import SwiftUI
import Charts

/// The pet's central record: who they are and everything medical, in one place.
struct PetProfileView: View {
    @Environment(AppStore.self) private var store
    @State private var showEditPet = false
    @State private var showAddPet = false
    @State private var showVetSummary = false
    @State private var allergy: Allergy?
    @State private var medication: Medication?
    @State private var vaccine: Vaccine?
    @State private var showWeight = false

    var body: some View {
        NavigationStack {
            Group {
                if let pet = store.selectedPet {
                    content(pet)
                } else {
                    ScrollView {
                        EmptyState(icon: "heart.text.square.fill", title: "No pets yet",
                                   message: "Add a pet to keep their allergies, medications, vaccines and vet details in one place.",
                                   actionTitle: store.primaryHousehold == nil ? nil : "Add a pet") { showAddPet = true }
                            .padding(.top, 60)
                    }
                }
            }
            .screenBackground()
            .navigationTitle("Health")
            .toolbar {
                if store.primaryHousehold != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showAddPet = true } label: { Label("Add a pet", systemImage: "plus.circle.fill").font(.title3) }
                    }
                }
            }
            .fullScreenCover(isPresented: $showAddPet) { SetupFlow(household: store.primaryHousehold) }
            .sheet(isPresented: $showEditPet) {
                if let pet = store.selectedPet { PetEditor(pet: pet) }
            }
            .sheet(isPresented: $showVetSummary) {
                if let pet = store.selectedPet { VetSummaryView(pet: pet) }
            }
            .sheet(item: $allergy) { AllergyEditor(allergy: $0) }
            .sheet(item: $medication) { MedicationEditor(medication: $0) }
            .sheet(item: $vaccine) { VaccineEditor(vaccine: $0) }
            .sheet(isPresented: $showWeight) {
                if let pet = store.selectedPet { WeightEditor(pet: pet).presentationDetents([.medium]) }
            }
        }
    }

    private func content(_ pet: Pet) -> some View {
        let canEdit = store.canEdit(pet)
        let allergies = store.allergies.filter { $0.petId == pet.id }
        let medications = store.medications.filter { $0.petId == pet.id }
        let vaccines = store.vaccines.filter { $0.petId == pet.id }
        let weights = store.weights.filter { $0.petId == pet.id }

        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if store.sortedPets.count > 1 { PetSwitcher() }

                // Identity
                HStack(spacing: 16) {
                    if canEdit {
                        Button { showEditPet = true } label: {
                            PetAvatar(pet: pet, size: 84)
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: "camera.fill")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(Theme.onPrimary)
                                        .frame(width: 28, height: 28)
                                        .background(Theme.primary, in: Circle())
                                        .overlay(Circle().strokeBorder(Theme.surface, lineWidth: 2))
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit \(pet.name)'s profile and photo")
                    } else {
                        PetAvatar(pet: pet, size: 84)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pet.name).font(.title.weight(.heavy)).foregroundStyle(Theme.text)
                        Text([pet.species.label, pet.breed].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(Theme.textSecondary)
                        let vitals = [pet.ageLabel, pet.weightLabel].compactMap { $0 }.joined(separator: " · ")
                        if !vitals.isEmpty {
                            Text(vitals).font(.subheadline).foregroundStyle(Theme.textSecondary)
                        }
                        if !canEdit { Pill(text: "You're sitting", icon: "person.badge.clock.fill", color: Theme.warning, soft: Theme.warningSoft) }
                    }
                    Spacer(minLength: 0)
                    if canEdit {
                        Button { showEditPet = true } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.onPrimary)
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                    }
                }
                .card()

                if canEdit {
                    Button { showVetSummary = true } label: {
                        Label("Share with a vet", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.primary)

                    HStack(spacing: 10) {
                        NavigationLink { RoutineListView(petId: pet.id) } label: {
                            quickLink("Routine", icon: "list.bullet.clipboard.fill")
                        }
                        NavigationLink { HistoryView(petId: pet.id) } label: {
                            quickLink("History", icon: "clock.arrow.circlepath")
                        }
                    }
                    .buttonStyle(.plain)
                }

                // Allergies
                section("Allergies", canAdd: canEdit) { allergy = Allergy(petId: pet.id) }
                if allergies.isEmpty {
                    placeholder(canEdit ? "No known allergies. Add any food, medication or environmental allergies." : "No known allergies.")
                } else {
                    FlowLayout(spacing: 8) {
                        ForEach(allergies) { item in
                            Button { if canEdit { allergy = item } } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "exclamationmark.triangle.fill").font(.caption2)
                                    Text(item.name).font(.subheadline.weight(.semibold))
                                    if !item.severity.isEmpty { Text("· \(item.severity)").font(.caption) }
                                }
                                .foregroundStyle(Theme.danger)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Theme.dangerSoft, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .card()
                }

                // Medications (a sitter only sees these if the plan includes medication)
                if canEdit || !medications.isEmpty {
                    section("Medications", canAdd: canEdit) { medication = Medication(petId: pet.id) }
                    if medications.isEmpty {
                        placeholder("No medications. Add one, then schedule its doses in the routine.")
                    } else {
                        listCard(medications) { item in
                            Button { if canEdit { medication = item } } label: {
                                row(icon: "pills.fill", tint: CareCategory.medication.tint,
                                    title: item.name, subtitle: item.summary.isEmpty ? item.instructions : item.summary) {
                                    if !item.active { Pill(text: "Stopped", color: Theme.textSecondary, soft: Theme.surfaceMuted) }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if canEdit {
                    // Vaccines
                    section("Vaccines", canAdd: true) { vaccine = Vaccine(petId: pet.id) }
                    if vaccines.isEmpty {
                        placeholder("No vaccine records. Add them with their due dates and you'll see them under Coming up.")
                    } else {
                        listCard(vaccines) { item in
                            Button { vaccine = item } label: {
                                row(icon: "syringe.fill", tint: Theme.primary, title: item.name,
                                    subtitle: item.dateGiven.map { "Given \($0.longLabel)" } ?? "") {
                                    VaccinePill(vaccine: item)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Weight
                    section("Weight", canAdd: true) { showWeight = true }
                    if weights.isEmpty {
                        placeholder(pet.weightLabel.map { "Currently \($0). Log weigh-ins to see the trend." } ?? "No weigh-ins logged.")
                    } else {
                        WeightCard(weights: weights)
                    }
                }

                // Contacts
                if pet.hasVetInfo || pet.hasEmergencyInfo || canEdit {
                    section("Vet & emergency", canAdd: false) {}
                    VStack(alignment: .leading, spacing: 14) {
                        if pet.hasVetInfo {
                            ContactRow(title: [pet.vetName, pet.vetClinic].filter { !$0.isEmpty }.joined(separator: " · "),
                                       subtitle: pet.vetAddress, phone: pet.vetPhone, icon: "cross.case.fill")
                        }
                        if pet.hasVetInfo, pet.hasEmergencyInfo { Divider() }
                        if pet.hasEmergencyInfo {
                            ContactRow(title: pet.emergencyName.isEmpty ? "Emergency contact" : pet.emergencyName,
                                       subtitle: "Emergency contact", phone: pet.emergencyPhone, icon: "staroflife.fill")
                        }
                        if !pet.hasVetInfo, !pet.hasEmergencyInfo {
                            Button("Add vet and emergency contacts") { showEditPet = true }.font(.subheadline.weight(.semibold))
                        }
                    }
                    .card()
                }

                if !pet.notes.isEmpty {
                    section("Good to know", canAdd: false) {}
                    Text(pet.notes).font(.body).foregroundStyle(Theme.text).card(fill: Theme.sunSoft)
                }

                if canEdit {
                    DocumentsSection(pet: pet)
                    if !pet.microchip.isEmpty {
                        DetailRow(label: "Microchip", value: pet.microchip, icon: "barcode").card()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .refreshable { await store.loadAll() }
    }

    // MARK: Building blocks

    private func quickLink(_ title: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(Theme.primary)
            Text(title).font(.headline).foregroundStyle(Theme.text)
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textSecondary)
        }
        .card(padding: 14)
    }

    private func section(_ title: String, canAdd: Bool, add: @escaping () -> Void) -> some View {
        SectionTitle(title) {
            if canAdd {
                Button(action: add) { Image(systemName: "plus.circle.fill").font(.title3) }
                    .accessibilityLabel("Add to \(title)")
            }
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(Theme.textSecondary).card()
    }

    private func listCard<Item: Identifiable, Row: View>(_ items: [Item], @ViewBuilder row: @escaping (Item) -> Row) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider().padding(.leading, 52) }
                row(item).padding(.vertical, 10)
            }
        }
        .card(padding: 14)
    }

    private func row<Trailing: View>(icon: String, tint: Color, title: String, subtitle: String,
                                     @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.body.weight(.semibold)).foregroundStyle(tint)
                .frame(width: 38, height: 38).background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Theme.text)
                if !subtitle.isEmpty { Text(subtitle).font(.subheadline).foregroundStyle(Theme.textSecondary) }
            }
            Spacer(minLength: 0)
            trailing()
        }
        .contentShape(Rectangle())
    }
}

struct VaccinePill: View {
    let vaccine: Vaccine

    var body: some View {
        switch vaccine.status {
        case .upToDate: Pill(text: "Up to date", icon: "checkmark", color: Theme.success, soft: Theme.successSoft)
        case .dueSoon: Pill(text: "Due \(vaccine.dueDate?.shortLabel ?? "soon")", color: Theme.warning, soft: Theme.warningSoft)
        case .overdue: Pill(text: "Overdue", icon: "exclamationmark", color: Theme.danger, soft: Theme.dangerSoft)
        case .unknown: Pill(text: "No date", color: Theme.textSecondary, soft: Theme.surfaceMuted)
        }
    }
}

struct ContactRow: View {
    let title: String
    let subtitle: String
    let phone: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.body.weight(.semibold)).foregroundStyle(Theme.primary)
                .frame(width: 38, height: 38).background(Theme.primarySoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title.isEmpty ? "Veterinarian" : title).font(.headline).foregroundStyle(Theme.text)
                if !subtitle.isEmpty { Text(subtitle).font(.subheadline).foregroundStyle(Theme.textSecondary) }
                if !phone.isEmpty { Text(phone).font(.subheadline).foregroundStyle(Theme.textSecondary) }
            }
            Spacer(minLength: 0)
            if !phone.isEmpty, let url = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
                Link(destination: url) {
                    Image(systemName: "phone.fill")
                        .foregroundStyle(Theme.onPrimary)
                        .frame(width: 44, height: 44)
                        .background(Theme.success, in: Circle())
                }
                .accessibilityLabel("Call \(title)")
            }
        }
    }
}

private struct WeightCard: View {
    let weights: [WeightEntry]

    var body: some View {
        let sorted = weights.sorted { $0.measuredOn < $1.measuredOn }
        VStack(alignment: .leading, spacing: 10) {
            if let last = sorted.last {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(last.weight.formatted(.number.precision(.fractionLength(0...1)))) \(last.unit)")
                        .font(.title2.weight(.bold)).foregroundStyle(Theme.text)
                    Text("on \(last.measuredOn.longLabel)").font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
            }
            if sorted.count > 1 {
                Chart(sorted) { entry in
                    LineMark(x: .value("Date", entry.measuredOn.date), y: .value("Weight", entry.weight))
                        .foregroundStyle(Theme.primary)
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Date", entry.measuredOn.date), y: .value("Weight", entry.weight))
                        .foregroundStyle(Theme.primary)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 120)
                .accessibilityLabel("Weight over time")
            }
        }
        .card()
    }
}

/// Wraps chips onto as many lines as they need.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
