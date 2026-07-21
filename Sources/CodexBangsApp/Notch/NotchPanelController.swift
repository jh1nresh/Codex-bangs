@preconcurrency import AppKit
import CodexNotchPetCore
import SwiftUI

@MainActor
final class NotchPanelController {
    private let model: AppModel
    private let onOpenSettings: @MainActor () -> Void
    private let panel: NotchPanel
    private let hostingView: FirstMouseHostingView<NotchRootView>

    private var screenObserver: NSObjectProtocol?
    private var globalMouseMonitor: Any?
    private var localEventMonitor: Any?
    private var hoverHideTask: Task<Void, Never>?
    private var focusTask: Task<Void, Never>?
    private var renderedCenterGapWidth: CGFloat?
    private var renderedHasNotch: Bool?

    init(
        model: AppModel,
        onOpenSettings: @escaping @MainActor () -> Void
    ) {
        self.model = model
        self.onOpenSettings = onOpenSettings
        panel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        hostingView = FirstMouseHostingView(
            rootView: NotchRootView(
                model: model,
                centerGap: 76,
                hasNotch: false,
                onToggleExpanded: {},
                onHoverChanged: { _ in },
                onRefresh: {},
                onOpenInCodex: {},
                onSettings: {},
                onQuit: {}
            )
        )

        configurePanel()
        installEventMonitors()
        installScreenObserver()
        updateLayout(animated: false)
    }

    func show() {
        updateLayout(animated: false)
        if model.isExpanded {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        hoverHideTask?.cancel()
        hoverHideTask = nil
        focusTask?.cancel()
        focusTask = nil
        if !model.isExpanded {
            model.isNotchRevealed = false
        }
        panel.orderOut(nil)
    }

    func toggleVisibility() {
        panel.isVisible ? hide() : show()
    }

    func setExpanded(_ expanded: Bool) {
        guard model.isExpanded != expanded else { return }
        hoverHideTask?.cancel()
        if !expanded {
            focusTask?.cancel()
            focusTask = nil
        }
        model.isExpanded = expanded
        model.isNotchRevealed = expanded
        panel.permitsKey = expanded
        panel.styleMask = expanded ? [.borderless] : [.borderless, .nonactivatingPanel]
        panel.level = .mainMenu + 3
        updateLayout(animated: panel.isVisible)

        if expanded {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.resignKey()
            panel.orderFrontRegardless()
        }
    }

    func showTalkToPet() {
        show()
        setExpanded(true)
        panel.makeKeyAndOrderFront(nil)
        model.requestTaskFocus()
        scheduleTaskFieldFocus()
    }

    func tearDown() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        hoverHideTask?.cancel()
        hoverHideTask = nil
        focusTask?.cancel()
        focusTask = nil
        panel.orderOut(nil)
    }

    private func configurePanel() {
        panel.title = "Codex-bangs"
        panel.isFloatingPanel = true
        panel.level = .mainMenu + 3
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .stationary,
        ]
        panel.contentView = hostingView
        panel.setAccessibilityLabel("Codex-bangs status panel")
    }

    private func installScreenObserver() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateLayout(animated: false)
            }
        }
    }

    private func installEventMonitors() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.collapseIfPointerIsOutside()
            }
        }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            let isEscape = event.type == .keyDown && event.keyCode == 53
            let isMouseDown = event.type == .leftMouseDown || event.type == .rightMouseDown

            if isEscape {
                let shouldCollapse = MainActor.assumeIsolated {
                    self?.model.isExpanded == true
                }
                guard shouldCollapse else { return event }
                Task { @MainActor in self?.setExpanded(false) }
                return nil
            }

            if isMouseDown {
                Task { @MainActor in
                    self?.collapseIfPointerIsOutside()
                }
            }
            return event
        }
    }

    private func collapseIfPointerIsOutside() {
        guard model.isExpanded, panel.isVisible else { return }
        if !panel.frame.contains(NSEvent.mouseLocation) {
            setExpanded(false)
        }
    }

    private func updateLayout(animated: Bool) {
        guard let screen = targetScreen() else { return }
        let cameraHousing = cameraHousing(for: screen)
        let menuBarHeight = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
        let metrics = panelMetrics(cameraHousing: cameraHousing)
        let layout = NotchGeometry.layout(
            screenFrame: screen.frame,
            cameraHousing: cameraHousing,
            expanded: model.isExpanded,
            noNotchTopOffset: menuBarHeight + 6,
            metrics: metrics
        )

        let centerGapWidth = layout.centerGap?.width ?? 76
        if renderedCenterGapWidth != centerGapWidth
            || renderedHasNotch != layout.hasNotch {
            hostingView.rootView = NotchRootView(
                model: model,
                centerGap: centerGapWidth,
                hasNotch: layout.hasNotch,
                onToggleExpanded: { [weak self] in
                    self?.setExpanded(!(self?.model.isExpanded ?? false))
                },
                onHoverChanged: { [weak self] hovering in
                    self?.handleHoverChanged(hovering)
                },
                onRefresh: { [weak self] in
                    self?.model.refresh()
                },
                onOpenInCodex: { [weak self] in
                    self?.openTaskInCodex()
                },
                onSettings: { [weak self] in
                    self?.openSettings()
                },
                onQuit: {
                    NSApp.terminate(nil)
                }
            )
            renderedCenterGapWidth = centerGapWidth
            renderedHasNotch = layout.hasNotch
        }

        let shouldAnimate = animated
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if shouldAnimate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.38
                context.timingFunction = CAMediaTimingFunction(
                    controlPoints: 0.16,
                    1.00,
                    0.30,
                    1.0
                )
                panel.animator().setFrame(layout.frame, display: true)
            }
        } else {
            panel.setFrame(layout.frame, display: true)
        }
    }

    private func targetScreen() -> NSScreen? {
        NSScreen.screens.first(where: { cameraHousing(for: $0) != nil })
            ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func cameraHousing(for screen: NSScreen) -> CGRect? {
        let height = screen.safeAreaInsets.top
        guard height > 0,
              let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea else {
            return nil
        }
        let width = rightArea.minX - leftArea.maxX
        guard width > 0 else { return nil }
        return CGRect(
            x: leftArea.maxX,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }

    private func panelMetrics(cameraHousing: CGRect?) -> NotchPanelMetrics {
        guard let cameraHousing else {
            return .noNotchDefault
        }
        guard !model.isExpanded,
              !model.isNotchRevealed else {
            return .productDefault
        }

        return NotchPanelMetrics(
            collapsedSize: CGSize(
                width: cameraHousing.width + 24,
                height: cameraHousing.height + 8
            ),
            expandedSize: NotchPanelMetrics.productDefault.expandedSize
        )
    }

    private func handleHoverChanged(_ hovering: Bool) {
        guard panel.isVisible else { return }

        hoverHideTask?.cancel()
        hoverHideTask = nil

        if hovering {
            guard let screen = targetScreen(),
                  cameraHousing(for: screen) != nil else {
                return
            }
            guard !model.isNotchRevealed else { return }
            model.isNotchRevealed = true
            updateLayout(animated: true)
            return
        }

        guard !model.isExpanded else { return }
        hoverHideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled,
                  let self,
                  !self.model.isExpanded,
                  !self.panel.frame.contains(NSEvent.mouseLocation) else {
                return
            }
            self.model.isNotchRevealed = false
            self.updateLayout(animated: true)
            self.hoverHideTask = nil
        }
    }

    private func openSettings() {
        setExpanded(false)
        onOpenSettings()
    }

    private func openTaskInCodex() {
        CodexDesktopLauncher.open(prompt: model.taskPromptForHandoff) { [weak self] opened in
            self?.model.recordTaskHandoff(opened: opened)
        }
    }

    private func scheduleTaskFieldFocus() {
        focusTask?.cancel()
        focusTask = Task { [weak self] in
            for _ in 0..<5 {
                guard !Task.isCancelled, let self else { return }
                if self.focusTaskField() {
                    self.focusTask = nil
                    return
                }
                try? await Task.sleep(for: .milliseconds(75))
            }
            self?.focusTask = nil
        }
    }

    private func focusTaskField() -> Bool {
        guard let field = hostingView.firstEditableTextInput() else {
            return false
        }
        return panel.makeFirstResponder(field)
    }
}

@MainActor
private final class NotchPanel: NSPanel {
    var permitsKey = false

    override var canBecomeKey: Bool {
        permitsKey
    }

    override var canBecomeMain: Bool {
        false
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

@MainActor
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    func firstEditableTextInput() -> NSResponder? {
        firstEditableTextField(in: self)
            ?? firstEditableTextView(in: self)
    }

    private func firstEditableTextField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField,
           field.isEditable,
           field.isEnabled {
            return field
        }

        for subview in view.subviews {
            if let field = firstEditableTextField(in: subview) {
                return field
            }
        }
        return nil
    }

    private func firstEditableTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView,
           textView.isEditable {
            return textView
        }

        for subview in view.subviews {
            if let textView = firstEditableTextView(in: subview) {
                return textView
            }
        }
        return nil
    }
}
