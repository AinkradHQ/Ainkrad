import AppKit
import SwiftUI

/// The single thing that can hold keyboard focus in a Hoard pane.
///
/// ONE `@FocusState` for the whole pane, deliberately. The list container and
/// the search field previously owned separate focus states, and because the
/// container WRAPS the field, its `.focused(...)` kept re-asserting itself and
/// pulled focus straight back off the field — which is why ⌥F (and ⌘⇧F before
/// it) appeared to do nothing. With one shared value they cannot compete:
/// focus is wherever this says it is.
enum HoardFocusTarget: Hashable {
    case list
    case search
}

/// Attaches the M1 key map to the pane. A `ViewModifier` rather than scattered
/// `.onKeyPress` calls so the whole map is readable in one place — and so M2
/// can extend it without touching the views.
struct HoardKeyboardHandling: ViewModifier {
    let store: HoardPaneStore
    let actions: HoardActions
    let undoStack: UndoStack
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onTogglePreview: () -> Void
    let onOpenFinder: (HoardFinderMode) -> Void
    let onFocusFilter: () -> Void
    /// ⌘D — pin or unpin the current directory in the sidebar.
    let onTogglePin: () -> Void
    /// True while a finder palette owns the keyboard.
    let isFinderOpen: Bool
    /// Opt-in modal navigation. Off by default — see `HoardSettingsStore`.
    let vimKeys: Bool
    /// Shared with the pane; see `HoardFocusTarget`.
    var focus: FocusState<HoardFocusTarget?>.Binding
    @Binding var isEditingPath: Bool

    /// Type-to-select state. Lives here rather than in the store because it is
    /// keyboard ephemera — it must not survive a navigation, and nothing else
    /// in the app has any business reading it.
    @State private var typeAhead = TypeAheadBuffer()
    /// When the last bare `g` arrived, for the `gg` double-tap.
    @State private var lastGPress = Date.distantPast

    private var tab: HoardTab { store.activeTab }

    /// While the path editor owns the keyboard, the unmodified navigation keys
    /// (arrows, Return, Delete, Space) belong to the TEXT FIELD — arrowing
    /// through a path you are typing must move the caret, not the file cursor.
    /// Command-modified bindings stay live throughout, since the field never
    /// wants those.
    /// The path editor AND the finder palettes both take the keyboard: while
    /// either is up, unmodified keys belong to their text field.
    /// Navigation keys belong to the list only while the list actually has
    /// focus — never while the user is typing in the search field or the path
    /// editor.
    private var navigationEnabled: Bool {
        !isEditingPath && !isFinderOpen && focus.wrappedValue == .list
    }

    /// Function keys are private-use unicode scalars, not `KeyEquivalent`
    /// members — `.f5` does not exist. These are the AppKit `NSF*FunctionKey`
    /// constants.
    private static let f2 = KeyEquivalent(Character(UnicodeScalar(0xF705)!))
    private static let f5 = KeyEquivalent(Character(UnicodeScalar(0xF708)!))
    private static let f6 = KeyEquivalent(Character(UnicodeScalar(0xF709)!))
    private static let f7 = KeyEquivalent(Character(UnicodeScalar(0xF70A)!))

    /// Shared by every arrow/page binding: guard, move, report handled.
    /// ⇧ extends the selection as it goes, which is the only case where
    /// cursor movement should touch `selection` at all.
    private func moveCursor(_ delta: Int) -> KeyPress.Result {
        guard navigationEnabled else { return .ignored }
        tab.moveCursor(by: delta)
        if NSEvent.modifierFlags.contains(.shift) {
            tab.selectCursor(extending: true)
        }
        return .handled
    }

    func body(content: Content) -> some View {
        content
            // Focused on appear, so the key map is live the moment the pane
            // opens. NOTE: no `.defaultFocus` — it re-asserted itself over the
            // search field every render.
            .focusable()
            .focusEffectDisabled()
            .focused(focus, equals: .list)
            .onAppear { if focus.wrappedValue == nil { focus.wrappedValue = .list } }
            // Navigation — suppressed while the path editor is focused.
            // Arrows move the CURSOR only. They used to rewrite `selection`
            // on every press, which invalidated every row's membership check
            // and re-rendered the whole list per keystroke. ⇧-arrow still
            // extends the selection, which is the case that wants it.
            .onKeyPress(.upArrow) { moveCursor(-1) }
            .onKeyPress(.downArrow) { moveCursor(1) }
            .onKeyPress(.pageUp) { moveCursor(-20) }
            .onKeyPress(.pageDown) { moveCursor(20) }
            .onKeyPress(.home) {
                guard navigationEnabled else { return .ignored }
                tab.moveCursorToStart()
                return .handled
            }
            .onKeyPress(.end) {
                guard navigationEnabled else { return .ignored }
                tab.moveCursorToEnd()
                return .handled
            }
            .onKeyPress(.return) {
                guard navigationEnabled else { return .ignored }
                tab.activateCursor()
                return .handled
            }
            .onKeyPress(.delete) {
                guard navigationEnabled else { return .ignored }
                tab.ascend()
                return .handled
            }
            .onKeyPress(.space) {
                guard navigationEnabled else { return .ignored }
                tab.toggleCursorSelection()
                return .handled
            }
            // Clipboard — the ordinary idiom, and the primary one.
            .onKeyPress(keys: ["c"], phases: .down) { press in
                guard navigationEnabled, press.modifiers.contains(.command) else { return .ignored }
                actions.copySelection()
                return .handled
            }
            .onKeyPress(keys: ["x"], phases: .down) { press in
                guard navigationEnabled, press.modifiers.contains(.command) else { return .ignored }
                actions.cutSelection()
                return .handled
            }
            .onKeyPress(keys: ["v"], phases: .down) { press in
                guard navigationEnabled, press.modifiers.contains(.command) else { return .ignored }
                Task { await actions.paste() }
                return .handled
            }
            // Selection
            .onKeyPress(keys: ["a"], phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                tab.selectAll()
                return .handled
            }
            .onKeyPress(keys: ["i"], phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                tab.invertSelection()
                return .handled
            }
            // View toggles. ⌘. is dotfiles; ⌘⇧. is git-ignored files — two
            // different questions, so two toggles. ⇧. arrives as ">", which is
            // why the shifted variant is bound by character rather than by
            // checking the modifier on ".".
            .onKeyPress(keys: [".", ">"], phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                if press.modifiers.contains(.shift) || press.key.character == ">" {
                    tab.showIgnored.toggle()
                } else {
                    tab.showHidden.toggle()
                }
                store.persist()
                return .handled
            }
            // ⌘R renames, alongside F2. F2 is the orthodox chord this app was
            // designed around, but on a Mac laptop it means Fn+F2 — so the
            // most ordinary operation in a file manager was the hardest to
            // reach. ⌘R costs nothing and is what a Mac user will try.
            .onKeyPress(keys: ["r"], phases: .down) { press in
                guard navigationEnabled, press.modifiers == [.command] else { return .ignored }
                actions.beginRename()
                return .handled
            }
            // ⌘D pins the current folder. The design specified favourites but
            // not how to add one; this is the chord, and the sidebar's context
            // menu is how you take one away.
            .onKeyPress(keys: ["d"], phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                onTogglePin()
                return .handled
            }
            // ⌘1–9 jump straight to a tab. ⌘9 is the LAST tab, not the ninth —
            // matching every browser, and the only version that stays useful
            // when there are three tabs open.
            .onKeyPress(
                keys: ["1", "2", "3", "4", "5", "6", "7", "8", "9"],
                phases: .down
            ) { press in
                guard press.modifiers.contains(.command),
                    let digit = press.key.character.wholeNumberValue
                else { return .ignored }
                store.selectTab(at: digit == 9 ? store.tabs.count - 1 : digit - 1)
                return .handled
            }
            // Opt-in vim layer. Bound ONLY when enabled, so type-to-select
            // keeps working for everyone else.
            .onKeyPress(keys: ["h", "j", "k", "l", "g", "G"], phases: .down) { press in
                guard vimKeys, navigationEnabled,
                    press.modifiers.isEmpty
                        || press.modifiers == [.shift]
                else { return .ignored }
                switch press.key.character {
                case "j": tab.moveCursor(by: 1)
                case "k": tab.moveCursor(by: -1)
                case "h": tab.ascend()
                case "l": tab.activateCursor()
                case "g":
                    // `gg`, as vim spells it: a lone `g` is a prefix waiting
                    // for its second half, not a jump.
                    let now = Date()
                    if now.timeIntervalSince(lastGPress) < 0.6 {
                        tab.moveCursorToStart()
                        lastGPress = .distantPast
                    } else {
                        lastGPress = now
                    }
                case "G": tab.moveCursorToEnd()
                default: return .ignored
                }
                return .handled
            }
            // Type-to-select. Bound to alphanumerics only, so it can never
            // swallow arrows, Return or a chord — and it yields to the vim
            // layer, which is the conflict that made vim keys opt-in.
            .onKeyPress(characters: .alphanumerics, phases: .down) { press in
                guard navigationEnabled,
                    press.modifiers.isEmpty,
                    let character = press.characters.first
                else { return .ignored }
                if vimKeys && "hjklgG".contains(character) { return .ignored }

                let names = tab.visibleEntries.map(\.name)
                let query: String
                let start: Int
                switch typeAhead.append(character) {
                case .search(let text):
                    query = text
                    start = 0
                case .nextMatch(let text):
                    query = text
                    start = tab.cursorIndex + 1
                }

                // A miss is still HANDLED: falling through would hand the key
                // to whatever else claims it, so a typo would suddenly trigger
                // an unrelated command.
                guard
                    let index = typeAheadIndex(
                        in: names, matching: query,
                        from: start)
                else { return .handled }
                tab.moveCursor(by: index - tab.cursorIndex)
                return .handled
            }
            // Finder affordances. `/` filters here, ⌘F searches below here,
            // ⌘P jumps across the tree — three different questions, so three
            // different entry points rather than one overloaded box.
            // `/` is a second way into the same scoped field.
            .onKeyPress(keys: ["/"], phases: .down) { _ in
                guard navigationEnabled else { return .ignored }
                onFocusFilter()
                return .handled
            }
            // Plain ⌘F only. The in-pane field's ⌥F is handled by
            // `HoardKeyMonitor`, because `onKeyPress` depends on this
            // container holding focus, which it often does not.
            .onKeyPress(keys: ["f"], phases: .down) { press in
                guard press.modifiers.contains(.command),
                    !press.modifiers.contains(.shift)
                else { return .ignored }
                onOpenFinder(.globalSearch)
                return .handled
            }
            .onKeyPress(keys: ["p"], phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                onOpenFinder(.jump)
                return .handled
            }
            // Preview strip — ⌘Y, matching Quick Look's muscle memory.
            .onKeyPress(keys: ["y"], phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                onTogglePreview()
                return .handled
            }
            // Path bar
            .onKeyPress(keys: ["l"], phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                isEditingPath = true
                return .handled
            }
            // Tabs
            .onKeyPress(keys: ["t"], phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                store.newTab()
                return .handled
            }
            .onKeyPress(keys: ["w"], phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                store.closeTab(at: store.activeTabIndex)
                return .handled
            }
            // Operations — the orthodox function-key set. Guarded like the
            // navigation keys so they never fire while the path editor is up.
            .onKeyPress(keys: [Self.f5, Self.f6, Self.f2, Self.f7], phases: .down) { press in
                guard navigationEnabled else { return .ignored }
                switch press.key {
                case Self.f5: Task { await actions.copyToOtherPane() }
                case Self.f6: Task { await actions.moveToOtherPane() }
                case Self.f2: actions.beginRename()
                case Self.f7: actions.beginNewFolder()
                default: return .ignored
                }
                return .handled
            }
            .onKeyPress(keys: [.delete], phases: .down) { press in
                // ⌘⌫ trashes; bare Delete still ascends (handled above).
                guard navigationEnabled, press.modifiers.contains(.command) else { return .ignored }
                Task { await actions.trashSelection() }
                return .handled
            }
            // Undo / redo
            // Same uppercase problem as ⌘⇧F: ⌘⇧Z arrives as "Z", so binding
            // only "z" meant redo was unreachable from the keyboard.
            .onKeyPress(keys: ["z", "Z"], phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                if press.modifiers.contains(.shift) || press.key.character == "Z" {
                    onRedo()
                } else {
                    onUndo()
                }
                return .handled
            }
            // History
            .onKeyPress(keys: ["["], phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                tab.goBack()
                return .handled
            }
            .onKeyPress(keys: ["]"], phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                tab.goForward()
                return .handled
            }
    }
}

extension View {
    func filesKeyboardHandling(
        store: HoardPaneStore, actions: HoardActions,
        undoStack: UndoStack,
        onUndo: @escaping () -> Void,
        onRedo: @escaping () -> Void,
        onTogglePreview: @escaping () -> Void,
        onOpenFinder: @escaping (HoardFinderMode) -> Void,
        onFocusFilter: @escaping () -> Void,
        onTogglePin: @escaping () -> Void,
        isFinderOpen: Bool,
        vimKeys: Bool,
        focus: FocusState<HoardFocusTarget?>.Binding,
        isEditingPath: Binding<Bool>
    ) -> some View {
        modifier(
            HoardKeyboardHandling(
                store: store, actions: actions, undoStack: undoStack,
                onUndo: onUndo, onRedo: onRedo,
                onTogglePreview: onTogglePreview,
                onOpenFinder: onOpenFinder,
                onFocusFilter: onFocusFilter,
                onTogglePin: onTogglePin,
                isFinderOpen: isFinderOpen,
                vimKeys: vimKeys,
                focus: focus,
                isEditingPath: isEditingPath))
    }
}
