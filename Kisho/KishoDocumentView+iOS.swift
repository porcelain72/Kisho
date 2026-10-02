//
//  KishoDocumentView+iOS.swift
//  Kisho
//
//  The iOS document window: the card editor, with block commands in the
//  navigation bar. DocumentGroup supplies the bar itself (title, Done).
//  The outline sidebar, inspector and the rest arrive in Phases C and D.
//

#if os(iOS)
import SwiftUI
import Combine

struct KishoDocumentView: View {
    let fileURL: URL?
    @EnvironmentObject var document: KishoDocumentModel
    @Environment(\.undoManager) private var undoManager
    @State private var showDeleteAlert = false
    /// Bumped after every undo-manager change so Undo/Redo re-evaluate their
    /// enabled state (nothing else observes the undo manager). Not on
    /// NSUndoManagerCheckpoint: reading `canRedo` posts that, which would
    /// make the bar re-render itself forever.
    @State private var undoTick = 0

    var body: some View {
        KishoCardListEditorView()
            .environmentObject(document)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        undoManager?.undo()
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.left")
                    }
                    .disabled(!(undoManager?.canUndo ?? false))

                    Button {
                        undoManager?.redo()
                    } label: {
                        Label("Redo", systemImage: "arrow.uturn.right")
                    }
                    .disabled(!(undoManager?.canRedo ?? false))

                    Menu {
                        Button {
                            document.addSiblingSection(using: undoManager)
                        } label: {
                            Label("Add Block After", systemImage: "plus")
                        }
                        Button {
                            document.addChildSection(using: undoManager)
                        } label: {
                            Label("Add Sub-block", systemImage: "plus.square.on.square")
                        }
                        .disabled(document.selectedSection == nil)

                        Divider()

                        Button {
                            document.indentSelectedSection(using: undoManager)
                        } label: {
                            Label("Indent Block", systemImage: "increase.indent")
                        }
                        .disabled(document.selectedSectionID.map { document.canIndent(sectionID: $0) } != true)
                        Button {
                            document.outdentSelectedSection(using: undoManager)
                        } label: {
                            Label("Outdent Block", systemImage: "decrease.indent")
                        }
                        .disabled(document.selectedSectionID.map { document.canOutdent(sectionID: $0) } != true)

                        Divider()

                        Button {
                            document.makeChildren(undoManager: undoManager)
                        } label: {
                            Label("Split Paragraphs into Blocks", systemImage: "square.fill.text.grid.1x2")
                        }
                        .disabled(document.selectedSection == nil)
                        Button {
                            document.gather(undoManager: undoManager)
                        } label: {
                            Label("Gather Sub-blocks", systemImage: "rectangle.compress.vertical")
                        }
                        .disabled(document.selectedSection?.children.isEmpty ?? true)

                        Divider()

                        Button(role: .destructive) {
                            showDeleteAlert = true
                        } label: {
                            Label("Delete Block…", systemImage: "trash")
                        }
                        .disabled(document.selectedSection == nil)
                    } label: {
                        Label("Block", systemImage: "square.stack.3d.up")
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidOpenUndoGroup).merge(with:
                       NotificationCenter.default.publisher(for: .NSUndoManagerDidCloseUndoGroup),
                       NotificationCenter.default.publisher(for: .NSUndoManagerDidUndoChange),
                       NotificationCenter.default.publisher(for: .NSUndoManagerDidRedoChange))) { note in
                guard (note.object as? UndoManager) === undoManager else { return }
                // After the current event, so an open typing group has closed.
                DispatchQueue.main.async { undoTick &+= 1 }
            }
            // Typing bursts register undo without opening a group of their
            // own; the model's stats signal fires on every body edit.
            .onReceive(document.stats.$version) { _ in
                DispatchQueue.main.async { undoTick &+= 1 }
            }
            .alert("Delete Block?", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {
                    document.deleteSelectedSection(using: undoManager)
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Its sub-blocks will be deleted with it.")
            }
    }
}
#endif
