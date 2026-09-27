//
//  SectionSubtreeEditorModel.swift
//  Kisho
//

import Combine
import Foundation
import RichTextEditor

final class SectionSubtreeEditorModel: ObservableObject {
    private(set) var root: KishoSection
    let compositeContent: RichTextModel

    weak var undoManager: UndoManager?

    private var isApplyingComposite = false
    private var isDistributing = false
    private var cancellables = Set<AnyCancellable>()
    private var subtreeCancellables = Set<AnyCancellable>()

    init(section: KishoSection) {
        self.root = section
        self.compositeContent = RichTextModel()
        rebuildComposite()
        observeCompositeChanges()
        observeSubtreeChanges()
    }

    func updateRoot(_ section: KishoSection) {
        root = section
        rebuildComposite()
        observeSubtreeChanges()
    }

    func rebuildComposite() {
        isApplyingComposite = true
        compositeContent.attributedString = root.compositeAttributedString()
        isApplyingComposite = false
    }

    private func observeCompositeChanges() {
        compositeContent.$attributedString
            .dropFirst()
            .sink { [weak self] newValue in
                guard let self, !self.isApplyingComposite else { return }
                self.distribute(newValue)
            }
            .store(in: &cancellables)
    }

    private func observeSubtreeChanges() {
        subtreeCancellables.removeAll()

        for section in root.subtreeSections() {
            section.objectWillChange
                .sink { [weak self] _ in
                    self?.handleSubtreeChange()
                }
                .store(in: &subtreeCancellables)
        }
    }

    private func handleSubtreeChange() {
        guard !isApplyingComposite, !isDistributing else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isDistributing, !self.isApplyingComposite else { return }
            self.rebuildComposite()
        }
    }

    private func distribute(_ composite: NSAttributedString) {
        let snapshot = root.subtreeSnapshot()
        isDistributing = true
        root.applyCompositeAttributedString(composite)
        root.inspectorVersion = UUID()
        isDistributing = false

        undoManager?.registerUndo(withTarget: self) { target in
            target.isDistributing = true
            target.root.applySnapshot(snapshot)
            target.root.inspectorVersion = UUID()
            target.isDistributing = false
            target.rebuildComposite()
        }
        undoManager?.setActionName("Edit Section")
    }
}

private extension KishoSection {
    func subtreeSections() -> [KishoSection] {
        var result = [self]
        for child in children {
            result.append(contentsOf: child.subtreeSections())
        }
        return result
    }
}
