import Foundation
import NaturalLanguage
import Security

enum Vault {
    static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "NotoNotes.Writing", kSecAttrAccount as String: "service"] }
    static func read() -> String {
        var q = query
        q[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
    static func write(_ value: String) throws {
        if value.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw WritingError.keychain }
            return
        }
        let attrs: [String: Any] = [kSecValueData as String: Data(value.utf8), kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(query.merging(attrs) { _, new in new } as CFDictionary,nil) == errSecSuccess else { throw WritingError.keychain }
        } else if status != errSecSuccess { throw WritingError.keychain }
    }
}
enum WritingError: LocalizedError {
    case setup, consent, offline, invalid, service, limit, keychain
    var errorDescription: String? {
        switch self {
        case .setup: "Configure the HTTPS service and access token in Settings."
        case .consent: "Enable cloud writing in Settings to send text for review."
        case .offline: "You’re offline. You can keep writing and try again later."
        case .invalid: "The suggestions could not be matched safely to this passage."
        case .service: "The writing service is unavailable. Try again later."
        case .limit: "Choose a shorter passage or wait before trying again."
        case .keychain: "The access token could not be saved to Keychain."
        }
    }
}
struct Suggestion: Codable, Identifiable, Equatable {
    let id: UUID
    let original, replacement, category, explanation: String
    let start, length: Int
}
struct Review {
    let noteID: UUID
    let version: Int
    let passage: NSRange
    let source: String
    let edits: [Suggestion]
    func ranges(in body: String, note: UUID, revision: Int) throws -> [(NSRange,Suggestion)] {
        guard note == noteID, revision == version, let r = Range(passage, in: body), String(body[r]) == source else { throw WritingError.invalid }
        var end = 0
        guard Set(edits.map(\.id)).count == edits.count else { throw WritingError.invalid }
        return try edits.sorted { $0.start < $1.start }.map { e in
            let size = source.utf16.count
            guard e.start >= end, e.start <= size, e.length > 0, e.length <= size - e.start else { throw WritingError.invalid }
            let range = NSRange(location: e.start, length: e.length)
            guard let slice = Range(range,in: source), String(source[slice]) == e.original,
                  (source as NSString).range(of: e.original, options: .literal) == range,
                  (source as NSString).range(of: e.original, options: [.literal,.backwards]) == range else { throw WritingError.invalid }
            end = NSMaxRange(range)
            return (NSRange(location: passage.location + e.start, length: e.length),e)
        }
    }
}
enum Writing {
    static let selections = ["Fix Grammar","Improve Writing","Make Clearer","Make Shorter","Make Longer","Make Professional","Make Friendly","Make Natural","Simplify","Rewrite","Fix Punctuation"]
    static let tones = ["Professional","Friendly","Casual","Formal","Confident","Simple","Academic"]
    static func analyze(_ text: String, action: String, tone: String?, language: String) async throws -> [Suggestion] {
        guard UserDefaults.standard.bool(forKey: "cloud") else { throw WritingError.consent }
        var token = Vault.read()
        var url = URL(string: UserDefaults.standard.string(forKey: "endpoint") ?? "")
        var scheme = "https"
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-noto-fixture") {
            url = URL(string: "http://127.0.0.1:8989")
            scheme = "http"
            token = "simulator-fixture"
        }
        #endif
        guard let base = url, base.scheme == scheme, base.host != nil, base.user == nil, base.password == nil, !token.isEmpty else { throw WritingError.setup }
        guard text.utf16.count <= 16000 else { throw WritingError.limit }
        var request = URLRequest(url: base.appendingPathComponent("v1/writing"))
        request.httpMethod = "POST"
        request.timeoutInterval = 50
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let lang = language == "Auto" ? NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue ?? "auto" : language
        var payload = ["text":text, "action":action, "language":lang]
        payload["tone"] = tone
        request.httpBody = try JSONEncoder().encode(payload)
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        let session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (data,response) = try await session.data(for: request)
            switch (response as? HTTPURLResponse)?.statusCode {
            case 200: break
            case 401,403: throw WritingError.setup
            case 413,429: throw WritingError.limit
            default: throw WritingError.service
            }
            struct Envelope: Decodable { let suggestions: [Suggestion] }
            guard let result = try? JSONDecoder().decode(Envelope.self, from: data), result.suggestions.count <= 50 else { throw WritingError.invalid }
            return result.suggestions
        } catch let err as URLError where [.notConnectedToInternet,.networkConnectionLost].contains(err.code) { throw WritingError.offline }
    }
}
private final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
