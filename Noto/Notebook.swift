import Foundation
import SwiftData
import SwiftUI
import UIKit

enum Days {
    static func calendar(_ zone: TimeZone = .autoupdatingCurrent) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        return c
    }
    static func key(_ date: Date = .now, zone: TimeZone = .autoupdatingCurrent) -> Int {
        let p = calendar(zone).dateComponents([.year, .month, .day], from: date)
        return p.year! * 10000 + p.month! * 100 + p.day!
    }
    static func date(_ key: Int, zone: TimeZone = .autoupdatingCurrent) -> Date {
        calendar(zone).date(from: DateComponents(year: key / 10000, month: key / 100 % 100, day: key % 100, hour: 12)) ?? .now
    }
    static func ago(_ days: Int, from: Date = .now, zone: TimeZone = .autoupdatingCurrent) -> Int {
        let c = calendar(zone)
        return key(c.date(byAdding: .day, value: -days, to: from)!, zone: zone)
    }
    static func label(_ key: Int) -> String {
        let format = UserDefaults.standard.string(forKey: "dateStyle") ?? "Long"
        let f = DateFormatter()
        f.calendar = calendar()
        f.dateStyle = format == "Short" ? .short : .long
        return f.string(from: date(key))
    }
}

@Model final class Note {
    @Attribute(.unique) var id: UUID
    var title: String
    var content: String
    var noteDate: Int
    var createdAt: Date
    var updatedAt: Date
    var isPinned = false
    var deletedAt: Date?
    init(day: Int = Days.key(), title: String = "", content: String = "", now: Date = .now) {
        id = UUID()
        self.title = title
        self.content = content
        noteDate = day
        createdAt = now
        updatedAt = now
    }
    var displayTitle: String { title.isEmpty ? "Untitled note" : title }
    var markdown: String { "# \(displayTitle)\n\n\(Days.label(noteDate))\n\n\(content)" }
    func matches(_ query: String) -> Bool {
        query.isEmpty || title.localizedStandardContains(query) || content.localizedStandardContains(query)
    }
}

struct Draft: Codable, Equatable {
    var title: String
    var body: String
    var day: Int
    static func url(_ id: UUID) throws -> URL {
        let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return folder.appendingPathComponent("draft-\(id).json")
    }
    func save(_ note: Note, in context: ModelContext) throws {
        let file = try Self.url(note.id)
        try JSONEncoder().encode(self).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        if note.title != title || note.content != body || note.noteDate != day {
            note.title = title
            note.content = body
            note.noteDate = day
            note.updatedAt = .now
        }
        try context.save()
        try? FileManager.default.removeItem(at: file)
    }
    static func load(_ note: Note) -> Self {
        if let url = try? url(note.id), let data = try? Data(contentsOf: url), let draft = try? JSONDecoder().decode(Self.self, from: data) { return draft }
        return Draft(title: note.title, body: note.content, day: note.noteDate)
    }
}

extension Color {
    static let paper = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.067, green: 0.071, blue: 0.078, alpha: 1) : UIColor(red: 0.98, green: 0.98, blue: 0.973, alpha: 1)
    })
    static let sage = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.57, green: 0.70, blue: 0.63, alpha: 1) : UIColor(red: 0.32, green: 0.42, blue: 0.38, alpha: 1)
    })
}
@main struct NotoApp: App {
    @AppStorage("appearance") private var appearance = "System"
    init() {
        _ = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }
    var body: some Scene {
        WindowGroup {
            Library().tint(.sage)
                .preferredColorScheme(appearance == "System" ? nil : appearance == "Dark" ? .dark : .light)
        }.modelContainer(for: Note.self)
    }
}
