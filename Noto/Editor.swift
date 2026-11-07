import SwiftUI
import SwiftData

struct Editor: View {
    enum Sheet: String, Identifiable {
        case date, info, assistant, review
        var id: String { rawValue }
    }
    let note: Note
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @Environment(\.dismiss) private var dismiss
    @AppStorage("spell") private var spell = true
    @AppStorage("cloud") private var cloud = false
    @AppStorage("mode") private var mode = "On Demand"
    @AppStorage("language") private var language = "Auto"
    @State private var draft: Draft
    @StateObject private var bridge = TextBridge()
    @State private var selection = NSRange(location: 0,length: 0)
    @State private var revision = 0
    @State private var sheet: Sheet?
    @State private var review: Review?
    @State private var message: String?
    @State private var busy = false
    @State private var confirm = false
    @State private var saveError: String?
    @State private var pending: Task<Void,Never>?
    @State private var saveTask: Task<Void,Never>?
    @State private var lastRequest: (String,String?,NSRange)?
    @State private var cachedAuto: String?
    init(note: Note) {
        self.note = note
        _draft = State(initialValue: Draft.load(note))
    }
    private var words: Int { draft.body.split(whereSeparator: \.isWhitespace).count }
    private var total: NSRange { NSRange(location:0,length:draft.body.utf16.count) }
    private var ranges: [(NSRange,Suggestion)] { (try? review?.ranges(in:draft.body,note:note.id,revision:revision)) ?? [] }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Title", text: $draft.title, axis: .vertical)
                .font(.system(.largeTitle,design:.serif)).padding(.horizontal,24).padding(.vertical,12)
                .accessibilityIdentifier("title")
            BodyEditor(text: Binding(get:{draft.body},set:{ changeBody($0) }), selection:$selection, spell:spell, highlights:ranges.map(\.0), bridge:bridge) { sheet = .assistant }
            if let saveError { Button("Retry save · \(saveError)") { save() }.padding(.horizontal) }
            if busy { HStack { ProgressView(); Text("Reviewing writing…") }.padding(.horizontal) }
            else if !ranges.isEmpty { Button("\(ranges.count) writing suggestions") { sheet = .review }.padding(.horizontal) }
            else if let message, sheet == nil { Text(message).font(.footnote).padding(.horizontal) }
            Divider()
            HStack(spacing: 4) {
                Menu {
                    Button("Heading") { bridge.prefix("## ") }
                    Button("List item") { bridge.prefix("- ") }
                    Button("Undo") { bridge.view?.undoManager?.undo() }
                    Button("Redo") { bridge.view?.undoManager?.redo() }
                } label: { Label("Formatting",systemImage:"textformat").labelStyle(.iconOnly).frame(width:44,height:44) }
                Button { sheet = review == nil ? .assistant : .review } label: { Label("Writing assistant", systemImage:"pencil.line").labelStyle(.iconOnly).frame(width:44,height:44) }
                Spacer()
                Text("\(words) words").font(.footnote).foregroundStyle(.secondary)
                Button("Hide keyboard", systemImage:"keyboard.chevron.compact.down") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil) }.labelStyle(.iconOnly).frame(width:44,height:44)
            }.padding(.horizontal,16)
        }.background(Color.paper).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.principal) { Button { sheet = .date } label: { Label(Days.label(draft.day),systemImage:"calendar").font(.subheadline) }.accessibilityIdentifier("noteDate") }
                ToolbarItem(placement:.topBarTrailing) {
                    Menu {
                        Button("Note information") { sheet = .info }
                        Button(note.isPinned ? "Unpin" : "Pin") { note.isPinned.toggle(); save() }
                        ShareLink(item:"# \(draft.title)\n\n\(Days.label(draft.day))\n\n\(draft.body)")
                        Button("Delete",role:.destructive) { note.deletedAt = .now; save(); if saveError == nil { dismiss() } }
                    } label: { Label("Note options",systemImage:"ellipsis.circle") }
                }
            }
            .sheet(item:$sheet) { current in
                switch current {
                case .date: DayPicker(day:$draft.day)
                case .info:
                    NavigationStack {
                        Form {
                            Button("Change note date") { sheet = .date }
                            LabeledContent("Note date",value:Days.label(draft.day))
                            LabeledContent("Created",value:note.createdAt.formatted(date:.abbreviated,time:.standard)).accessibilityIdentifier("created")
                            LabeledContent("Edited",value:note.updatedAt.formatted(date:.abbreviated,time:.standard))
                            LabeledContent("Words",value:String(words))
                            LabeledContent("Characters",value:String(draft.body.count))
                        }.navigationTitle("Note information").toolbar { Button("Done") { sheet = nil } }
                    }
                case .assistant: assistant
                case .review: reviewSheet
                }
            }
            .onChange(of:draft) { _,_ in
                saveTask?.cancel()
                saveTask = Task { try? await Task.sleep(for:.milliseconds(350)); if !Task.isCancelled { save() } }
            }
            .onChange(of:phase) { _,new in if new != .active { save() } }
            .onDisappear { saveTask?.cancel(); pending?.cancel(); save() }
    }
    private var assistant: some View {
        NavigationStack {
            List {
                if !cloud { Text("Cloud writing is off. In Settings, connect your writing service and allow text to be sent.") }
                if let message { Text(message).foregroundStyle(.secondary) }
                if busy { ProgressView("Reviewing writing…") }
                Section("Note") {
                    Button("Proofread Note") { run("Proofread Note",range:total) }.disabled(mode == "Off")
                    Button("Improve Note") { run("Improve Note",range:total) }
                    Button("Summarize") { run("Summarize",range:total) }
                }.disabled(!cloud || draft.body.isEmpty)
                Section("Selection") {
                    ForEach(Writing.selections,id:\.self) { action in Button(action) { run(action,range:selection) } }
                }.disabled(!cloud || selection.length == 0)
                Section("Change tone") {
                    ForEach(Writing.tones,id:\.self) { tone in Button(tone) { run("Change Tone",tone:tone,range:selection.length > 0 ? selection : total) } }
                }.disabled(!cloud || draft.body.isEmpty)
            }.navigationTitle("Writing assistant").toolbar { Button("Done") { sheet = nil } }
        }
    }
    private var reviewSheet: some View {
        NavigationStack {
            List {
                if let message { Text(message) }
                ForEach(ranges.map(\.1)) { e in
                    Section(e.category) {
                        VStack(alignment:.leading,spacing:12) {
                            Text("Original").font(.caption).foregroundStyle(.secondary)
                            Text(e.original)
                            Divider()
                            Text("Suggested").font(.caption).foregroundStyle(Color.sage)
                            Text(e.replacement)
                            Text(e.explanation).font(.footnote).foregroundStyle(.secondary)
                        }
                        Button("Accept") { apply([e]) }
                        Button("Dismiss") { discard(e) }
                        Button("Copy suggestion") { UIPasteboard.general.string = e.replacement }
                    }
                }
                if !ranges.isEmpty {
                    Button("Correct all") { confirm = true }
                    Button("Try again") { if let (a,t,r) = lastRequest { run(a,tone:t,range:r) } }
                }
            }.navigationTitle("Review writing").toolbar { Button("Done") { sheet = nil } }
                .confirmationDialog("Apply all current corrections?",isPresented:$confirm) { Button("Apply corrections") { apply(ranges.map(\.1)) } }
        }
    }
    private func discard(_ e: Suggestion) {
        guard let r = review else { return }
        review = Review(noteID:r.noteID,version:r.version,passage:r.passage,source:r.source,edits:r.edits.filter{$0.id != e.id})
        if review?.edits.isEmpty == true { review = nil; sheet = nil }
    }
    private func apply(_ edits: [Suggestion]) {
        guard let r = review, let valid = try? r.ranges(in:draft.body,note:note.id,revision:revision),
              let slice = Range(r.passage,in:draft.body), !edits.isEmpty else { message = WritingError.invalid.localizedDescription; return }
        let chosen = Set(edits.map(\.id))
        let changes = valid.filter { chosen.contains($0.1.id) }
        let output = NSMutableString(string:String(draft.body[slice]))
        for (range,e) in changes.reversed() {
            output.replaceCharacters(in:NSRange(location:range.location-r.passage.location,length:range.length),with:e.replacement)
        }
        bridge.replace(r.passage,with:output as String)
        pending?.cancel()
        let rest = r.edits.filter { !chosen.contains($0.id) }.map { e in
            let offset = changes.filter { $0.1.start < e.start }.reduce(0) { $0 + $1.1.replacement.utf16.count - $1.1.length }
            return Suggestion(id:e.id,original:e.original,replacement:e.replacement,category:e.category,explanation:e.explanation,start:e.start+offset,length:e.length)
        }
        let newRange = NSRange(location:r.passage.location,length:output.length)
        review = rest.isEmpty ? nil : Review(noteID:note.id,version:revision,passage:newRange,source:output as String,edits:rest)
        if let (a,t,_) = lastRequest { lastRequest = (a,t,newRange) }
        if rest.isEmpty { sheet = nil }
    }
    private func save() {
        do { try draft.save(note,in:context); saveError = nil } catch { saveError = error.localizedDescription }
    }
    private func changeBody(_ value: String) {
        guard value != draft.body else {return}
        draft.body = value
        revision += 1
        review = nil
        pending?.cancel()
        busy = false
        message = nil
        if cloud && mode == "Automatic" {
            pending = Task {
                try? await Task.sleep(for:.seconds(2))
                guard !Task.isCancelled, bridge.view?.markedTextRange == nil else {return}
                let s = value as NSString
                let range = s.paragraphRange(for:NSRange(location:min(selection.location,s.length),length:0))
                let passage = s.substring(with:range)
                guard !passage.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, passage != cachedAuto else { return }
                run("Proofread Note",range:range,automatic:true)
            }
        }
    }
    private func run(_ action: String,tone: String? = nil,range: NSRange,automatic: Bool = false) {
        guard let slice = Range(range,in:draft.body), range.length > 0 else {return}
        pending?.cancel()
        let source = String(draft.body[slice]), version = revision
        lastRequest = (action,tone,range)
        busy = true
        message = nil
        pending = Task {
            do {
                let edits = try await Writing.analyze(source,action:action,tone:tone,language:language)
                guard !Task.isCancelled, version == revision, cloud else {return}
                let r = Review(noteID:note.id,version:version,passage:range,source:source,edits:edits)
                _ = try r.ranges(in:draft.body,note:note.id,revision:revision)
                if automatic { cachedAuto = source }
                review = edits.isEmpty ? nil : r
                if edits.isEmpty { message = "No changes suggested" }
                else if !automatic { sheet = .review }
            } catch { if !Task.isCancelled { message = error.localizedDescription } }
            if !Task.isCancelled { busy = false }
        }
    }
}
