import Foundation
import Combine
#if canImport(AppKit)
import AppKit
#endif

class LocalSyncManager: ObservableObject {
    static let shared = LocalSyncManager()
    
    @Published var syncFolderURLPath = UserDefaults.standard.string(forKey: "syncFolderURLPath") ?? "" {
        didSet { UserDefaults.standard.set(syncFolderURLPath, forKey: "syncFolderURLPath") }
    }
    
    @Published var isSyncing = false
    @Published var lastSyncError: String?
    
    private init() {}
    
    var isConfigured: Bool {
        return !syncFolderURLPath.isEmpty
    }
    
    func syncBookmarks(localBookmarks: [String: [BookBookmark]], completion: @escaping (Result<[String: [BookBookmark]], Error>) -> Void) {
        guard !syncFolderURLPath.isEmpty else {
            completion(.failure(NSError(domain: "LocalSync", code: 1, userInfo: [NSLocalizedDescriptionKey: "Sync folder not configured"])))
            return
        }
        
        let fileManager = FileManager.default
        let rootURL = URL(fileURLWithPath: syncFolderURLPath)
        let profileURL = rootURL.appendingPathComponent("profile.Librera")
        
        // 1. Gather all bookmarks from all device.* folders
        var allRemoteBookmarks: [BookBookmark] = []
        
        if fileManager.fileExists(atPath: profileURL.path) {
            do {
                let deviceFolders = try fileManager.contentsOfDirectory(at: profileURL, includingPropertiesForKeys: nil)
                for folder in deviceFolders {
                    if folder.lastPathComponent.hasPrefix("device.") {
                        let bookmarksFile = folder.appendingPathComponent("app-Bookmarks.json")
                        if fileManager.fileExists(atPath: bookmarksFile.path) {
                            let data = try Data(contentsOf: bookmarksFile)
                            // Android format is [String(t): Bookmark]
                            let dict = try JSONDecoder().decode([String: BookBookmark].self, from: data)
                            allRemoteBookmarks.append(contentsOf: dict.values)
                        }
                    }
                }
            } catch {
                print("Failed to read remote bookmarks: \(error.localizedDescription)")
            }
        } else {
            // Create profile folder if it doesn't exist
            try? fileManager.createDirectory(at: profileURL, withIntermediateDirectories: true)
        }
        
        // 2. Merge all remote bookmarks with local bookmarks
        // Flatten local bookmarks
        var allLocalBookmarks: [BookBookmark] = []
        for list in localBookmarks.values {
            allLocalBookmarks.append(contentsOf: list)
        }
        
        var mergedDict: [Int64: BookBookmark] = [:]
        for b in allRemoteBookmarks { mergedDict[b.t] = b }
        for b in allLocalBookmarks { mergedDict[b.t] = b }
        
        let mergedList = Array(mergedDict.values)
        
        // Convert back to [String: [BookBookmark]] to return to app
        var returnDict: [String: [BookBookmark]] = [:]
        for b in mergedList {
            // we need to use the filename or path. AppBookmark.path might be absolute or relative, but usually contains the file name.
            // Android uses ExtUtils.getFileName(path) to match. Let's group by b.path for now, or match existing local book paths.
            // For simplicity, we just group by the file URL lastPathComponent if possible, but actually `b.path` is what we store.
            let key = b.path ?? "Unknown"
            if returnDict[key] == nil {
                returnDict[key] = []
            }
            returnDict[key]?.append(b)
        }
        
        // Sort each array by time
        for (key, list) in returnDict {
            returnDict[key] = list.sorted { $0.createdAt > $1.createdAt }
        }
        
        // 3. Save our merged data to our own device folder
        let macOSDeviceURL = profileURL.appendingPathComponent("device.macOS")
        let myBookmarksFile = macOSDeviceURL.appendingPathComponent("app-Bookmarks.json")
        
        try? fileManager.createDirectory(at: macOSDeviceURL, withIntermediateDirectories: true)
        
        // We write ALL merged bookmarks to our file. Android actually writes only local, but it's fine to write all.
        // Actually, writing all ensures we are a fully synced node.
        var exportDict: [String: BookBookmark] = [:]
        for b in mergedList {
            exportDict["\(b.t)"] = b
        }
        
        do {
            let data = try JSONEncoder().encode(exportDict)
            try data.write(to: myBookmarksFile, options: .atomic)
            completion(.success(returnDict))
        } catch {
            completion(.failure(error))
        }
    }
    
    func selectFolder() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Sync Folder"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                DispatchQueue.main.async {
                    self.syncFolderURLPath = url.path
                }
            }
        }
        #endif
    }
}
