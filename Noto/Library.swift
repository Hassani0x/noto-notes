import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DayPicker: View {
    @Binding var day: Int
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Note date", selection: Binding(get: { Days.date(day) }, set: { day = Days.key($0) }), in: ...Days.calendar().startOfDay(for: .now).addingTimeInterval(86399), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                Label(Days.label(day), systemImage: "bookmark.fill").foregroundStyle(Color.sage).accessibilityLabel("Selected day, \(Days.label(day))")
                Section("Quick dates") {
                    ForEach([0,1,2,3,7,10,30], id: \.self) { offset in
                        Button(offset == 0 ? "Today" : offset == 1 ? "Yesterday" : "\(offset) days ago") { day = Days.ago(offset); dismiss() }
                    }
                }
            }.navigationTitle("Note date").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Done") { dismiss() } }
        }
    }
}

struct Library: View {
    enum Page: String, CaseIterable { case notes = "Notes", calendar = "Calendar", timeline = "Timeline" }
    @Environment(\.modelContext) private var context
    @Query(sort: \Note.noteDate, order: .reverse) private var all: [Note]
    @State private var path = [UUID]()
    @State private var page = Page.notes
    @State private var day = Days.key()
    @State private var search = ""
    @State private var pinned = false
    @State private var dateFilter: Int?
    @State private var filterSheet = false
    @State private var settings = false
    @State private var error: String?
    @AppStorage("sorting") private var sorting = "Note date"
    @AppStorage("haptics") private var haptics = true
    private var active: [Note] { all.filter { $0.deletedAt == nil } }
    private var visible: [Note] {
        active.filter { note in
            switch page {
            case .calendar: return note.noteDate == day
            case .timeline: return true
            case .notes: return note.matches(search) && (!pinned || note.isPinned) && (dateFilter == nil || note.noteDate == dateFilter)
            }
        }.sorted { a,b in
            if page == .notes && sorting == "Title" { return a.displayTitle.localizedStandardCompare(b.displayTitle) == .orderedAscending }
            if page == .notes && sorting == "Last edited" { return a.updatedAt > b.updatedAt }
            return a.noteDate == b.noteDate ? a.createdAt > b.createdAt : a.noteDate > b.noteDate
        }
    }
    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                if page == .calendar {
                    MonthGrid(day: $day, marked: Set(active.map(\.noteDate))).padding(.horizontal)
                }
                if page == .notes {
                    list.searchable(text: $search, prompt: "Search notes")
                } else { list }
                Divider()
                HStack {
                    ForEach(Page.allCases, id: \.self) { item in
                        Button { page = item } label: {
                            VStack(spacing: 4) {
                                Image(systemName: item == .notes ? "note.text" : item == .calendar ? "calendar" : "clock")
                                Text(item.rawValue).font(.caption)
                            }.frame(maxWidth: .infinity, minHeight: 48)
                        }.foregroundStyle(item == page ? Color.sage : .secondary)
                            .accessibilityAddTraits(item == page ? .isSelected : [])
                    }
                }
            }.background(Color.paper).navigationTitle(page.rawValue)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Settings", systemImage: "gearshape") { settings = true } }
                    ToolbarItem(placement: .topBarTrailing) {
                        if page == .notes {
                            Menu {
                                Toggle("Pinned only", isOn: $pinned)
                                Button("Filter by date") { filterSheet = true }
                                if dateFilter != nil { Button("Clear date filter") { dateFilter = nil } }
                                Picker("Sort", selection: $sorting) { ForEach(["Note date","Last edited","Title"], id: \.self) { Text($0) } }
                            } label: { Label("Filter and sort", systemImage: "line.3.horizontal.decrease.circle") }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) { Button("New note", systemImage: "square.and.pencil") { create() } }
                }
                .navigationDestination(for: UUID.self) { id in
                    if let note = all.first(where: { $0.id == id }) { Editor(note: note).id(id) }
                }
                .sheet(isPresented: $settings) { SettingsView() }
                .sheet(isPresented: $filterSheet) { DayPicker(day: Binding(get: { dateFilter ?? Days.key() }, set: { dateFilter = $0 })).onAppear { if dateFilter == nil { dateFilter = Days.key() } } }
                .alert("Couldn’t save changes", isPresented: Binding(get: {error != nil}, set: {if !$0 {error=nil}})) { Button("OK") {} } message: { Text(error ?? "") }
        }
    }
    private var list: some View {
        let rows = visible
        let pins = page == .notes ? rows.filter(\.isPinned) : []
        let rest = page == .notes ? rows.filter { !$0.isPinned } : rows
        let groups = Dictionary(grouping: rest, by: \.noteDate)
        return List {
            if page == .notes, let dateFilter { Text("Showing \(Days.label(dateFilter))").font(.footnote) }
            if !pins.isEmpty { Section("Pinned") { ForEach(pins) { row($0) } } }
            if page == .notes && sorting != "Note date" {
                ForEach(rest) { row($0) }
            } else {
                ForEach(groups.keys.sorted(by: >), id: \.self) { key in
                    Section {
                        ForEach(groups[key] ?? []) { row($0) }
                    } header: {
                        HStack {
                            if page == .timeline && day == key { Image(systemName: "bookmark.fill").foregroundStyle(Color.sage); Text("Selected") }
                            Text(Days.label(key))
                        }.textCase(nil)
                    }
                }
            }
        }.listStyle(.plain).scrollContentBackground(.hidden)
            .overlay { if rows.isEmpty { ContentUnavailableView(search.isEmpty ? "No notes here" : "No matching notes", systemImage: "note.text", description: Text(search.isEmpty ? "Use New note to begin writing." : "Try another word or adjust your filters.")) } }
    }
    private func row(_ n: Note) -> some View {
        NavigationLink(value: n.id) {
            VStack(alignment: .leading, spacing: 6) {
                Text(n.displayTitle).font(.system(.title3, design: .serif))
                if !n.content.isEmpty { Text(n.content).lineLimit(2).foregroundStyle(.secondary) }
                Text(Days.label(n.noteDate)).font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 8)
        }.listRowBackground(Color.paper)
            .contextMenu {
                Button(n.isPinned ? "Unpin" : "Pin") { n.isPinned.toggle(); save() }
                Button("Duplicate") { create(copy: n) }
                Button("Delete", role: .destructive) { n.deletedAt = .now; save() }
            }
    }
    private func create(copy: Note? = nil) {
        let n = Note(day: copy?.noteDate ?? (page == .calendar ? day : Days.key()), title: copy?.title ?? "", content: copy?.content ?? "")
        context.insert(n)
        if save() {
            if haptics { UISelectionFeedbackGenerator().selectionChanged() }
            path.append(n.id)
        }
    }
    @discardableResult private func save() -> Bool {
        do { try context.save(); return true } catch { self.error = error.localizedDescription; return false }
    }
}

struct MonthGrid: View {
    @Binding var day: Int
    let marked: Set<Int>
    var body: some View {
        CalendarWidget(day: $day, marked: marked).frame(minHeight: 300, maxHeight: 360)
    }
}
struct CalendarWidget: UIViewRepresentable {
    @Binding var day: Int
    let marked: Set<Int>
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UICalendarView {
        let v = UICalendarView()
        v.calendar = Days.calendar()
        v.availableDateRange = DateInterval(start: Date.distantPast, end: Days.calendar().date(byAdding: .day, value: 1, to: Days.calendar().startOfDay(for: .now))!.addingTimeInterval(-1))
        v.delegate = context.coordinator
        v.selectionBehavior = UICalendarSelectionSingleDate(delegate: context.coordinator)
        return v
    }
    func updateUIView(_ view: UICalendarView, context: Context) {
        let previous = context.coordinator.parent.marked
        context.coordinator.parent = self
        let components = Days.calendar().dateComponents([.year,.month,.day], from: Days.date(day))
        if let sel = view.selectionBehavior as? UICalendarSelectionSingleDate, sel.selectedDate?.day != components.day || sel.selectedDate?.month != components.month || sel.selectedDate?.year != components.year {
            sel.setSelected(components, animated: false)
        }
        view.reloadDecorations(forDateComponents: previous.symmetricDifference(marked).map { Days.calendar().dateComponents([.year,.month,.day], from: Days.date($0)) }, animated: false)
    }
    final class Coordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
        var parent: CalendarWidget
        init(_ parent: CalendarWidget) { self.parent = parent }
        func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate components: DateComponents?) {
            if let components, let d = Days.calendar().date(from: components) { parent.day = Days.key(d) }
        }
        func calendarView(_ view: UICalendarView, decorationFor components: DateComponents) -> UICalendarView.Decoration? {
            guard let date = Days.calendar().date(from: components), parent.marked.contains(Days.key(date)) else { return nil }
            return .default(color: UIColor(Color.sage), size: .small)
        }
    }
}
