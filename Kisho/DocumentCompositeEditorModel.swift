//
//  DocumentCompositeEditorModel.swift
//  Kisho
//

import Combine
import Foundation
import RichTextEditor

/// Bridges the whole document (all top-level sections and their descendants)
/// to a single editable composite, and distributes edits back to each section.
final class DocumentCompositeEditorModel: ObservableObject {
    let document: KishoDocumentModel
    let compositeContent: RichTextModel

    weak var undoManager: UndoManager?

    private var isApplyingComposite = false
    private var isDistributing = false
    private var cancellables = Set<AnyCancellable>()
    private var structureCancellables = Set<AnyCancellable>()

    private var ignoreDistributeUntil: Date?

    init(document: KishoDocumentModel) {
        self.document = document
        self.compositeContent = RichTextModel()
        rebuild()
        observeCompositeEdits()
        observeStructureChanges()
        bindStructureEdits()
    }

    func rebuild(ignoringEditsFor hold: TimeInterval = 0) {
        isApplyingComposite = true
        compositeContent.attributedString =
            KishoSection.documentCompositeAttributedString(sections: document.sections)
        isApplyingComposite = false
        if hold > 0 {
            ignoreDistributeUntil = Date().addingTimeInterval(hold)
        }
        observeStructureChanges()
    }

    /// Copies the latest editor text into each section so Split/Gather see it.
    func flushLiveEdits(from liveText: NSAttributedString? = nil) {
        if let liveText {
            isApplyingComposite = true
            compositeContent.attributedString = liveText
            isApplyingComposite = false
        }
        isDistributing = true
        KishoSection.applyDocumentComposite(compositeContent.attributedString, to: document.sections)
        isDistributing = false
    }

    private func bindStructureEdits() {
        document.liveCompositeProvider = { [weak self] in
            self?.compositeContent.attributedString ?? NSAttributedString()
        }
        document.beforeStructureEdit = { [weak self] in
            self?.flushLiveEdits()
        }
        document.afterStructureEdit = { [weak self] in
            self?.rebuild(ignoringEditsFor: 0.25)
        }
    }

    // MARK: - Private

    private func observeCompositeEdits() {
        compositeContent.$attributedString
            .dropFirst()
            .sink { [weak self] newValue in
                guard let self, !self.isApplyingComposite else { return }
                if let until = self.ignoreDistributeUntil, Date() < until { return }
                self.distribute(newValue)
            }
            .store(in: &cancellables)
    }

    /// Rebuild the composite when the document structure changes from elsewhere
    /// (Split, Gather, add/remove section, etc.) — but not from our own edits.
    private func observeStructureChanges() {
        structureCancellables.removeAll()

        document.objectWillChange
            .sink { [weak self] _ in self?.scheduleRebuildIfNeeded() }
            .store(in: &structureCancellables)

        for section in KishoSection.allSections(in: document.sections) {
            section.objectWillChange
                .sink { [weak self] _ in self?.scheduleRebuildIfNeeded() }
                .store(in: &structureCancellables)
        }
    }

    private func scheduleRebuildIfNeeded() {
        guard !isApplyingComposite, !isDistributing else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isApplyingComposite, !self.isDistributing else { return }
            self.rebuild()
        }
    }

    private func distribute(_ composite: NSAttributedString) {
        let snapshot = KishoSection.documentSnapshot(of: document.sections)

        isDistributing = true
        KishoSection.applyDocumentComposite(composite, to: document.sections)
        isDistributing = false

        undoManager?.registerUndo(withTarget: self) { target in
            target.isDistributing = true
            KishoSection.applyDocumentSnapshot(snapshot, to: target.document.sections)
            target.isDistributing = false
            target.rebuild()
        }
        undoManager?.setActionName("Edit Text")
    }
}
