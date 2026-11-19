import SwiftUI

struct TodayView: View {
    @Environment(AppStore.self) private var store
    @State private var detailTask: CareTask?
    @State private var showNote = false
    @State private var showAddPet = false
    @State private var planInfo: CarePlan?
    @State private var editingRoutine: Routine?

    var body: some View {
        NavigationStack {
            Group {
                if let pet = store.selectedPet {
                    content(for: pet)
                } else {
                    noPets
                }
            }
            .screenBackground()
            .navigationTitle("Today")
            .toolbar {
                if let pet = store.selectedPet {
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink {
                            HistoryView(petId: pet.id)
                        } label: {
                            Label("History", systemImage: "clock.arrow.circlepath")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            if store.canLog(for: pet) {
                                Button { showNote = true } label: { Label("Log a note", systemImage: "square.and.pencil") }
                            }
                            if store.canEdit(pet) {
                                Button { editingRoutine = Routine(petId: pet.id) } label: { Label("Add a task", systemImage: "plus") }
                                NavigationLink {
                                    RoutineListView(petId: pet.id)
                                } label: {
                                    Label("Edit routine", systemImage: "slider.horizontal.3")
                                }
                            }
                        } label: {
                            Label("Add", systemImage: "plus.circle.fill").font(.title3)
                        }
                    }
                }
            }
            .sheet(item: $detailTask) { task in
                TaskDetailSheet(task: task).presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showNote) {
                if let pet = store.selectedPet { NoteSheet(pet: pet).presentationDetents([.medium]) }
            }
            .sheet(item: $planInfo) { plan in
                NavigationStack { ReceivedPlanView(plan: plan) }
            }
            .sheet(item: $editingRoutine) { routine in RoutineEditor(routine: routine, isNew: true) }
            .fullScreenCover(isPresented: $showAddPet) { SetupFlow(household: store.primaryHousehold) }
            .refreshable { await store.loadAll() }
        }
    }

    private var noPets: some View {
        ScrollView {
            if store.primaryHousehold != nil {
                EmptyState(icon: "pawprint.fill", title: "Add your first pet",
                           message: "Set up their routine once, and everyone who helps will see what's done and what's left.",
                           actionTitle: "Add a pet") { showAddPet = true }
                    .padding(.top, 60)
            } else {
                EmptyState(icon: "calendar.badge.clock", title: "Nothing to care for right now",
                           message: "Your care plan has ended. When someone shares a new plan with you, their pet will show up here.")
                    .padding(.top, 60)
            }
        }
    }

    private func content(for pet: Pet) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let tasks = store.tasks(for: pet.id)
            let sitterPlan = store.canEdit(pet) ? nil : store.sitterPlan(for: pet.id)
            let canLog = store.canLog(for: pet)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if store.sortedPets.count > 1 { PetSwitcher() }

                    HeroCard(pet: pet, tasks: tasks, previewStart: canLog ? nil : sitterPlan?.startDate)

                    if let sitterPlan {
                        SitterBanner(plan: sitterPlan) { planInfo = sitterPlan }
                    }

                    AllergyStrip(petId: pet.id)

                    if tasks.isEmpty {
                        if store.canEdit(pet) {
                            EmptyState(icon: "list.bullet.clipboard", title: "No tasks today",
                                       message: "Add \(pet.name)'s feeding, walks, medication and anything else that repeats.",
                                       actionTitle: "Add a task") { editingRoutine = Routine(petId: pet.id) }
                                .card(padding: 0)
                        } else {
                            Text("Nothing is scheduled for \(pet.name) today.")
                                .font(.subheadline).foregroundStyle(Theme.textSecondary).card()
                        }
                    }

                    ForEach(CareTask.Slot.allCases) { slot in
                        let group = tasks.filter { $0.slot == slot }
                        if !group.isEmpty {
                            SectionTitle(slot.label)
                            VStack(spacing: 10) {
                                ForEach(group) { task in
                                    TaskRow(task: task, now: timeline.date, canLog: canLog,
                                            onToggle: { toggle(task) }, onOpen: { detailTask = task })
                                }
                            }
                        }
                    }

                    TodayNotes(petId: pet.id)
                    ComingUp(petId: pet.id)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
    }

    private func toggle(_ task: CareTask) {
        Task {
            if let log = task.log {
                await store.undo(log)
            } else {
                await store.complete(task)
            }
        }
    }
}

// MARK: - Header pieces

struct PetSwitcher: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(store.sortedPets) { pet in
                    let isSelected = pet.id == store.selectedPet?.id
                    let remaining = store.canLog(for: pet) ? store.tasks(for: pet.id).filter { !$0.isResolved }.count : 0
                    Button {
                        withAnimation(.snappy) { store.selectPet(pet.id) }
                    } label: {
                        HStack(spacing: 8) {
                            PetAvatar(pet: pet, size: 32)
                            Text(pet.name).font(.subheadline.weight(.semibold))
                            if remaining > 0 {
                                Text("\(remaining)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(isSelected ? Theme.primary : Theme.onPrimary)
                                    .frame(minWidth: 18, minHeight: 18)
                                    .background(isSelected ? Theme.onPrimary : Theme.primary, in: Circle())
                            }
                        }
                        .foregroundStyle(isSelected ? Theme.onPrimary : Theme.text)
                        .padding(.leading, 6)
                        .padding(.trailing, 12)
                        .padding(.vertical, 6)
                        .background(isSelected ? Theme.primary : Theme.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(pet.name), \(remaining) tasks left")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }
}

private struct HeroCard: View {
    @Environment(AppStore.self) private var store
    let pet: Pet
    let tasks: [CareTask]
    /// Set when a sitter's plan hasn't started: the list is a preview, not a checklist.
    var previewStart: Day?

    private var done: Int { tasks.filter(\.isResolved).count }
    private var lastLog: CareLog? { store.logs.first { $0.petId == pet.id && $0.scheduledFor == .today } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                PetAvatar(pet: pet, size: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(pet.name).font(.title2.weight(.heavy)).foregroundStyle(.white)
                    Text(Date.now.formatted(.dateTime.weekday(.wide).month().day()))
                        .font(.subheadline).foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
            }
            if let previewStart {
                Text("Here's the daily routine. You can start checking things off \(previewStart.relativeLabel == "Tomorrow" ? "tomorrow" : "on \(previewStart.relativeLabel)").")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.white)
            } else if !tasks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(done == tasks.count ? "All done for today" : "\(done) of \(tasks.count) done")
                            .font(.headline).foregroundStyle(.white)
                        Spacer()
                        if let lastLog {
                            Text("Last: \(lastLog.loggedByName), \(lastLog.loggedAt.formatted(date: .omitted, time: .shortened))")
                                .font(.caption).foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    ProgressView(value: Double(done), total: Double(max(tasks.count, 1)))
                        .tint(.white)
                        .background(.white.opacity(0.25), in: Capsule())
                        .animation(.snappy, value: done)
                }
            }
        }
        .padding(18)
        .background(
            LinearGradient(colors: [Color(hex: 0x2A867A), Color(hex: 0x1F6E78)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct SitterBanner: View {
    let plan: CarePlan
    let onInfo: () -> Void

    var body: some View {
        Button(action: onInfo) {
            HStack(spacing: 12) {
                Image(systemName: "person.badge.clock.fill").font(.title3).foregroundStyle(Theme.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Care plan from \(plan.createdByName.isEmpty ? "the owner" : plan.createdByName)")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    Text(plan.phase == .upcoming
                         ? "Starts \(plan.startDate.relativeLabel) · you can look around until then"
                         : "Through \(plan.endDate.relativeLabel) · notes and emergency info")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text("Notes").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.primary)
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textSecondary)
            }
            .card(padding: 14, fill: Theme.warningSoft)
        }
        .buttonStyle(.plain)
    }
}

/// Allergies are safety-critical, so they sit on the daily screen where every caregiver sees them.
struct AllergyStrip: View {
    @Environment(AppStore.self) private var store
    let petId: UUID

    var body: some View {
        let allergies = store.allergies.filter { $0.petId == petId }
        if !allergies.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.danger)
                Text("Allergies: ").font(.subheadline.weight(.bold)).foregroundStyle(Theme.text)
                + Text(allergies.map(\.name).joined(separator: ", ")).font(.subheadline).foregroundStyle(Theme.text)
                Spacer(minLength: 0)
            }
            .card(padding: 12, fill: Theme.dangerSoft)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Task row

struct TaskRow: View {
    let task: CareTask
    let now: Date
    let canLog: Bool
    let onToggle: () -> Void
    let onOpen: () -> Void

    var body: some View {
        let state: CareTask.State = canLog ? task.state(now: now) : .anytime
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    CategoryIcon(category: task.routine.category, dimmed: task.isResolved)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.routine.title)
                            .font(.headline)
                            .foregroundStyle(task.isResolved ? Theme.textSecondary : Theme.text)
                            .strikethrough(task.isSkipped)
                        if !task.routine.amount.isEmpty, !task.isResolved {
                            Text(task.routine.amount).font(.subheadline).foregroundStyle(Theme.text.opacity(0.8))
                        }
                        HStack(spacing: 4) {
                            if state == .overdue || state == .dueNow {
                                Image(systemName: "clock.fill").font(.caption2)
                            }
                            Text(canLog ? task.statusLine(now: now) : (task.routine.timeOfDay?.label ?? "Any time")).font(.subheadline)
                            if let note = task.log?.note, !note.isEmpty {
                                Image(systemName: "text.bubble.fill").font(.caption2)
                            }
                        }
                        .foregroundStyle(statusColor(state))
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onToggle) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : (task.isSkipped ? "minus.circle.fill" : "circle"))
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(task.isDone ? Theme.success : (task.isSkipped ? Theme.textSecondary : Theme.primary))
                    .frame(width: 48, height: 48)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .disabled(!canLog)
            .opacity(canLog ? 1 : 0)
            .accessibilityLabel(task.isResolved ? "Undo \(task.routine.title)" : "Mark \(task.routine.title) done")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 10)
        .background(background(state), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
            .strokeBorder(state == .overdue ? Theme.warning.opacity(0.5) : .clear, lineWidth: 1.5))
    }

    private func statusColor(_ state: CareTask.State) -> Color {
        switch state {
        case .done: Theme.success
        case .overdue: Theme.warning
        case .dueNow: Theme.primary
        default: Theme.textSecondary
        }
    }

    private func background(_ state: CareTask.State) -> Color {
        switch state {
        case .done, .skipped: Theme.surface.opacity(0.6)
        case .overdue: Theme.warningSoft
        default: Theme.surface
        }
    }
}

// MARK: - Task detail

struct TaskDetailSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let task: CareTask
    @State private var note = ""
    @State private var editing: Routine?
    @State private var editingLog: CareLog?

    private var pet: Pet? { store.pets.first { $0.id == task.routine.petId } }
    private var log: CareLog? { store.logs.first { $0.routineId == task.routine.id && $0.scheduledFor == task.day } }
    private var medication: Medication? { store.medications.first { $0.id == task.routine.medicationId } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        CategoryIcon(category: task.routine.category, size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.routine.title).font(.title2.weight(.bold))
                            Text(task.routine.scheduleLabel).font(.subheadline).foregroundStyle(Theme.textSecondary)
                        }
                    }

                    if !task.routine.amount.isEmpty || !task.routine.details.isEmpty || medication != nil {
                        VStack(alignment: .leading, spacing: 12) {
                            if !task.routine.amount.isEmpty { DetailRow(label: "Amount", value: task.routine.amount, icon: "scalemass.fill") }
                            if let medication {
                                DetailRow(label: "Medication", value: [medication.name, medication.summary].filter { !$0.isEmpty }.joined(separator: " · "), icon: "pills.fill")
                                if !medication.instructions.isEmpty {
                                    DetailRow(label: "How to give it", value: medication.instructions, icon: "info.circle.fill")
                                }
                            }
                            if !task.routine.details.isEmpty { DetailRow(label: "Instructions", value: task.routine.details, icon: "text.alignleft") }
                        }
                        .card()
                    }

                    if let log {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(log.isDone ? "Done" : "Skipped", systemImage: log.isDone ? "checkmark.circle.fill" : "minus.circle.fill")
                                .font(.headline)
                                .foregroundStyle(log.isDone ? Theme.success : Theme.textSecondary)
                            Text("\(log.loggedByName) · \(log.loggedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.subheadline).foregroundStyle(Theme.textSecondary)
                            if !log.note.isEmpty { Text(log.note).font(.body) }
                            if store.canModify(log) {
                                Button(log.note.isEmpty ? "Add a note" : "Edit note") { editingLog = log }
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.top, 2)
                            }
                        }
                        .card(fill: log.isDone ? Theme.successSoft : Theme.surface)

                        if let pet, store.canLog(for: pet) {
                            Button("Undo") {
                                Task { await store.undo(log); dismiss() }
                            }
                            .buttonStyle(.secondary)
                        }
                    } else if let pet, store.canLog(for: pet) {
                        TextField("Add a note (optional), e.g. \u{201C}ate about half\u{201D}", text: $note, axis: .vertical)
                            .lineLimit(2...4)
                            .padding(14)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))

                        Button {
                            Task { await store.complete(task, note: note); dismiss() }
                        } label: {
                            Label("Mark as done", systemImage: "checkmark")
                        }
                        .buttonStyle(.primary)

                        Button("Skip for today") {
                            Task { await store.complete(task, status: "skipped", note: note); dismiss() }
                        }
                        .buttonStyle(.secondary)
                    } else {
                        Text("You can log this once your care plan starts.")
                            .font(.subheadline).foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(20)
            }
            .screenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if let pet, store.canEdit(pet) {
                    ToolbarItem(placement: .primaryAction) { Button("Edit task") { editing = task.routine } }
                }
            }
            .sheet(item: $editing) { routine in RoutineEditor(routine: routine, isNew: false) }
            .sheet(item: $editingLog) { LogEditor(log: $0) }
        }
    }
}

/// A free-form observation: "Threw up after breakfast", "Limping on the walk".
struct NoteSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let pet: Pet
    @State private var title = ""
    @State private var note = ""
    @FocusState private var focused: Bool

    private let suggestions = ["Extra treat", "Accident", "Vomiting", "Not eating", "Seemed off", "Great day"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Anything the next person should know about \(pet.name).")
                        .font(.subheadline).foregroundStyle(Theme.textSecondary)
                    TextField("What happened?", text: $title)
                        .font(.headline)
                        .padding(14)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                        .focused($focused)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button(suggestion) { title = suggestion }
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(Theme.primarySoft, in: Capsule())
                            }
                        }
                    }
                    TextField("Details (optional)", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                        .padding(14)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                }
                .padding(20)
            }
            .screenBackground()
            .navigationTitle("Log a note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await store.addNote(petId: pet.id, title: title.trimmingCharacters(in: .whitespaces), note: note) { dismiss() }
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
    }
}

// MARK: - Notes and upcoming

private struct TodayNotes: View {
    @Environment(AppStore.self) private var store
    let petId: UUID
    @State private var editingLog: CareLog?

    var body: some View {
        let notes = store.logs.filter { $0.petId == petId && $0.routineId == nil && $0.scheduledFor == .today }
        if !notes.isEmpty {
            SectionTitle("Notes today")
            VStack(spacing: 10) {
                ForEach(notes) { log in
                    Button { if store.canModify(log) { editingLog = log } } label: {
                    HStack(alignment: .top, spacing: 12) {
                        CategoryIcon(category: .note, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(log.title).font(.headline).foregroundStyle(Theme.text)
                            if !log.note.isEmpty { Text(log.note).font(.subheadline).foregroundStyle(Theme.text) }
                            Text("\(log.loggedByName), \(log.loggedAt.formatted(date: .omitted, time: .shortened))")
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .card(padding: 12, fill: Theme.sunSoft)
                    }
                    .buttonStyle(.plain)
                }
            }
            .sheet(item: $editingLog) { LogEditor(log: $0) }
        }
    }
}

/// Occasional tasks and vaccines: the things that fall through the cracks because they aren't daily.
struct ComingUp: View {
    @Environment(AppStore.self) private var store
    let petId: UUID
    var limit = 4

    var body: some View {
        let items = Schedule.upcoming(petIds: [petId], routines: store.routines, logs: store.logs, vaccines: store.vaccines)
        if !items.isEmpty {
            SectionTitle("Coming up") {
                NavigationLink { UpcomingView(petId: petId) } label: {
                    Text(items.count > limit ? "See all \(items.count)" : "See all").font(.subheadline.weight(.semibold))
                }
            }
            VStack(spacing: 0) {
                ForEach(Array(items.prefix(limit).enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().padding(.leading, 56) }
                    HStack(spacing: 12) {
                        CategoryIcon(category: item.category, size: 36)
                        Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                        Spacer()
                        let overdue = item.day < .today
                        Text(overdue ? "Overdue" : item.day.relativeLabel)
                            .font(.subheadline.weight(overdue ? .bold : .regular))
                            .foregroundStyle(overdue ? Theme.danger : Theme.textSecondary)
                    }
                    .padding(.vertical, 10)
                }
            }
            .card(padding: 14)
        }
    }
}
