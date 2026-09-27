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

    /// Called synchronously whenever the composite is rebuilt from the model
    /// (which resets the text view), so the view can ignore the resulting
    /// selection change.
    var onRebuild: (() -> Void)?

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
        onRebuild?()
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

    /// Rebuild the composite when the document *structure* changes from
    /// elsewhere (add/remove/move, undo, typography) — but not from our own
    /// edits, and not for selection or tag changes, which don't affect the
    /// text. Every rebuild resets the text view, so this is kept narrow.
    private func observeStructureChanges() {
        structureCancellables.removeAll()

        document.$sections
            .dropFirst()
            .sink { [weak self] _ in self?.scheduleRebuildIfNeeded() }
            .store(in: &structureCancellables)

        for section in KishoSection.allSections(in: document.sections) {
            section.$children
                .dropFirst()
                .sink { [weak self] _ in self?.scheduleRebuildIfNeeded() }
                .store(in: &structureCancellables)
            section.$title
                .dropFirst()
                .sink { [weak self] _ in self?.scheduleRebuildIfNeeded() }
                .store(in: &structureCancellables)
            section.$inspectorVersion
                .dropFirst()
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
        let before = KishoSection.documentSnapshot(of: document.sections)

        isDistributing = true
        KishoSection.applyDocumentComposite(composite, to: document.sections)
        isDistributing = false

        let after = KishoSection.documentSnapshot(of: document.sections)
        registerTextUndo(undoManager, restore: before, reapply: after)
    }

    /// Undo restores `restore`; undoing that restores `reapply` (redo), and so on.
    private func registerTextUndo(_ undoManager: UndoManager?, restore: SubtreeSnapshot, reapply: SubtreeSnapshot) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { [weak undoManager] target in
            target.isDistributing = true
            KishoSection.applyDocumentSnapshot(restore, to: target.document.sections)
            target.isDistributing = false
            target.rebuild(ignoringEditsFor: 0.25)
            target.registerTextUndo(undoManager, restore: reapply, reapply: restore)
        }
        undoManager.setActionName("Edit Text")
    }
}
