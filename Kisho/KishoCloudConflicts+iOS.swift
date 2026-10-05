//
//  KishoCloudConflicts+iOS.swift
//  Kisho
//
//  iCloud conflict resolution on iOS. The Mac's NSDocument shows a sheet
//  when a document has been edited on two devices while one was offline;
//  SwiftUI's DocumentGroup on iOS shows nothing, and will not open the
//  file until something resolves the conflict. This resolves it the way
//  the plan accepted — the most recently saved version wins — and keeps
//  every other version beside the document as "<name> (conflicted copy
//  from <device> <date>).kisho", so nothing is lost and the writer can
//  merge by hand. Two triggers: a metadata query that watches the iCloud
//  container for the life of the app, and a direct scan of the container
//  whenever the app comes to the foreground. Everything is logged under
//  subsystem com.PM.Kisho, category iCloud (Xcode console / Console.app).
//

#if os(iOS)
import Foundation
import UIKit
import OSLog

final class CloudConflictResolver: NSObject {
    static let shared = CloudConflictResolver()
    private static let log = Logger(subsystem: "com.PM.Kisho", category: "iCloud")

    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private let work = DispatchQueue(label: "com.PM.Kisho.iCloudConflicts", qos: .userInitiated)

    /// Start watching the iCloud container for documents with unresolved
    /// conflicts. Safe to call more than once; does nothing without iCloud.
    func start() {
        guard query == nil else { return }
        guard FileManager.default.ubiquityIdentityToken != nil else {
            Self.log.notice("No iCloud identity; conflict resolver not started")
            return
        }
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K == YES", NSMetadataUbiquitousItemHasUnresolvedConflictsKey)
        let center = NotificationCenter.default
        for name in [NSNotification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(center.addObserver(forName: name, object: query, queue: .main) { [weak self] note in
                Self.log.notice("Metadata query \(note.name.rawValue, privacy: .public)")
                self?.resolveQueryResults()
            })
        }
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.scanContainer()
        })
        self.query = query
        let started = query.start()
        Self.log.notice("Conflict resolver started; query running: \(started)")
        scanContainer()
    }

    private func resolveQueryResults() {
        guard let query else { return }
        query.disableUpdates()
        let urls = (0..<query.resultCount).compactMap { index in
            (query.result(at: index) as? NSMetadataItem)?.value(forAttribute: NSMetadataItemURLKey) as? URL
        }
        query.enableUpdates()
        Self.log.notice("Query reports \(urls.count) document(s) in conflict")
        for url in urls {
            work.async { Self.resolveConflicts(at: url) }
        }
    }

    /// Walk the container's Documents folder and resolve anything in conflict
    /// (belt and braces for the query, and the source of the diagnostic log).
    func scanContainer() {
        work.async {
            guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
                Self.log.notice("Scan: no ubiquity container URL")
                return
            }
            let documents = container.appendingPathComponent("Documents", isDirectory: true)
            let keys: [URLResourceKey] = [.ubiquitousItemHasUnresolvedConflictsKey, .ubiquitousItemDownloadingStatusKey,
                                          .ubiquitousItemIsUploadingKey, .ubiquitousItemIsDownloadingKey, .isDirectoryKey]
            guard let items = try? FileManager.default.contentsOfDirectory(at: documents, includingPropertiesForKeys: keys,
                                                                          options: [.skipsHiddenFiles]) else {
                Self.log.notice("Scan: cannot list \(documents.path, privacy: .public)")
                return
            }
            Self.log.notice("Scan: \(items.count) item(s) in \(documents.path, privacy: .public)")
            for url in items {
                let values = try? url.resourceValues(forKeys: Set(keys))
                let unresolved = NSFileVersion.unresolvedConflictVersionsOfItem(at: url)?.count ?? 0
                let others = NSFileVersion.otherVersionsOfItem(at: url)?.count ?? 0
                let download = values?.ubiquitousItemDownloadingStatus?.rawValue ?? "?"
                Self.log.notice("\(url.lastPathComponent, privacy: .public): hasUnresolvedConflicts=\(values?.ubiquitousItemHasUnresolvedConflicts ?? false) unresolvedVersions=\(unresolved) otherVersions=\(others) download=\(download, privacy: .public) uploading=\(values?.ubiquitousItemIsUploading ?? false) downloading=\(values?.ubiquitousItemIsDownloading ?? false)")
                if unresolved > 0 || values?.ubiquitousItemHasUnresolvedConflicts == true {
                    Self.resolveConflicts(at: url)
                }
            }
        }
    }

    /// Resolve the conflict on one document: the newest version becomes the
    /// document, every other version is copied beside it, then the extra
    /// versions are marked resolved and removed. Returns the URLs of the
    /// copies it made.
    @discardableResult
    static func resolveConflicts(at url: URL) -> [URL] {
        var copies: [URL] = []
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        coordinator.coordinate(writingItemAt: url, options: .contentIndependentMetadataOnly, error: &coordinationError) { url in
            guard let others = NSFileVersion.unresolvedConflictVersionsOfItem(at: url), !others.isEmpty else {
                log.notice("Resolve \(url.lastPathComponent, privacy: .public): no unresolved versions inside coordination")
                return
            }
            guard let current = NSFileVersion.currentVersionOfItem(at: url) else {
                log.error("Resolve \(url.lastPathComponent, privacy: .public): no current version")
                return
            }

            let candidates = [current] + others
            let winner = candidates.max { ($0.modificationDate ?? .distantPast) < ($1.modificationDate ?? .distantPast) } ?? current
            let losers = candidates.filter { $0 !== winner }
            log.notice("Resolve \(url.lastPathComponent, privacy: .public): \(others.count) conflict version(s); winner from \(winner.localizedNameOfSavingComputer ?? "?", privacy: .public) at \(winner.modificationDate?.description ?? "?", privacy: .public); current wins: \(winner === current)")

            for loser in losers {
                let copyURL = archiveURL(for: url, version: loser)
                do {
                    try FileManager.default.copyItem(at: loser.url, to: copyURL)
                    copies.append(copyURL)
                    log.notice("Kept copy \(copyURL.lastPathComponent, privacy: .public)")
                } catch {
                    log.error("Copy failed for \(copyURL.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }

            if winner !== current {
                do {
                    _ = try winner.replaceItem(at: url, options: [])
                } catch {
                    log.error("Replace failed: \(error.localizedDescription, privacy: .public)")
                }
            }

            for version in others { version.isResolved = true }
            do {
                try NSFileVersion.removeOtherVersionsOfItem(at: url)
                log.notice("Resolved \(url.lastPathComponent, privacy: .public)")
            } catch {
                log.error("removeOtherVersions failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        if let coordinationError {
            log.error("Coordination failed for \(url.lastPathComponent, privacy: .public): \(coordinationError.localizedDescription, privacy: .public)")
        }
        return copies
    }

    /// "<name> (conflicted copy from <device> <date>).<ext>", numbered if taken.
    static func archiveURL(for url: URL, version: NSFileVersion) -> URL {
        let folder = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let device = version.localizedNameOfSavingComputer ?? "another device"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        let date = formatter.string(from: version.modificationDate ?? Date())
        let stem = "\(base) (conflicted copy from \(device) \(date))"
        var candidate = folder.appendingPathComponent(stem).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(stem) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }
}
#endif
