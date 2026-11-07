import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DayPicker: View {
    @Binding var day: Int
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Quick dates") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], alignment: .leading, spacing: 4) {
                        ForEach([0,1,2,3,7,10,30], id: \.self) { offset in
                            Button(offset == 0 ? "Today" : offset == 1 ? "Yesterday" : "\(offset) days ago") {
                                day = Days.ago(offset)
                                dismiss()
                            }
                            .buttonStyle(.borderless)
                            .frame(minHeight: 44)
                        }
                    }
                }
                DatePicker("Note date", selection: Binding(get: { Days.date(day) }, set: { day = Days.key($0) }), in: ...Days.calendar().dateInterval(of: .day, for: .now)!.end.addingTimeInterval(-1), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                Label(Days.label(day), systemImage: "bookmark.fill").foregroundStyle(Color.sage).accessibilityLabel("Selected day, \(Days.label(day))")
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
    @State private var calendarJump = false
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
                .sheet(isPresented: $calendarJump) { DayPicker(day: $day) }
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
            if page == .calendar {
                MonthGrid(day: $day, marked: Set(active.map(\.noteDate)), jump: { calendarJump = true })
                    .listRowBackground(Color.paper)
                    .listRowSeparator(.hidden)
            }
            if rows.isEmpty && page == .calendar {
                Text("No notes for this day").foregroundStyle(.secondary).listRowBackground(Color.paper)
            }
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
            .overlay { if rows.isEmpty && page != .calendar { ContentUnavailableView(search.isEmpty ? "No notes here" : "No matching notes", systemImage: "note.text", description: Text(search.isEmpty ? "Use New note to begin writing." : "Try another word or adjust your filters.")) } }
    }
    private func row(_ n: Note) -> some View {
        NavigationLink(value: n.id) {
            VStack(alignment: .leading, spacing: 6) {
                Text(n.displayTitle).font(.system(.title3, design: .serif))
                if !n.content.isEmpty { Text(n.content).lineLimit(2).foregroundStyle(.secondary) }
                Text(Days.label(n.noteDate)).font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 8)
        }.accessibilityIdentifier("entry-\(n.title)").listRowBackground(Color.paper)
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
    let jump: () -> Void
    private var calendar: Calendar { Days.calendar() }
    private var first: Date { Days.date(day / 100 * 100 + 1) }
    private var month: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: first)
    }
    private var offsets: [Int?] {
        let blanks = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: first)!.count
        return Array(repeating: nil, count: blanks) + (1...count).map(Optional.some)
    }
    private func move(_ delta: Int) {
        guard let next = calendar.date(byAdding: .month, value: delta, to: Days.date(day)) else {return}
        day = min(Days.key(next), Days.key())
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: jump) {
                    HStack { Text(month).font(.headline); Image(systemName: "chevron.down").font(.caption) }
                        .frame(minHeight: 44)
                }.accessibilityIdentifier("calendarDay")
                Spacer()
                Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .accessibilityLabel("Previous month")
                Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    .accessibilityLabel("Next month").disabled(day / 100 >= Days.key() / 100)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    Text(calendar.veryShortStandaloneWeekdaySymbols[(calendar.firstWeekday-1+i)%7])
                        .font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
                }
                ForEach(Array(offsets.enumerated()), id: \.offset) { _, number in
                    if let number {
                        let key = day / 100 * 100 + number
                        Button { day = key } label: {
                            VStack(spacing: 2) {
                                Text(String(number)).font(.body.monospacedDigit())
                                    .foregroundStyle(day == key ? Color.white : Color.primary)
                                    .padding(5)
                                    .background { if day == key { Capsule().fill(Color(red:0.32,green:0.42,blue:0.38)) } }
                                Circle().fill(marked.contains(key) ? Color.sage : Color.clear).frame(width: 4,height: 4)
                            }.frame(maxWidth: .infinity, minHeight: 44)
                        }.accessibilityLabel(Days.label(key))
                            .accessibilityValue(marked.contains(key) ? "Contains notes" : "No notes")
                            .accessibilityIdentifier("day-\(key)")
                            .accessibilityAddTraits(day == key ? .isSelected : [])
                            .disabled(key > Days.key())
                    } else { Color.clear.frame(height: 1).accessibilityHidden(true) }
                }
            }
        }.buttonStyle(.borderless)
    }
}

