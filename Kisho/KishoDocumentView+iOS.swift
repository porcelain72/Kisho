//
//  KishoDocumentView+iOS.swift
//  Kisho
//
//  The iOS document window. iPad (regular width): the outline as a column
//  beside the card editor, toggled from the bar. iPhone (compact): the
//  editor fills the screen and the outline is a sheet. The inspector is a
//  sheet on both. DocumentGroup supplies the navigation bar itself
//  (title, Done); the block commands live in it.
//

#if os(iOS)
import SwiftUI
import Combine
import UniformTypeIdentifiers

struct KishoDocumentView: View {
    let fileURL: URL?
    @EnvironmentObject var document: KishoDocumentModel
    @Environment(\.undoManager) private var undoManager
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage(KishoPreferences.Key.showSidebar) private var showSidebar = true
    @AppStorage(KishoPreferences.Key.showSynopses) private var showSynopses = false
    @AppStorage(KishoPreferences.Key.editorTheme) private var editorThemeRaw = EditorTheme.system.rawValue
    @StateObject private var find = FindState()
    @State private var showOutlineSheet = false
    @State private var showInspector = false
    @State private var showSettings = false
    @State private var showDeleteAlert = false
    @State private var showImporter = false
    @State private var shareItem: ShareItem?
    @State private var errorMessage: String?
    /// Focus Mode is per window: just the cards, the current block bright.
    @State private var focusMode = false
    /// Bumped after every undo-manager change so Undo/Redo re-evaluate their
    /// enabled state (nothing else observes the undo manager). Not on
    /// NSUndoManagerCheckpoint: reading `canRedo` posts that, which would
    /// make the bar re-render itself forever.
    @State private var undoTick = 0

    private var isCompact: Bool { sizeClass == .compact }
    private var editorTheme: EditorTheme { EditorTheme(rawValue: editorThemeRaw) ?? .system }

    private var documentTitle: String {
        fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
    }

    // Read `undoTick` here so the bar's enabled state depends on it: SwiftUI
    // only re-evaluates for state that the body reads.
    private var canUndo: Bool { undoTick >= 0 && (undoManager?.canUndo ?? false) }
    private var canRedo: Bool { undoTick >= 0 && (undoManager?.canRedo ?? false) }

    var body: some View {
        HStack(spacing: 0) {
            if !isCompact && showSidebar && !focusMode {
                KishoOutlineView()
                    .frame(width: 300)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                Divider()
            }
            KishoCardListEditorView()
        }
        .animation(.easeInOut(duration: 0.2), value: showSidebar)
        .animation(.easeInOut(duration: 0.2), value: focusMode)
        .environmentObject(document)
        .environmentObject(find)
        .environment(\.kishoFocusMode, focusMode)
        .environment(\.kishoEditorTheme, editorTheme)
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                if isCompact {
                    Button {
                        showOutlineSheet = true
                    } label: {
                        Label("Outline", systemImage: "list.bullet.indent")
                    }
                } else {
                    Button {
                        showSidebar.toggle()
                    } label: {
                        Label(showSidebar ? "Hide Outline" : "Show Outline", systemImage: "sidebar.leading")
                    }
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    undoManager?.undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.left")
                }
                .disabled(!canUndo)

                Button {
                    undoManager?.redo()
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.right")
                }
                .disabled(!canRedo)

                Button {
                    showInspector = true
                } label: {
                    Label("Inspector", systemImage: "info.circle")
                }

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

                    Toggle(isOn: $showSynopses) {
                        Label("Show Synopses in Outline", systemImage: "text.alignleft")
                    }

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

                Menu {
                    Button {
                        find.show()
                    } label: {
                        Label("Find and Replace", systemImage: "magnifyingglass")
                    }
                    .keyboardShortcut("f", modifiers: .command)

                    Toggle(isOn: $focusMode) {
                        Label("Focus Mode", systemImage: "rectangle.inset.filled")
                    }

                    Divider()

                    Menu {
                        ForEach(Exporter.Format.allCases) { format in
                            Button(format.title) { export(format) }
                        }
                    } label: {
                        Label("Export As", systemImage: "square.and.arrow.up")
                    }
                    if let fileURL {
                        ShareLink(item: fileURL) {
                            Label("Share Document", systemImage: "doc")
                        }
                    }
                    Button {
                        DocumentExport.print(document, title: documentTitle)
                    } label: {
                        Label("Print…", systemImage: "printer")
                    }

                    Divider()

                    Button {
                        showImporter = true
                    } label: {
                        Label("Import Markdown or OPML into This Document…", systemImage: "square.and.arrow.down")
                    }

                    Divider()

                    Button {
                        showSettings = true
                    } label: {
                        Label("Settings…", systemImage: "gearshape")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(url: item.url)
        }
        .sheet(isPresented: $showSettings) {
            KishoSettingsSheet()
                .presentationDetents([.large])
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.markdownText, .plainText, .opml, .xml]) { result in
            switch result {
            case .success(let url):
                switch DocumentImportResult.read(url) {
                case .document(let model):
                    // iOS has no way to open a second document from here, so the
                    // file's blocks are added to the end of this one (one undo step).
                    document.appendImportedSections(model.sections, using: undoManager)
                case .failure(let message):
                    errorMessage = message
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .alert("Couldn’t Complete", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        // Sheets get their own environment; hand them the document's undo
        // manager explicitly, or their edits register with a different one
        // and the bar's Undo takes back something else.
        .sheet(isPresented: $showOutlineSheet) {
            VStack(spacing: 0) {
                SheetHeader(title: "Outline") { showOutlineSheet = false }
                KishoOutlineView(onChoose: { showOutlineSheet = false })
            }
            .environmentObject(document)
            .environment(\.documentUndoManager, undoManager)
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showInspector) {
            BlockInspectorSheet()
                .environmentObject(document)
                .environment(\.documentUndoManager, undoManager)
                .presentationDetents([.large])
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerDidOpenUndoGroup).merge(with:
                   NotificationCenter.default.publisher(for: .NSUndoManagerDidCloseUndoGroup),
                   NotificationCenter.default.publisher(for: .NSUndoManagerDidUndoChange),
                   NotificationCenter.default.publisher(for: .NSUndoManagerDidRedoChange))) { _ in
            DispatchQueue.main.async { undoTick &+= 1 }
        }
        // Typing registers undo inside the event's automatic group, which
        // the undo manager closes only once the event is over; the model's
        // body-edit signal fires at once, so look again a moment later.
        .onReceive(document.stats.$version) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { undoTick &+= 1 }
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

extension KishoDocumentView {
    /// Convert and hand the file to the share sheet.
    private func export(_ format: Exporter.Format) {
        guard let url = DocumentExport.file(for: document, as: format, title: documentTitle) else {
            errorMessage = "The document could not be converted to \(format.title)."
            return
        }
        shareItem = ShareItem(url: url)
    }
}

/// A file for the share sheet (`sheet(item:)` wants Identifiable).
struct ShareItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// A plain title-and-Done bar for a sheet (a NavigationStack inside a
/// DocumentGroup sheet picks up a stray back button).
struct SheetHeader: View {
    let title: String
    let done: () -> Void

    var body: some View {
        ZStack {
            Text(title).font(.headline)
            HStack {
                Spacer()
                Button("Done", action: done).fontWeight(.semibold)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        Divider()
    }
}
#endif
