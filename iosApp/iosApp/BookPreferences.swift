import Foundation

struct BookBookmark: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var path: String?
    var text: String
    var p: Double
    var t: Int64
    var isF: Bool = false
    
    var progress: Double {
        get { p }
        set { p = newValue }
    }
    
    var isFloating: Bool {
        get { isF }
        set { isF = newValue }
    }
    
    var createdAt: Date {
        get { Date(timeIntervalSince1970: TimeInterval(t) / 1000.0) }
        set { t = Int64(newValue.timeIntervalSince1970 * 1000.0) }
    }
    
    enum CodingKeys: String, CodingKey {
        case id, path, text, p, t, isF
    }
    
    init(id: UUID = UUID(), path: String? = nil, text: String, progress: Double, isFloating: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.path = path
        self.text = text
        self.p = progress
        self.isF = isFloating
        self.t = Int64(createdAt.timeIntervalSince1970 * 1000.0)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        self.path = try? container.decodeIfPresent(String.self, forKey: .path)
        self.text = try container.decode(String.self, forKey: .text)
        self.p = try container.decode(Double.self, forKey: .p)
        self.t = try container.decode(Int64.self, forKey: .t)
        self.isF = (try? container.decodeIfPresent(Bool.self, forKey: .isF)) ?? false
    }
}

struct BookPreference: Codable {
    var fontSize: Double = 22.0
    var fontFamily: String = "Serif"
    var themeName: String = "sepia"
    var textAlignmentName: String = "justify"
    var hyphenationLanguageCode: String = "auto"
    var scrollProgress: Double = 0.0
    var bookmarks: [BookBookmark] = []
    
    var theme: ReaderSettings.ReaderTheme {
        get { ReaderSettings.ReaderTheme(rawValue: themeName) ?? .white }
        set { themeName = newValue.rawValue }
    }
    
    var textAlignment: ReaderSettings.TextAlignment {
        get { ReaderSettings.TextAlignment(rawValue: textAlignmentName) ?? .left }
        set { textAlignmentName = newValue.rawValue }
    }
    
    var hyphenationLanguage: ReaderSettings.HyphenationLanguage {
        get { ReaderSettings.HyphenationLanguage(rawValue: hyphenationLanguageCode) ?? .auto }
        set { hyphenationLanguageCode = newValue.rawValue }
    }
    
    enum CodingKeys: String, CodingKey {
        case fontSize, fontFamily, themeName, textAlignmentName, hyphenationLanguageCode, scrollProgress, bookmarks
    }
    
    init() {}
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? 22.0
        self.fontFamily = try container.decodeIfPresent(String.self, forKey: .fontFamily) ?? "Serif"
        self.themeName = try container.decodeIfPresent(String.self, forKey: .themeName) ?? "sepia"
        self.textAlignmentName = try container.decodeIfPresent(String.self, forKey: .textAlignmentName) ?? "justify"
        self.hyphenationLanguageCode = try container.decodeIfPresent(String.self, forKey: .hyphenationLanguageCode) ?? "auto"
        self.scrollProgress = try container.decodeIfPresent(Double.self, forKey: .scrollProgress) ?? 0.0
        self.bookmarks = (try? container.decodeIfPresent([BookBookmark].self, forKey: .bookmarks)) ?? []
    }
    
    func toReaderSettings() -> ReaderSettings {
        var settings = ReaderSettings()
        settings.fontSize = fontSize
        settings.fontFamily = fontFamily
        settings.theme = theme
        settings.textAlignment = textAlignment
        settings.hyphenationLanguage = hyphenationLanguage
        return settings
    }
    
    mutating func update(from settings: ReaderSettings) {
        fontSize = settings.fontSize
        fontFamily = settings.fontFamily
        themeName = settings.theme.rawValue
        textAlignmentName = settings.textAlignment.rawValue
        hyphenationLanguageCode = settings.hyphenationLanguage.rawValue
    }
}

class BookPreferencesManager {
    static let shared = BookPreferencesManager()
    
    private let userDefaults = UserDefaults.standard
    private let preferencesKey = "BookPreferences"
    
    private init() {}
    
    private func key(for bookPath: String) -> String {
        // Use a stable hash of the path. Swift's .hashValue is not stable across restarts.
        let stableHash = bookPath.utf8.reduce(5381) {
            ($0 << 5) &+ $0 &+ Int($1)
        }
        return "\(preferencesKey)_\(stableHash)"
    }
    
    func load(for bookPath: String) -> BookPreference {
        let key = key(for: bookPath)
        guard let data = userDefaults.data(forKey: key),
              let preference = try? JSONDecoder().decode(BookPreference.self, from: data) else {
            return BookPreference()
        }
        return preference
    }
    
    func save(_ preference: BookPreference, for bookPath: String) {
        let key = key(for: bookPath)
        if let data = try? JSONEncoder().encode(preference) {
            userDefaults.set(data, forKey: key)
            // Notify that progress might have changed
            NotificationCenter.default.post(name: .bookProgressChanged, object: bookPath)
            NotificationCenter.default.post(name: .bookmarksChanged, object: bookPath)
        }
    }

    func addBookmark(_ bookmark: BookBookmark, for bookPath: String) {
        var preference = load(for: bookPath)
        preference.bookmarks.append(bookmark)
        preference.bookmarks.sort { $0.createdAt > $1.createdAt }
        save(preference, for: bookPath)
    }

    func updateBookmark(_ bookmark: BookBookmark, for bookPath: String) {
        var preference = load(for: bookPath)
        if let index = preference.bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
            preference.bookmarks[index] = bookmark
            save(preference, for: bookPath)
        }
    }

    func deleteBookmark(_ bookmarkID: UUID, for bookPath: String) {
        var preference = load(for: bookPath)
        preference.bookmarks.removeAll { $0.id == bookmarkID }
        save(preference, for: bookPath)
    }

    func bookmarks(for bookPath: String) -> [BookBookmark] {
        load(for: bookPath).bookmarks.sorted { $0.createdAt > $1.createdAt }
    }

    func allBookmarks(for bookPaths: [String]) -> [String: [BookBookmark]] {
        Dictionary(uniqueKeysWithValues: bookPaths.map { path in
            (path, bookmarks(for: path))
        })
    }
}

extension Notification.Name {
    static let bookProgressChanged = Notification.Name("bookProgressChanged")
    static let bookmarksChanged = Notification.Name("bookmarksChanged")
    static let favoritesChanged = Notification.Name("favoritesChanged")
}
