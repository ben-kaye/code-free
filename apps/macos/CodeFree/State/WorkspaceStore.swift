import AppKit
import Foundation

/// Shell-owned project/workspace bookmark. Orch only stores session `cwd`.
struct Workspace: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var path: String
    var name: String
    var lastUsedAt: Date

    var displayName: String {
        if !name.isEmpty { return name }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    var shortPath: String {
        Self.displayPath(path)
    }

    /// Tilde-abbreviate under the home directory only at a path boundary
    /// (`/Users/ben` must not match `/Users/benedict`).
    static func displayPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home {
            return "~"
        }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    static func normalizePath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    static func make(path: String, name: String? = nil) -> Workspace {
        let normalized = normalizePath(path)
        let folder = URL(fileURLWithPath: normalized).lastPathComponent
        return Workspace(
            id: UUID().uuidString,
            path: normalized,
            name: name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? folder,
            lastUsedAt: Date()
        )
    }
}

/// Persists workspaces under Application Support. Design: display name / recents / bookmarks are shell.
@MainActor
final class WorkspaceStore: ObservableObject {
    @Published private(set) var workspaces: [Workspace] = []
    @Published var selectedId: String?
    /// Normalized paths the user closed from Projects; not re-added by session bootstrap.
    @Published private(set) var closedPaths: Set<String> = []
    /// Set when an existing workspaces.json could not be decoded; surfaced by AppModel.
    @Published private(set) var loadError: String?

    private let fileURL: URL
    /// After a failed load, do not overwrite the on-disk file until the user mutates intentionally.
    private var suppressSave = false
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    var selected: Workspace? {
        guard let selectedId else { return nil }
        return workspaces.first { $0.id == selectedId }
    }

    func isClosed(_ path: String) -> Bool {
        closedPaths.contains(Workspace.normalizePath(path))
    }

    init(appSupport: URL? = nil) {
        let root: URL
        if let appSupport {
            root = appSupport
        } else if let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            root = base.appendingPathComponent("code-free", isDirectory: true)
        } else {
            root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("code-free", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        fileURL = root.appendingPathComponent("workspaces.json")
        load()
    }

    // MARK: - Mutations

    @discardableResult
    func add(path: String, name: String? = nil, select: Bool = true) -> Workspace {
        clearLoadFailure()
        let normalized = Workspace.normalizePath(path)
        // Re-opening a closed project (New project / pick folder).
        if closedPaths.contains(normalized) {
            closedPaths.remove(normalized)
        }
        if let existing = workspaces.first(where: { Workspace.normalizePath($0.path) == normalized }) {
            if select {
                selectAndTouch(existing.id)
            } else {
                touch(existing.id)
            }
            return existing
        }
        let ws = Workspace.make(path: normalized, name: name)
        workspaces.insert(ws, at: 0)
        if select { selectedId = ws.id }
        save()
        return ws
    }

    func remove(id: String) {
        guard let ws = workspaces.first(where: { $0.id == id }) else { return }
        close(path: ws.path)
    }

    /// Close a project: hide from Projects and drop the bookmark. Sessions stay in Recents.
    func close(path: String) {
        clearLoadFailure()
        let key = Workspace.normalizePath(path)
        guard !key.isEmpty else { return }
        closedPaths.insert(key)
        let removedId = workspaces.first(where: { Workspace.normalizePath($0.path) == key })?.id
        workspaces.removeAll { Workspace.normalizePath($0.path) == key }
        if let removedId, selectedId == removedId {
            selectedId = workspaces.first?.id
        }
        save()
    }

    /// Bump recency and move to front of the list. Does not change `selectedId`.
    func touch(_ id: String) {
        guard let idx = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces[idx].lastUsedAt = Date()
        let item = workspaces.remove(at: idx)
        workspaces.insert(item, at: 0)
        save()
    }

    /// Update selection only — does not reorder Projects (session switch).
    func select(_ id: String?) {
        selectedId = id
        save()
    }

    /// Selection + recency for explicit workspace use (home menu, pick folder).
    func selectAndTouch(_ id: String) {
        selectedId = id
        touch(id)
    }

    /// Prefer known selection; otherwise most-recent workspace.
    func ensureSelection() {
        if let selectedId, workspaces.contains(where: { $0.id == selectedId }) { return }
        selectedId = workspaces.first?.id
    }

    /// Register cwd from a session without changing selection order aggressively.
    /// Does not clear a load failure — bootstrap must not overwrite a corrupt file.
    /// Skips paths the user closed so projects stay closed across launches.
    func rememberPath(_ path: String) {
        let normalized = Workspace.normalizePath(path)
        guard !normalized.isEmpty else { return }
        if closedPaths.contains(normalized) { return }
        if workspaces.contains(where: { Workspace.normalizePath($0.path) == normalized }) {
            return
        }
        workspaces.append(Workspace.make(path: normalized))
        workspaces.sort { $0.lastUsedAt > $1.lastUsedAt }
        save()
    }

    // MARK: - Folder picker

    /// Modal folder picker. Returns chosen path or nil if cancelled.
    func pickFolder(startingAt path: String? = nil) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select"
        panel.message = "Choose a workspace folder for this task"
        if let path {
            panel.directoryURL = URL(fileURLWithPath: path)
        } else if let selected {
            panel.directoryURL = URL(fileURLWithPath: selected.path)
        } else {
            panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }

    @discardableResult
    func pickAndAdd() -> Workspace? {
        guard let path = pickFolder() else { return nil }
        return add(path: path, select: true)
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            workspaces = []
            closedPaths = []
            loadError = nil
            suppressSave = false
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let file = try decoder.decode(WorkspaceFile.self, from: data)
            workspaces = file.workspaces.sorted { $0.lastUsedAt > $1.lastUsedAt }
            closedPaths = Set((file.closedPaths ?? []).map(Workspace.normalizePath))
            if let id = file.selectedId, workspaces.contains(where: { $0.id == id }) {
                selectedId = id
            } else {
                selectedId = workspaces.first?.id
            }
            loadError = nil
            suppressSave = false
        } catch {
            // Keep empty in-memory state but do not write over the file until the user
            // explicitly adds/removes a workspace (see clearLoadFailure / suppressSave).
            workspaces = []
            closedPaths = []
            selectedId = nil
            suppressSave = true
            loadError = "Could not load workspaces: \(error.localizedDescription)"
            NSLog("WorkspaceStore load failed: \(error.localizedDescription)")
        }
    }

    private func clearLoadFailure() {
        guard suppressSave || loadError != nil else { return }
        suppressSave = false
        loadError = nil
    }

    private func save() {
        guard !suppressSave else {
            NSLog("WorkspaceStore save suppressed after load failure")
            return
        }
        let file = WorkspaceFile(
            workspaces: workspaces,
            selectedId: selectedId,
            closedPaths: closedPaths.sorted()
        )
        do {
            let data = try encoder.encode(file)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // Shell metadata only — surface via console; not critical path
            NSLog("WorkspaceStore save failed: \(error.localizedDescription)")
        }
    }
}

private struct WorkspaceFile: Codable {
    var workspaces: [Workspace]
    var selectedId: String?
    /// Optional for backward compatibility with older workspaces.json files.
    var closedPaths: [String]?
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
