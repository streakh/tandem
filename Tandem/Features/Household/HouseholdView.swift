import SwiftUI

/// The people side: who shares care day to day, who has temporary access, and your own account.
struct HouseholdView: View {
    @Environment(AppStore.self) private var store
    @State private var showJoin = false
    @State private var showSetup = false
    @State private var addPetTo: Household?
    @State private var editingPet: Pet?
    @State private var showInvite: Household?
    @State private var editingName = false
    @State private var nameDraft = ""
    @State private var renaming: Household?
    @State private var removing: HouseholdMember?
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(store.myHouseholds) { household in
                        householdSection(household)
                    }

                    if store.myHouseholds.isEmpty {
                        EmptyState(icon: "house.fill", title: "No household of your own",
                                   message: "You're helping with someone else's pet. Have a pet too? Set up your own household to track their care.",
                                   actionTitle: "Set up my pet") { showSetup = true }
                            .card(padding: 0)
                    }

                    SectionTitle("You")
                    VStack(spacing: 0) {
                        Button {
                            nameDraft = store.profile?.displayName ?? ""
                            editingName = true
                        } label: {
                            HStack(spacing: 12) {
                                InitialsAvatar(name: store.myName, size: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(store.myName).font(.headline).foregroundStyle(Theme.text)
                                    Text(store.email).font(.subheadline).foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                Text("Edit").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.primary)
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.vertical, 8)
                        Toggle(isOn: Binding(get: { store.remindersEnabled }, set: { on in Task { await store.setReminders(enabled: on) } })) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Task reminders").foregroundStyle(Theme.text)
                                    Text("A nudge when a timed task is due and nobody has logged it.")
                                        .font(.caption).foregroundStyle(Theme.textSecondary)
                                }
                            } icon: {
                                Image(systemName: "bell.badge.fill").foregroundStyle(Theme.primary)
                            }
                        }
                        .tint(Theme.primary)

                        Divider().padding(.vertical, 8)
                        Toggle(isOn: Binding(get: { store.pushEnabled }, set: { on in Task { await store.setPush(enabled: on) } })) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Updates from other caregivers").foregroundStyle(Theme.text)
                                    Text("A notification when someone else logs care for your pets.")
                                        .font(.caption).foregroundStyle(Theme.textSecondary)
                                }
                            } icon: {
                                Image(systemName: "person.2.wave.2.fill").foregroundStyle(Theme.primary)
                            }
                        }
                        .tint(Theme.primary)

                        if store.pushEnabled {
                            Toggle("When a task is checked off", isOn: Binding(
                                get: { store.profile?.notifyTasks ?? true }, set: { on in Task { await store.setNotify(tasks: on) } }))
                                .font(.subheadline).tint(Theme.primary).padding(.leading, 36).padding(.top, 10)
                            Toggle("When someone leaves a note", isOn: Binding(
                                get: { store.profile?.notifyNotes ?? true }, set: { on in Task { await store.setNotify(notes: on) } }))
                                .font(.subheadline).tint(Theme.primary).padding(.leading, 36).padding(.top, 6)
                        }
                    }
                    .card()

                    VStack(spacing: 10) {
                        Button { showJoin = true } label: { Label("Enter an invite code", systemImage: "ticket.fill") }
                            .buttonStyle(.secondary)
                        Button("Sign out") { confirmSignOut = true }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.danger)
                            .padding(.top, 6)
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .screenBackground()
            .navigationTitle("Household")
            .sheet(isPresented: $showJoin) { JoinCodeView() }
            .sheet(item: $showInvite) { household in InviteMemberSheet(householdId: household.id) }
            .fullScreenCover(isPresented: $showSetup) { SetupFlow() }
            .fullScreenCover(item: $addPetTo) { household in SetupFlow(household: household) }
            .sheet(item: $editingPet) { pet in PetEditor(pet: pet) }
            .alert("Your name", isPresented: $editingName) {
                TextField("First name", text: $nameDraft)
                Button("Save") {
                    let name = nameDraft.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { Task { await store.updateName(name) } }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This is what others see next to what you log.")
            }
            .alert("Household name", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $nameDraft)
                Button("Save") {
                    let name = nameDraft.trimmingCharacters(in: .whitespaces)
                    if let household = renaming, !name.isEmpty { Task { await store.rename(household: household, to: name) } }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert(removing.map { $0.userId == store.userId ? "Leave this household?" : "Remove \($0.displayName)?" } ?? "",
                   isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
                Button(removing?.userId == store.userId ? "Leave household" : "Remove", role: .destructive) {
                    if let member = removing { Task { await store.remove(member: member) } }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("They'll lose access to the household's pets. Everything they logged stays in the history.")
            }
            .alert("Sign out of Tandem?", isPresented: $confirmSignOut) {
                Button("Sign out", role: .destructive) { Task { await store.signOut() } }
                Button("Cancel", role: .cancel) {}
            }
            .refreshable { await store.loadAll() }
        }
    }

    @ViewBuilder
    private func householdSection(_ household: Household) -> some View {
        let members = store.members.filter { $0.householdId == household.id }.sorted { $0.isOwner && !$1.isOwner }
        let amOwner = store.isOwner(ofHousehold: household.id)
        let pets = store.pets.filter { $0.householdId == household.id }
        let sitters = store.plans.filter { $0.householdId == household.id && $0.isAccepted && ($0.phase == .current || $0.phase == .upcoming) }

        HStack(alignment: .firstTextBaseline) {
            Text(household.name).font(.title2.weight(.heavy)).foregroundStyle(Theme.text)
            Spacer()
            if amOwner {
                Button("Rename") { nameDraft = household.name; renaming = household }
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.top, 4)

        if !pets.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(pets) { pet in
                        Button { editingPet = pet } label: {
                            VStack(spacing: 4) {
                                PetAvatar(pet: pet, size: 52)
                                Text(pet.name).font(.caption.weight(.semibold)).foregroundStyle(Theme.text)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Edit profile and photo")
                    }
                    Button { addPetTo = household } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "plus").font(.title3.weight(.semibold)).foregroundStyle(Theme.primary)
                                .frame(width: 52, height: 52).background(Theme.primarySoft, in: Circle())
                            Text("Add pet").font(.caption.weight(.semibold)).foregroundStyle(Theme.primary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .card()
        }

        SectionTitle("Shares care every day")
        VStack(spacing: 0) {
            ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                if index > 0 { Divider().padding(.leading, 56) }
                HStack(spacing: 12) {
                    InitialsAvatar(name: member.displayName.isEmpty ? "?" : member.displayName, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.displayName.isEmpty ? "Member" : member.displayName)
                            .font(.headline).foregroundStyle(Theme.text)
                        Text(member.userId == store.userId ? (member.isOwner ? "You · Owner" : "You") : (member.isOwner ? "Owner" : "Member"))
                            .font(.subheadline).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    if (amOwner && member.userId != store.userId) || (!member.isOwner && member.userId == store.userId) {
                        Menu {
                            Button(member.userId == store.userId ? "Leave household" : "Remove from household", role: .destructive) { removing = member }
                        } label: {
                            Image(systemName: "ellipsis").foregroundStyle(Theme.textSecondary).frame(width: 44, height: 44)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            Divider().padding(.vertical, 8)
            Button { showInvite = household } label: {
                Label("Invite someone to the household", systemImage: "person.badge.plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .card()

        if !sitters.isEmpty {
            SectionTitle("Temporary access")
            VStack(spacing: 0) {
                ForEach(Array(sitters.enumerated()), id: \.element.id) { index, plan in
                    if index > 0 { Divider().padding(.leading, 56) }
                    NavigationLink { PlanDetailView(planId: plan.id) } label: {
                        HStack(spacing: 12) {
                            InitialsAvatar(name: plan.caregiverName, size: 44, color: Theme.warning)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(plan.caregiverName).font(.headline).foregroundStyle(Theme.text)
                                Text("Sitter · \(plan.dateRangeLabel)").font(.subheadline).foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .card()
        }
    }
}

/// Invites someone as a full household member (sees everything, every day). Sitters get a care plan instead.
struct InviteMemberSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let householdId: UUID

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Invite a roommate, partner or family member")
                        .font(.title2.weight(.heavy)).foregroundStyle(Theme.text)
                    Text("Household members see everything about your pets and can check off tasks every day. For a sitter who only needs a few days, create a care plan instead.")
                        .font(.subheadline).foregroundStyle(Theme.textSecondary)

                    if let household = store.household(householdId) {
                        InviteCodeCard(code: household.inviteCode,
                                       message: "Join \(household.name) on Tandem so we can both see what's been done for our pets.")
                        if store.isOwner(ofHousehold: householdId) {
                            Button("Get a new code") { Task { await store.rotateInviteCode(household: household) } }
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                            Text("A new code stops the old one from working. People who already joined aren't affected.")
                                .font(.footnote).foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .padding(20)
            }
            .screenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
