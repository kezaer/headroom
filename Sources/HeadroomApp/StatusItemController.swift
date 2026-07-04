import AppKit
import SwiftUI
import Observation
import HeadroomCore

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate, NSViewToolTipOwner {
    private let store: UsageStore
    private let settingsPresenter: SettingsWindowPresenter
    private let statusItem: NSStatusItem
    private var popover: NSPopover?
    private var tooltipByTag: [NSView.ToolTipTag: String] = [:]
    private var isObservingStore = false

    private static let horizontalImagePadding: CGFloat = 8
    private static let popoverWidth: CGFloat = 348
    private static let minimumPopoverHeight: CGFloat = 120

    init(store: UsageStore, softwareUpdates: SoftwareUpdateControlling) {
        self.store = store
        self.settingsPresenter = SettingsWindowPresenter(store: store, softwareUpdates: softwareUpdates)
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureStatusButton()
    }

    func start() {
        updateStatusItem()
        observeStore()
        Task { await store.start() }
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.sendAction(on: [.leftMouseUp])
    }

    private func observeStore() {
        guard !isObservingStore else { return }
        isObservingStore = true
        withObservationTracking {
            _ = store.menuBarMeters
            _ = store.showMenuBarPercentage
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.isObservingStore = false
                self?.updateStatusItem()
                self?.observeStore()
            }
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let result = MenuBarLabelRenderer.render(
            meters: store.menuBarMeters,
            showsPercentage: store.showMenuBarPercentage
        )
        let statusWidth = ceil(result.image.size.width + Self.horizontalImagePadding)
        statusItem.length = statusWidth
        button.image = result.image
        button.toolTip = result.tooltip
        button.setAccessibilityLabel(result.accessibilityLabel)
        installTooltipRegions(result.regions, imageSize: result.image.size, statusWidth: statusWidth, in: button)
    }

    private func installTooltipRegions(
        _ regions: [MenuBarLabelTooltipRegion],
        imageSize: NSSize,
        statusWidth: CGFloat,
        in button: NSStatusBarButton
    ) {
        button.removeAllToolTips()
        tooltipByTag.removeAll()

        guard !regions.isEmpty else { return }
        let xOffset = max(0, (statusWidth - imageSize.width) / 2)
        let yOffset = max(0, (button.bounds.height - imageSize.height) / 2)
        for region in regions {
            let rect = region.rect.offsetBy(dx: xOffset, dy: yOffset)
            let tag = button.addToolTip(rect, owner: self, userData: nil)
            tooltipByTag[tag] = region.tooltip
        }
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover?.isShown == true {
            closePopover()
        } else {
            showPopover(relativeTo: sender)
        }
    }

    private func showPopover(relativeTo button: NSStatusBarButton) {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        let root = PopoverView(
            store: store,
            onClose: { [weak self] in self?.closePopover() },
            onOpenSettings: { [weak self] in
                self?.settingsPresenter.show()
            }
        )
        let host = NSHostingController(rootView: root)
        host.view.setFrameSize(NSSize(width: Self.popoverWidth, height: 10))
        host.view.layoutSubtreeIfNeeded()
        let fitting = host.view.fittingSize
        popover.contentSize = NSSize(
            width: max(Self.popoverWidth, fitting.width),
            height: max(Self.minimumPopoverHeight, fitting.height)
        )
        popover.contentViewController = host
        self.popover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func closePopover() {
        popover?.performClose(nil)
        popover = nil
    }

    nonisolated func view(
        _ view: NSView,
        stringForToolTip tag: NSView.ToolTipTag,
        point: NSPoint,
        userData data: UnsafeMutableRawPointer?
    ) -> String {
        MainActor.assumeIsolated {
            tooltipByTag[tag] ?? ""
        }
    }

    func popoverDidClose(_ notification: Notification) {
        popover = nil
    }
}

@MainActor
final class SettingsWindowPresenter {
    private let store: UsageStore
    private let softwareUpdates: SoftwareUpdateControlling
    private var window: NSWindow?

    init(store: UsageStore, softwareUpdates: SoftwareUpdateControlling) {
        self.store = store
        self.softwareUpdates = softwareUpdates
    }

    func show() {
        let window = existingOrCreateWindow()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        placeWindowOnActiveScreenIfNeeded(window)
    }

    private func existingOrCreateWindow() -> NSWindow {
        if let window { return window }

        let root = SettingsView(
            store: store,
            softwareUpdates: softwareUpdates,
            onDone: { [weak self] in self?.window?.close() }
        )
        let host = NSHostingController(rootView: root)
        host.view.layoutSubtreeIfNeeded()
        let size = host.view.fittingSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: max(380, size.width), height: max(520, size.height))),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Headroom Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentViewController = host
        window.setContentSize(host.view.fittingSize)
        self.window = window
        return window
    }

    private func placeWindowOnActiveScreenIfNeeded(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        let activeScreen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let activeScreen else { return }

        if window.isVisible, activeScreen.frame.intersects(window.frame) { return }

        window.layoutIfNeeded()
        let visible = activeScreen.visibleFrame
        let size = window.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2 + size.height * 0.05
        )
        window.setFrameOrigin(origin)
    }
}
