import SwiftUI

/// Everything that repeats for one pet, grouped by kind of care.
struct RoutineListView: View {
    @Environment(AppStore.self) private var store
    let petId: UUID
    @State private var editing: Routine?
    @State private var isNew = false

    private var pet: Pet? { store.pets.first { $0.id == petId } }

    var body: some View {
        let routines = store.routines.filter { $0.petId == petId }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if routines.isEmpty {
                    EmptyState(icon: "list.bullet.clipboard", title: "No routine yet",
                               message: "Add feeding, walks, medication and anything else that repeats. Everyone who helps will see the same list.",
                               actionTitle: "Add a task") { add() }
                }
                ForEach(CareCategory.routineCases) { category in
                    let group = routines.filter { $0.category == category }
                    if !group.isEmpty {
                        SectionTitle(category.label)
                        VStack(spacing: 10) {
                            ForEach(group) { routine in
                                Button {
                                    isNew = false
                                    editing = routine
                                } label: {
                                    HStack(spacing: 12) {
                                        CategoryIcon(category: routine.category, size: 40, dimmed: !routine.active)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(routine.title).font(.headline)
                                                .foregroundStyle(routine.active ? Theme.text : Theme.textSecondary)
                                            Text(routine.active ? routine.scheduleLabel : "Paused")
                                                .font(.subheadline).foregroundStyle(Theme.textSecondary)
                                            if !routine.amount.isEmpty {
                                                Text(routine.amount).font(.subheadline).foregroundStyle(Theme.textSecondary)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textSecondary)
                                    }
                                    .card(padding: 12)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .navigationTitle("\(pet?.name ?? "Pet")'s routine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { add() } label: { Label("Add a task", systemImage: "plus") }
            }
        }
        .sheet(item: $editing) { routine in RoutineEditor(routine: routine, isNew: isNew) }
    }

    private func add() {
        isNew = true
        editing = Routine(petId: petId)
    }
}

struct RoutineEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var routine: Routine
    let isNew: Bool

    @State private var hasTime = false
    @State private var time = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: .now) ?? .now
    @State private var hasEnd = false
    @State private var confirmDelete = false

    private var medications: [Medication] { store.medications.filter { $0.petId == routine.petId && $0.active } }

    private var isValid: Bool {
        !routine.title.trimmingCharacters(in: .whitespaces).isEmpty
            && (routine.schedule != .weekly || !routine.weekdays.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What kind of care?") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(CareCategory.routineCases) { category in
                                let isOn = routine.category == category
                                Button {
                                    routine.category = category
                                } label: {
                                    VStack(spacing: 6) {
                                        CategoryIcon(category: category, size: 46, dimmed: !isOn)
                                        Text(category.label)
                                            .font(.caption.weight(isOn ? .bold : .regular))
                                            .foregroundStyle(isOn ? Theme.text : Theme.textSecondary)
                                    }
                                    .frame(minWidth: 68)
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(isOn ? .isSelected : [])
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 0))
                }

                Section {
                    TextField(titlePlaceholder, text: $routine.title)
                    TextField(amountPlaceholder, text: $routine.amount)
                    TextField("Instructions (optional)", text: $routine.details, axis: .vertical).lineLimit(1...5)
                    if routine.category == .medication, !medications.isEmpty {
                        Picker("Medication", selection: $routine.medicationId) {
                            Text("None").tag(UUID?.none)
                            ForEach(medications) { Text($0.name).tag(UUID?.some($0.id)) }
                        }
                    }
                } header: {
                    Text("Details")
                } footer: {
                    Text("Amounts and instructions show up for whoever does the task, including a sitter.")
                }

                Section("When") {
                    Picker("Repeats", selection: $routine.schedule) {
                        ForEach(ScheduleKind.allCases) { Text($0.label).tag($0) }
                    }
                    switch routine.schedule {
                    case .daily:
                        EmptyView()
                    case .weekly:
                        WeekdayPicker(selection: $routine.weekdays)
                    case .interval:
                        Stepper(value: Binding(get: { routine.intervalDays ?? 7 }, set: { routine.intervalDays = $0 }), in: 2...90) {
                            Text("Every \(routine.intervalDays ?? 7) days")
                        }
                        HStack {
                            ForEach([(7, "Weekly"), (14, "2 weeks"), (30, "Monthly"), (90, "3 months")], id: \.0) { days, label in
                                Button(label) { routine.intervalDays = days }
                                    .buttonStyle(.bordered)
                                    .tint(routine.intervalDays == days ? Theme.primary : .gray)
                                    .font(.caption)
                            }
                        }
                        DatePicker("First due", selection: dayBinding(\.startDate), displayedComponents: .date)
                    case .once:
                        DatePicker("Date", selection: dayBinding(\.startDate), displayedComponents: .date)
                    }

                    Toggle("At a set time", isOn: $hasTime)
                    if hasTime {
                        DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    }

                    if routine.schedule != .once {
                        Toggle("Has an end date", isOn: $hasEnd)
                        if hasEnd {
                            DatePicker("Ends", selection: Binding(
                                get: { (routine.endDate ?? Day.today.adding(10)).date },
                                set: { routine.endDate = Day($0) }), displayedComponents: .date)
                        }
                    }
                }

                if !isNew {
                    Section {
                        Toggle("Paused", isOn: Binding(get: { !routine.active }, set: { routine.active = !$0 }))
                        Button("Delete task", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Pausing hides the task from Today without losing its history.")
                    }
                }
            }
            .themedForm()
            .navigationTitle(isNew ? "New task" : "Edit task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!isValid) }
            }
            .alert("Delete \u{201C}\(routine.title)\u{201D}?", isPresented: $confirmDelete) {
                Button("Delete task", role: .destructive) {
                    Task { await store.delete(routine); dismiss() }
                Button("Cancel", role: .cancel) {}
                }
            } message: {
                Text("Past entries stay in the history.")
            }
            .onAppear {
                if let t = routine.timeOfDay {
                    hasTime = true
                    time = t.date(on: .today)
                }
                hasEnd = routine.endDate != nil
                if routine.schedule == .interval, routine.intervalDays == nil { routine.intervalDays = 7 }
            }
            .onChange(of: routine.schedule) { _, new in
                if new == .interval, routine.intervalDays == nil { routine.intervalDays = 7 }
            }
        }
    }

    private var titlePlaceholder: String {
        switch routine.category {
        case .feeding: "Name, e.g. Breakfast"
        case .water: "Name, e.g. Fresh water"
        case .walk: "Name, e.g. Morning walk"
        case .medication: "Name, e.g. Morning pill"
        case .cleaning: "Name, e.g. Scoop litter box"
        case .grooming: "Name, e.g. Brush coat"
        case .play: "Name, e.g. Play time"
        case .vet: "Name, e.g. Annual checkup"
        default: "Name"
        }
    }

    private var amountPlaceholder: String {
        switch routine.category {
        case .feeding: "Amount, e.g. \u{00BD} cup dry food"
        case .medication: "Dose, e.g. 1 tablet in a pill pocket"
        case .walk: "How long, e.g. 20 minutes"
        default: "Amount or duration (optional)"
        }
    }

    private func dayBinding(_ keyPath: WritableKeyPath<Routine, Day>) -> Binding<Date> {
        Binding(get: { routine[keyPath: keyPath].date }, set: { routine[keyPath: keyPath] = Day($0) })
    }

    private func save() {
        routine.title = routine.title.trimmingCharacters(in: .whitespaces)
        routine.timeOfDay = hasTime ? ClockTime(time) : nil
        if !hasEnd || routine.schedule == .once { routine.endDate = nil }
        if routine.schedule != .interval { routine.intervalDays = nil }
        if routine.schedule != .weekly { routine.weekdays = [] }
        if routine.category != .medication { routine.medicationId = nil }
        let routine = routine
        Task {
            if await store.save(routine) {
                if isNew { store.track("routine_created", ["category": routine.category.rawValue, "schedule": routine.schedule.rawValue]) }
                dismiss()
            }
        }
    }
}

struct WeekdayPicker: View {
    @Binding var selection: [Int]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { day in
                let isOn = selection.contains(day)
                Button {
                    if isOn { selection.removeAll { $0 == day } } else { selection.append(day) }
                } label: {
                    Text(Calendar.current.veryShortWeekdaySymbols[day - 1])
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(isOn ? Theme.onPrimary : Theme.text)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(isOn ? Theme.primary : Theme.surfaceMuted, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}
