import SwiftUI
import AppKit
import Foundation
import CryptoKit
import UserNotifications
import UniformTypeIdentifiers

struct Manifest: Codable {
    let formatVersion: Int
    let project: String
    let version: String
    let description: String
    let files: [PatchFile]
}
struct PatchFile: Codable {
    let source: String
    let destination: String
    let sha256: String
}
enum UpdateSort: String, CaseIterable, Identifiable {
    case newest = "Newest", oldest = "Oldest", version = "Version", project = "Project"
    var id: String { rawValue }
}
struct Candidate: Identifiable {
    let id: String
    let path: URL
    let manifest: Manifest
    let projectPath: URL?
    let isSelfUpdate: Bool
}
struct Project: Identifiable, Hashable {
    let id: String
    let directory: URL
    let xcodeproj: URL
}

private extension Double {
    var roundedToTwoPlaces: Double { (self * 100).rounded() / 100 }
}
@MainActor final class Bridge: ObservableObject {
    @Published var projects: [Project] = []
    @Published var candidates: [Candidate] = []
    @Published var selected: String = ""
    @Published var log: String = "Starting local bridge…\n"
    @Published var busy = false
    @Published var buildInProgress = false
    @Published var selfUpdateInProgress = false
    @Published var scheme = ""
    @Published var buildAfterInstall = true
    @Published var showLegacy = false
    @Published var latestOnly = true
    @Published var updateSort: UpdateSort = .newest
    @Published var textScale: Double = min(1.8, max(0.75, UserDefaults.standard.double(forKey: "lub.textScale") == 0 ? 1 : UserDefaults.standard.double(forKey: "lub.textScale"))) {
        didSet { UserDefaults.standard.set(textScale, forKey: "lub.textScale") }
    }
    @Published var xcodeAvailable = false
    @Published var xcodeStatus = "Checking Xcode…"
    @Published var operationStage = "Idle"
    @Published var progress: Double = 0
    @Published var notice: String? = nil
    @Published var completionEvent = 0
    @Published var completionColor: Color = .clear
    @Published var statusHeadline: String = "Idle"
    @Published var statusTint: Color = .secondary
    @Published var rollbackSelfUpdateCandidate: URL? = nil
    @Published var selfUpdateCandidate: URL? = nil
    @Published var sourceUpdateCandidate: URL? = nil
    @Published var projectRootOverride = UserDefaults.standard.string(forKey: "lub.projectRoot") ?? ""
    @Published var destinationOverrides: [String: String] = UserDefaults.standard.dictionary(forKey: "lub.projectDestinations") as? [String: String] ?? [:]
    @Published var installedKeys: Set<String> = []
    @Published var autoScan = UserDefaults.standard.object(forKey: "lub.autoScan") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoScan, forKey: "lub.autoScan") }
    }
    @Published var extraScanFolders: [String] = UserDefaults.standard.stringArray(forKey: "lub.scanFolders") ?? []
    @Published var permissionNotice = "Auto-scan uses LUB Inbox and approved watch folders only."
    private var scopedURLs: [String: URL] = [:]
    private var scopedAccess: [String: Bool] = [:]
    @Published var lastScanDate: Date?
    @Published var approvedCandidate: Candidate?
    @Published var lastBackup: URL?
    var root: URL {
        let fallback = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/App projects")
        return projectRootOverride.isEmpty ? fallback : URL(fileURLWithPath: projectRootOverride, isDirectory: true)
    }
    // Updates default to the selected project's own folder; overrides are scoped per project.
    var selectedProject: Project? { projects.first(where: { $0.id == selected }) }
    func installDestination(for project: Project) -> URL {
        if let override = destinationOverrides[project.directory.standardizedFileURL.path], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true).standardizedFileURL
        }
        return project.directory.standardizedFileURL
    }
    var installDestination: URL? { selectedProject.map { installDestination(for: $0) } }
    var hasCustomDestination: Bool {
        guard let project = selectedProject else { return false }
        return destinationOverrides[project.directory.standardizedFileURL.path] != nil
    }
    // Staging/backups are deliberately separate from the project destination.
    var destinationRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Local Update Bridge", isDirectory: true)
    }
    func installedKey(project: String, version: String, target: URL) -> String {
        "\(project.lowercased())|\(version)|\(target.standardizedFileURL.path)"
    }
    // Self-updates are installed when the running application's bundle version matches
    // the release manifest. This survives restarts without relying on project backups.
    var runningLUBVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
    // Only genuine app backups produced by our updater are offered as rollback targets.
    func previousLUBApp(version: String) -> URL? {
        let folder = Bundle.main.bundleURL.deletingLastPathComponent()
        guard let entries = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: []) else { return nil }
        return entries.filter { url in
            guard url.lastPathComponent.hasPrefix(".Local Update Bridge-backup-"), url.pathExtension == "app",
                  let plist = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
                  plist["CFBundleIdentifier"] as? String == "org.lub.LocalUpdateBridge",
                  plist["CFBundleShortVersionString"] as? String == version else { return false }
            return fm.isExecutableFile(atPath: url.appendingPathComponent("Contents/MacOS/LocalUpdateBridge").path)
        }.sorted { a,b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da > db
        }.first
    }
    func canRollbackLUB(_ item: Candidate) -> Bool {
        item.isSelfUpdate && isOlderSelfUpdate(item) && previousLUBApp(version: item.manifest.version) != nil
    }
    func requestLUBRollback(_ item: Candidate) {
        guard canRollbackLUB(item) else {
            announce("Rollback unavailable for v\(item.manifest.version): no verified application backup exists. Download a signed release instead.")
            return
        }
        rollbackSelfUpdateCandidate = previousLUBApp(version: item.manifest.version)
    }
    func performLUBRollback() {
        guard let backup = rollbackSelfUpdateCandidate else { return }
        rollbackSelfUpdateCandidate = nil
        // This uses the same backed-up swap and restart pathway as regular self-updates.
        prepareSelfUpdate(from: backup)
        if selfUpdateCandidate != nil { installSelfUpdate() }
    }
    func isOlderSelfUpdate(_ item: Candidate) -> Bool {
        item.isSelfUpdate && item.manifest.version.compare(runningLUBVersion, options: .numeric) == .orderedAscending
    }
    func isCurrentSelfUpdate(_ item: Candidate) -> Bool {
        item.isSelfUpdate && item.manifest.version.compare(runningLUBVersion, options: .numeric) == .orderedSame
    }
    // A same-version source release can be reinstalled deliberately when recovering from a bad install.
    func requestSelfUpdate(_ item: Candidate) {
        guard item.isSelfUpdate else { return }
        if isOlderSelfUpdate(item) { requestLUBRollback(item) }
        else { prepareSourceSelfUpdate(from: item.path) }
    }
    func isInstalled(_ item: Candidate) -> Bool {
        if item.isSelfUpdate {
            return item.manifest.version.compare(runningLUBVersion, options: .numeric) == .orderedSame
        }
        guard let project = projects.first(where: { $0.directory.standardizedFileURL == item.projectPath?.standardizedFileURL }) else { return false }
        return installedKeys.contains(installedKey(project: project.id, version: item.manifest.version, target: installDestination(for: project)))
    }
    func reloadInstalledHistory() {
        var discovered = Set<String>()
        let directory = bridgeRoot.appendingPathComponent("Backups")
        if let projectDirs = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for projectDir in projectDirs {
                guard let updates = try? fm.contentsOfDirectory(at: projectDir, includingPropertiesForKeys: nil) else { continue }
                for update in updates {
                    guard let data = try? Data(contentsOf: update.appendingPathComponent("restore.json")),
                          let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          record["completed"] as? Bool == true,
                          record["rolledBack"] as? Bool != true,
                          let name = record["project"] as? String,
                          let version = record["version"] as? String,
                          let target = record["target"] as? String else { continue }
                    discovered.insert(installedKey(project: name, version: version, target: URL(fileURLWithPath: target)))
                }
            }
        }
        installedKeys = discovered
    }
    // Store user-selected folder bookmarks, rather than repeatedly walking protected folders.
    func rememberAccess(_ url: URL) {
        let key = url.standardizedFileURL.path
        do {
            let data = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            var saved = UserDefaults.standard.dictionary(forKey: "lub.folderBookmarks") as? [String: Data] ?? [:]
            saved[key] = data
            UserDefaults.standard.set(saved, forKey: "lub.folderBookmarks")
            if let old = scopedURLs.removeValue(forKey: key), scopedAccess[key] == true { old.stopAccessingSecurityScopedResource() }
            scopedURLs[key] = url
            scopedAccess[key] = url.startAccessingSecurityScopedResource()
            permissionNotice = "Folder authorized: \(url.lastPathComponent)"
        } catch {
            // NSOpenPanel still grants immediate access in non-sandboxed Developer ID builds.
            scopedURLs[key] = url
            scopedAccess[key] = false
            permissionNotice = "Using selected folder for this session. Re-select if access expires."
        }
    }
    func restoreFolderAccess() {
        let saved = UserDefaults.standard.dictionary(forKey: "lub.folderBookmarks") as? [String: Data] ?? [:]
        for (path, data) in saved {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale), !stale else {
                permissionNotice = "A folder permission expired. Use Choose Projects Folder or Add Scan Location to renew it."
                continue
            }
            scopedURLs[path] = url
            scopedAccess[path] = url.startAccessingSecurityScopedResource()
        }
    }
    func importUpdateZIP(_ url: URL) {
        guard url.pathExtension.lowercased() == "zip" else { announce("Select a ZIP update package."); return }
        let hasScope = url.startAccessingSecurityScopedResource()
        defer { if hasScope { url.stopAccessingSecurityScopedResource() } }
        do {
            try fm.createDirectory(at: updateInbox, withIntermediateDirectories: true)
            let destination = updateInbox.appendingPathComponent(url.lastPathComponent)
            let output = fm.fileExists(atPath: destination.path) ? updateInbox.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)") : destination
            try fm.copyItem(at: url, to: output)
            refresh()
            announce("Imported \(url.lastPathComponent) into LUB Inbox.")
        } catch { announce("Import failed: \(error.localizedDescription)") }
    }
    var updateInbox: URL { destinationRoot.appendingPathComponent("Inbox", isDirectory: true) }
    func setRoot(_ path: String) {
        rememberAccess(URL(fileURLWithPath: path, isDirectory: true))
        projectRootOverride = path
        UserDefaults.standard.set(path, forKey: "lub.projectRoot")
        selected = ""; refresh()
    }
    func setDestination(_ path: String) {
        guard let project = selectedProject else { announce("Select a project first."); return }
        rememberAccess(URL(fileURLWithPath: path, isDirectory: true))
        destinationOverrides[project.directory.standardizedFileURL.path] = URL(fileURLWithPath: path).standardizedFileURL.path
        UserDefaults.standard.set(destinationOverrides, forKey: "lub.projectDestinations")
    }
    func resetDestination() {
        guard let project = selectedProject else { return }
        destinationOverrides.removeValue(forKey: project.directory.standardizedFileURL.path)
        UserDefaults.standard.set(destinationOverrides, forKey: "lub.projectDestinations")
    }
    func addScanFolder(_ path: String) {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        rememberAccess(URL(fileURLWithPath: normalized, isDirectory: true))
        if !extraScanFolders.contains(normalized) {
            extraScanFolders.append(normalized)
            UserDefaults.standard.set(extraScanFolders, forKey: "lub.scanFolders")
        }
        refresh()
    }
    func removeScanFolder(_ path: String) {
        extraScanFolders.removeAll { $0 == path }
        UserDefaults.standard.set(extraScanFolders, forKey: "lub.scanFolders")
        refresh()
    }
    func updateProgress(_ stage: String, _ fraction: Double) {
        operationStage = stage; progress = min(1, max(0, fraction))
        statusHeadline = stage.uppercased()
        statusTint = .secondary
    }
    func announce(_ message: String) {
        notice = message.localizedCaseInsensitiveContains("success") || message.localizedCaseInsensitiveContains("succeeded") ? nil : message
        append(message)
    }
    func finish(_ message: String, color: Color) {
        completionColor = color
        completionEvent += 1
        statusHeadline = message.uppercased()
        statusTint = color
        announce(message)
    }
    // Matching requires an exact normalized name and an unambiguous project location.
    func detectProject(for item: Candidate? = nil) {
        let wanted = item?.manifest.project ?? candidates.first(where: { $0.manifest.project.caseInsensitiveCompare(selected) == .orderedSame })?.manifest.project
        guard let wanted, !wanted.isEmpty else { announce("Choose an update first, then detect its project folder."); return }
        let roots = [root] + extraScanFolders.compactMap { scopedURLs[URL(fileURLWithPath: $0).standardizedFileURL.path] }
        var matches: [Project] = []
        for directory in roots { matches += findMatchingProjects(in: directory, named: wanted, depth: 4) }
        let unique = Dictionary(grouping: matches, by: { $0.directory.resolvingSymlinksInPath().path }).compactMap { $0.value.first }
        guard unique.count == 1, let match = unique.first else {
            announce(unique.isEmpty ? "No project folder found for \(wanted). Choose Projects Folder or Add Scan Location." : "Multiple matching projects found for \(wanted). Select the correct folder manually; no automatic installation.")
            return
        }
        if !projects.contains(where: { $0.directory.standardizedFileURL == match.directory.standardizedFileURL }) { projects.append(match) }
        selected = match.id
        rememberAccess(match.directory)
        matchOverrides[wanted.lowercased()] = match.directory
        refresh()
        announce("Matched \(wanted) to \(match.directory.path). Review before applying any update.")
    }
    private var matchOverrides: [String: URL] = [:]
    private func findMatchingProjects(in folder: URL, named name: String, depth: Int) -> [Project] {
        guard depth >= 0, let entries = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        var result: [Project] = []
        for child in entries where (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let n = child.lastPathComponent
            if n == "node_modules" || n == ".build" || n == ".git" || n == "dist" || n == "Backups" { continue }
            if n.caseInsensitiveCompare(name) == .orderedSame {
                let xcode = (try? fm.contentsOfDirectory(at: child, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "xcodeproj" }))
                let projectFile = xcode ?? child
                result.append(Project(id: n, directory: child, xcodeproj: projectFile))
            }
            if depth > 0 { result += findMatchingProjects(in: child, named: name, depth: depth - 1) }
        }
        return result
    }
    // Updating the running app is delegated to a separate, audited launcher script.
    func prepareSelfUpdate(from replacement: URL) {
        guard !busy else { return }
        let bundle = replacement.appendingPathComponent("Contents/Info.plist")
        let executable = replacement.appendingPathComponent("Contents/MacOS/LocalUpdateBridge")
        guard replacement.pathExtension == "app", fm.isExecutableFile(atPath: executable.path),
              let info = NSDictionary(contentsOf: bundle) as? [String: Any],
              info["CFBundleIdentifier"] as? String == "org.lub.LocalUpdateBridge" else {
            announce("Self-update rejected: choose a built Local Update Bridge.app with a matching bundle identifier and executable.")
            return
        }
        guard Bundle.main.bundleURL.pathExtension == "app" else { announce("Run LUB from its installed .app bundle before self-updating."); return }
        selfUpdateCandidate = replacement
    }
    func installSelfUpdate() {
        guard let replacement = selfUpdateCandidate else { return }
        let installed = Bundle.main.bundleURL
        guard replacement.standardizedFileURL != installed.standardizedFileURL else { announce("Choose a separate replacement app bundle."); return }
        guard let script = Bundle.main.url(forResource: "lub-self-update", withExtension: "sh") else { announce("Self-update helper missing from the installed app. Rebuild LUB with vNext.4 first."); return }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [script.path, installed.path, replacement.path, String(ProcessInfo.processInfo.processIdentifier)]
        do {
            try proc.run()
            selfUpdateCandidate = nil
            selfUpdateInProgress = true
            updateProgress("Preparing self-update", 0.08)
            announce("Self-update handed to the external helper. LUB will quit and reopen if verification succeeds.")
            NSApp.terminate(nil)
        } catch { announce("Could not start self-update: \(error.localizedDescription)") }
    }
    // Self-update directly from a trusted LUB source ZIP, without manually building another app.
    func prepareSourceSelfUpdate(from archive: URL) {
        // Don't let a double-click or direct source selection reinstall the running version.
        if let version = readLUBReleaseVersion(archive) {
            let comparison = version.compare(runningLUBVersion, options: .numeric)
            guard comparison == .orderedDescending else {
                announce(comparison == .orderedSame ? "LUB v\(version) is already installed." : "LUB v\(version) is older than the running version.")
                return
            }
        }
        guard !busy, archive.pathExtension.lowercased() == "zip", fm.fileExists(atPath: archive.path) else {
            announce("Choose a local LUB source ZIP."); return
        }
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            announce("Launch LUB from its .app bundle before self-updating."); return
        }
        sourceUpdateCandidate = archive
    }
    func installSourceSelfUpdate() {
        guard let archive = sourceUpdateCandidate,
              let sourceHelper = Bundle.main.url(forResource: "lub-source-update", withExtension: "sh"),
              let installHelper = Bundle.main.url(forResource: "lub-self-update", withExtension: "sh") else {
            announce("Source updater unavailable. Build and launch the newly packaged version first."); return
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        let permanentApp = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/App projects/Update Bridge/Local Update Bridge.app")
        proc.arguments = [sourceHelper.path, Bundle.main.bundleURL.path, archive.path,
                          String(ProcessInfo.processInfo.processIdentifier), installHelper.path, permanentApp.path]
        do {
            try proc.run()
            sourceUpdateCandidate = nil
            selfUpdateInProgress = true
            updateProgress("Preparing self-update", 0.08)
            announce("LUB is preparing its own update. On failure, the existing app is kept. See ~/Library/Logs/Local Update Bridge/.")
            NSApp.terminate(nil)
        } catch { announce("Unable to start source update: \(error.localizedDescription)") }
    }
    func zoom(_ amount: Double) { textScale = min(1.8, max(0.75, (textScale + amount).roundedToTwoPlaces)) }
    func resetZoom() { textScale = 1.0 }
    func detectToolchain() {
        let (selectionStatus, selection) = run("/usr/bin/xcode-select", ["-p"])
        guard selectionStatus == 0, selection.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("Contents/Developer") else {
            xcodeAvailable = false
            xcodeStatus = "Xcode unavailable — install the complete Xcode app to build projects"
            return
        }
        let (status, version) = run("/usr/bin/xcrun", ["xcodebuild", "-version"])
        xcodeAvailable = status == 0 && version.contains("Xcode")
        xcodeStatus = xcodeAvailable ? (version.split(separator: "\n").first.map(String.init) ?? "Xcode available") : "Xcode build tools unavailable"
    }
    var visibleCandidates: [Candidate] {
        let base = candidates.filter { candidate in
            // Keep the currently installed LUB release visible even with latest-only enabled.
            if candidate.isSelfUpdate && isCurrentSelfUpdate(candidate) { return true }
            guard latestOnly else { return true }
            return !candidates.contains { other in
                other.isSelfUpdate == candidate.isSelfUpdate &&
                other.manifest.project.caseInsensitiveCompare(candidate.manifest.project) == .orderedSame &&
                other.manifest.version.compare(candidate.manifest.version, options: .numeric) == .orderedDescending
            }
        }
        return base.sorted {
            switch updateSort {
            case .newest: return ((try? $0.path.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > ((try? $1.path.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
            case .oldest: return ((try? $0.path.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) < ((try? $1.path.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
            case .version: return $0.manifest.version.compare($1.manifest.version, options: .numeric) == .orderedDescending
            case .project: return $0.manifest.project.localizedCaseInsensitiveCompare($1.manifest.project) == .orderedAscending
            }
        }
    }
    private var timer: Timer?
    private var observed = Set<String>()
    private let fm = FileManager.default

    init() {
        detectToolchain()
        restoreFolderAccess()
        try? fm.createDirectory(at: updateInbox, withIntermediateDirectories: true)
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 12, repeats: true) { [weak self] _ in
            Task { @MainActor in
                if self?.autoScan == true && self?.busy == false { self?.refresh() }
            }
        }
    }
    // Destination is LUB's staging, snapshots and log storage, NOT the target project.
    var bridgeRoot: URL { destinationRoot.appendingPathComponent("Update Bridge") }
    func append(_ line: String) { log += "[\(Date().formatted(date: .omitted, time: .standard))] \(line)\n" }
    func refresh() {
        var found: [Project] = []
        // Include the projects root itself (if it is an Xcode project) and all
        // immediate project directories, including LUB's own Update Bridge folder.
        // Previously this folder was explicitly skipped, hiding LUB from the picker.
        func includeXcodeProjects(in folder: URL) {
            guard let entries = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return }
            for xcode in entries where xcode.pathExtension == "xcodeproj" {
                let name = xcode.deletingPathExtension().lastPathComponent == "LocalUpdateBridge" ? "Local Update Bridge" : folder.lastPathComponent
                found.append(Project(id: name, directory: folder, xcodeproj: xcode))
            }
        }
        // Permission failures must not suppress inbox scanning or silently hide all projects.
        // In unsandboxed builds, previously configured project roots may remain readable
        // even when there is no persistent security-scoped bookmark.
        let projectRootIsUsable = fm.isReadableFile(atPath: root.path)
        if projectRootIsUsable { includeXcodeProjects(in: root) }
        if projectRootIsUsable, let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for folder in items where (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                includeXcodeProjects(in: folder)
            }
        }
        found += matchOverrides.values.filter { fm.isReadableFile(atPath: $0.path) }.compactMap { folder in
            let name = folder.lastPathComponent
            let xcode = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "xcodeproj" })) ?? folder
            return Project(id: name, directory: folder, xcodeproj: xcode)
        }
        projects = Array(Dictionary(grouping: found, by: { $0.directory.path }).compactMap { $0.value.first }).sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
        if !projects.contains(where: { $0.id == selected }) {
            selected = projects.first(where: { $0.id == "Local Update Bridge" })?.id ?? projects.first?.id ?? ""
        }

        var packageURLs: [URL] = []
        // Never implicitly enumerate Downloads, Desktop, Documents or private temp trees.
        // These are privacy-protected locations and can trigger recurring TCC prompts.
        let scanRoots = [updateInbox] + extraScanFolders.compactMap { path -> URL? in
            let normalized = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
            let folder = scopedURLs[normalized] ?? URL(fileURLWithPath: normalized, isDirectory: true)
            return fm.isReadableFile(atPath: folder.path) ? folder : nil
        }
        for folder in scanRoots { packageURLs += scanDirectory(folder, depth: 1) }
        if !fm.isReadableFile(atPath: root.path) {
            permissionNotice = "Projects folder is unavailable. Choose Projects Folder to grant access again; imported ZIPs remain available in the LUB Inbox."
        }
        var unique = Set<String>()
        var accepted: [Candidate] = []
        for p in packageURLs where unique.insert(p.path).inserted {
            // Native source releases are recognized separately from project-patch manifests.
            if isLUBSourceArchive(p) {
                let release = readLUBReleaseVersion(p) ?? "source"
                let m = Manifest(formatVersion: 1, project: "Local Update Bridge", version: release,
                                 description: "LUB application update — build, back up and restart", files: [])
                accepted.append(Candidate(id: p.path, path: p, manifest: m, projectPath: nil, isSelfUpdate: true))
                if observed.insert(p.path).inserted { append("Found LUB self-update v\(release)") }
                continue
            }
            if let m = readManifest(p), m.formatVersion == 1, !m.files.isEmpty {
                let matched = projects.first { $0.directory.standardizedFileURL == matchOverrides[m.project.lowercased()]?.standardizedFileURL } ?? projects.first { $0.id.caseInsensitiveCompare(m.project) == .orderedSame }
                let item = Candidate(id: p.path, path: p, manifest: m, projectPath: matched?.directory, isSelfUpdate: false)
                accepted.append(item)
                if observed.insert(p.path).inserted { append("Found update \(m.project) v\(m.version)") }
            }
        }
        candidates = accepted.sorted {
            let a = (try? $0.path.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.path.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }
        reloadInstalledHistory()
        lastScanDate = Date()
    }
    private func scanDirectory(_ dir: URL, depth: Int) -> [URL] {
        guard depth >= 0, let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        var result: [URL] = []
        for u in entries {
            let name = u.lastPathComponent.lowercased()
            // Filenames are not trusted as update identifiers: manifests are validated later.
            if name.hasSuffix(".zip") { result.append(u) }
            if depth > 0, (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { result += scanDirectory(u, depth: depth - 1) }
            if name == "bridge-manifest.json" { result.append(dir) }
        }
        return result
    }
    private func scanPreviewTree(_ dir: URL, depth: Int) -> [URL] {
        guard depth >= 0, let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        var result: [URL] = []
        for url in entries {
            let name = url.lastPathComponent
            if name.hasPrefix("codex-file-preview-") { result += scanDirectory(url, depth: 3) }
            else if depth > 0, (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                result += scanPreviewTree(url, depth: depth - 1)
            }
        }
        return result
    }
    private func isLUBSourceArchive(_ path: URL) -> Bool {
        guard path.pathExtension.lowercased() == "zip" else { return false }
        let (status, listing) = run("/usr/bin/unzip", ["-Z1", path.path])
        guard status == 0 else { return false }
        let entries = Set(listing.split(separator: "\n").map(String.init))
        // Either a flat source ZIP or one top-level project folder is supported.
        let prefixes = ["", "Update Bridge/"]
        return prefixes.contains { prefix in
            entries.contains(prefix + "LocalUpdateBridge.swift") &&
            entries.contains(prefix + "build-macos.sh") &&
            entries.contains(prefix + "lub-source-update.sh") &&
            entries.contains(prefix + "lub-self-update.sh") &&
            entries.contains(prefix + "branding/LUBIcon.iconset/icon_512x512.png")
        }
    }
    private func readLUBReleaseVersion(_ path: URL) -> String? {
        for name in ["lub-self-update.json", "Update Bridge/lub-self-update.json"] {
            let (status, output) = run("/usr/bin/unzip", ["-p", path.path, name])
            if status == 0,
               let obj = try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: String],
               obj["bundleID"] == "org.lub.LocalUpdateBridge",
               let version = obj["version"], !version.isEmpty {
                return version
            }
        }
        return nil
    }
    private func readManifest(_ path: URL) -> Manifest? {
        if path.pathExtension.lowercased() == "zip" {
            let (code, output) = run("/usr/bin/unzip", ["-p", path.path, "bridge-manifest.json"])
            guard code == 0 else { return nil }
            return try? JSONDecoder().decode(Manifest.self, from: Data(output.utf8))
        }
        return try? JSONDecoder().decode(Manifest.self, from: Data(contentsOf: path.appendingPathComponent("bridge-manifest.json")))
    }
    private func safeRelative(_ text: String) -> Bool {
        if text.isEmpty || text.hasPrefix("/") || text.contains("\\") { return false }
        return text.split(separator: "/").allSatisfy { $0 != ".." && $0 != "." && !$0.isEmpty }
    }
    nonisolated private func run(_ executable: String, _ args: [String], current: URL? = nil) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        p.currentDirectoryURL = current
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
    // Double-click performs the same reviewed, confirm-before-writing flow as the Review button.
    func openUpdate(_ item: Candidate) {
        guard !busy else { return }
        if item.isSelfUpdate { requestSelfUpdate(item); return }
        guard !isInstalled(item) else { return }
        if item.projectPath != nil { request(item) }
    }
    func request(_ item: Candidate) { approvedCandidate = item }
    func install(_ item: Candidate) {
        guard !busy else { return }
        busy = true
        updateProgress("Preparing", 0.03)
        Task { @MainActor in
            defer { busy = false; approvedCandidate = nil }
            guard let projectPath = item.projectPath,
                  let project = projects.first(where: { $0.directory == projectPath }) else {
                append("BLOCKED: Cannot match manifest project name to a discovered Xcode project."); return
            }
            let target = installDestination(for: project)
            let m = item.manifest
            guard m.project == project.id || m.project.caseInsensitiveCompare(project.id) == .orderedSame else { append("BLOCKED: project mismatch"); return }
            let staging = bridgeRoot.appendingPathComponent("Staging/\(UUID().uuidString)")
            let backup = bridgeRoot.appendingPathComponent("Backups/\(project.id)/\(m.version)-\(Int(Date().timeIntervalSince1970))")
            do {
                updateProgress("Snapshotting / staging", 0.10)
                try fm.createDirectory(at: staging, withIntermediateDirectories: true)
                try fm.createDirectory(at: backup, withIntermediateDirectories: true)
                defer { try? fm.removeItem(at: staging) }
                if item.path.pathExtension.lowercased() == "zip" {
                    let (status, listing) = run("/usr/bin/unzip", ["-Z1", item.path.path])
                    guard status == 0 else { append("BLOCKED: bad ZIP archive"); return }
                    for entry in listing.split(separator: "\n") {
                        guard safeRelative(String(entry).trimmingCharacters(in: CharacterSet(charactersIn: "/"))) else { append("BLOCKED: unsafe ZIP path"); return }
                    }
                    let (status2, extraction) = run("/usr/bin/ditto", ["-x", "-k", item.path.path, staging.path])
                    guard status2 == 0 else { append("Extraction failed: \(extraction)"); return }
                } else {
                    // Folder-based previews are staged before review/apply.
                    try fm.copyItem(at: item.path.appendingPathComponent("bridge-manifest.json"), to: staging.appendingPathComponent("bridge-manifest.json"))
                    try fm.copyItem(at: item.path.appendingPathComponent("payload"), to: staging.appendingPathComponent("payload"))
                }
                updateProgress("Validating", 0.30)
                // Validate every listed destination and SHA-256 BEFORE changing any project file.
                for f in m.files {
                    guard safeRelative(f.source), safeRelative(f.destination), f.source.hasPrefix("payload/"), f.sha256.count == 64 else { append("BLOCKED: invalid manifest paths"); return }
                    let source = staging.appendingPathComponent(f.source)
                    let dest = target.appendingPathComponent(f.destination)
                    guard !source.resolvingSymlinksInPath().path.hasPrefix(staging.path + "/") == false else { append("BLOCKED: source path escapes staging"); return }
                    guard source.isFileURL, let data = try? Data(contentsOf: source), data.count <= 20_000_000 else { append("BLOCKED: missing or oversized source \(f.source)"); return }
                    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                    guard digest.caseInsensitiveCompare(f.sha256) == .orderedSame else { append("BLOCKED: checksum mismatch for \(f.source)"); return }
                    let parent = dest.deletingLastPathComponent()
                    guard parent.resolvingSymlinksInPath().path.hasPrefix(target.resolvingSymlinksInPath().path + "/") || parent.standardizedFileURL == target.standardizedFileURL else { append("BLOCKED: destination leaves project"); return }
                    if fm.fileExists(atPath: dest.path), (try? dest.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { append("BLOCKED: destination symlink"); return }
                }
                let originalPresence = Dictionary(uniqueKeysWithValues: m.files.map {
                    ($0.destination, fm.fileExists(atPath: target.appendingPathComponent($0.destination).path))
                })
                var changed: [String] = []
                // Record the full intended mutation set before changing any project file.
                let restoreRecord: [String: Any] = [
                    "project": project.id, "version": m.version, "target": target.path,
                    "files": m.files.map { $0.destination }, "originalPresence": originalPresence,
                    "created": ISO8601DateFormatter().string(from: Date()), "completed": false
                ]
                try JSONSerialization.data(withJSONObject: restoreRecord, options: [.prettyPrinted, .sortedKeys])
                    .write(to: backup.appendingPathComponent("restore.json"), options: .atomic)
                updateProgress("Applying", 0.55)
                for (index, f) in m.files.enumerated() {
                    let dest = target.appendingPathComponent(f.destination)
                    let backupFile = backup.appendingPathComponent(f.destination)
                    if fm.fileExists(atPath: dest.path) {
                        try fm.createDirectory(at: backupFile.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try fm.copyItem(at: dest, to: backupFile)
                    }
                    let newFile = staging.appendingPathComponent(f.source)
                    try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
                    try fm.copyItem(at: newFile, to: dest)
                    changed.append(f.destination)
                    updateProgress("Applying", 0.55 + 0.25 * Double(index + 1) / Double(m.files.count))
                }
                let record: [String: Any] = ["project": project.id, "version": m.version, "target": target.path, "files": changed,
                                              "originalPresence": originalPresence, "completed": true,
                                              "created": ISO8601DateFormatter().string(from: Date())]
                let json = try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
                try json.write(to: backup.appendingPathComponent("restore.json"))
                lastBackup = backup
                reloadInstalledHistory()
                updateProgress("Applied", 0.85)
                announce("Installed \(m.version) into \(project.id), backup: \(backup.lastPathComponent)")
                if buildAfterInstall { build(project) } else { updateProgress("Complete", 1.0); finish("Update applied successfully.", color: .green) }
            } catch { announce("ERROR: \(error.localizedDescription). Inspect backup before retrying.") }
        }
    }
    // Build off the main actor so SwiftUI can keep animating the branded mark.
    func build(_ project: Project) {
        guard xcodeAvailable else { announce("Build unavailable: " + xcodeStatus); return }
        guard !buildInProgress else { return }
        buildInProgress = true
        let chosen = scheme.isEmpty ? project.xcodeproj.deletingPathExtension().lastPathComponent : scheme
        updateProgress("Building", 0.90)
        append("Building \(project.id) with scheme \(chosen)…")
        let projectPath = project.xcodeproj.path
        let logDir = bridgeRoot.appendingPathComponent("Logs")
        let filename = "\(project.id.replacingOccurrences(of: "/", with: "_"))-\(Int(Date().timeIntervalSince1970)).log"
        Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            proc.arguments = ["xcodebuild", "-project", projectPath, "-scheme", chosen,
                              "-configuration", "Debug", "-destination", "generic/platform=iOS Simulator",
                              "CODE_SIGNING_ALLOWED=NO", "build"]
            let outputFile = FileManager.default.temporaryDirectory.appendingPathComponent("lub-build-\(UUID().uuidString).log")
            FileManager.default.createFile(atPath: outputFile.path, contents: nil)
            var status: Int32 = -1
            var output = ""
            do {
                let handle = try FileHandle(forWritingTo: outputFile)
                proc.standardOutput = handle
                proc.standardError = handle
                do {
                    try proc.run()
                    proc.waitUntilExit()
                    status = proc.terminationStatus
                } catch { output = error.localizedDescription }
                try? handle.close()
                output += String(data: (try? Data(contentsOf: outputFile)) ?? Data(), encoding: .utf8) ?? ""
            } catch { output = error.localizedDescription }
            try? FileManager.default.removeItem(at: outputFile)
            try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
            try? output.write(to: logDir.appendingPathComponent(filename), atomically: true, encoding: .utf8)
            let resultStatus = status
            let resultOutput = output
            await MainActor.run {
                self.buildInProgress = false
                self.updateProgress(resultStatus == 0 ? "Complete" : "Build failed", 1.0)
                if resultStatus == 0 {
                    self.finish("BUILD SUCCESSFUL", color: .green)
                } else {
                    self.finish("BUILD FAILED", color: .red)
                    for row in resultOutput.split(separator: "\n").filter({ $0.contains("error:") }).prefix(8) {
                        self.append(String(row))
                    }
                }
                self.append("Build log: \(filename)")
            }
        }
    }
    // Package the selected macOS Xcode project's Release .app into a standalone DMG.
    // iOS/watchOS projects are intentionally not packaged as macOS installers.
    func createDMG(for project: Project) {
        let savePanel = NSSavePanel()
        savePanel.title = "Save macOS installer"
        savePanel.nameFieldStringValue = "\(project.id)-installer.dmg"
        savePanel.allowedContentTypes = [.init(filenameExtension: "dmg")!]
        savePanel.canCreateDirectories = true
        savePanel.directoryURL = project.directory.appendingPathComponent("releases", isDirectory: true)
        guard savePanel.runModal() == .OK, let chosenDMGURL = savePanel.url else { return }
        guard chosenDMGURL.pathExtension.lowercased() == "dmg" else {
            announce("Choose a .dmg destination."); return
        }
        guard xcodeAvailable else { announce("Cannot build a DMG: " + xcodeStatus); return }
        guard !busy else { return }
        guard project.xcodeproj.pathExtension == "xcodeproj" else {
            announce("DMG export currently requires an Xcode project with a macOS app target.")
            return
        }
        busy = true
        updateProgress("Building macOS Release", 0.05)
        let requestedScheme = scheme.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosenScheme = requestedScheme.isEmpty
            ? (project.xcodeproj.deletingPathExtension().lastPathComponent == "LocalUpdateBridge" ? "Local Update Bridge" : project.xcodeproj.deletingPathExtension().lastPathComponent)
            : requestedScheme
        let xcodeproj = project.xcodeproj
        let logDirectory = bridgeRoot.appendingPathComponent("Logs", isDirectory: true)
        Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            let session = fm.temporaryDirectory.appendingPathComponent("LUB-DMG-\(UUID().uuidString)", isDirectory: true)
            let derived = session.appendingPathComponent("DerivedData", isDirectory: true)
            let stage = session.appendingPathComponent("DMG", isDirectory: true)
            let outputDir = chosenDMGURL.deletingLastPathComponent()
            let logFile = logDirectory.appendingPathComponent("\(project.id)-dmg-\(Int(Date().timeIntervalSince1970)).log")
            var fullLog = ""
            defer { try? fm.removeItem(at: session) }
            do {
                try fm.createDirectory(at: derived, withIntermediateDirectories: true)
                try fm.createDirectory(at: stage, withIntermediateDirectories: true)
                try fm.createDirectory(at: outputDir, withIntermediateDirectories: true)
                try fm.createDirectory(at: logDirectory, withIntermediateDirectories: true)
                func execute(_ binary: String, _ arguments: [String]) throws {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: binary)
                    process.arguments = arguments
                    let file = session.appendingPathComponent("command-\(UUID().uuidString).log")
                    fm.createFile(atPath: file.path, contents: nil)
                    let handle = try FileHandle(forWritingTo: file)
                    process.standardOutput = handle
                    process.standardError = handle
                    defer { try? handle.close() }
                    try process.run()
                    process.waitUntilExit()
                    let data = (try? Data(contentsOf: file)) ?? Data()
                    fullLog += "\n$ \(binary) \(arguments.joined(separator: " "))\n" + (String(data: data, encoding: .utf8) ?? "")
                    guard process.terminationStatus == 0 else {
                        throw NSError(domain: "LUB.DMG", code: Int(process.terminationStatus),
                                      userInfo: [NSLocalizedDescriptionKey: "Command failed (\(process.terminationStatus)): \(URL(fileURLWithPath: binary).lastPathComponent). See build log."])
                    }
                }
                try execute("/usr/bin/xcrun", ["xcodebuild", "-project", xcodeproj.path,
                    "-scheme", chosenScheme, "-configuration", "Release", "-destination", "generic/platform=macOS",
                    "-derivedDataPath", derived.path, "build"])
                await MainActor.run { self.updateProgress("Packaging application", 0.70) }
                let appsRoot = derived.appendingPathComponent("Build/Products/Release")
                let apps = (try? fm.contentsOfDirectory(at: appsRoot, includingPropertiesForKeys: nil)) ?? []
                let appCandidates = apps.filter { $0.pathExtension == "app" &&
                    fm.fileExists(atPath: $0.appendingPathComponent("Contents/Info.plist").path) }
                guard appCandidates.count == 1, let app = appCandidates.first else {
                    throw NSError(domain: "LUB.DMG", code: 1, userInfo: [NSLocalizedDescriptionKey:
                        "Expected exactly one built macOS .app; found \(appCandidates.count). Check the Xcode scheme."])
                }
                let safeName = app.deletingPathExtension().lastPathComponent
                    .replacingOccurrences(of: "/", with: "-")
                // Respect the destination selected in the Save panel.
                let dmg = chosenDMGURL
                try execute("/usr/bin/ditto", [app.path, stage.appendingPathComponent(app.lastPathComponent).path])
                try fm.createSymbolicLink(at: stage.appendingPathComponent("Applications"), withDestinationURL: URL(fileURLWithPath: "/Applications"))
                let tempDMG = session.appendingPathComponent("output.dmg")
                await MainActor.run { self.updateProgress("Creating disk image", 0.88) }
                try execute("/usr/bin/hdiutil", ["create", "-volname", safeName, "-srcfolder", stage.path,
                    "-format", "UDZO", "-ov", tempDMG.path])
                guard let attrs = try? fm.attributesOfItem(atPath: tempDMG.path),
                      (attrs[.size] as? NSNumber)?.int64Value ?? 0 > 0 else {
                    throw NSError(domain: "LUB.DMG", code: 2, userInfo: [NSLocalizedDescriptionKey: "Created DMG is missing or empty."])
                }
                if fm.fileExists(atPath: dmg.path) {
                    _ = try fm.replaceItemAt(dmg, withItemAt: tempDMG)
                } else {
                    try fm.moveItem(at: tempDMG, to: dmg)
                }
                try fullLog.write(to: logFile, atomically: true, encoding: .utf8)
                await MainActor.run {
                    self.updateProgress("DMG complete", 1)
                    self.finish("DMG CREATED SUCCESSFULLY", color: .green)
                    self.announce("Installer: \(dmg.path)")
                    NSWorkspace.shared.activateFileViewerSelecting([dmg])
                    self.busy = false
                }
            } catch {
                try? fullLog.write(to: logFile, atomically: true, encoding: .utf8)
                await MainActor.run {
                    self.updateProgress("DMG failed", 1)
                    self.finish("DMG BUILD FAILED", color: .red)
                    self.announce("\(error.localizedDescription) Log: \(logFile.path)")
                    self.busy = false
                }
            }
        }
    }
    func rollback() {
        guard let backup = lastBackup, let data = try? Data(contentsOf: backup.appendingPathComponent("restore.json")),
              let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let targetText = record["target"] as? String, let files = record["files"] as? [String] else { append("No rollback available in current session."); return }
        let target = URL(fileURLWithPath: targetText)
        guard projects.contains(where: { installDestination(for: $0) == target.standardizedFileURL }) else { append("BLOCKED: rollback target no longer matches a configured project destination"); return }
        let originalPresence = record["originalPresence"] as? [String: Bool] ?? [:]
        // First validate the entire rollback set. Never follow symlinks out of the project.
        for path in files {
            guard safeRelative(path) else { announce("BLOCKED: unsafe rollback path \(path)"); return }
            let destination = target.appendingPathComponent(path)
            let parent = destination.deletingLastPathComponent().resolvingSymlinksInPath()
            let canonical = target.resolvingSymlinksInPath()
            guard parent.path == canonical.path || parent.path.hasPrefix(canonical.path + "/") else {
                announce("BLOCKED: rollback destination escapes project"); return
            }
            if (originalPresence[path] ?? fm.fileExists(atPath: backup.appendingPathComponent(path).path)) &&
                !fm.fileExists(atPath: backup.appendingPathComponent(path).path) {
                announce("BLOCKED: original backup missing for \(path)"); return
            }
        }
        var failures = 0
        for path in files.reversed() {
            let destination = target.appendingPathComponent(path)
            let source = backup.appendingPathComponent(path)
            do {
                if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
                if originalPresence[path] ?? fm.fileExists(atPath: source.path) {
                    try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.copyItem(at: source, to: destination)
                }
            } catch { failures += 1; append("Rollback error at \(path): \(error.localizedDescription)") }
        }
        if failures == 0 {
            var updatedRecord = record
            updatedRecord["rolledBack"] = true
            if let json = try? JSONSerialization.data(withJSONObject: updatedRecord, options: [.prettyPrinted, .sortedKeys]) {
                try? json.write(to: backup.appendingPathComponent("restore.json"), options: .atomic)
            }
            lastBackup = nil
            reloadInstalledHistory()
            finish("Rollback restored files from \(backup.lastPathComponent)", color: .green)
        }
        else { announce("Rollback incomplete: \(failures) file(s) could not be restored") }
    }
}

/// Branded dual-arrow mark; the same artwork is bundled as the macOS application icon.
struct LUBBrandMark: View {
    var body: some View {
        if let resource = Bundle.main.url(forResource: "LUBMark", withExtension: "png"),
           let picture = NSImage(contentsOf: resource) {
            Image(nsImage: picture).resizable().scaledToFit()
        } else {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .resizable().scaledToFit()
        }
    }
}

struct BridgeView: View {
    @ObservedObject var bridge: Bridge
    @State private var spinAngle: Double = 0
    @State private var pulseScale: CGFloat = 1
    @State private var pulseColor: Color = .clear
    private func completionPulse() {
        // Only one completion event is emitted per operation, never repeatForever.
        pulseColor = bridge.completionColor
        pulseScale = 1
        withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) { pulseScale = 1.18 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(290))
            withAnimation(.easeOut(duration: 0.24)) { pulseScale = 1; pulseColor = .clear }
        }
    }
    private func chooseFolder(_ completion: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { completion(url) }
    }
    private func startSpin() {
        spinAngle = 0
        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { spinAngle = 360 }
    }
    private func stopSpin() {
        // Cancel the infinite animation explicitly and restore the resting angle.
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { spinAngle = 0 }
    }
    var body: some View {
        ScrollView(.vertical) {
          VStack(alignment: .leading, spacing: 14) {
            HStack {
                LUBBrandMark()
                    .frame(width: 32, height: 32)
                    .rotationEffect(.degrees(spinAngle))
                    .scaleEffect(pulseScale)
                    .background(Circle().fill(pulseColor.opacity(0.25)).padding(-5))
                    .onAppear { if bridge.busy || bridge.buildInProgress || bridge.selfUpdateInProgress { startSpin() } }
                    .onChange(of: bridge.busy || bridge.buildInProgress || bridge.selfUpdateInProgress) { _, active in
                        if active { startSpin() }
                        else { stopSpin() }
                    }
                    .onChange(of: bridge.completionEvent) { _, _ in completionPulse() }
                Text("Local Update Bridge").font(.system(size: 21 * bridge.textScale, weight: .bold))
                Spacer()
                Button("Scan Now") { bridge.refresh() }
                    .frame(width: 100)
            }
            Text("\(bridge.projects.count) projects  •  \(bridge.candidates.count) recognized updates  •  Scanning watched folders")
                .font(.system(size: 12 * bridge.textScale))
                .foregroundStyle(.secondary)
            HStack {
                Picker("Project", selection: $bridge.selected) {
                    ForEach(bridge.projects) { project in Text(project.id).tag(project.id) }
                }
                Button("Detect Matching Project") {
                    if let chosen = bridge.visibleCandidates.first(where: { $0.manifest.project.caseInsensitiveCompare(bridge.selected) == .orderedSame }) {
                        bridge.detectProject(for: chosen)
                    } else { bridge.announce("Select Detect Project beside the update to search for its matching folder.") }
                }.help("Use Detect Project beside an update if its project isn't already listed")
                Button("Open in Xcode") {
                    if let project = bridge.selectedProject { NSWorkspace.shared.open(project.xcodeproj) }
                }.disabled(bridge.selectedProject == nil)
                Button("Convert to DMG") {
                    if let project = bridge.selectedProject { bridge.createDMG(for: project) }
                }
                .frame(width: 145)
                .disabled(bridge.selectedProject == nil || bridge.busy || !bridge.xcodeAvailable)
                .help("Build the selected macOS app and export a DMG to the project's releases folder")
            }
            HStack {
                TextField("Optional build scheme", text: $bridge.scheme).textFieldStyle(.roundedBorder)
                Toggle("Build after install", isOn: $bridge.buildAfterInstall)
                    .disabled(!bridge.xcodeAvailable)
            }
            HStack(spacing: 8) {
                Image(systemName: bridge.xcodeAvailable ? "checkmark.circle.fill" : "info.circle")
                    .foregroundStyle(bridge.xcodeAvailable ? Color.green : Color.orange)
                Text(bridge.xcodeStatus)
                Spacer()
                Button("Recheck Xcode") { bridge.detectToolchain() }
            }
            HStack {
                Text("Available updates").font(.system(size: 17 * bridge.textScale, weight: .semibold))
                Spacer()
                Picker("Sort", selection: $bridge.updateSort) {
                    ForEach(UpdateSort.allCases) { sort in Text(sort.rawValue).tag(sort) }
                }.frame(width: 165)
                Toggle("Latest only", isOn: $bridge.latestOnly).toggleStyle(.checkbox)
                    .frame(width: 120, alignment: .trailing)
            }
            if bridge.visibleCandidates.isEmpty {
                Text("No matching manifest-enabled updates found. Use Add Scan Location to watch another folder.")
                    .foregroundStyle(.secondary)
            } else {
                List(bridge.visibleCandidates) { candidate in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading) {
                            Text("\(candidate.manifest.project) v\(candidate.manifest.version)").bold()
                            Text(candidate.manifest.description).font(.system(size: 12 * bridge.textScale)).lineLimit(2)
                            Text(candidate.path.path).font(.system(size: 10 * bridge.textScale)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(-1)
                        Spacer(minLength: 8)
                        if candidate.isSelfUpdate {
                            if bridge.isCurrentSelfUpdate(candidate) {
                                Text("Current Version")
                                    .font(.system(size: 12 * bridge.textScale, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 9).padding(.vertical, 4)
                                    .background(.gray.opacity(0.14), in: Capsule())
                                Button("Reapply Update") { bridge.requestSelfUpdate(candidate) }
                                    .disabled(bridge.busy)
                                    .help("Rebuild and reinstall the same LUB version after confirmation")
                            } else if bridge.isOlderSelfUpdate(candidate) {
                                Text(bridge.canRollbackLUB(candidate) ? "Previously installed" : "Older version")
                                    .font(.system(size: 12 * bridge.textScale, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 9).padding(.vertical, 4)
                                    .background(.gray.opacity(0.14), in: Capsule())
                                if bridge.canRollbackLUB(candidate) {
                                    Button("Roll Back…") { bridge.requestLUBRollback(candidate) }
                                        .disabled(bridge.busy)
                                }
                            } else {
                                Button("Update LUB") { bridge.requestSelfUpdate(candidate) }
                                    .disabled(bridge.busy)
                            }
                        } else {
                            if bridge.isInstalled(candidate) {
                                Text("Installed")
                                    .font(.system(size: 12 * bridge.textScale, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 9).padding(.vertical, 4)
                                    .background(.gray.opacity(0.14), in: Capsule())
                            }
                            if candidate.projectPath == nil {
                                Button("Detect Project") { bridge.detectProject(for: candidate) }
                                    .disabled(bridge.busy)
                            }
                        }
                        if !candidate.isSelfUpdate {
                            Button("Review") { bridge.request(candidate) }
                                .disabled(candidate.projectPath == nil || bridge.busy || bridge.isInstalled(candidate))
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { bridge.openUpdate(candidate) }
                    .help(candidate.isSelfUpdate && bridge.isCurrentSelfUpdate(candidate) ? "Double-click to reapply this release after confirmation" : (candidate.isSelfUpdate && bridge.isOlderSelfUpdate(candidate) ? "Double-click to offer rollback when a verified backup exists" : "Double-click to review and install this update"))
                    .frame(minHeight: 48)
                    .opacity((bridge.isInstalled(candidate) || bridge.isOlderSelfUpdate(candidate)) ? 0.60 : 1)
                }.frame(height: 230)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(bridge.operationStage)
                        .lineLimit(1)
                    Spacer(minLength: 12)
                    Text("\(Int(bridge.progress * 100))%")
                        .monospacedDigit()
                        .frame(width: 52, alignment: .trailing)
                }
                .font(.system(size: 12 * bridge.textScale))
                ProgressView(value: bridge.progress)
            }
            .frame(height: 37)
            .opacity(bridge.busy || bridge.progress > 0 ? 1 : 0)
            .accessibilityHidden(!(bridge.busy || bridge.progress > 0))
            HStack(spacing: 8) {
                Text("Status")
                    .font(.system(size: 12 * bridge.textScale))
                    .foregroundStyle(.secondary)
                Text(bridge.statusHeadline)
                    .font(.system(size: 13 * bridge.textScale, weight: .bold))
                    .foregroundStyle(bridge.statusTint)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
            }
            HStack {
                Text("Activity").font(.system(size: 17 * bridge.textScale, weight: .semibold))
                Spacer()
                Button("Roll Back Last Update") { bridge.rollback() }.disabled(bridge.lastBackup == nil || bridge.busy)
            }
            ScrollView { Text(bridge.log).font(.system(size: 11 * bridge.textScale, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                .frame(height: 180).padding(8).background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 7) {
                Text("Folder Configuration").font(.system(size: 17 * bridge.textScale, weight: .semibold))
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Projects location").font(.system(size: 15 * bridge.textScale, weight: .bold))
                        Text("Where your existing development projects live. Updates modify a reviewed project here.")
                            .font(.system(size: 12 * bridge.textScale)).foregroundStyle(.secondary)
                        Text(bridge.root.path).font(.system(size: 10 * bridge.textScale)).textSelection(.enabled).lineLimit(1)
                    }
                    Spacer()
                    Button("Choose Projects Folder…") { chooseFolder { bridge.setRoot($0.path) } }
                }
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Update destination (selected project)").font(.system(size: 15 * bridge.textScale, weight: .bold))
                        Text("Defaults to the selected project's folder. Choose another folder only when needed.")
                            .font(.system(size: 12 * bridge.textScale)).foregroundStyle(.secondary)
                        Text(bridge.installDestination?.path ?? "Select a project above")
                            .font(.system(size: 10 * bridge.textScale)).textSelection(.enabled).lineLimit(2)
                        if bridge.hasCustomDestination {
                            Text("Custom destination").font(.system(size: 10 * bridge.textScale)).foregroundStyle(.orange)
                        } else {
                            Text("Using selected project folder").font(.system(size: 10 * bridge.textScale)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if bridge.hasCustomDestination {
                        Button("Use Project Folder") { bridge.resetDestination() }
                    }
                    Button("Change Destination…") { chooseFolder { bridge.setDestination($0.path) } }
                        .disabled(bridge.selectedProject == nil)
                }
                Text("LUB backups and temporary staging are kept separately in Application Support.")
                    .font(.system(size: 10 * bridge.textScale)).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Toggle("Automatically scan for updates", isOn: $bridge.autoScan).toggleStyle(.checkbox)
                Spacer()
                Button("Add Scan Location…") { chooseFolder { bridge.addScanFolder($0.path) } }
                Button("Open LUB Inbox") { 
                    try? FileManager.default.createDirectory(at: bridge.updateInbox, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(bridge.updateInbox)
                }
                Button("Import ZIP…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.zip]
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = false
                    if panel.runModal() == .OK, let url = panel.url { bridge.importUpdateZIP(url) }
                }
                Button("Scan Now") { bridge.refresh() }.disabled(bridge.busy)
            }
            if !bridge.permissionNotice.isEmpty {
                Text(bridge.permissionNotice).font(.system(size: 11 * bridge.textScale)).foregroundStyle(.secondary)
            }
            Text("Auto-scan: LUB Inbox + folders you explicitly approved. Use Import ZIP for downloads.")
                .font(.system(size: 11 * bridge.textScale)).foregroundStyle(.secondary)
            if !bridge.extraScanFolders.isEmpty {
                HStack {
                    Text("Additional watched folders:").font(.system(size: 12 * bridge.textScale)).foregroundStyle(.secondary)
                    ForEach(bridge.extraScanFolders, id: \.self) { folder in
                        Button("Remove \(URL(fileURLWithPath: folder).lastPathComponent)") { bridge.removeScanFolder(folder) }
                            .help(folder)
                    }
                }
            }
            if let last = bridge.lastScanDate {
                Text("Last scan: \(last.formatted(date: .abbreviated, time: .standard)) • Showing newest available updates first")
                    .font(.system(size: 10 * bridge.textScale)).foregroundStyle(.secondary)
            }
            HStack {
                Button("Update LUB from Source ZIP…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.zip]
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = false
                    panel.message = "Select a trusted LUB source release ZIP. LUB will compile and install it automatically after your confirmation."
                    if panel.runModal() == .OK, let url = panel.url { bridge.prepareSourceSelfUpdate(from: url) }
                }.disabled(bridge.busy)
                Button("Self-Update LUB…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.applicationBundle]
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = false
                    panel.message = "Choose a trusted, newly built Local Update Bridge.app. The running app will be backed up before replacement."
                    if panel.runModal() == .OK, let url = panel.url { bridge.prepareSelfUpdate(from: url) }
                }.disabled(bridge.busy)
                Spacer()
                Button("Open Bridge Folder") { NSWorkspace.shared.open(bridge.bridgeRoot) }
                Spacer()
                Text("Manual approval required • No Codex usage").font(.system(size: 12 * bridge.textScale)).foregroundStyle(.secondary)
                Text("LUB v" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")).font(.system(size: 12 * bridge.textScale)).foregroundStyle(.secondary)
            }
          }
          .font(.system(size: 13 * bridge.textScale))
          .padding(20)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .topTrailing) {
            if let notice = bridge.notice {
                Text(notice)
                    .font(.system(size: 12 * bridge.textScale))
                    .lineLimit(3)
                    .frame(maxWidth: 320, alignment: .leading)
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding(10)
                    .onTapGesture { bridge.notice = nil }
            }
        }
        .frame(minWidth: 760, idealWidth: 1040, minHeight: 570, idealHeight: 820)
        .alert("Restore previous LUB version?", isPresented: Binding(get: { bridge.rollbackSelfUpdateCandidate != nil }, set: { if !$0 { bridge.rollbackSelfUpdateCandidate = nil } })) {
            Button("Cancel", role: .cancel) { bridge.rollbackSelfUpdateCandidate = nil }
            Button("Restore Backup and Restart") { bridge.performLUBRollback() }
        } message: {
            Text("Restore the previously installed app from the verified backup. The running LUB app will close and should relaunch in the selected version. This changes the app bundle, not your Xcode source directory.")
        }
        .alert("Build and install LUB source update?", isPresented: Binding(get: { bridge.sourceUpdateCandidate != nil }, set: { if !$0 { bridge.sourceUpdateCandidate = nil } })) {
            Button("Cancel", role: .cancel) { bridge.sourceUpdateCandidate = nil }
            Button("Build, Back Up and Restart") { bridge.installSourceSelfUpdate() }
        } message: {
            Text("This also allows reapplying the current version for recovery. Only continue with a LUB source ZIP you trust. Its Swift code will be compiled, the current app backed up, and the replacement installed by an external helper. On build failure, the installed app is not replaced. Logs are saved in ~/Library/Logs/Local Update Bridge/.")
        }
        .alert("Confirm LUB self-update", isPresented: Binding(get: { bridge.selfUpdateCandidate != nil }, set: { if !$0 { bridge.selfUpdateCandidate = nil } })) {
            Button("Cancel", role: .cancel) { bridge.selfUpdateCandidate = nil }
            Button("Back Up, Replace and Restart") { bridge.installSelfUpdate() }
        } message: {
            Text("LUB will quit, back up the installed app, verify and replace it, then relaunch. Only use a trusted build. If replacement fails, the helper restores the previous application.")
        }
        .alert("Review project update", isPresented: Binding(get: { bridge.approvedCandidate != nil }, set: { if !$0 { bridge.approvedCandidate = nil } })) {
            Button("Cancel", role: .cancel) { bridge.approvedCandidate = nil }
            Button("Apply to project") { if let c = bridge.approvedCandidate { bridge.install(c) } }
        } message: {
            if let c = bridge.approvedCandidate {
                Text("\(c.manifest.project) v\(c.manifest.version)\n\(c.manifest.files.count) files will be replaced or added. Project: \(c.projectPath?.path ?? "unmatched")\nA backup will be created. Apply only updates you trust.")
            }
        }
    }
}

@main struct LocalUpdateBridgeApp: App {
    @StateObject private var bridge = Bridge()

    var body: some Scene {
        WindowGroup("Local Update Bridge", id: "dashboard") {
            BridgeView(bridge: bridge)
        }
        .defaultSize(width: 1060, height: 860)
        .commands {
            CommandGroup(after: .textEditing) {
                Button("Increase Text Size") { bridge.zoom(0.1) }.keyboardShortcut("+", modifiers: [.command])
                Button("Decrease Text Size") { bridge.zoom(-0.1) }.keyboardShortcut("-", modifiers: [.command])
                Button("Reset Text Size") { bridge.resetZoom() }.keyboardShortcut("0", modifiers: [.command])
            }
            CommandGroup(replacing: .newItem) {
                Button("Scan for Updates") { bridge.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }

        MenuBarExtra("Update Bridge", systemImage: "arrow.triangle.2.circlepath.circle.fill") {
            BridgeMenu(bridge: bridge)
        }
    }
}

struct BridgeMenu: View {
    @ObservedObject var bridge: Bridge
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Bridge Dashboard") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "dashboard")
        }
        Button("Scan for Updates") { bridge.refresh() }
        Divider()
        Text("\(bridge.projects.count) projects · \(bridge.candidates.count) updates")
        Divider()
        Button("Quit Update Bridge") { NSApp.terminate(nil) }
    }
}
