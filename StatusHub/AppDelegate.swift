import AppKit
import SwiftUI
import Combine

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var hubStore: HubStore!
    private var gitLabProvider: GitLabProvider!
    private var automationStore: CodexAutomationStore!
    private var externalProviderStore: ExternalProviderStore!
    private var cancellables = Set<AnyCancellable>()
    private var eventMonitor: Any?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        gitLabProvider = GitLabProvider()
        automationStore = CodexAutomationStore()
        externalProviderStore = ExternalProviderStore()
        hubStore = HubStore(
            gitLabProvider: gitLabProvider,
            automationStore: automationStore,
            externalProviderStore: externalProviderStore
        )

        setupStatusItem()
        setupPopover()

        gitLabProvider.start()
        automationStore.start()
        externalProviderStore.start()

        hubStore.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateIcon()
            }
        }.store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateIcon),
            name: .repositoryStateDidChange,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openSettingsWindow),
            name: .openSettings,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRefresh),
            name: .refreshRequested,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleClosePopover),
            name: .closePopoverRequested,
            object: nil
        )
    }

    @objc private func handleClosePopover() {
        closePopover()
    }

    @objc private func handleRefresh() {
        Task { @MainActor in
            await gitLabProvider.refresh()
            await automationStore.refresh()
            await externalProviderStore.refresh()
        }
    }

    @objc private func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let view = SettingsView(store: hubStore)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Status Hub 设置"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 560, height: 620))
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon()
        statusItem.button?.action = #selector(handleClick)
        statusItem.button?.target = self
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 380, height: 520)
        popover.behavior = .applicationDefined
        popover.contentViewController = NSHostingController(
            rootView: HubView(store: hubStore)
        )
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showQuitMenu()
        } else {
            togglePopover()
        }
    }

    private func showQuitMenu() {
        closePopover()
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "退出 Status Hub", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            openPopover()
        }
    }

    private func openPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    @objc private func updateIcon() {
        Task { @MainActor in
            let status = self.hubStore.overallStatus
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            let image = NSImage(systemSymbolName: status.systemSymbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
            image?.isTemplate = true
            self.statusItem.button?.image = image
        }
    }
}

private extension HubStatus {
    var systemSymbolName: String {
        switch self {
        case .failed: return "exclamationmark.circle.fill"
        case .attention: return "exclamationmark.triangle.fill"
        case .running: return "clock.fill"
        case .success: return "checkmark.circle.fill"
        case .idle, .unknown: return "circle.grid.2x2.fill"
        }
    }
}
