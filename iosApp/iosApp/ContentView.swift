//
//  ContentView.swift
//  Books3
//
//  Created by Ivan Ivanenko on 04.02.2026.
//

import SwiftUI
import UniformTypeIdentifiers


struct ContentView: View {
    @State private var bookManager = BookManager.shared
    @State private var isExtracting: Bool = false
    @State private var extractionError: String?
    @State private var selectedCategory: NavigationCategory? = .library
    @State private var searchText = ""
    @State private var sortOption: SortOption = .date
    @State private var sortOrder: SortOrder = .descending
    @AppStorage("library_display_mode") private var displayModeRawValue = LibraryDisplayMode.cover.rawValue
    @Environment(\.openWindow) private var openWindow
    @State private var selectedBookData: ReaderWindowData?
    @State private var isShowingFolderPicker = false
    
    enum NavigationCategory: String, CaseIterable, Identifiable {
        case library = "All Books"
        case bookmarks = "Bookmarks"
        case favorites = "Favorites"
        case recent = "Recent Books"
        case settings = "Settings"
        case about = "About"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .library: return "books.vertical"
            case .bookmarks: return "bookmark"
            case .favorites: return "star"
            case .recent: return "clock"
            case .settings: return "gearshape"
            case .about: return "info.circle"
            }
        }
    }
    
    enum SortOption: String, CaseIterable, Identifiable {
        case title = "Title"
        case date = "Date"
        var id: String { rawValue }
    }
    
    enum SortOrder {
        case ascending, descending
        var icon: String {
            self == .ascending ? "arrow.up" : "arrow.down"
        }
    }

    enum LibraryDisplayMode: String, CaseIterable, Identifiable {
        case cover = "Cover"
        case list = "List"
        case compact = "Checklist"
        case table = "Table"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .cover: return "square.grid.2x2"
            case .list: return "list.bullet"
            case .compact: return "checklist"
            case .table: return "tablecells"
            }
        }
    }

    private var displayMode: LibraryDisplayMode {
        get { LibraryDisplayMode(rawValue: displayModeRawValue) ?? .cover }
        set { displayModeRawValue = newValue.rawValue }
    }
    
    private var columns: [GridItem] {
        #if os(macOS)
        [GridItem(.adaptive(minimum: 160), spacing: 20)]
        #else
        [GridItem(.adaptive(minimum: 100), spacing: 10)]
        #endif
    }

    private func categoryCount(_ category: NavigationCategory) -> Int {
        switch category {
        case .library:
            return bookManager.books.count
        case .bookmarks:
            return bookManager.bookmarkEntries.count
        case .favorites:
            return bookManager.favoriteBooks.count
        case .recent:
            return bookManager.recentBooks.count
        case .settings, .about:
            return 0
        }
    }
    
    var body: some View {
        let _ = bookManager.forceUpdateTrigger
        NavigationSplitView {
            List(NavigationCategory.allCases.filter { $0 != .about && $0 != .settings }, selection: $selectedCategory) { category in
                NavigationLink(value: category) {
                    HStack {
                        Label(category.rawValue, systemImage: category.icon)
                        Spacer()
                        Text("\(categoryCount(category))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }
            
            Spacer()
            
            List(selection: $selectedCategory) {
                NavigationLink(value: NavigationCategory.settings) {
                    Label(NavigationCategory.settings.rawValue, systemImage: NavigationCategory.settings.icon)
                }
                NavigationLink(value: NavigationCategory.about) {
                    Label(NavigationCategory.about.rawValue, systemImage: NavigationCategory.about.icon)
                }
            }
            .frame(height: 80)
            
            .navigationTitle("Librera")
        } detail: {
            Group {
                if let category = selectedCategory {
                    switch category {
                    case .library:
                        libraryView
                    case .bookmarks:
                        bookmarksView
                    case .favorites:
                        favoritesView
                    case .recent:
                        recentView
                    case .settings:
                        settingsView
                    case .about:
                        aboutView
                    }
                } else {
                    Text("Select a category")
                }
            }
            .searchable(text: $searchText, placement: .automatic, prompt: "Search Title")
        }
        #if os(macOS)
        .sheet(item: $selectedBookData) { data in
            ReaderContainerView(
                url: data.url,
                rootURL: data.rootURL,
                title: data.title,
                bookPath: data.bookPath,
                initialJumpToProgress: data.jumpToProgress
            )
        }
        #else
        .fullScreenCover(item: $selectedBookData) { data in
            ReaderContainerView(
                url: data.url,
                rootURL: data.rootURL,
                title: data.title,
                bookPath: data.bookPath,
                initialJumpToProgress: data.jumpToProgress
            )
        }
        #endif
        .fileImporter(
            isPresented: $isShowingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    bookManager.loadFolder(at: url)
                }
            case .failure(let error):
                print("Error picking folder: \(error.localizedDescription)")
            }
        }
        #if os(macOS)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        let ext = url.pathExtension.lowercased()
                        let supported = ["pdf", "epub", "fb2", "mobi", "azw", "azw3", "cbz", "cbr"]
                        if supported.contains(ext) {
                            Task { @MainActor in
                                self.openBook(Book(url: url))
                            }
                        }
                    }
                }
            }
            return true
        }
        .frame(minWidth: 800, minHeight: 500)
        #endif
        .onChange(of: bookManager.requestToOpenURL) { old, new in
            if let url = new {
                bookManager.requestToOpenURL = nil
                openBook(Book(url: url))
            }
        }
        .onAppear {
            bookManager.restoreLastOpenedFolder()
        }
// ... intermediate part ...
        .overlay {
            if isExtracting {
                ZStack {
                    Color.black.opacity(0.4)
                    ProgressView("Opening Book...")
                        .controlSize(.large)
                        .padding()
                        .background(Material.regular)
                        .cornerRadius(12)
                }
            }
        }
        .alert("Error Opening Book", isPresented: Binding(get: { extractionError != nil }, set: { if !$0 { extractionError = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            if let error = extractionError {
                Text(error)
            }
        }
    }
    
    private var libraryView: some View {
        bookListView(books: bookManager.books, title: "All Books", isRecent: false)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        #if os(macOS)
                        bookManager.openFolder()
                        #else
                        isShowingFolderPicker = true
                        #endif
                    }) {
                        Label("Open Folder", systemImage: "folder.badge.plus")
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Display Mode", selection: $displayModeRawValue) {
                            ForEach(LibraryDisplayMode.allCases) { mode in
                                Label(mode.rawValue, systemImage: mode.icon).tag(mode.rawValue)
                            }
                        }
                    } label: {
                        Label("Display", systemImage: displayMode.icon)
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Sort By", selection: $sortOption) {
                            ForEach(SortOption.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        
                        Divider()
                        
                        Button(action: {
                            sortOrder = sortOrder == .ascending ? .descending : .ascending
                        }) {
                            Label(sortOrder == .ascending ? "Ascending" : "Descending", systemImage: sortOrder.icon)
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                }
                
                #if os(macOS)
                if let path = bookManager.currentFolderURL?.path {
                    ToolbarItem(placement: .principal) {
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .font(.headline)
                    }
                }
                #endif
            }
    }

    private var favoritesView: some View {
        bookListView(books: bookManager.favoriteBooks, title: "Favorites", isRecent: false)
    }

    private var bookmarksView: some View {
        let filteredBookmarks = bookManager.bookmarkEntries.filter { entry in
            searchText.isEmpty
                || entry.bookTitle.localizedCaseInsensitiveContains(searchText)
                || entry.bookmark.text.localizedCaseInsensitiveContains(searchText)
        }

        return Group {
            if filteredBookmarks.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Bookmarks" : "No Matching Bookmarks",
                    systemImage: "bookmark.slash",
                    description: Text(searchText.isEmpty ? "Bookmarks you create while reading will appear here." : "Try searching by book title or bookmark text.")
                )
            } else {
                List(filteredBookmarks) { entry in
                    Button {
                        openBookmark(entry)
                    } label: {
                        BookmarkLibraryRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Open Bookmark") {
                            openBookmark(entry)
                        }
                        Button("Open Book") {
                            openBook(bookForPath(entry.bookPath))
                        }
                    }
                }
            }
        }
        .navigationTitle("Bookmarks")
    }
    
    private var recentView: some View {
        bookListView(books: bookManager.recentBooks, title: "Recent Books", isRecent: true)
    }
    
    private var aboutView: some View {
        VStack(spacing: 20) {
            if let icon = PlatformImage.appIcon {
                Image(platformImage: icon)
                    .resizable()
                    .frame(width: 128, height: 128)
                    .shadow(radius: 10)
            } else {
                Image(systemName: "books.vertical")
                    .font(.system(size: 80))
                    .foregroundColor(.accentColor)
                    .frame(width: 128, height: 128)
            }
            
            VStack(spacing: 8) {
                Text("Librera")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.1"
                Text("Version \(version)")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Text("Author: Ivan Ivanenko")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("Librera Book reader supports PDF, EPUB, FB2, MOBI, AZW, AZW3, CBZ, CBR book formats")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .frame(maxWidth: 400)
                
                Link("librera.mobi", destination: URL(string: "https://librera.mobi/")!)
                    .font(.headline)
                    .padding(.top, 4)
            }
            
            Text("© 2026 Librera Team")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
                .padding(.top, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(PlatformColor.windowBackgroundColor))
    }
    
    @StateObject private var webDAVSyncManager = WebDAVSyncManager.shared
    
    private var settingsView: some View {
        Form {
            Section(header: Text("WebDAV Bookmark Sync").font(.headline)) {
                HStack {
                    Text("Server URL:")
                    TextField("https://example.com/remote.php/dav/files/user/Librera", text: $webDAVSyncManager.serverURL)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Text("Username:")
                    TextField("Username", text: $webDAVSyncManager.username)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Text("Password:")
                    SecureField("Password", text: $webDAVSyncManager.password)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Text("Profile:")
                    TextField("Librera", text: $webDAVSyncManager.profileName)
                        .textFieldStyle(.roundedBorder)
                }
                
                Text("Remote layout follows Android sync rules: `profile.<name>/device.<name>/app-Bookmarks.json`.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let error = webDAVSyncManager.lastSyncError {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                HStack {
                    Button(action: {
                        syncBookmarks()
                    }) {
                        if webDAVSyncManager.isSyncing {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.trailing, 4)
                        }
                        Text(webDAVSyncManager.isSyncing ? "Syncing..." : "Sync Now")
                    }
                    .disabled(!webDAVSyncManager.isConfigured || webDAVSyncManager.isSyncing)
                    #if os(macOS)
                    .buttonStyle(.borderedProminent)
                    #endif
                }
                .padding(.top, 8)
            }
            .padding()
        }
        .navigationTitle("Settings")
        #if os(macOS)
        .padding()
        #endif
    }
    
    private func syncBookmarks() {
        webDAVSyncManager.isSyncing = true
        webDAVSyncManager.lastSyncError = nil

        let bookPaths = bookManager.allKnownBookPaths
        let localBookmarks = BookPreferencesManager.shared.allBookmarks(for: bookPaths)

        webDAVSyncManager.syncBookmarks(localBookmarks: localBookmarks, knownBookPaths: bookPaths) { result in
            DispatchQueue.main.async {
                self.webDAVSyncManager.isSyncing = false
                switch result {
                case .success(let mergedBookmarks):
                    for path in bookPaths {
                        var pref = BookPreferencesManager.shared.load(for: path)
                        pref.bookmarks = mergedBookmarks[path] ?? []
                        BookPreferencesManager.shared.save(pref, for: path)
                    }

                    self.bookManager.forceUpdate()
                case .failure(let error):
                    self.webDAVSyncManager.lastSyncError = error.localizedDescription
                }
            }
        }
    }
    
    private func bookListView(books: [Book], title: String, isRecent: Bool) -> some View {
        let sortedBooks: [Book]
        if isRecent {
            // Recent books are already ordered by "last opened" in BookManager.recents
            sortedBooks = books
        } else {
            sortedBooks = books.sorted { a, b in
                let result: Bool
                switch sortOption {
                case .title:
                    result = a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
                case .date:
                    result = a.date < b.date
                }
                return sortOrder == .ascending ? result : !result
            }
        }
        
        let filteredBooks = sortedBooks.filter {
            searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(searchText)
        }
        
        return Group {
            if bookManager.isLoading {
                ProgressView("Scanning Library...")
                    .controlSize(.large)
                    .padding(.top, 50)
            } else if filteredBooks.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: searchText.isEmpty ? "books.vertical" : "magnifyingglass")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    
                    Text(searchText.isEmpty ? (title == "All Books" ? "No Books Found" : "No Recent Books") : "No Results for \"\(searchText)\"")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    if title == "All Books" && searchText.isEmpty {
                        Text("Open a folder with book files to get started.")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                          Button(action: {
                        #if os(macOS)
                        bookManager.openFolder()
                        #else
                        isShowingFolderPicker = true
                        #endif
                    }) {
                        Label("Open Folder", systemImage: "folder.badge.plus")
                    }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                switch displayMode {
                case .cover:
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 24) {
                            ForEach(filteredBooks) { book in
                                BookGridItem(book: book, isFavorite: bookManager.isFavorite(book))
                                    .onTapGesture {
                                        openBook(book)
                                    }
                                    .contextMenu {
                                        bookContextMenu(for: book)
                                    }
                            }
                        }
                        .padding()
                    }
                case .list:
                    List(filteredBooks) { book in
                        BookListRow(book: book, isFavorite: bookManager.isFavorite(book))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                openBook(book)
                            }
                            .contextMenu {
                                bookContextMenu(for: book)
                            }
                    }
                case .compact:
                    List(filteredBooks) { book in
                        CompactBookRow(
                            book: book,
                            isFavorite: bookManager.isFavorite(book),
                            onToggleFavorite: { bookManager.toggleFavorite(book) })
                        .contentShape(Rectangle())
                        .onTapGesture {
                            openBook(book)
                        }
                        .contextMenu {
                            bookContextMenu(for: book)
                        }
                    }
                case .table:
                    #if os(macOS)
                    Table(filteredBooks) {
                        TableColumn("Title") { book in
                            Button(book.title) {
                                openBook(book)
                            }
                            .buttonStyle(.plain)
                        }
                        TableColumn("Type") { book in
                            Text(book.type.rawValue.uppercased())
                        }
                        TableColumn("Date") { book in
                            Text(book.date, style: .date)
                        }
                        TableColumn("Progress") { book in
                            Text("\(Int(BookPreferencesManager.shared.load(for: book.url.path).scrollProgress * 100))%")
                        }
                        TableColumn("Favorite") { book in
                            Button {
                                bookManager.toggleFavorite(book)
                            } label: {
                                Image(systemName: bookManager.isFavorite(book) ? "star.fill" : "star")
                                    .foregroundColor(bookManager.isFavorite(book) ? .yellow : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    #else
                    List(filteredBooks) { book in
                        BookListRow(book: book, isFavorite: bookManager.isFavorite(book))
                    }
                    #endif
                }
            }
        }
        .navigationTitle(title)
    }

    @ViewBuilder
    private func bookContextMenu(for book: Book) -> some View {
        Button("Open") {
            openBook(book)
        }
        Button(bookManager.isFavorite(book) ? "Remove from Favorites" : "Add to Favorites") {
            bookManager.toggleFavorite(book)
        }
        #if os(macOS)
        Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([book.url])
        }
        #endif
    }

    private func bookForPath(_ path: String) -> Book {
        booksForLookup.first(where: { $0.url.path == path }) ?? Book(url: URL(fileURLWithPath: path))
    }

    private var booksForLookup: [Book] {
        var seen = Set<String>()
        return (bookManager.books + bookManager.favoriteBooks + bookManager.recentBooks).filter { book in
            seen.insert(book.url.path).inserted
        }
    }

    private func openBookmark(_ entry: LibraryBookmarkEntry) {
        openBook(bookForPath(entry.bookPath), jumpToProgress: entry.bookmark.progress)
    }

    private func openBook(_ book: Book, jumpToProgress: Double?) {
        // Track recent
        bookManager.addToRecents(book)

        if book.type == .pdf {
            let data = ReaderWindowData(
                url: book.url,
                rootURL: book.url.deletingLastPathComponent(),
                title: book.title,
                bookPath: book.url.path,
                jumpToProgress: jumpToProgress
            )
            #if os(macOS)
            openWindow(value: data)
            #else
            selectedBookData = data
            #endif
        } else if book.type == .epub || book.type == .fb2 || book.type == .mobi || book.type == .azw || book.type == .azw3 || book.type == .cbz || book.type == .cbr {
            isExtracting = true
            #if os(macOS)
            let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .suddenTerminationDisabled, .automaticTerminationDisabled], reason: "Extracting and preparing book for reading")
            #endif
            
            Task {
                #if os(macOS)
                defer { ProcessInfo.processInfo.endActivity(activity) }
                #endif
                do {
                    let (readerURL, rootURL): (URL, URL)
                    if book.type == .epub {
                        (readerURL, rootURL) = try await EpubExtractor.extractEpub(sourceURL: book.url)
                    } else if book.type == .fb2 {
                        (readerURL, rootURL) = try await Fb2Converter.convertFb2(sourceURL: book.url)
                    } else if book.type == .mobi || book.type == .azw || book.type == .azw3 {
                        (readerURL, rootURL) = try await MobiConverter.convertMobi(sourceURL: book.url)
                    } else if book.type == .cbz {
                        (readerURL, rootURL) = try await CbzConverter.convertCbz(sourceURL: book.url)
                    } else {
                        (readerURL, rootURL) = try await CbrConverter.convertCbr(sourceURL: book.url)
                    }
                    
                    await MainActor.run {
                        let data = ReaderWindowData(
                            url: readerURL,
                            rootURL: rootURL,
                            title: book.title,
                            bookPath: book.url.path,
                            jumpToProgress: jumpToProgress
                        )
                        #if os(macOS)
                        openWindow(value: data)
                        #else
                        selectedBookData = data
                        #endif
                        self.isExtracting = false
                    }
                } catch {
                    await MainActor.run {
                        let typeStr: String
                        switch book.type {
                        case .epub: typeStr = "EPUB"
                        case .fb2: typeStr = "FB2"
                        case .mobi: typeStr = "MOBI"
                        case .azw: typeStr = "AZW"
                        case .azw3: typeStr = "AZW3"
                        case .cbz: typeStr = "CBZ"
                        case .cbr: typeStr = "CBR"
                        default: typeStr = "Book"
                        }
                        self.extractionError = "Failed to open \(typeStr): \(error.localizedDescription)"
                        self.isExtracting = false
                    }
                }
            }
        }
    }

    private func openBook(_ book: Book) {
        openBook(book, jumpToProgress: nil)
    }
}

private struct BookListRow: View {
    let book: Book
    let isFavorite: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title2)
                .frame(width: 28)
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .fontWeight(.medium)
                Text(book.type.rawValue.uppercased())
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if isFavorite {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
            }
            Text(book.date, style: .date)
                .foregroundColor(.secondary)
        }
    }

    private var iconName: String {
        book.type == .pdf ? "doc.richtext" : "books.vertical"
    }
}

private struct CompactBookRow: View {
    let book: Book
    let isFavorite: Bool
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundColor(isFavorite ? .yellow : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.body)
                Text(book.type.rawValue.uppercased())
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text("\(Int(BookPreferencesManager.shared.load(for: book.url.path).scrollProgress * 100))%")
                .foregroundColor(.secondary)
                .font(.caption)
        }
    }
}

private struct BookmarkLibraryRow: View {
    let entry: LibraryBookmarkEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.bookmark.isFloating ? "bookmark.fill" : "bookmark")
                .foregroundColor(entry.bookmark.isFloating ? .accentColor : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(entry.bookTitle)
                        .font(.headline)
                }

                Text(entry.bookmark.text)
                    .lineLimit(2)

                HStack(spacing: 10) {
                    Text("Position \(Int(entry.bookmark.progress * 100))%")
                    Text(entry.bookmark.createdAt, style: .date)
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}


extension URL: Identifiable {
    public var id: String { self.absoluteString }
}

#Preview {
    ContentView()
}
