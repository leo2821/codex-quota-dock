import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var observer: AnyCancellable?
    private var showMain: (() -> Void)?

    @MainActor
    func configure(model: AppModel, showMain: @escaping () -> Void) {
        self.showMain = showMain
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "CodexAccountsStatus"
        item.isVisible = true
        if let button = item.button {
            let image = NSImage(systemSymbolName: "person.2.circle", accessibilityDescription: "Codex 账号管理")!
            image.size = NSSize(width: 17, height: 17)
            image.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
            button.title = " Codex"
            button.toolTip = "查看账号额度与快速切换"
            button.target = self
            button.action = #selector(toggleMenu)
        }
        statusItem = item
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuPanel(model: model, openMainWindow: { [weak self] in
            self?.popover.performClose(nil)
            self?.showMain?()
        }))
        observer = model.objectWillChange.sink { [weak self, weak model] _ in
            DispatchQueue.main.async {
                guard let self, let model else { return }
                self.statusItem?.button?.title = model.menuTitle.isEmpty ? " Codex" : " Codex \(model.menuTitle)"
            }
        }
    }

    @objc private func toggleMenu() {
        guard let button = statusItem?.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }

    @MainActor
    func writeDiagnostics(model: AppModel) throws {
        guard let path = ProcessInfo.processInfo.environment["CODEX_ACCOUNTS_DIAGNOSTIC_OUTPUT"] else { return }
        let diagnostics: [String: Any] = [
            "statusItemCreated": statusItem != nil,
            "statusItemVisible": statusItem?.isVisible ?? false,
            "statusButtonTitle": statusItem?.button?.title ?? "",
            "statusButtonWidth": statusItem?.button?.frame.width ?? 0,
            "statusButtonHeight": statusItem?.button?.frame.height ?? 0,
            "statusWindowFrame": statusItem?.button?.window.map { NSStringFromRect($0.frame) } ?? "",
            "accountCount": model.profiles.count,
            "accountsWithUsage": model.profiles.filter { $0.usage != nil && $0.lastError == nil }.count,
            "mainWindows": NSApp.windows.filter { $0.title == "Codex Accounts" }.map {
                ["width": $0.frame.width, "height": $0.frame.height, "visible": $0.isVisible] as [String: Any]
            }
        ]
        try JSONSerialization.data(withJSONObject: diagnostics, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMain?() }
        return true
    }
}

struct AppRoot: View {
    @ObservedObject var model: AppModel
    let delegate: AppDelegate
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        MainView(model: model).frame(minWidth: 920, minHeight: 620)
            .onAppear {
                delegate.configure(model: model) {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            .task {
                await model.start()
                do { try delegate.writeDiagnostics(model: model) }
                catch { model.errorMessage = error.localizedDescription }
            }
    }
}

@main
struct CodexAccountsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        Window("Codex Accounts", id: "main") {
            AppRoot(model: model, delegate: delegate)
        }
        .defaultSize(width: 1080, height: 760)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("添加账号") { Task { await model.login() } }
                    .keyboardShortcut("n").disabled(model.busy)
                Button("刷新全部账号") { Task { await model.refreshAll() } }
                    .keyboardShortcut("r").disabled(model.busy)
            }
        }
    }
}
