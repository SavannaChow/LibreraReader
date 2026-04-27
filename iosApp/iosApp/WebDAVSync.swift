import Foundation
import Combine

private struct AndroidBookmarkRecord: Codable {
    var path: String
    var text: String
    var p: Double
    var t: Int64
    var isF: Bool
}

private struct WebDAVItem {
    let href: String
    let isCollection: Bool
}

final class WebDAVSyncManager: ObservableObject {
    static let shared = WebDAVSyncManager()

    @Published var serverURL = UserDefaults.standard.string(forKey: "webdav_server_url") ?? "" {
        didSet { UserDefaults.standard.set(serverURL, forKey: "webdav_server_url") }
    }

    @Published var username = UserDefaults.standard.string(forKey: "webdav_username") ?? "" {
        didSet { UserDefaults.standard.set(username, forKey: "webdav_username") }
    }

    @Published var password = UserDefaults.standard.string(forKey: "webdav_password") ?? "" {
        didSet { UserDefaults.standard.set(password, forKey: "webdav_password") }
    }

    @Published var profileName = UserDefaults.standard.string(forKey: "webdav_profile_name") ?? "Librera" {
        didSet { UserDefaults.standard.set(profileName, forKey: "webdav_profile_name") }
    }

    @Published var isSyncing = false
    @Published var lastSyncError: String?

    private let deviceName = "device.macOS"
    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        session = URLSession(configuration: configuration)
    }

    var isConfigured: Bool {
        guard let url = normalizedBaseURL() else {
            return false
        }
        return !username.isEmpty && !password.isEmpty && !profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !url.absoluteString.isEmpty
    }

    func syncBookmarks(
        localBookmarks: [String: [BookBookmark]],
        knownBookPaths: [String],
        completion: @escaping (Result<[String: [BookBookmark]], Error>) -> Void
    ) {
        guard let baseURL = normalizedBaseURL() else {
            completion(.failure(syncError("WebDAV URL not configured")))
            return
        }

        let trimmedProfile = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedProfile.isEmpty else {
            completion(.failure(syncError("Profile name not configured")))
            return
        }

        Task.detached(priority: .userInitiated) { [self] in
            do {
                let profileURL = baseURL.appendingPathComponent("profile.\(trimmedProfile)", isDirectory: true)
                let deviceURL = profileURL.appendingPathComponent(deviceName, isDirectory: true)
                let remoteBookmarksURL = deviceURL.appendingPathComponent("app-Bookmarks.json")

                try await ensureDirectoryExists(baseURL)
                try await ensureDirectoryExists(profileURL)
                try await ensureDirectoryExists(deviceURL)

                let remoteBookmarks = try await fetchAllRemoteBookmarks(profileURL: profileURL)
                let mergedBookmarks = mergeBookmarks(remote: remoteBookmarks, local: localBookmarks)

                try await uploadBookmarks(mergedBookmarks, to: remoteBookmarksURL)

                let resolved = resolveBookmarksForLocalLibrary(mergedBookmarks, knownBookPaths: knownBookPaths)
                await MainActor.run {
                    completion(.success(resolved))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }

    private func mergeBookmarks(remote: [BookBookmark], local: [String: [BookBookmark]]) -> [BookBookmark] {
        var mergedByTime: [Int64: BookBookmark] = [:]

        for bookmark in remote {
            mergedByTime[bookmark.t] = bookmark
        }

        for (path, bookmarks) in local {
            for var bookmark in bookmarks {
                bookmark.path = path
                mergedByTime[bookmark.t] = bookmark
            }
        }

        return mergedByTime.values.sorted { $0.t > $1.t }
    }

    private func resolveBookmarksForLocalLibrary(_ bookmarks: [BookBookmark], knownBookPaths: [String]) -> [String: [BookBookmark]] {
        let pathsByFilename = Dictionary(grouping: knownBookPaths) { path in
            URL(fileURLWithPath: path).lastPathComponent.lowercased()
        }

        var grouped: [String: [BookBookmark]] = [:]

        for var bookmark in bookmarks {
            guard let originalPath = bookmark.path else { continue }

            let fileName = URL(fileURLWithPath: originalPath).lastPathComponent.lowercased()
            guard let resolvedPath = pathsByFilename[fileName]?.first else { continue }

            bookmark.path = resolvedPath
            grouped[resolvedPath, default: []].append(bookmark)
        }

        for key in grouped.keys {
            grouped[key]?.sort { $0.t > $1.t }
        }

        return grouped
    }

    private func fetchAllRemoteBookmarks(profileURL: URL) async throws -> [BookBookmark] {
        let deviceFolders = try await listDirectory(profileURL)
        var mergedByTime: [Int64: BookBookmark] = [:]

        for item in deviceFolders where item.isCollection {
            let folderName = URL(string: item.href)?.lastPathComponent.removingPercentEncoding ?? ""
            guard folderName.hasPrefix("device.") else { continue }

            let bookmarkFileURL = profileURL
                .appendingPathComponent(folderName, isDirectory: true)
                .appendingPathComponent("app-Bookmarks.json")

            guard let data = try await downloadIfExists(bookmarkFileURL) else { continue }

            let decoded = try JSONDecoder().decode([String: AndroidBookmarkRecord].self, from: data)
            for record in decoded.values {
                let bookmark = BookBookmark(
                    path: record.path,
                    text: record.text,
                    progress: record.p,
                    isFloating: record.isF,
                    createdAt: Date(timeIntervalSince1970: TimeInterval(record.t) / 1000.0)
                )
                mergedByTime[bookmark.t] = bookmark
            }
        }

        return mergedByTime.values.sorted { $0.t > $1.t }
    }

    private func uploadBookmarks(_ bookmarks: [BookBookmark], to url: URL) async throws {
        var export: [String: AndroidBookmarkRecord] = [:]

        for bookmark in bookmarks {
            guard let path = bookmark.path else { continue }
            export[String(bookmark.t)] = AndroidBookmarkRecord(
                path: path,
                text: bookmark.text,
                p: bookmark.p,
                t: bookmark.t,
                isF: bookmark.isF
            )
        }

        let data = try JSONEncoder().encode(export)
        _ = try await sendRequest(url: url, method: "PUT", body: data, contentType: "application/json")
    }

    private func normalizedBaseURL() -> URL? {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.hasSuffix("/") ? trimmed : trimmed + "/"
        return URL(string: normalized)
    }

    private func ensureDirectoryExists(_ url: URL) async throws {
        let (_, response) = try await sendRequest(url: url, method: "PROPFIND", body: Data("<propfind xmlns=\"DAV:\"><prop><resourcetype/></prop></propfind>".utf8), depth: "0", contentType: "application/xml", acceptableStatusCodes: [200, 207, 301, 302, 401, 403, 404])

        if let http = response as? HTTPURLResponse, [200, 207, 301, 302].contains(http.statusCode) {
            return
        }

        _ = try await sendRequest(url: url, method: "MKCOL", acceptableStatusCodes: [201, 405])
    }

    private func listDirectory(_ url: URL) async throws -> [WebDAVItem] {
        let body = Data("<propfind xmlns=\"DAV:\"><prop><resourcetype/></prop></propfind>".utf8)
        let (data, _) = try await sendRequest(url: url, method: "PROPFIND", body: body, depth: "1", contentType: "application/xml", acceptableStatusCodes: [207])
        return try WebDAVDirectoryParser.parse(data: data)
    }

    private func downloadIfExists(_ url: URL) async throws -> Data? {
        do {
            let (data, _) = try await sendRequest(url: url, method: "GET", acceptableStatusCodes: [200])
            return data
        } catch let error as NSError where error.domain == "WebDAVSync" && error.code == 404 {
            return nil
        }
    }

    @discardableResult
    private func sendRequest(
        url: URL,
        method: String,
        body: Data? = nil,
        depth: String? = nil,
        contentType: String? = nil,
        acceptableStatusCodes: [Int] = [200, 201, 204, 207]
    ) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body

        if let depth {
            request.setValue(depth, forHTTPHeaderField: "Depth")
        }
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }

        let credentials = "\(username):\(password)"
        if let encoded = credentials.data(using: .utf8)?.base64EncodedString() {
            request.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw syncError("Invalid response from WebDAV server")
        }

        guard acceptableStatusCodes.contains(http.statusCode) else {
            throw NSError(
                domain: "WebDAVSync",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "WebDAV request failed (\(http.statusCode)) for \(method) \(url.absoluteString)"]
            )
        }

        return (data, response)
    }

    private func syncError(_ message: String) -> NSError {
        NSError(domain: "WebDAVSync", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

private final class WebDAVDirectoryParser: NSObject, XMLParserDelegate {
    private var items: [WebDAVItem] = []
    private var currentElement = ""
    private var currentHref = ""
    private var currentIsCollection = false
    private var insideResponse = false

    static func parse(data: Data) throws -> [WebDAVItem] {
        let parserDelegate = WebDAVDirectoryParser()
        let parser = XMLParser(data: data)
        parser.delegate = parserDelegate
        guard parser.parse() else {
            throw NSError(domain: "WebDAVSync", code: 2, userInfo: [NSLocalizedDescriptionKey: parser.parserError?.localizedDescription ?? "Failed to parse WebDAV response"])
        }
        return parserDelegate.items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName.lowercased()
        if currentElement == "response" {
            insideResponse = true
            currentHref = ""
            currentIsCollection = false
        } else if currentElement == "collection" {
            currentIsCollection = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideResponse, currentElement == "href" else { return }
        currentHref += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let lowered = elementName.lowercased()
        if lowered == "response" {
            insideResponse = false
            if !currentHref.isEmpty {
                items.append(WebDAVItem(href: currentHref.trimmingCharacters(in: .whitespacesAndNewlines), isCollection: currentIsCollection))
            }
        }
        currentElement = ""
    }
}
