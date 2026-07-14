import AppKit
import SwiftUI
import Combine
import UsageCore

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let animator = SpriteAnimator()
    private let engine = UsageEngine()
    private var popover: NSPopover?
    private var settingsWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: SpriteFrames.spriteSize.width + 4)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
        }

        animator.onFrame = { [weak self] image in
            self?.statusItem.button?.image = image
        }
        animator.appearanceProvider = { [weak self] in
            self?.statusItem.button?.effectiveAppearance
        }
        animator.set(display: .normal(.sleeping))

        // 한도 오버라이드(§F2): 80%+ 🥵, 95%+ ⚠️ — 속도 상태보다 우선
        Publishers.CombineLatest(engine.$catState, engine.$alertLevel)
            .map { state, level -> SpriteDisplay in
                switch level {
                case .critical: return .alert
                case .tired: return .tired
                case .normal: return .normal(state)
                }
            }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] display in self?.animator.set(display: display) }
            .store(in: &cancellables)

        Notifier.shared.requestAuthorization()
        engine.start()
    }

    @objc private func togglePopover() {
        if let popover, popover.isShown {
            popover.performClose(nil)
            return
        }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)   // RunCat 스타일 다크 팝오버
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(engine: engine, settings: engine.settings) { [weak self] in
                self?.openSettings()
            })
        if let button = statusItem.button {
            engine.refreshNow()   // 여는 순간 JSONL 재스캔 + 공식 재조회(30초 스로틀)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        self.popover = popover
    }

    private func openSettings() {
        popover?.performClose(nil)
        if settingsWindow == nil {
            let hosting = NSHostingController(
                rootView: SettingsView(settings: engine.settings, engine: engine))
            let window = NSWindow(contentViewController: hosting)
            window.title = "TokenCat 설정"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
