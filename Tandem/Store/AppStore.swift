import Foundation
import Supabase
import SwiftUI
import UIKit

/// A row the app keeps in memory and syncs to one Supabase table.
protocol Record: Codable, Identifiable, Hashable where ID == UUID {
    static var table: String { get }
    @MainActor static var list: ReferenceWritableKeyPath<AppStore, [Self]> { get }
}

extension Pet: Record { static let table = "pets"; static var list: ReferenceWritableKeyPath<AppStore, [Pet]> { \.pets } }
extension Routine: Record { static let table = "routines"; static var list: ReferenceWritableKeyPath<AppStore, [Routine]> { \.routines } }
extension CareLog: Record { static let table = "care_logs"; static var list: ReferenceWritableKeyPath<AppStore, [CareLog]> { \.logs } }
extension Allergy: Record { static let table = "allergies"; static var list: ReferenceWritableKeyPath<AppStore, [Allergy]> { \.allergies } }
extension Medication: Record { static let table = "medications"; static var list: ReferenceWritableKeyPath<AppStore, [Medication]> { \.medications } }
extension Vaccine: Record { static let table = "vaccines"; static var list: ReferenceWritableKeyPath<AppStore, [Vaccine]> { \.vaccines } }
extension WeightEntry: Record { static let table = "weight_entries"; static var list: ReferenceWritableKeyPath<AppStore, [WeightEntry]> { \.weights } }
extension PetDocument: Record { static let table = "documents"; static var list: ReferenceWritableKeyPath<AppStore, [PetDocument]> { \.documents } }

struct Toast: Equatable, Identifiable {
    let id = UUID()
    var message: String
    var isError = false
}

/// Everything the signed-in person can see, kept in memory and refreshed whenever anyone changes it.
/// Row-level security on the server decides what comes back, so a sitter's store simply contains less.
@MainActor
@Observable
final class AppStore {
    enum Phase { case launching, signedOut, onboarding, ready }

    var phase: Phase = .launching
    var userId: UUID?
    var email = ""
    var profile: Profile?

    var households: [Household] = []
    var members: [HouseholdMember] = []
    var pets: [Pet] = []
    var routines: [Routine] = []
    var logs: [CareLog] = []
    var allergies: [Allergy] = []
    var medications: [Medication] = []
    var vaccines: [Vaccine] = []
    var weights: [WeightEntry] = []
    var documents: [PetDocument] = []
    var plans: [CarePlan] = []
    var planPets: [CarePlanPet] = []

    var selectedPetId: UUID?
    var toast: Toast?
    var pendingInviteCode: String?
    var remindersEnabled = UserDefaults.standard.bool(forKey: "remindersEnabled")

    @ObservationIgnored private let client = Backend.client
    @ObservationIgnored private var realtimeChannel: RealtimeChannelV2?
    @ObservationIgnored private var realtimeTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private let imageCache = NSCache<NSString, UIImage>()

    // MARK: - Session

    /// Runs for the life of the app, reacting to sign-in and sign-out.
    func start() async {
        #if DEBUG
        // Test hook: `-autoLoginEmail x -autoLoginPassword y` launch arguments sign in as a demo account.
        let defaults = UserDefaults.standard
        if let email = defaults.string(forKey: "autoLoginEmail"), let password = defaults.string(forKey: "autoLoginPassword") {
            if client.auth.currentUser?.email != email {
                try? await client.auth.signOut(scope: .local)
                _ = try? await client.auth.signIn(email: email, password: password)
            }
        }
        #endif
        for await (event, session) in client.auth.authStateChanges {
            switch event {
            case .initialSession, .signedIn, .tokenRefreshed:
                if let session, !session.isExpired {
                    await didSignIn(session.user)
                } else if event == .initialSession, session == nil {
                    phase = .signedOut
                }
            case .signedOut, .userDeleted:
                reset()
            default:
                break
            }
        }
    }

    private func didSignIn(_ user: User) async {
        guard userId != user.id else { return }
        userId = user.id
        email = user.email ?? ""
        if let saved = UserDefaults.standard.string(forKey: "selectedPet") { selectedPetId = UUID(uuidString: saved) }
        await loadAll()
        if let code = pendingInviteCode {
            pendingInviteCode = nil
            _ = await redeem(code: code)
        }
        updatePhase()
        await subscribeToChanges()
    }

    /// Set while the first-run setup is saving, so the screen doesn't switch out from under it.
    @ObservationIgnored var holdPhase = false

    func updatePhase() {
        guard userId != nil else { phase = .signedOut; return }
        guard !holdPhase else { return }
        phase = (myHouseholds.isEmpty && receivedPlans.isEmpty) ? .onboarding : .ready
    }

    private func reset() {
        realtimeTask?.cancel()
        if let channel = realtimeChannel { Task { await client.removeChannel(channel) } }
        realtimeChannel = nil
        userId = nil; email = ""; profile = nil
        households = []; members = []; pets = []; routines = []; logs = []
        allergies = []; medications = []; vaccines = []; weights = []; documents = []
        plans = []; planPets = []
        selectedPetId = nil
        Reminders.cancelAll()
        phase = .signedOut
    }

    func signIn(email: String, password: String) async -> String? {
        do {
            try await client.auth.signIn(email: email, password: password)
            return nil
        } catch { return friendlyMessage(for: error) }
    }

    func signUp(name: String, email: String, password: String) async -> String? {
        do {
            let response = try await client.auth.signUp(email: email, password: password, data: ["display_name": .string(name)])
            if response.session == nil {
                // Project requires email confirmation; signing in works once it's confirmed.
                do { try await client.auth.signIn(email: email, password: password) }
                catch { return "Check your email to confirm your account, then sign in." }
            }
            track("signed_up")
            return nil
        } catch { return friendlyMessage(for: error) }
    }

    func signInWithApple(idToken: String, nonce: String, name: String?) async -> String? {
        do {
            try await client.auth.signInWithIdToken(credentials: .init(provider: .apple, idToken: idToken, nonce: nonce))
            if let name, !name.isEmpty, (profile?.displayName ?? "").isEmpty { await updateName(name) }
            return nil
        } catch { return friendlyMessage(for: error) }
    }

    func signOut() async {
        try? await client.auth.signOut(scope: .local)
        reset()
    }

    // MARK: - Loading

    private func fetch<T: Decodable>(_ table: String) async throws -> [T] {
        try await client.from(table).select().execute().value
    }

    func loadAll(quiet: Bool = false) async {
        guard let userId else { return }
        do {
            let since = Day.today.adding(-120).string
            async let profiles: [Profile] = fetch("profiles")
            async let h: [Household] = fetch("households")
            async let m: [HouseholdMember] = fetch("household_members")
            async let p: [Pet] = client.from("pets").select().order("created_at").execute().value
            async let r: [Routine] = client.from("routines").select().order("created_at").execute().value
            async let l: [CareLog] = client.from("care_logs").select().gte("scheduled_for", value: since)
                .order("logged_at", ascending: false).limit(3000).execute().value
            async let a: [Allergy] = client.from("allergies").select().order("created_at").execute().value
            async let med: [Medication] = client.from("medications").select().order("created_at").execute().value
            async let v: [Vaccine] = client.from("vaccines").select().order("created_at").execute().value
            async let w: [WeightEntry] = client.from("weight_entries").select().order("measured_on").execute().value
            async let d: [PetDocument] = client.from("documents").select().order("created_at").execute().value
            async let pl: [CarePlan] = client.from("care_plans").select().order("start_date", ascending: false).execute().value
            async let pp: [CarePlanPet] = fetch("care_plan_pets")

            let loaded = try await (profiles, h, m, p, r, l, a, med, v, w, d, pl, pp)
            guard self.userId == userId else { return }
            profile = loaded.0.first { $0.id == userId } ?? Profile(id: userId)
            households = loaded.1; members = loaded.2; pets = loaded.3; routines = loaded.4; logs = loaded.5
            allergies = loaded.6; medications = loaded.7; vaccines = loaded.8; weights = loaded.9; documents = loaded.10
            plans = loaded.11; planPets = loaded.12

            if selectedPet == nil || !pets.contains(where: { $0.id == selectedPetId }) { selectedPetId = sortedPets.first?.id }
            if phase == .ready || phase == .onboarding { updatePhase() }
            Reminders.reschedule(for: self)
        } catch {
            if !quiet { report(error) }
        }
    }

    private func subscribeToChanges() async {
        guard realtimeChannel == nil else { return }
        let channel = client.channel("tandem-changes")
        let changes = channel.postgresChange(AnyAction.self, schema: "public")
        realtimeChannel = channel
        realtimeTask = Task { [weak self] in
            for await _ in changes { self?.scheduleRefresh() }
        }
        try? await channel.subscribeWithError()
    }

    /// Collapses a burst of change notifications into one reload.
    func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await self?.loadAll(quiet: true)
        }
    }

    // MARK: - Who am I, and what can I do

    var myName: String {
        let name = profile?.displayName ?? ""
        return name.isEmpty ? (email.split(separator: "@").first.map(String.init) ?? "Me") : name
    }

    func isMember(ofHousehold id: UUID) -> Bool {
        members.contains { $0.householdId == id && $0.userId == userId }
    }

    func isOwner(ofHousehold id: UUID) -> Bool {
        members.contains { $0.householdId == id && $0.userId == userId && $0.isOwner }
    }

    var myHouseholds: [Household] { households.filter { isMember(ofHousehold: $0.id) } }
    var primaryHousehold: Household? { myHouseholds.first }
    var receivedPlans: [CarePlan] { plans.filter { $0.sitterId == userId && $0.status == "active" } }
    var ownedPlans: [CarePlan] { plans.filter { isMember(ofHousehold: $0.householdId) } }

    func canEdit(_ pet: Pet) -> Bool { isMember(ofHousehold: pet.householdId) }

    /// The plan through which I'm looking after this pet as a sitter, if any.
    func sitterPlan(for petId: UUID) -> CarePlan? {
        let mine = receivedPlans.filter { plan in planPets.contains { $0.carePlanId == plan.id && $0.petId == petId } }
        return mine.first { $0.phase == .current } ?? mine.first { $0.phase == .upcoming } ?? mine.first
    }

    func canLog(for pet: Pet, on day: Day = .today) -> Bool {
        if canEdit(pet) { return true }
        guard let plan = sitterPlan(for: pet.id) else { return false }
        return plan.startDate <= day && day <= plan.endDate
    }

    func pets(in plan: CarePlan) -> [Pet] {
        let ids = Set(planPets.filter { $0.carePlanId == plan.id }.map(\.petId))
        return pets.filter { ids.contains($0.id) }
    }

    func household(_ id: UUID) -> Household? { households.first { $0.id == id } }

    /// My own pets first, then pets I'm sitting.
    var sortedPets: [Pet] {
        pets.filter { canEdit($0) } + pets.filter { !canEdit($0) }
    }

    var selectedPet: Pet? { pets.first { $0.id == selectedPetId } ?? sortedPets.first }

    func selectPet(_ id: UUID) {
        selectedPetId = id
        UserDefaults.standard.set(id.uuidString, forKey: "selectedPet")
    }

    func tasks(for petId: UUID, on day: Day = .today) -> [CareTask] {
        Schedule.tasks(petId: petId, on: day, routines: routines, logs: logs)
    }

    // MARK: - Generic saves

    @discardableResult
    func save<T: Record>(_ item: T) async -> Bool {
        let previous = self[keyPath: T.list]
        let exists = previous.contains { $0.id == item.id }
        if let index = previous.firstIndex(where: { $0.id == item.id }) {
            self[keyPath: T.list][index] = item
        } else {
            self[keyPath: T.list].append(item)
        }
        do {
            if exists {
                try await client.from(T.table).update(item, returning: .minimal).eq("id", value: item.id).execute()
            } else {
                try await client.from(T.table).insert(item, returning: .minimal).execute()
            }
            Reminders.reschedule(for: self)
            return true
        } catch {
            self[keyPath: T.list] = previous
            report(error)
            return false
        }
    }

    @discardableResult
    func delete<T: Record>(_ item: T) async -> Bool {
        let previous = self[keyPath: T.list]
        self[keyPath: T.list].removeAll { $0.id == item.id }
        do {
            try await client.from(T.table).delete(returning: .minimal).eq("id", value: item.id).execute()
            Reminders.reschedule(for: self)
            return true
        } catch {
            self[keyPath: T.list] = previous
            report(error)
            return false
        }
    }

    // MARK: - Logging care

    func complete(_ task: CareTask, status: String = "done", note: String = "") async {
        guard task.log == nil, let userId else { return }
        let log = CareLog(
            petId: task.routine.petId, routineId: task.routine.id, category: task.routine.category,
            title: task.routine.title, scheduledFor: task.day, status: status, note: note,
            loggedBy: userId, loggedByName: myName, loggedAt: .now, carePlanId: sitterPlan(for: task.routine.petId)?.id
        )
        logs.insert(log, at: 0)
        if status == "done", let index = routines.firstIndex(where: { $0.id == task.routine.id }) {
            routines[index].lastDone = max(routines[index].lastDone ?? task.day, task.day)
        }
        do {
            try await client.from("care_logs").insert(log, returning: .minimal).execute()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            track(status == "done" ? "task_completed" : "task_skipped", ["category": task.routine.category.rawValue])
            Reminders.reschedule(for: self)
        } catch {
            logs.removeAll { $0.id == log.id }
            await loadAll(quiet: true)
            if (error as? PostgrestError)?.code == "23505" {
                let who = logs.first { $0.routineId == task.routine.id && $0.scheduledFor == task.day }?.loggedByName ?? "someone else"
                toast = Toast(message: "Already logged by \(who).")
                track("duplicate_prevented", ["category": task.routine.category.rawValue])
            } else {
                report(error)
            }
        }
    }

    func undo(_ log: CareLog) async {
        guard await delete(log) else { return }
        track("task_undone")
        // Occasional tasks are scheduled from when they were last done, which only the server knows for sure.
        if let index = routines.firstIndex(where: { $0.id == log.routineId }), routines[index].schedule != .daily {
            routines[index].lastDone = nil
            await loadAll(quiet: true)
        }
    }

    /// A free-form observation that isn't one of the scheduled tasks.
    func addNote(petId: UUID, title: String, note: String) async -> Bool {
        guard let userId else { return false }
        let log = CareLog(petId: petId, category: .note, title: title, note: note, loggedBy: userId,
                          loggedByName: myName, carePlanId: sitterPlan(for: petId)?.id)
        logs.insert(log, at: 0)
        do {
            try await client.from("care_logs").insert(log, returning: .minimal).execute()
            track("note_added")
            return true
        } catch {
            logs.removeAll { $0.id == log.id }
            report(error)
            return false
        }
    }

    // MARK: - Households and invites

    func createHousehold(name: String) async -> UUID? {
        do {
            let id: UUID = try await client.rpc("create_household", params: ["p_name": name]).execute().value
            await loadAll()
            track("household_created")
            return id
        } catch { report(error); return nil }
    }

    struct Redeemed: Decodable { let kind: String; let id: UUID }

    /// Joins a household or accepts a care plan, whichever the code belongs to.
    func redeem(code: String) async -> Redeemed? {
        do {
            let result: Redeemed = try await client.rpc("redeem_invite", params: ["p_code": code]).execute().value
            await loadAll()
            updatePhase()
            if result.kind == "care_plan", let pet = plans.first(where: { $0.id == result.id }).flatMap({ pets(in: $0).first }) {
                selectPet(pet.id)
            }
            track("invite_accepted", ["kind": result.kind])
            toast = Toast(message: result.kind == "household" ? "You've joined the household." : "Care plan added.")
            return result
        } catch { report(error); return nil }
    }

    func rotateInviteCode(household: Household) async {
        do {
            let _: String = try await client.rpc("rotate_household_code", params: ["p_household": household.id]).execute().value
            await loadAll()
        } catch { report(error) }
    }

    func rename(household: Household, to name: String) async {
        do {
            try await client.from("households").update(["name": name], returning: .minimal).eq("id", value: household.id).execute()
            await loadAll()
        } catch { report(error) }
    }

    func remove(member: HouseholdMember) async {
        do {
            try await client.from("household_members").delete(returning: .minimal)
                .eq("household_id", value: member.householdId).eq("user_id", value: member.userId).execute()
            await loadAll()
            updatePhase()
        } catch { report(error) }
    }

    func updateName(_ name: String) async {
        guard let userId else { return }
        do {
            try await client.from("profiles").upsert(Profile(id: userId, displayName: name), returning: .minimal).execute()
            profile = Profile(id: userId, displayName: name)
            await loadAll(quiet: true)
        } catch { report(error) }
    }

    // MARK: - Care plans

    func savePlan(_ plan: CarePlan, petIds: Set<UUID>, isNew: Bool) async -> CarePlan? {
        do {
            var saved = plan
            if isNew {
                saved.createdBy = userId
                saved.createdByName = myName
                saved = try await client.from("care_plans").insert(saved).select().single().execute().value
                track("care_plan_created", ["days": String(plan.startDate.days(until: plan.endDate) + 1)])
            } else {
                let edit = CarePlanEdit(title: plan.title, caregiverLabel: plan.caregiverLabel, startDate: plan.startDate,
                                        endDate: plan.endDate, categories: plan.categories, notes: plan.notes,
                                        emergencyNotes: plan.emergencyNotes)
                try await client.from("care_plans").update(edit, returning: .minimal).eq("id", value: plan.id).execute()
                try await client.from("care_plan_pets").delete(returning: .minimal).eq("care_plan_id", value: plan.id).execute()
            }
            let links = petIds.map { CarePlanPet(carePlanId: saved.id, petId: $0) }
            if !links.isEmpty { try await client.from("care_plan_pets").insert(links, returning: .minimal).execute() }
            await loadAll()
            return plans.first { $0.id == saved.id } ?? saved
        } catch { report(error); return nil }
    }

    func endAccess(for plan: CarePlan) async {
        do {
            try await client.from("care_plans").update(["status": "revoked"], returning: .minimal).eq("id", value: plan.id).execute()
            await loadAll()
            track("care_plan_revoked")
        } catch { report(error) }
    }

    func deletePlan(_ plan: CarePlan) async {
        do {
            try await client.from("care_plans").delete(returning: .minimal).eq("id", value: plan.id).execute()
            await loadAll()
        } catch { report(error) }
    }

    // MARK: - Photos and documents

    private func folder(for pet: Pet) -> String {
        "\(pet.householdId.uuidString.lowercased())/\(pet.id.uuidString.lowercased())"
    }

    func setPhoto(_ image: UIImage, for pet: Pet) async {
        guard let data = image.resized(maxSide: 900).jpegData(compressionQuality: 0.8) else { return }
        let path = "\(folder(for: pet))/photo-\(UUID().uuidString.lowercased()).jpg"
        do {
            try await client.storage.from(Config.bucket).upload(path, data: data, options: FileOptions(contentType: "image/jpeg"))
            imageCache.setObject(image, forKey: path as NSString)
            var updated = pets.first { $0.id == pet.id } ?? pet
            let old = updated.photoPath
            updated.photoPath = path
            await save(updated)
            if let old { _ = try? await client.storage.from(Config.bucket).remove(paths: [old]) }
        } catch { report(error) }
    }

    func addDocument(_ image: UIImage, title: String, kind: String, for pet: Pet) async -> Bool {
        guard let data = image.resized(maxSide: 1800).jpegData(compressionQuality: 0.8) else { return false }
        let path = "\(folder(for: pet))/docs/\(UUID().uuidString.lowercased()).jpg"
        do {
            try await client.storage.from(Config.bucket).upload(path, data: data, options: FileOptions(contentType: "image/jpeg"))
            imageCache.setObject(image, forKey: path as NSString)
            return await save(PetDocument(petId: pet.id, title: title, kind: kind, storagePath: path))
        } catch { report(error); return false }
    }

    func deleteDocument(_ document: PetDocument) async {
        if await delete(document) {
            _ = try? await client.storage.from(Config.bucket).remove(paths: [document.storagePath])
        }
    }

    func image(at path: String) async -> UIImage? {
        if let cached = imageCache.object(forKey: path as NSString) { return cached }
        guard let data = try? await client.storage.from(Config.bucket).download(path: path),
              let image = UIImage(data: data) else { return nil }
        imageCache.setObject(image, forKey: path as NSString)
        return image
    }

    // MARK: - Reminders, metrics, errors

    func setReminders(enabled: Bool) async {
        if enabled, !(await Reminders.requestPermission()) {
            remindersEnabled = false
            toast = Toast(message: "Turn on notifications for Tandem in Settings to get reminders.", isError: true)
        } else {
            remindersEnabled = enabled
        }
        UserDefaults.standard.set(remindersEnabled, forKey: "remindersEnabled")
        Reminders.reschedule(for: self)
    }

    private struct Event: Encodable {
        let userId: UUID
        let name: String
        let props: [String: String]
    }

    /// Anonymous usage counts, used to measure whether the app is actually doing its job.
    func track(_ name: String, _ props: [String: String] = [:]) {
        guard let userId else { return }
        let event = Event(userId: userId, name: name, props: props)
        Task { _ = try? await client.from("events").insert(event, returning: .minimal).execute() }
    }

    func report(_ error: Error) {
        if error is CancellationError { return }
        if (error as? URLError)?.code == .cancelled { return }
        toast = Toast(message: friendlyMessage(for: error), isError: true)
    }
}

extension UIImage {
    func resized(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self }
        let scale = maxSide / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
