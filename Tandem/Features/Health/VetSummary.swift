import SwiftUI
import PDFKit
import UIKit

/// The owner picks what's relevant, and the vet gets a short PDF instead of the whole record.
struct VetSummaryView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let pet: Pet

    @State private var options = VetSummaryPDF.Options()
    @State private var pdfURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Reason for the visit or symptoms you've noticed", text: $options.reason, axis: .vertical)
                        .lineLimit(2...6)
                } header: {
                    Text("What's going on?")
                } footer: {
                    Text("This goes at the top of the summary.")
                }

                Section("Include") {
                    Toggle("Allergies", isOn: $options.allergies)
                    Toggle("Medications", isOn: $options.medications)
                    Toggle("Vaccines", isOn: $options.vaccines)
                    Toggle("Weight history", isOn: $options.weights)
                    Toggle("Recent care and notes", isOn: $options.careLog)
                    if options.careLog {
                        Picker("Covering", selection: $options.days) {
                            Text("Last 7 days").tag(7)
                            Text("Last 14 days").tag(14)
                            Text("Last 30 days").tag(30)
                        }
                    }
                }

                Section {
                    if let pdfURL {
                        PDFPreview(url: pdfURL)
                            .frame(height: 360)
                            .listRowInsets(EdgeInsets())
                    }
                } header: {
                    Text("Preview")
                }
            }
            .themedForm()
            .navigationTitle("Share with a vet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                if let pdfURL {
                    ShareLink(item: pdfURL, preview: SharePreview("\(pet.name) – health summary", image: Image(systemName: "doc.richtext"))) {
                        Label("Share PDF", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.primary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.bar)
                    .simultaneousGesture(TapGesture().onEnded { store.track("vet_summary_shared", ["days": String(options.days)]) })
                }
            }
            .task(id: options) {
                // Small pause so typing doesn't regenerate the PDF on every keystroke.
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                pdfURL = VetSummaryPDF.make(pet: pet, store: store, options: options)
            }
        }
    }
}

private struct PDFPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .secondarySystemBackground
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        view.document = PDFDocument(url: url)
    }
}

enum VetSummaryPDF {
    struct Options: Equatable {
        var reason = ""
        var allergies = true
        var medications = true
        var vaccines = true
        var weights = true
        var careLog = true
        var days = 14
    }

    @MainActor
    static func make(pet: Pet, store: AppStore, options: Options) -> URL? {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let data = renderer.pdfData { context in
            let w = Writer(context: context, page: page)
            w.title("\(pet.name) — Health summary")
            w.caption("Prepared \(Date.now.formatted(date: .long, time: .omitted)) by \(store.myName) with Tandem")
            w.space(10)

            // Identity
            var facts: [(String, String)] = [("Species", pet.species.label)]
            if !pet.breed.isEmpty { facts.append(("Breed", pet.breed)) }
            if !pet.sex.isEmpty { facts.append(("Sex", pet.sex)) }
            if let birth = pet.birthdate, let age = pet.ageLabel { facts.append(("Born", "\(birth.longLabel) (\(age))")) }
            if let weight = pet.weightLabel { facts.append(("Weight", weight)) }
            if !pet.microchip.isEmpty { facts.append(("Microchip", pet.microchip)) }
            w.facts(facts)

            if !options.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                w.heading("Reason for visit")
                w.body(options.reason)
            }

            if options.allergies {
                w.heading("Allergies")
                let items = store.allergies.filter { $0.petId == pet.id }
                if items.isEmpty { w.body("None known.") }
                for a in items {
                    w.bullet([a.name, a.severity.isEmpty ? nil : "(\(a.severity))", a.notes.isEmpty ? nil : "– \(a.notes)"].compactMap { $0 }.joined(separator: " "))
                }
            }

            if options.medications {
                w.heading("Medications")
                let items = store.medications.filter { $0.petId == pet.id }
                if items.isEmpty { w.body("None.") }
                for m in items {
                    var line = m.name
                    if !m.summary.isEmpty { line += " – \(m.summary)" }
                    if !m.active { line += " (stopped)" }
                    w.bullet(line)
                    if !m.instructions.isEmpty { w.indented(m.instructions) }
                }
            }

            if options.vaccines {
                w.heading("Vaccines")
                let items = store.vaccines.filter { $0.petId == pet.id }
                if items.isEmpty { w.body("No records.") }
                for v in items {
                    let given = v.dateGiven.map { "given \($0.longLabel)" }
                    let due = v.dueDate.map { "next due \($0.longLabel)" }
                    w.bullet(([v.name] + [given, due].compactMap { $0 }).joined(separator: ", "))
                }
            }

            if options.weights {
                let items = store.weights.filter { $0.petId == pet.id }.sorted { $0.measuredOn > $1.measuredOn }
                if !items.isEmpty {
                    w.heading("Weight history")
                    for entry in items.prefix(8) {
                        w.bullet("\(entry.measuredOn.longLabel): \(entry.weight.formatted(.number.precision(.fractionLength(0...1)))) \(entry.unit)")
                    }
                }
            }

            if options.careLog {
                let start = Day.today.adding(-(options.days - 1))
                let logs = store.logs.filter { $0.petId == pet.id && $0.scheduledFor >= start }
                w.heading("Care over the last \(options.days) days")

                // How consistently each routine task was done: the quickest read on appetite and adherence.
                let routines = store.routines.filter { $0.petId == pet.id && $0.active }
                var rows: [(String, String)] = []
                for routine in routines {
                    if routine.schedule == .interval || routine.schedule == .once {
                        let times = logs.filter { $0.routineId == routine.id && $0.isDone }
                        if let last = times.map(\.scheduledFor).max() {
                            rows.append((routine.title, "done \(times.count == 1 ? "once" : "\(times.count) times"), last on \(last.shortLabel)"))
                        }
                        continue
                    }
                    var scheduled = 0
                    for offset in 0..<options.days {
                        let day = start.adding(offset)
                        scheduled += Schedule.tasks(petId: pet.id, on: day, routines: [routine], logs: logs).count
                    }
                    guard scheduled > 0 else { continue }
                    let mine = logs.filter { $0.routineId == routine.id }
                    let done = mine.filter(\.isDone).count
                    let skipped = mine.filter(\.isSkipped).count
                    var value = "\(min(done, scheduled)) of \(scheduled) done"
                    if skipped > 0 { value += ", \(skipped) skipped" }
                    rows.append((routine.title + (routine.amount.isEmpty ? "" : " (\(routine.amount))"), value))
                }
                if rows.isEmpty { w.body("No routine tasks were scheduled in this period.") } else { w.facts(rows, labelWidth: 300) }

                let notes = logs.filter { !$0.note.isEmpty || $0.category == .note }.sorted { $0.loggedAt > $1.loggedAt }
                if !notes.isEmpty {
                    w.subheading("Notes and observations")
                    for log in notes.prefix(40) {
                        let when = log.loggedAt.formatted(date: .abbreviated, time: .shortened)
                        let text = log.note.isEmpty ? log.title : "\(log.title): \(log.note)"
                        w.bullet("\(when) – \(text) (\(log.loggedByName))")
                    }
                }
            }

            if pet.hasVetInfo {
                w.heading("Regular veterinarian")
                w.body([pet.vetName, pet.vetClinic, pet.vetPhone, pet.vetAddress].filter { !$0.isEmpty }.joined(separator: " · "))
            }
        }

        let safeName = pet.name.filter { $0.isLetter || $0.isNumber }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName.isEmpty ? "Pet" : safeName)-health-summary.pdf")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Lays text down the page and starts a new page when it runs out of room.
    private final class Writer {
        let context: UIGraphicsPDFRendererContext
        let page: CGRect
        let margin: CGFloat = 54
        var y: CGFloat = 0

        private let ink = UIColor(red: 0.12, green: 0.17, blue: 0.16, alpha: 1)
        private let muted = UIColor(red: 0.40, green: 0.45, blue: 0.43, alpha: 1)
        private let accent = UIColor(red: 0.16, green: 0.53, blue: 0.48, alpha: 1)

        init(context: UIGraphicsPDFRendererContext, page: CGRect) {
            self.context = context
            self.page = page
            newPage()
        }

        private var width: CGFloat { page.width - margin * 2 }

        private func newPage() {
            context.beginPage()
            y = margin
        }

        private func draw(_ text: String, font: UIFont, color: UIColor, x: CGFloat = 0, maxWidth: CGFloat? = nil, after: CGFloat = 4) {
            let w = (maxWidth ?? width) - (maxWidth == nil ? x : 0)
            let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
            let height = ceil(attributed.boundingRect(with: CGSize(width: w, height: .greatestFiniteMagnitude),
                                                      options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
            if y + height > page.height - margin { newPage() }
            attributed.draw(with: CGRect(x: margin + x, y: y, width: w, height: height),
                            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            y += height + after
        }

        func space(_ points: CGFloat) { y += points }
        func title(_ text: String) { draw(text, font: .systemFont(ofSize: 24, weight: .bold), color: ink) }
        func caption(_ text: String) { draw(text, font: .systemFont(ofSize: 10), color: muted) }

        func heading(_ text: String) {
            y += 12
            if y + 60 > page.height - margin { newPage() }
            draw(text.uppercased(), font: .systemFont(ofSize: 10.5, weight: .bold), color: accent, after: 3)
            let line = UIBezierPath()
            line.move(to: CGPoint(x: margin, y: y))
            line.addLine(to: CGPoint(x: page.width - margin, y: y))
            accent.withAlphaComponent(0.35).setStroke()
            line.lineWidth = 0.75
            line.stroke()
            y += 7
        }

        func subheading(_ text: String) {
            y += 8
            draw(text, font: .systemFont(ofSize: 11.5, weight: .semibold), color: ink)
        }

        func body(_ text: String) { draw(text, font: .systemFont(ofSize: 11.5), color: ink) }
        func indented(_ text: String) { draw(text, font: .systemFont(ofSize: 10.5), color: muted, x: 14) }

        func bullet(_ text: String) {
            let startY = y
            if startY + 16 <= page.height - margin {
                NSAttributedString(string: "•", attributes: [.font: UIFont.systemFont(ofSize: 11.5), .foregroundColor: accent])
                    .draw(at: CGPoint(x: margin + 2, y: startY))
            }
            draw(text, font: .systemFont(ofSize: 11.5), color: ink, x: 14)
        }

        func facts(_ rows: [(String, String)], labelWidth: CGFloat = 110) {
            for (label, value) in rows {
                let startY = y
                if startY + 16 > page.height - margin { newPage() }
                let rowY = y
                draw(label, font: .systemFont(ofSize: 11.5), color: muted, maxWidth: labelWidth - 8, after: 0)
                let labelEnd = y
                y = rowY
                draw(value, font: .systemFont(ofSize: 11.5, weight: .medium), color: ink, x: labelWidth, after: 0)
                y = max(y, labelEnd) + 5
            }
        }
    }
}
