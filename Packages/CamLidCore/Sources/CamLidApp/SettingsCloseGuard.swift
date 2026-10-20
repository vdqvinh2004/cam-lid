import AppKit

@MainActor
final class SettingsCloseGuard: NSObject, NSWindowDelegate {
    let editor: SettingsEditor
    private let installationPending: @MainActor () -> Bool
    private let settleInstallation: @MainActor () async -> Bool
    private let onClose: @MainActor () -> Void
    private let onKeepOpen: @MainActor () -> Void
    private var settling = false
    init(editor: SettingsEditor, installationPending: @escaping @MainActor () -> Bool = { false },
         settleInstallation: @escaping @MainActor () async -> Bool = { true },
         onClose: @escaping @MainActor () -> Void = {},
         onKeepOpen: @escaping @MainActor () -> Void = {}) {
        self.editor = editor; self.installationPending = installationPending; self.settleInstallation = settleInstallation
        self.onClose = onClose; self.onKeepOpen = onKeepOpen
    }
    func windowWillClose(_ notification: Notification) {
        // Reopen installs a fresh host; hidden Settings need no retained view graph.
        (notification.object as? NSWindow)?.contentView = nil
        onClose()
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        editor.flush()
        guard editor.isDirty || installationPending() else { return true }
        guard !settling, sender.attachedSheet == nil else { return false }
        settling = true
        Task { [weak self, weak sender] in
            guard let self, let sender else { return }
            let installed = await self.settleInstallation()
            let applied = installed ? await self.editor.settle() : false
            self.settling = false
            if applied { sender.close(); return }
            self.showDisposition(sender)
        }
        return false
    }
    private func showDisposition(_ sender: NSWindow) {
        guard sender.attachedSheet == nil else { return }
        let pending = installationPending()
        let alert = NSAlert()
        alert.messageText = pending ? "Settings write still finishing" : "Unapplied preference edits"
        alert.informativeText = pending ? "The write may apply later. Keep editing or wait for its result; discarding input cannot cancel an installation already in progress." : "Applied changes are saved. Retry failed edits, keep editing, or discard only unapplied input."
        alert.addButton(withTitle: "Keep Editing")
        alert.addButton(withTitle: pending ? "Wait Again" : "Retry")
        if !pending { alert.addButton(withTitle: "Discard Unapplied Input") }
        alert.beginSheetModal(for: sender) { [weak self, weak sender] response in
            guard let self, let sender else { return }
            if response == .alertFirstButtonReturn { self.onKeepOpen() }
            else if response == .alertThirdButtonReturn {
                self.editor.discard(); sender.close()
            } else if response == .alertSecondButtonReturn {
                if !pending { for key in self.editor.fieldMessages.keys { self.editor.retry(key: key) } }
                Task { @MainActor in
                    let installed = await self.settleInstallation()
                    let applied = installed ? await self.editor.settle() : false
                    if applied { sender.close() }
                    else { self.showDisposition(sender) }
                }
            }
        }
    }
}
