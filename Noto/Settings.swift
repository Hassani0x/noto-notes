import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct NotebookExport: FileDocument {
    static let readableContentTypes: [UTType] = [.plainText]
    var text: String
    init(_ text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws { text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents:Data(text.utf8)) }
}
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort:\Note.noteDate,order:.reverse) private var notes: [Note]
    @AppStorage("appearance") private var appearance = "System"
    @AppStorage("sorting") private var sorting = "Note date"
    @AppStorage("dateStyle") private var dateStyle = "Long"
    @AppStorage("haptics") private var haptics = true
    @AppStorage("spell") private var spell = true
    @AppStorage("cloud") private var cloud = false
    @AppStorage("mode") private var mode = "On Demand"
    @AppStorage("language") private var language = "Auto"
    @AppStorage("endpoint") private var endpoint = ""
    @State private var token = ""
    @State private var consent = false
    @State private var export = false
    @State private var status: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Notebook") {
                    picker("Appearance",$appearance,["System","Light","Dark"])
                    picker("Date format",$dateStyle,["Long","Short"])
                    picker("Default sorting",$sorting,["Note date","Last edited","Title"])
                    Toggle("Haptic feedback",isOn:$haptics)
                    Button("Export Markdown") { export = true }
                    NavigationLink("Recently deleted") {
                        List(notes.filter{$0.deletedAt != nil}) { note in
                            LabeledContent(note.displayTitle) {
                                Button("Restore") {
                                    note.deletedAt = nil
                                    do { try context.save() } catch { context.rollback(); status = error.localizedDescription }
                                }
                            }
                        }.navigationTitle("Recently deleted")
                    }
                }
                Section("Writing") {
                    Toggle("Native spelling",isOn:$spell)
                    picker("Proofreading",$mode,["Off","On Demand","Automatic"])
                    Picker("Writing language",selection:$language) {
                        Text("Detect automatically").tag("Auto")
                        Text("English").tag("en")
                        Text("دری").tag("prs")
                        Text("فارسی").tag("fa")
                        Text("پښتو").tag("ps")
                    }
                }
                Section("Cloud privacy") {
                    Toggle("Allow cloud writing",isOn:Binding(get:{cloud},set:{ if $0 { consent = true } else { cloud = false } }))
                    TextField("HTTPS service URL",text:$endpoint).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Service access token",text:$token).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Save token") {
                        do { try Vault.write(token); status = "Access token saved" } catch { status = error.localizedDescription }
                    }
                    if let status { Text(status).font(.footnote) }
                }
                Section("About") { Text("Noto Notes"); Text("Notes are stored on this iPhone. Cloud writing uses your configured service and its model provider.") }
            }.navigationTitle("Settings").toolbar { Button("Done") { dismiss() } }
                .onAppear { token = Vault.read() }
                .alert("Allow cloud writing?",isPresented:$consent) {
                    Button("Allow") { cloud = true }
                    Button("Cancel",role:.cancel) {}
                } message: { Text("Selected passages go to your configured server and its AI provider. Whole-note actions send the current note body. Automatic proofreading sends the edited paragraph after you pause.") }
                .fileExporter(isPresented:$export,document:NotebookExport(notes.filter{$0.deletedAt == nil}.map(\.markdown).joined(separator:"\n\n---\n\n")),contentType:.plainText,defaultFilename:"Noto Notes.md") { result in
                    if case .failure(let e) = result {status = e.localizedDescription}
                }
        }
    }
    private func picker(_ title:String,_ selection:Binding<String>,_ values:[String]) -> some View {
        Picker(title,selection:selection) { ForEach(values,id:\.self) { Text($0) } }
    }
}
