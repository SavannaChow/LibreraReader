import SwiftUI

struct ReaderContainerView: View {
    let url: URL
    let rootURL: URL
    let title: String
    let bookPath: String  // Original book path for preferences key
    let initialJumpToProgress: Double?
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var settings = ReaderSettings()
    @State private var scrollProgress: Double = 0.0
    @State private var initialScrollProgress: Double = 0.0
    @State private var isLoaded = false
    @State private var showUI = true
    @State private var bookmarks: [BookBookmark] = []
    @State private var isShowingBookmarks = false
    @State private var isShowingAddBookmark = false
    @State private var isShowingSearch = false
    @State private var bookmarkText = ""
    @State private var bookmarkTag = ""
    @State private var bookmarkIsFloating = false
    @State private var editingBookmark: BookBookmark?
    @State private var jumpToProgress: Double?
    @State private var jumpToken: UUID?
    @State private var searchJumpResult: ReaderSearchResult?
    @State private var searchJumpToken: UUID?
    @State private var searchQuery = ""
    @State private var searchResults: [ReaderSearchResult] = []
    @State private var searchToken: UUID?
    @State private var isSearching = false
    @State private var selectedText = ""
    
    private var isPDF: Bool {
        url.pathExtension.lowercased() == "pdf"
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            Color(PlatformColor.windowBackgroundColor)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                #if os(iOS)
                if showUI {
                    VStack(spacing: 0) {
                        // Header / Navigation - Line 1 (iOS)
                        HStack {
                            Text(title)
                                .font(.headline)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            // Progress indicator
                            Text("\(Int(scrollProgress * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Button {
                                isShowingSearch = true
                            } label: {
                                Image(systemName: "magnifyingglass")
                            }
                            .keyboardShortcut("f", modifiers: .command)

                            Button {
                                isShowingBookmarks = true
                            } label: {
                                Image(systemName: "bookmark")
                            }
                            
                            Button("Close") {
                                savePreferences()
                                dismiss()
                            }
                            .keyboardShortcut(.cancelAction)
                        }
                        .padding([.horizontal, .top])
                        .padding(.bottom, 8)
                        
                        if !isPDF {
                            // Header / Settings - Line 2 (iOS)
                            HStack(spacing: 0) {
                                // Font Size
                                HStack(spacing: 0) {
                                    Button(action: { 
                                        settings.fontSize = max(12, settings.fontSize - 2)
                                        savePreferences()
                                    }) {
                                        Image(systemName: "textformat.size.smaller")
                                            .padding(8)
                                    }
                                    Divider().frame(height: 20)
                                    Button(action: { 
                                        settings.fontSize = min(36, settings.fontSize + 2)
                                        savePreferences()
                                    }) {
                                        Image(systemName: "textformat.size.larger")
                                            .padding(8)
                                    }
                                }
                                .background(Color.primary.opacity(0.1))
                                .cornerRadius(8)
                                
                                Spacer()
                                
                                // Alignment
                                Picker("Align", selection: $settings.textAlignment) {
                                    ForEach(ReaderSettings.TextAlignment.allCases) { alignment in
                                        Image(systemName: alignment.iconName).tag(alignment)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 100)
                                .onChange(of: settings.textAlignment) { _, _ in savePreferences() }
                                
                                Spacer()
                                
                                // Settings Menu (Font & Hyphenation)
                                Menu {
                                    Picker("Font Family", selection: $settings.fontFamily) {
                                        ForEach(ReaderSettings.availableFonts, id: \.self) { font in
                                            Text(font).tag(font)
                                        }
                                    }
                                    
                                    Picker("Hyphenation", selection: $settings.hyphenationLanguage) {
                                        ForEach(ReaderSettings.HyphenationLanguage.allCases) { lang in
                                            Text(lang.displayName).tag(lang)
                                        }
                                    }
                                } label: {
                                    Image(systemName: "gearshape")
                                        .font(.title3)
                                        .padding(8)
                                        .contentShape(Rectangle())
                                }
                                
                                Spacer()
                                
                                // Themes
                                HStack(spacing: 12) {
                                    ForEach(ReaderSettings.ReaderTheme.allCases) { theme in
                                        Button(action: {
                                            settings.theme = theme
                                            savePreferences()
                                        }) {
                                            ZStack {
                                                Circle()
                                                    .fill(theme.color)
                                                    .frame(width: 22, height: 22)
                                                    .overlay(
                                                        Circle()
                                                            .stroke(Color.primary.opacity(0.3), lineWidth: 1)
                                                    )
                                                
                                                if settings.theme == theme {
                                                    Circle()
                                                        .stroke(Color.primary, lineWidth: 2)
                                                        .frame(width: 28, height: 28)
                                                }
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding([.horizontal, .bottom])
                            .padding(.top, 4)
                        }
                    }
                    .background(Color(PlatformColor.windowBackgroundColor))
                    .transition(.move(edge: .top).combined(with: .opacity))
                    
                    Divider()
                }
                #else
                // Original macOS Header
                HStack {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Progress indicator
                    Text("\(Int(scrollProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button {
                        isShowingSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .keyboardShortcut("f", modifiers: .command)

                    Button {
                        isShowingBookmarks = true
                    } label: {
                        Image(systemName: "bookmark")
                    }
                    
                    Button("Close") {
                        savePreferences()
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
                .padding()
                .background(Color(PlatformColor.windowBackgroundColor))
                
                Divider()
                #endif
                
                if isLoaded {
                    ReaderView(
                        url: url,
                        rootURL: rootURL,
                        settings: settings,
                        initialScrollProgress: initialScrollProgress,
                        jumpToProgress: jumpToProgress,
                        jumpToken: jumpToken,
                        searchJumpResult: searchJumpResult,
                        searchJumpToken: searchJumpToken,
                        searchQuery: searchQuery,
                        searchToken: searchToken,
                        onSearchResults: handleSearchResults(_:),
                        scrollProgress: $scrollProgress,
                        selectedText: $selectedText
                    )
                        #if os(iOS)
                        .onTapGesture(count: 1) {
                            withAnimation(.easeInOut) {
                                showUI.toggle()
                            }
                        }
                        #endif
                }
            }
        }
        #if os(iOS)
        .statusBar(hidden: !showUI)
        .persistentSystemOverlays(showUI ? .automatic : .hidden)
        .toolbar(showUI ? .automatic : .hidden, for: .navigationBar)
        #else
        .frame(minWidth: 800, idealWidth: 1000, maxWidth: .infinity, minHeight: 600, idealHeight: 800, maxHeight: .infinity)
        .toolbar {
            if !isPDF {
                ToolbarItem(placement: .automatic) {
                    ControlGroup {
                        Button(action: { 
                            settings.fontSize = max(12, settings.fontSize - 2)
                            savePreferences()
                        }) {
                            Image(systemName: "textformat.size.smaller")
                        }
                        Button(action: { 
                            settings.fontSize = min(36, settings.fontSize + 2)
                            savePreferences()
                        }) {
                            Image(systemName: "textformat.size.larger")
                        }
                    }
                }
                
                ToolbarItem(placement: .automatic) {
                    Picker("Align", selection: $settings.textAlignment) {
                        ForEach(ReaderSettings.TextAlignment.allCases) { alignment in
                            Image(systemName: alignment.iconName).tag(alignment)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                    .onChange(of: settings.textAlignment) { _, _ in savePreferences() }
                }
                
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Picker("Font Family", selection: $settings.fontFamily) {
                            ForEach(ReaderSettings.availableFonts, id: \.self) { font in
                                Text(font).tag(font)
                            }
                        }
                        
                        Picker("Hyphenation", selection: $settings.hyphenationLanguage) {
                            ForEach(ReaderSettings.HyphenationLanguage.allCases) { lang in
                                Text(lang.displayName).tag(lang)
                            }
                        }
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                
                ToolbarItem(placement: .automatic) {
                    Button {
                        isShowingSearch = true
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .keyboardShortcut("f", modifiers: .command)
                }

                ToolbarItem(placement: .automatic) {
                    Button {
                        isShowingBookmarks = true
                    } label: {
                        Label("Bookmarks", systemImage: "bookmark")
                    }
                }

                ToolbarItem(placement: .automatic) {
                    HStack(spacing: 8) {
                        ForEach(ReaderSettings.ReaderTheme.allCases) { theme in
                            Button(action: {
                                settings.theme = theme
                                savePreferences()
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(theme.color)
                                        .frame(width: 20, height: 20)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.primary.opacity(0.3), lineWidth: 1)
                                        )
                                    
                                    if settings.theme == theme {
                                        Circle()
                                            .stroke(Color.primary, lineWidth: 2)
                                            .frame(width: 24, height: 24)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .help(theme.displayName)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
        #endif
        .sheet(isPresented: $isShowingBookmarks) {
            BookmarkListView(
                bookmarks: bookmarks,
                currentPageLabel: currentPageLabel,
                onAdd: openAddBookmarkFromPanel,
                onQuickAdd: saveQuickBookmarkFromPanel,
                onOpen: jumpToBookmark(_:),
                onEdit: startEditingBookmark(_:),
                onDelete: deleteBookmark(_:),
                onClose: { isShowingBookmarks = false })
        }
        .sheet(isPresented: $isShowingAddBookmark) {
            AddBookmarkView(
                title: editingBookmark == nil ? currentPageLabel : "Edit Bookmark",
                pageLabel: currentPageLabel,
                text: $bookmarkText,
                tag: $bookmarkTag,
                isFloating: $bookmarkIsFloating,
                progress: scrollProgress,
                onSave: saveBookmarkFromForm,
                onCancel: cancelBookmarkForm)
        }
        .sheet(isPresented: $isShowingSearch) {
            ReaderSearchView(
                query: $searchQuery,
                results: searchResults,
                isSearching: isSearching,
                onSearch: runSearch,
                onOpen: openSearchResult(_:),
                onClose: { isShowingSearch = false })
        }
        
        .onAppear {
            loadPreferences()
        }
        .onReceive(NotificationCenter.default.publisher(for: .bookmarksChanged)) { notification in
            if let path = notification.object as? String, path == bookPath {
                reloadBookmarks()
            }
        }
        .onDisappear {
            savePreferences()
        }
        #if os(macOS)
        .onExitCommand {
            savePreferences()
            dismiss()
        }
        #endif
    }
    
    private func loadPreferences() {
        let pref = BookPreferencesManager.shared.load(for: bookPath)
        settings = pref.toReaderSettings()
        scrollProgress = pref.scrollProgress
        initialScrollProgress = pref.scrollProgress
        bookmarks = pref.bookmarks.sorted { $0.createdAt > $1.createdAt }
        if let initialJumpToProgress {
            jumpToProgress = initialJumpToProgress
            jumpToken = UUID()
        }
        isLoaded = true
    }
    
    private func savePreferences() {
        var pref = BookPreferencesManager.shared.load(for: bookPath)
        pref.update(from: settings)
        pref.scrollProgress = scrollProgress
        BookPreferencesManager.shared.save(pref, for: bookPath)
    }

    private var currentPageLabel: String {
        "Bookmark on page \(max(1, Int((scrollProgress * 100).rounded(.towardZero))))"
    }

    private func reloadBookmarks() {
        bookmarks = BookPreferencesManager.shared.bookmarks(for: bookPath)
    }

    private func prepareBookmarkForm() {
        editingBookmark = nil
        bookmarkText = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        bookmarkTag = ""
        bookmarkIsFloating = false
        isShowingAddBookmark = true
    }

    private func saveBookmarkFromForm() {
        let cleanText = bookmarkText.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTag = bookmarkTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else {
            return
        }

        if var editingBookmark {
            editingBookmark.text = cleanText
            editingBookmark.tag = cleanTag
            editingBookmark.isFloating = bookmarkIsFloating
            BookPreferencesManager.shared.updateBookmark(editingBookmark, for: bookPath)
        } else {
            let bookmark = BookBookmark(
                text: cleanText,
                tag: cleanTag,
                progress: scrollProgress,
                isFloating: bookmarkIsFloating
            )
            BookPreferencesManager.shared.addBookmark(bookmark, for: bookPath)
        }

        isShowingAddBookmark = false
        clearBookmarkForm()
    }

    private func saveQuickBookmark() {
        let bookmark = BookBookmark(
            text: currentPageLabel,
            tag: "",
            progress: scrollProgress,
            isFloating: false
        )
        BookPreferencesManager.shared.addBookmark(bookmark, for: bookPath)
    }

    private func startEditingBookmark(_ bookmark: BookBookmark) {
        editingBookmark = bookmark
        bookmarkText = bookmark.text
        bookmarkTag = bookmark.tag
        bookmarkIsFloating = bookmark.isFloating
        isShowingBookmarks = false
        isShowingAddBookmark = true
    }

    private func deleteBookmark(_ bookmark: BookBookmark) {
        BookPreferencesManager.shared.deleteBookmark(bookmark.id, for: bookPath)
    }

    private func jumpToBookmark(_ bookmark: BookBookmark) {
        jumpToProgress = bookmark.progress
        jumpToken = UUID()
    }

    private func openAddBookmarkFromPanel() {
        isShowingBookmarks = false
        DispatchQueue.main.async {
            prepareBookmarkForm()
        }
    }

    private func saveQuickBookmarkFromPanel() {
        saveQuickBookmark()
    }

    private func cancelBookmarkForm() {
        isShowingAddBookmark = false
        clearBookmarkForm()
    }

    private func clearBookmarkForm() {
        editingBookmark = nil
        bookmarkText = ""
        bookmarkTag = ""
        bookmarkIsFloating = false
    }

    private func runSearch() {
        isSearching = true
        searchResults = []
        searchToken = UUID()
    }

    private func handleSearchResults(_ results: [ReaderSearchResult]) {
        searchResults = results
        isSearching = false
    }

    private func openSearchResult(_ result: ReaderSearchResult) {
        searchJumpResult = result
        searchJumpToken = UUID()
    }
}

private struct AddBookmarkView: View {
    let title: String
    let pageLabel: String
    @Binding var text: String
    @Binding var tag: String
    @Binding var isFloating: Bool
    let progress: Double
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)

            Text(pageLabel)
                .foregroundColor(.secondary)

            TextEditor(text: $text)
                .frame(minHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

            TextField("Tag", text: $tag)
                .textFieldStyle(.roundedBorder)

            Toggle("Floating bookmark", isOn: $isFloating)

            Text("Current position: \(Int(progress * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 360)
    }
}

private struct BookmarkListView: View {
    enum BookmarkSort: String, CaseIterable, Identifiable {
        case newest = "Newest"
        case oldest = "Oldest"
        case location = "Location"

        var id: String { rawValue }
    }

    let bookmarks: [BookBookmark]
    let currentPageLabel: String
    let onAdd: () -> Void
    let onQuickAdd: () -> Void
    let onOpen: (BookBookmark) -> Void
    let onEdit: (BookBookmark) -> Void
    let onDelete: (BookBookmark) -> Void
    let onClose: () -> Void
    
    @State private var searchText = ""
    @State private var sort = BookmarkSort.newest

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Bookmarks")
                .font(.title2)
                .fontWeight(.semibold)

            HStack(spacing: 12) {
                Button {
                    onAdd()
                } label: {
                    Label("Add", systemImage: "square.and.pencil")
                }

                Button {
                    onQuickAdd()
                } label: {
                    Label("Bookmark", systemImage: "bookmark.badge.plus")
                }

                Spacer()

                Button("Close", action: onClose)
            }

            Text(currentPageLabel)
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                TextField("Search bookmarks", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                Picker("Sort", selection: $sort) {
                    ForEach(BookmarkSort.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
            }

            if filteredBookmarks.isEmpty {
                ContentUnavailableView("No Bookmarks", systemImage: "bookmark.slash")
            } else {
                List(filteredBookmarks) { bookmark in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(bookmarkLine(bookmark))
                                .fontWeight(.medium)
                            if bookmark.isFloating {
                                Text("Floating bookmark")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if !bookmark.tag.isEmpty {
                                Text("#\(bookmark.tag)")
                                    .font(.caption)
                                    .foregroundColor(.accentColor)
                            }
                        }
                        Spacer()
                        Text("\(Int(bookmark.progress * 100))%")
                            .foregroundColor(.secondary)
                        Button {
                            onOpen(bookmark)
                        } label: {
                            Image(systemName: "arrow.turn.down.right")
                        }
                        .buttonStyle(.plain)
                        Button {
                            onEdit(bookmark)
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.plain)
                        Button(role: .destructive) {
                            onDelete(bookmark)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(24)
        .frame(minWidth: 420, minHeight: 320)
    }

    private var filteredBookmarks: [BookBookmark] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let searched = trimmedSearch.isEmpty ? bookmarks : bookmarks.filter {
            $0.text.localizedCaseInsensitiveContains(trimmedSearch)
                || $0.tag.localizedCaseInsensitiveContains(trimmedSearch)
        }

        switch sort {
        case .newest:
            return searched.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            return searched.sorted { $0.createdAt < $1.createdAt }
        case .location:
            return searched.sorted { $0.progress < $1.progress }
        }
    }

    private func bookmarkLine(_ bookmark: BookBookmark) -> String {
        let location = max(1, Int((bookmark.progress * 100).rounded(.towardZero)))
        let prefix = bookmark.isFloating ? "{\(location)}" : "\(location)"
        return "\(prefix): \(bookmark.text)"
    }
}

private struct ReaderSearchView: View {
    @Binding var query: String
    let results: [ReaderSearchResult]
    let isSearching: Bool
    let onSearch: () -> Void
    let onOpen: (ReaderSearchResult) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Search In Book")
                .font(.title2)
                .fontWeight(.semibold)

            HStack(spacing: 12) {
                TextField("Keyword", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(onSearch)

                Button("Search", action: onSearch)
                    .keyboardShortcut(.defaultAction)

                Button("Close", action: onClose)
            }

            if isSearching {
                ProgressView("Searching...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && results.isEmpty {
                ContentUnavailableView("No Results", systemImage: "magnifyingglass")
            } else {
                List(results) { result in
                    Button {
                        onOpen(result)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.displayPage)
                                .font(.headline)
                            Text(result.snippet)
                                .foregroundColor(.primary)
                                .lineLimit(3)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 480, minHeight: 360)
    }
}
