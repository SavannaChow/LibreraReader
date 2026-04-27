import Foundation

struct BookBookmark: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var text: String
    var tag: String = ""
    var progress: Double
    var isFloating: Bool = false
    var createdAt: Date = Date()
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
