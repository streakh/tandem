import SwiftUI

/// Handing care over to someone temporarily, and plans other people have handed to you.
struct PlansView: View {
    @Environment(AppStore.self) private var store
    @State private var draft: PlanDraft?
    @State private var opened: CarePlan?
    @State private var showJoin = false

    var body: some View {
        NavigationStack {
            let received = store.receivedPlans
            let owned = store.ownedPlans
            let live = owned.filter { $0.phase == .current || $0.phase == .upcoming }
            let past = owned.filter { $0.phase == .ended || $0.phase == .revoked }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !received.isEmpty {
                        SectionTitle("You're caring for")
                        ForEach(received) { plan in
                            NavigationLink { ReceivedPlanView(plan: plan) } label: { ReceivedPlanCard(plan: plan) }
                                .buttonStyle(.plain)
                        }
                    }

                    if store.primaryHousehold != nil {
                        if owned.isEmpty {
                            EmptyState(icon: "arrow.left.arrow.right.circle.fill", title: "Going away?",
                                       message: "A care plan gives a sitter exactly what they need for the days they're covering: the routine, allergies, emergency contacts and your notes. It's built from the routine you've already set up.",
                                       actionTitle: "Create a care plan") { newPlan() }
                                .card(padding: 0)
                        }
                        if !live.isEmpty {
                            SectionTitle("Active and upcoming")
                            ForEach(live) { plan in planLink(plan) }
                        }
                        if !past.isEmpty {
                            SectionTitle("Past plans")
                            ForEach(past) { plan in planLink(plan) }
                        }
                    } else if received.isEmpty {
                        EmptyState(icon: "ticket.fill", title: "No care plans",
                                   message: "When a pet owner shares a care plan with you, enter their invite code to open it.",
                                   actionTitle: "Enter invite code") { showJoin = true }
                            .padding(.top, 40)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .screenBackground()
            .navigationTitle("Care plans")
            .toolbar {
                if store.primaryHousehold != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { newPlan() } label: { Label("New care plan", systemImage: "plus.circle.fill").font(.title3) }
                    }
                }
            }
            .navigationDestination(item: $opened) { plan in PlanDetailView(planId: plan.id) }
            .sheet(item: $draft) { draft in
                PlanEditor(draft: draft) { saved in opened = saved }
            }
            .sheet(isPresented: $showJoin) { JoinCodeView() }
            .refreshable { await store.loadAll() }
        }
    }

    private func planLink(_ plan: CarePlan) -> some View {
        NavigationLink { PlanDetailView(planId: plan.id) } label: { PlanCard(plan: plan) }
            .buttonStyle(.plain)
    }

    private func newPlan() {
        guard let household = store.primaryHousehold else { return }
        let pets = store.pets.filter { $0.householdId == household.id }
        draft = PlanDraft(plan: CarePlan(householdId: household.id), petIds: Set(pets.count == 1 ? pets.map(\.id) : []), isNew: true)
    }
}

/// A plan being created or edited, along with which pets it covers.
struct PlanDraft: Identifiable {
    var plan: CarePlan
    var petIds: Set<UUID>
    var isNew: Bool
    var id: UUID { plan.id }
}

struct PlanStatusPill: View {
    let plan: CarePlan

    var body: some View {
        switch plan.phase {
        case .revoked:
            Pill(text: "Access ended early", color: Theme.textSecondary, soft: Theme.surfaceMuted)
        case .ended:
            Pill(text: "Ended", icon: "checkmark", color: Theme.textSecondary, soft: Theme.surfaceMuted)
        case .current:
            if plan.isAccepted {
                Pill(text: "\(plan.caregiverName) has access", icon: "checkmark", color: Theme.success, soft: Theme.successSoft)
            } else {
                Pill(text: "Not joined yet", icon: "hourglass", color: Theme.warning, soft: Theme.warningSoft)
            }
        case .upcoming:
            if plan.isAccepted {
                Pill(text: "\(plan.caregiverName) joined", icon: "checkmark", color: Theme.success, soft: Theme.successSoft)
            } else {
                Pill(text: "Invite not used yet", icon: "hourglass", color: Theme.warning, soft: Theme.warningSoft)
            }
        }
    }
}

private struct PlanCard: View {
    @Environment(AppStore.self) private var store
    let plan: CarePlan

    var body: some View {
        let pets = store.pets(in: plan)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(plan.displayTitle).font(.headline).foregroundStyle(Theme.text)
                    Label(plan.dateRangeLabel, systemImage: "calendar").font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                HStack(spacing: -10) {
                    ForEach(pets.prefix(3)) { PetAvatar(pet: $0, size: 36).overlay(Circle().strokeBorder(Theme.surface, lineWidth: 2)) }
                }
            }
            HStack {
                PlanStatusPill(plan: plan)
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textSecondary)
            }
        }
        .card()
    }
}

private struct ReceivedPlanCard: View {
    @Environment(AppStore.self) private var store
    let plan: CarePlan

    var body: some View {
        let pets = store.pets(in: plan)
        HStack(spacing: 14) {
            if let pet = pets.first { PetAvatar(pet: pet, size: 52) }
            VStack(alignment: .leading, spacing: 3) {
                Text(pets.isEmpty ? plan.displayTitle : pets.map(\.name).joined(separator: " & "))
                    .font(.headline).foregroundStyle(Theme.text)
                Text("From \(plan.createdByName.isEmpty ? "the owner" : plan.createdByName) · \(plan.dateRangeLabel)")
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
                switch plan.phase {
                case .upcoming: Pill(text: "Starts \(plan.startDate.relativeLabel)", color: Theme.warning, soft: Theme.warningSoft)
                case .current: Pill(text: "Happening now", icon: "circle.fill", color: Theme.success, soft: Theme.successSoft)
                default: Pill(text: "Ended", color: Theme.textSecondary, soft: Theme.surfaceMuted)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textSecondary)
        }
        .card()
    }
}

// MARK: - Owner's view of a plan

struct PlanDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let planId: UUID
    @State private var draft: PlanDraft?
    @State private var confirmEnd = false
    @State private var confirmDelete = false

    var body: some View {
        if let plan = store.plans.first(where: { $0.id == planId }) {
            content(plan)
        } else {
            Color.clear.onAppear { dismiss() }
        }
    }

    private func content(_ plan: CarePlan) -> some View {
        let pets = store.pets(in: plan)
        let petIds = Set(pets.map(\.id))
        let activity = store.logs.filter { $0.carePlanId == plan.id }
        let included = store.routines.filter { petIds.contains($0.petId) && $0.active && plan.categories.contains($0.category) }
        let isLive = plan.phase == .current || plan.phase == .upcoming

        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        HStack(spacing: -10) {
                            ForEach(pets) { PetAvatar(pet: $0, size: 48).overlay(Circle().strokeBorder(Theme.surface, lineWidth: 2)) }
                        }
                        Spacer()
                        PlanStatusPill(plan: plan)
                    }
                    Text(plan.displayTitle).font(.title2.weight(.heavy)).foregroundStyle(Theme.text)
                    Label(plan.dateRangeLabel, systemImage: "calendar").font(.subheadline).foregroundStyle(Theme.textSecondary)
                    if !pets.isEmpty {
                        Label(pets.map(\.name).joined(separator: ", "), systemImage: "pawprint.fill")
                            .font(.subheadline).foregroundStyle(Theme.textSecondary)
                    }
                }
                .card()

                if isLive, !plan.isAccepted, let code = plan.inviteCode {
                    SectionTitle("Invite \(plan.caregiverName)")
                    InviteCodeCard(code: code, message: inviteMessage(plan, pets: pets))
                    Text("They install Tandem, create an account and enter this code. Their access starts when they join and ends automatically after \(plan.endDate.shortLabel).")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                }

                SectionTitle("What \(plan.caregiverName) sees")
                VStack(alignment: .leading, spacing: 12) {
                    FlowLayout(spacing: 8) {
                        ForEach(plan.categories) { category in
                            Pill(text: category.label, icon: category.icon, color: category.tint, soft: category.tint.opacity(0.14))
                        }
                    }
                    Text("\(included.count) routine \(included.count == 1 ? "task" : "tasks"), plus allergies, vet and emergency contacts. Vaccines, weight, documents and other history stay private.")
                        .font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
                .card()

                if !plan.notes.isEmpty {
                    SectionTitle("Your notes")
                    Text(plan.notes).font(.body).foregroundStyle(Theme.text).card(fill: Theme.sunSoft)
                }
                if !plan.emergencyNotes.isEmpty {
                    SectionTitle("In an emergency")
                    Text(plan.emergencyNotes).font(.body).foregroundStyle(Theme.text).card(fill: Theme.dangerSoft)
                }

                if plan.isAccepted {
                    SectionTitle("What \(plan.caregiverName) has logged")
                    if activity.isEmpty {
                        Text("Nothing yet. Everything they check off shows up here and in your shared history.")
                            .font(.subheadline).foregroundStyle(Theme.textSecondary).card()
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(activity.prefix(30).enumerated()), id: \.element.id) { index, log in
                                if index > 0 { Divider().padding(.leading, 52) }
                                HStack(alignment: .top) {
                                    LogRow(log: log)
                                    Text(log.scheduledFor.shortLabel).font(.caption).foregroundStyle(Theme.textSecondary).padding(.top, 10)
                                }
                            }
                        }
                        .card(padding: 12)
                    }
                }

                VStack(spacing: 10) {
                    Button {
                        var copy = plan
                        copy.id = UUID()
                        copy.inviteCode = nil; copy.sitterId = nil; copy.sitterName = nil; copy.acceptedAt = nil; copy.status = "active"
                        let length = plan.startDate.days(until: plan.endDate)
                        copy.startDate = .today
                        copy.endDate = Day.today.adding(length)
                        draft = PlanDraft(plan: copy, petIds: petIds, isNew: true)
                    } label: {
                        Label("Reuse this plan for new dates", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.secondary)

                    if isLive {
                        Button("End access now", role: .destructive) { confirmEnd = true }
                            .buttonStyle(SecondaryButtonStyle(tint: Theme.danger))
                    }
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .navigationTitle("Care plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if isLive {
                        Button { draft = PlanDraft(plan: plan, petIds: petIds, isNew: false) } label: { Label("Edit", systemImage: "pencil") }
                    }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete plan", systemImage: "trash") }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $draft) { draft in PlanEditor(draft: draft) { _ in } }
        .alert("End \(plan.caregiverName)'s access now?", isPresented: $confirmEnd) {
            Button("End access", role: .destructive) { Task { await store.endAccess(for: plan) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They'll stop seeing your pets right away. What they logged stays in your history.")
        }
        .alert("Delete this care plan?", isPresented: $confirmDelete) {
            Button("Delete plan", role: .destructive) { Task { await store.deletePlan(plan); dismiss() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The sitter loses access. What they logged stays in your history.")
        }
    }

    private func inviteMessage(_ plan: CarePlan, pets: [Pet]) -> String {
        let names = pets.map(\.name).joined(separator: " and ")
        return "Hi! I've set up a care plan for \(names.isEmpty ? "my pet" : names) from \(plan.startDate.shortLabel) to \(plan.endDate.shortLabel) in Tandem. It has the routine, allergies and emergency contacts, and you can check things off as you go."
    }
}

// MARK: - Sitter's view of a plan

struct ReceivedPlanView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented
    let plan: CarePlan

    var body: some View {
        let pets = store.pets(in: plan)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Caring for \(pets.isEmpty ? "their pet" : pets.map(\.name).joined(separator: " & "))")
                        .font(.title2.weight(.heavy)).foregroundStyle(Theme.text)
                    Label("From \(plan.createdByName.isEmpty ? "the owner" : plan.createdByName)", systemImage: "person.fill")
                        .font(.subheadline).foregroundStyle(Theme.textSecondary)
                    Label("\(plan.dateRangeLabel) · access ends after \(plan.endDate.shortLabel)", systemImage: "calendar")
                        .font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
                .card()

                if !plan.notes.isEmpty {
                    SectionTitle("Notes from \(plan.createdByName.isEmpty ? "the owner" : plan.createdByName)")
                    Text(plan.notes).font(.body).foregroundStyle(Theme.text).card(fill: Theme.sunSoft)
                }
                if !plan.emergencyNotes.isEmpty {
                    SectionTitle("In an emergency")
                    Text(plan.emergencyNotes).font(.body).foregroundStyle(Theme.text).card(fill: Theme.dangerSoft)
                }

                if pets.isEmpty {
                    Text("This plan has ended, so the pet's details are no longer shared with you.")
                        .font(.subheadline).foregroundStyle(Theme.textSecondary).card()
                }

                ForEach(pets) { pet in
                    SectionTitle(pet.name)
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            PetAvatar(pet: pet, size: 52)
                            Text(pet.summaryLine).font(.subheadline).foregroundStyle(Theme.textSecondary)
                        }
                        let allergies = store.allergies.filter { $0.petId == pet.id }
                        if !allergies.isEmpty {
                            Label("Allergic to \(allergies.map(\.name).joined(separator: ", "))", systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.danger)
                        }
                        if !pet.notes.isEmpty {
                            Text(pet.notes).font(.subheadline).foregroundStyle(Theme.text)
                        }
                        if pet.hasVetInfo {
                            Divider()
                            ContactRow(title: [pet.vetName, pet.vetClinic].filter { !$0.isEmpty }.joined(separator: " · "),
                                       subtitle: pet.vetAddress, phone: pet.vetPhone, icon: "cross.case.fill")
                        }
                        if pet.hasEmergencyInfo {
                            Divider()
                            ContactRow(title: pet.emergencyName.isEmpty ? "Emergency contact" : pet.emergencyName,
                                       subtitle: "Emergency contact", phone: pet.emergencyPhone, icon: "staroflife.fill")
                        }
                    }
                    .card()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .navigationTitle("Care plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isPresented { Button("Done") { dismiss() } }
            }
        }
    }
}
