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
//  merge by hand. A metadata query watches the iCloud container for the
//  life of the app, so a conflict is resolved whether or not the document
//  is open.
//

#if os(iOS)
import Foundation

final class CloudConflictResolver: NSObject {
    static let shared = CloudConflictResolver()

    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []

    /// Start watching the iCloud container for documents with unresolved
    /// conflicts. Safe to call more than once; does nothing without iCloud.
    func start() {
        guard query == nil, FileManager.default.ubiquityIdentityToken != nil else { return }
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K == YES", NSMetadataUbiquitousItemHasUnresolvedConflictsKey)
        let center = NotificationCenter.default
        for name in [NSNotification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(center.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                self?.resolveAll()
            })
        }
        self.query = query
        query.start()
    }

    private func resolveAll() {
        guard let query else { return }
        query.disableUpdates()
        let urls = (0..<query.resultCount).compactMap { index in
            (query.result(at: index) as? NSMetadataItem)?.value(forAttribute: NSMetadataItemURLKey) as? URL
        }
        query.enableUpdates()
        for url in urls {
            DispatchQueue.global(qos: .userInitiated).async {
                Self.resolveConflicts(at: url)
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
            guard let others = NSFileVersion.unresolvedConflictVersionsOfItem(at: url), !others.isEmpty,
                  let current = NSFileVersion.currentVersionOfItem(at: url) else { return }

            let candidates = [current] + others
            let winner = candidates.max { ($0.modificationDate ?? .distantPast) < ($1.modificationDate ?? .distantPast) } ?? current
            let losers = candidates.filter { $0 !== winner }

            for loser in losers {
                let copyURL = archiveURL(for: url, version: loser)
                do {
                    try FileManager.default.copyItem(at: loser.url, to: copyURL)
                    copies.append(copyURL)
                } catch {
                    // The copy is a courtesy; the version is still in the
                    // conflict history until removed below, so carry on.
                }
            }

            if winner !== current {
                _ = try? winner.replaceItem(at: url, options: [])
            }

            for version in others { version.isResolved = true }
            try? NSFileVersion.removeOtherVersionsOfItem(at: url)
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
