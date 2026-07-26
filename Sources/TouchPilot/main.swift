@preconcurrency import AppKit
import SwiftUI
@preconcurrency import ApplicationServices
@preconcurrency import CoreGraphics
import UserNotifications
import UniformTypeIdentifiers
import ServiceManagement
import Darwin
import Carbon

@main
struct TouchPilotApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private enum WindowMetrics {
        static let contentSize = NSSize(width: 980, height: 640)
    }

    private let state = AppState()
    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private var shortcutWindow: NSWindow?
    private var localOpenShortcutMonitor: Any?
    private var openShortcutHotKeyRef: EventHotKeyRef?
    private var openShortcutEventHandlerRef: EventHandlerRef?
    private lazy var updateController = UpdateController(language: { [weak self] in
        self?.state.language ?? .ru
    })

    func applicationDidFinishLaunching(_ notification: Notification) {
        state.openWindow = { [weak self] in self?.showWindow() }
        state.hideWindow = { [weak self] in self?.hideWindowToMenuBar() }
        state.refreshMenu = { [weak self] in self?.refreshMenu() }
        state.openShortcutChanged = { [weak self] in self?.registerOpenShortcutHotKey() }
        setupMainMenu()
        setupStatusItem()
        setupOpenShortcutMonitor()
        state.start()
        updateController.checkAutomaticallyIfNeeded()
        if state.showingTutorial {
            showWindow()
        }
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit TouchPilot", action: #selector(quitAction), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Close Window", action: #selector(closeWindowAction), keyEquivalent: "w"))
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(minimizeWindowAction), keyEquivalent: "m"))
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.imagePosition = .imageLeading

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: L.openTouchPilot.text(state.language), action: #selector(openWindowAction), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: openShortcutMenuTitle, action: #selector(openShortcutSettingsAction), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: state.isEnabled ? L.pauseGestures.text(state.language) : L.resumeGestures.text(state.language), action: #selector(toggleEnabledAction), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Русский", action: #selector(selectRussianLanguageAction), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "English", action: #selector(selectEnglishLanguageAction), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: state.language == .ru ? "Экспорт настроек" : "Export Settings", action: #selector(exportSettingsAction), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: state.language == .ru ? "Импорт настроек" : "Import Settings", action: #selector(importSettingsAction), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: state.language == .ru ? "Разрешения..." : "Permissions...", action: #selector(requestPermissionsAction), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: updateMenuTitle, action: #selector(checkForUpdatesAction), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: aboutMenuTitle, action: #selector(aboutAction), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L.quit.text(state.language), action: #selector(quitAction), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
        refreshMenu()
        updateStatusItemIcon()
    }

    private func refreshMenu() {
        statusItem?.menu?.item(at: 0)?.title = L.openTouchPilot.text(state.language)
        statusItem?.menu?.item(at: 1)?.title = openShortcutMenuTitle
        statusItem?.menu?.item(at: 2)?.title = state.isEnabled ? L.pauseGestures.text(state.language) : L.resumeGestures.text(state.language)
        statusItem?.menu?.item(at: 4)?.state = state.language == .ru ? .on : .off
        statusItem?.menu?.item(at: 5)?.state = state.language == .en ? .on : .off
        statusItem?.menu?.item(at: 7)?.title = state.language == .ru ? "Экспорт настроек" : "Export Settings"
        statusItem?.menu?.item(at: 8)?.title = state.language == .ru ? "Импорт настроек" : "Import Settings"
        statusItem?.menu?.item(at: 9)?.title = state.language == .ru ? "Разрешения..." : "Permissions..."
        statusItem?.menu?.item(at: 10)?.title = updateMenuTitle
        statusItem?.menu?.item(at: 12)?.title = aboutMenuTitle
        statusItem?.menu?.item(at: 14)?.title = L.quit.text(state.language)
        updateStatusItemIcon()
    }

    private func updateStatusItemIcon() {
        guard let button = statusItem?.button else { return }
        let image = NSImage(systemSymbolName: "hand.point.up.braille", accessibilityDescription: "TouchPilot")
        image?.isTemplate = true
        button.image = image
        button.contentTintColor = nil
    }

    private var openShortcutMenuTitle: String {
        let shortcut = ShortcutRecorder.prettyString(from: state.openWindowShortcut) ?? (state.language == .ru ? "не задано" : "not set")
        return state.language == .ru ? "Открыть/скрыть окно: \(shortcut)" : "Show/Hide Window: \(shortcut)"
    }

    private var aboutMenuTitle: String {
        state.language == .ru ? "О программе TouchPilot" : "About TouchPilot"
    }

    private var updateMenuTitle: String {
        state.language == .ru ? "Проверить обновления..." : "Check for Updates..."
    }

    @objc private func openWindowAction() {
        showWindow()
    }

    @objc private func openShortcutSettingsAction() {
        showOpenShortcutSettings()
    }

    @objc private func toggleEnabledAction() {
        state.isEnabled.toggle()
        refreshMenu()
    }

    @objc private func selectRussianLanguageAction() {
        state.language = .ru
    }

    @objc private func selectEnglishLanguageAction() {
        state.language = .en
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }

    @objc private func requestPermissionsAction() {
        state.requestAccessibilityPermission()
    }

    @objc private func exportSettingsAction() {
        state.exportGestureSettings()
    }

    @objc private func importSettingsAction() {
        state.importGestureSettings()
    }

    @objc private func checkForUpdatesAction() {
        updateController.checkForUpdates(manual: true)
    }

    @objc private func aboutAction() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.6.9"
        let build = info?["CFBundleVersion"] as? String ?? "21"
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.icon = NSApp.applicationIconImage
        alert.messageText = "TouchPilot"
        alert.informativeText = state.language == .ru
            ? "Версия \(version)\nСборка \(build)\n\nСоздатели: Kapfilm + Codex"
            : "Version \(version)\nBuild \(build)\n\nCreated by Kapfilm + Codex"
        alert.addButton(withTitle: state.language == .ru ? "Готово" : "Done")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func closeWindowAction() {
        NSApp.keyWindow?.performClose(nil)
    }

    @objc private func minimizeWindowAction() {
        hideWindowToMenuBar()
    }

    private func setupOpenShortcutMonitor() {
        localOpenShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if ShortcutRecorder.matches(event: event, shortcut: state.openWindowShortcut) {
                toggleWindowFromShortcut()
                return nil
            }
            return event
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    delegate.toggleWindowFromShortcut()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &openShortcutEventHandlerRef
        )
        registerOpenShortcutHotKey()
    }

    private func registerOpenShortcutHotKey() {
        if let openShortcutHotKeyRef {
            UnregisterEventHotKey(openShortcutHotKeyRef)
            self.openShortcutHotKeyRef = nil
        }

        guard let hotKey = ShortcutRecorder.carbonHotKey(from: state.openWindowShortcut) else { return }
        let hotKeyID = EventHotKeyID(signature: 0x5450484B, id: 1)
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &openShortcutHotKeyRef
        )
        if status != noErr {
            NSLog("[TouchPilot] Could not register open shortcut: \(status)")
        }
    }

    private func toggleWindowFromShortcut() {
        if window?.isVisible == true || shortcutWindow?.isVisible == true {
            state.showingOpenShortcutSettings = false
            shortcutWindow?.close()
            hideWindowToMenuBar()
        } else {
            showWindow()
        }
    }

    private func showOpenShortcutSettings() {
        showWindow()
        state.cancelGestureEditing()
        state.showingActionEditor = false
        state.showingSystemActionPicker = false
        state.showingCleaningModeSettings = false
        state.showingOpenShortcutSettings = true
    }

    private func showWindow() {
        if window == nil {
            let view = MainView()
                .environmentObject(state)
                .frame(minWidth: WindowMetrics.contentSize.width, minHeight: WindowMetrics.contentSize.height)
            let hosting = NSHostingController(rootView: view)
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "TouchPilot"
            newWindow.setContentSize(WindowMetrics.contentSize)
            newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            newWindow.titleVisibility = .hidden
            newWindow.titlebarAppearsTransparent = true
            newWindow.isMovableByWindowBackground = true
            newWindow.backgroundColor = .clear
            newWindow.isOpaque = false
            newWindow.hasShadow = true
            newWindow.isReleasedWhenClosed = false
            newWindow.delegate = self
            roundWindowContent(for: newWindow)
            window = newWindow
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        if let window {
            applyWindowPolish(to: window)
        }
    }

    private func applyWindowPolish(to window: NSWindow) {
        roundWindowContent(for: window)
        styleTrafficLights(for: window)
        DispatchQueue.main.async { [weak window] in
            guard let window else { return }
            self.roundWindowContent(for: window)
            self.styleTrafficLights(for: window)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak window] in
            guard let window else { return }
            self.roundWindowContent(for: window)
            self.styleTrafficLights(for: window)
        }
    }

    private func roundWindowContent(for window: NSWindow) {
        [window.contentView, window.contentView?.superview].compactMap { $0 }.forEach { view in
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            view.layer?.cornerRadius = 24
            view.layer?.cornerCurve = .continuous
            view.layer?.masksToBounds = true
        }
    }

    private func styleTrafficLights(for window: NSWindow) {
        guard let closeButton = window.standardWindowButton(.closeButton),
              let minimizeButton = window.standardWindowButton(.miniaturizeButton),
              let zoomButton = window.standardWindowButton(.zoomButton) else { return }

        let closeX = closeButton.frame.origin.x
        let xOffsets = [
            closeButton.frame.origin.x - closeX,
            minimizeButton.frame.origin.x - closeX,
            zoomButton.frame.origin.x - closeX
        ]
        let buttons = [closeButton, minimizeButton, zoomButton]
        let targetCloseX: CGFloat = 24
        let targetY: CGFloat = 6
        let targetSize = NSSize(width: 16, height: 16)

        for (index, button) in buttons.enumerated() {
            button.frame = NSRect(
                origin: NSPoint(x: targetCloseX + xOffsets[index], y: targetY),
                size: targetSize
            )
            button.needsDisplay = true
        }
    }

    func windowWillClose(_ notification: Notification) {
        enterMenuBarMode()
    }

    func windowDidMiniaturize(_ notification: Notification) {
        hideWindowToMenuBar()
    }

    func applicationDidHide(_ notification: Notification) {
        enterMenuBarMode()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return false
    }

    private func hideWindowToMenuBar() {
        if window?.isMiniaturized == true {
            window?.deminiaturize(nil)
        }
        window?.orderOut(nil)
        NSApp.hide(nil)
        enterMenuBarMode()
    }

    private func enterMenuBarMode() {
        NSApp.setActivationPolicy(.accessory)
    }

}

enum VersionComparator {
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let candidateParts = numericParts(candidate)
        let currentParts = numericParts(current)
        let count = max(candidateParts.count, currentParts.count)
        for index in 0..<count {
            let candidatePart = index < candidateParts.count ? candidateParts[index] : 0
            let currentPart = index < currentParts.count ? currentParts[index] : 0
            if candidatePart != currentPart {
                return candidatePart > currentPart
            }
        }
        return false
    }

    private static func numericParts(_ value: String) -> [Int] {
        value
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: ".", omittingEmptySubsequences: false)
            .map { component in
                Int(component.prefix { $0.isNumber }) ?? 0
            }
    }
}

@MainActor
final class UpdateController {
    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL

            private enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let name: String?
        let body: String?
        let htmlURL: URL
        let assets: [Asset]

        private enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case body
            case htmlURL = "html_url"
            case assets
        }
    }

    private enum UpdateError: LocalizedError {
        case invalidResponse
        case missingDMG

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "GitHub returned an invalid response."
            case .missingDMG:
                return "The release does not contain a DMG file."
            }
        }
    }

    private static let repository = "Kapfilm/TouchPilot"
    private static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/\(repository)/releases/latest"
    )!
    private static let automaticCheckInterval: TimeInterval = 24 * 60 * 60
    private let language: () -> AppLanguage
    private var checkInProgress = false

    init(language: @escaping () -> AppLanguage) {
        self.language = language
    }

    func checkAutomaticallyIfNeeded() {
        let lastCheck = UserDefaults.standard.object(forKey: "TouchPilotLastUpdateCheck") as? Date
        guard lastCheck.map({ Date().timeIntervalSince($0) >= Self.automaticCheckInterval }) ?? true else {
            return
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            self?.checkForUpdates(manual: false)
        }
    }

    func checkForUpdates(manual: Bool) {
        guard !checkInProgress else { return }
        checkInProgress = true
        Task { [weak self] in
            guard let self else { return }
            defer { checkInProgress = false }
            do {
                let release = try await fetchLatestRelease()
                UserDefaults.standard.set(Date(), forKey: "TouchPilotLastUpdateCheck")
                let currentVersion = Bundle.main.object(
                    forInfoDictionaryKey: "CFBundleShortVersionString"
                ) as? String ?? "0.6.7"
                if VersionComparator.isNewer(release.tagName, than: currentVersion) {
                    presentAvailableUpdate(release, currentVersion: currentVersion)
                } else if manual {
                    presentUpToDate(version: currentVersion)
                }
            } catch {
                if manual {
                    presentError(error)
                }
            }
        }
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("TouchPilot-Updater", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw UpdateError.invalidResponse
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    private func presentAvailableUpdate(_ release: GitHubRelease, currentVersion: String) {
        let currentLanguage = language()
        let latestVersion = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.icon = NSApp.applicationIconImage
        alert.messageText = currentLanguage == .ru
            ? "Доступна новая версия TouchPilot \(latestVersion)"
            : "TouchPilot \(latestVersion) is available"
        let notes = release.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let versionText = currentLanguage == .ru
            ? "Установлена версия \(currentVersion)."
            : "You have version \(currentVersion)."
        alert.informativeText = notes.isEmpty ? versionText : "\(versionText)\n\n\(notes)"
        alert.addButton(withTitle: currentLanguage == .ru ? "Скачать" : "Download")
        alert.addButton(withTitle: currentLanguage == .ru ? "Позже" : "Later")
        alert.addButton(withTitle: currentLanguage == .ru ? "Открыть GitHub" : "Open GitHub")
        NSApp.activate(ignoringOtherApps: true)

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task { [weak self] in
                await self?.download(release)
            }
        case .alertThirdButtonReturn:
            NSWorkspace.shared.open(release.htmlURL)
        default:
            break
        }
    }

    private func download(_ release: GitHubRelease) async {
        let currentLanguage = language()
        do {
            guard let asset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }) else {
                throw UpdateError.missingDMG
            }
            var request = URLRequest(url: asset.browserDownloadURL)
            request.setValue("TouchPilot-Updater", forHTTPHeaderField: "User-Agent")
            let (temporaryURL, response) = try await URLSession.shared.download(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw UpdateError.invalidResponse
            }

            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            let destination = uniqueDestination(for: asset.name, in: downloads)
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
            NSWorkspace.shared.activateFileViewerSelecting([destination])
            NSWorkspace.shared.open(destination)

            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = currentLanguage == .ru ? "Обновление загружено" : "Update Downloaded"
            alert.informativeText = currentLanguage == .ru
                ? "DMG сохранён в «Загрузки» и открыт. Перетащите TouchPilot в папку Applications."
                : "The DMG was saved to Downloads and opened. Drag TouchPilot to Applications."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        } catch {
            presentError(error)
        }
    }

    private func uniqueDestination(for filename: String, in directory: URL) -> URL {
        let fileManager = FileManager.default
        let original = directory.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: original.path) else { return original }
        let base = original.deletingPathExtension().lastPathComponent
        let pathExtension = original.pathExtension
        for suffix in 2...100 {
            let candidate = directory.appendingPathComponent("\(base)-\(suffix).\(pathExtension)")
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return directory.appendingPathComponent("\(base)-\(UUID().uuidString).\(pathExtension)")
    }

    private func presentUpToDate(version: String) {
        let currentLanguage = language()
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.icon = NSApp.applicationIconImage
        alert.messageText = currentLanguage == .ru
            ? "Установлена актуальная версия"
            : "TouchPilot is up to date"
        alert.informativeText = currentLanguage == .ru
            ? "Версия \(version) — новее пока нет."
            : "Version \(version) is the latest available version."
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func presentError(_ error: Error) {
        let currentLanguage = language()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = currentLanguage == .ru
            ? "Не удалось проверить обновления"
            : "Could Not Check for Updates"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

enum GestureKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case twoFingerSwipeUp = "Swipe Up"
    case twoFingerSwipeDown = "Swipe Down"
    case twoFingerSwipeLeft = "Swipe Left"
    case twoFingerSwipeRight = "Swipe Right"
    case twoFingerPinchIn = "Pinch In"
    case twoFingerPinchOut = "Pinch Out"
    case twoFingerRotateLeft = "Rotate Left"
    case twoFingerRotateRight = "Rotate Right"
    case twoFingerTap = "2 Finger Tap"
    case twoFingerDoubleTap = "2 Finger Double Tap"
    case twoFingerClick = "2 Finger Click"
    case twoFingerPressDragLeft = "2 Finger Press Drag Left"
    case twoFingerPressDragRight = "2 Finger Press Drag Right"
    case threeFingerPressDragLeft = "3 Finger Press Drag Left"
    case threeFingerPressDragRight = "3 Finger Press Drag Right"
    case threeFingerSwipeUp = "3 Finger Swipe Up"
    case threeFingerSwipeDown = "3 Finger Swipe Down"
    case threeFingerSwipeLeft = "3 Finger Swipe Left"
    case threeFingerSwipeRight = "3 Finger Swipe Right"
    case threeFingerTap = "3 Finger Tap"
    case threeFingerClick = "3 Finger Click"
    case fourFingerSwipeUp = "4 Finger Swipe Up"
    case fourFingerSwipeDown = "4 Finger Swipe Down"
    case fourFingerSwipeLeft = "4 Finger Swipe Left"
    case fourFingerSwipeRight = "4 Finger Swipe Right"
    case fourFingerTap = "4 Finger Tap"
    case fiveFingerTap = "5 Finger Tap"
    case tipTapLeft = "TipTap Left"
    case tipTapRight = "TipTap Right"
    case tipTapMiddle = "TipTap Middle"
    case tipTapThirdFingerLeft = "TipTap Third Finger Left"
    case tipTapThirdFingerRight = "TipTap Third Finger Right"
    case circleClockwise = "Circle Clockwise"
    case circleCounterClockwise = "Circle Counter-Clockwise"
    case drawTriangle = "Draw Triangle"
    case leftEdgeSlideUp = "Left Edge Slide Up"
    case leftEdgeSlideDown = "Left Edge Slide Down"
    case rightEdgeSlideUp = "Right Edge Slide Up"
    case rightEdgeSlideDown = "Right Edge Slide Down"
    case cornerClickTopLeft = "Corner Click Top Left"
    case cornerClickTopRight = "Corner Click Top Right"
    case cornerClickBottomLeft = "Corner Click Bottom Left"
    case cornerClickBottomRight = "Corner Click Bottom Right"
    case middleClickTop = "Middle Click Top"
    case middleClickBottom = "Middle Click Bottom"

    var id: String { rawValue }

    var pressDragFingerCount: Int? {
        switch self {
        case .twoFingerPressDragLeft, .twoFingerPressDragRight:
            return 2
        case .threeFingerPressDragLeft, .threeFingerPressDragRight:
            return 3
        default:
            return nil
        }
    }

    var family: GestureFamily {
        switch self {
        case .twoFingerSwipeUp, .twoFingerSwipeDown, .twoFingerSwipeLeft, .twoFingerSwipeRight,
             .threeFingerSwipeUp, .threeFingerSwipeDown, .threeFingerSwipeLeft, .threeFingerSwipeRight,
             .fourFingerSwipeUp, .fourFingerSwipeDown, .fourFingerSwipeLeft, .fourFingerSwipeRight:
            return .swipes
        case .twoFingerPinchIn, .twoFingerPinchOut, .twoFingerRotateLeft, .twoFingerRotateRight:
            return .pinchRotate
        case .twoFingerTap, .twoFingerDoubleTap, .threeFingerTap, .fourFingerTap, .fiveFingerTap,
             .twoFingerClick, .threeFingerClick:
            return .tapsClicks
        case .tipTapLeft, .tipTapRight, .tipTapMiddle,
             .tipTapThirdFingerLeft, .tipTapThirdFingerRight:
            return .tipTaps
        case .circleClockwise, .circleCounterClockwise, .drawTriangle:
            return .drawings
        case .leftEdgeSlideUp, .leftEdgeSlideDown, .rightEdgeSlideUp, .rightEdgeSlideDown:
            return .edgeSlides
        case .cornerClickTopLeft, .cornerClickTopRight, .cornerClickBottomLeft, .cornerClickBottomRight,
             .middleClickTop, .middleClickBottom:
            return .zones
        case .twoFingerPressDragLeft, .twoFingerPressDragRight,
             .threeFingerPressDragLeft, .threeFingerPressDragRight:
            return .pressDrag
        }
    }

    func title(_ language: AppLanguage) -> String {
        switch (self, language) {
        case (.twoFingerSwipeUp, .ru): return "Свайп вверх двумя пальцами"
        case (.twoFingerSwipeDown, .ru): return "Свайп вниз двумя пальцами"
        case (.twoFingerSwipeLeft, .ru): return "Свайп влево двумя пальцами"
        case (.twoFingerSwipeRight, .ru): return "Свайп вправо двумя пальцами"
        case (.twoFingerPinchIn, .ru): return "Сведение двумя пальцами"
        case (.twoFingerPinchOut, .ru): return "Разведение двумя пальцами"
        case (.twoFingerRotateLeft, .ru): return "Поворот влево двумя пальцами"
        case (.twoFingerRotateRight, .ru): return "Поворот вправо двумя пальцами"
        case (.twoFingerTap, .ru): return "Касание двумя пальцами"
        case (.twoFingerDoubleTap, .ru): return "Двойное касание двумя пальцами"
        case (.twoFingerClick, .ru): return "Клик двумя пальцами"
        case (.twoFingerPressDragLeft, .ru): return "Нажать и тянуть влево двумя пальцами"
        case (.twoFingerPressDragRight, .ru): return "Нажать и тянуть вправо двумя пальцами"
        case (.threeFingerPressDragLeft, .ru): return "Нажать и тянуть влево тремя пальцами"
        case (.threeFingerPressDragRight, .ru): return "Нажать и тянуть вправо тремя пальцами"
        case (.threeFingerSwipeUp, .ru): return "Свайп вверх тремя пальцами"
        case (.threeFingerSwipeDown, .ru): return "Свайп вниз тремя пальцами"
        case (.threeFingerSwipeLeft, .ru): return "Свайп влево тремя пальцами"
        case (.threeFingerSwipeRight, .ru): return "Свайп вправо тремя пальцами"
        case (.threeFingerTap, .ru): return "Касание тремя пальцами"
        case (.threeFingerClick, .ru): return "Клик тремя пальцами"
        case (.fourFingerSwipeUp, .ru): return "Свайп вверх четырьмя пальцами"
        case (.fourFingerSwipeDown, .ru): return "Свайп вниз четырьмя пальцами"
        case (.fourFingerSwipeLeft, .ru): return "Свайп влево четырьмя пальцами"
        case (.fourFingerSwipeRight, .ru): return "Свайп вправо четырьмя пальцами"
        case (.fourFingerTap, .ru): return "Касание четырьмя пальцами"
        case (.fiveFingerTap, .ru): return "Касание пятью пальцами"
        case (.tipTapLeft, .ru): return "TipTap влево"
        case (.tipTapRight, .ru): return "TipTap вправо"
        case (.tipTapMiddle, .ru): return "TipTap по центру"
        case (.tipTapThirdFingerLeft, .ru): return "TipTap: третий палец слева"
        case (.tipTapThirdFingerRight, .ru): return "TipTap: третий палец справа"
        case (.circleClockwise, .ru): return "Круг по часовой стрелке"
        case (.circleCounterClockwise, .ru): return "Круг против часовой стрелки"
        case (.drawTriangle, .ru): return "Нарисовать треугольник"
        case (.leftEdgeSlideUp, .ru): return "Слайд вверх по левому краю"
        case (.leftEdgeSlideDown, .ru): return "Слайд вниз по левому краю"
        case (.rightEdgeSlideUp, .ru): return "Слайд вверх по правому краю"
        case (.rightEdgeSlideDown, .ru): return "Слайд вниз по правому краю"
        case (.cornerClickTopLeft, .ru): return "Клик в левом верхнем углу"
        case (.cornerClickTopRight, .ru): return "Клик в правом верхнем углу"
        case (.cornerClickBottomLeft, .ru): return "Клик в левом нижнем углу"
        case (.cornerClickBottomRight, .ru): return "Клик в правом нижнем углу"
        case (.middleClickTop, .ru): return "Клик сверху по центру"
        case (.middleClickBottom, .ru): return "Клик снизу по центру"
        default: return rawValue
        }
    }

    var isPubliclyDetected: Bool {
        switch self {
        case .twoFingerSwipeUp, .twoFingerSwipeDown, .twoFingerSwipeLeft, .twoFingerSwipeRight,
             .twoFingerPinchIn, .twoFingerPinchOut, .twoFingerRotateLeft, .twoFingerRotateRight:
            return true
        default:
            return false
        }
    }

    func supportNote(_ language: AppLanguage) -> String {
        if isPubliclyDetected {
            return language == .ru ? "Работает сейчас" : "Works now"
        }
        return language == .ru ? "Готово к назначению" : "Ready to assign"
    }

    var icon: String {
        switch self {
        case .twoFingerSwipeLeft, .threeFingerSwipeLeft, .fourFingerSwipeLeft: return "arrow.left"
        case .twoFingerSwipeRight, .threeFingerSwipeRight, .fourFingerSwipeRight: return "arrow.right"
        case .twoFingerSwipeUp, .threeFingerSwipeUp, .fourFingerSwipeUp: return "arrow.up"
        case .twoFingerSwipeDown, .threeFingerSwipeDown, .fourFingerSwipeDown: return "arrow.down"
        case .twoFingerPinchIn: return "arrow.down.right.and.arrow.up.left"
        case .twoFingerPinchOut: return "arrow.up.left.and.arrow.down.right"
        case .twoFingerRotateLeft: return "rotate.left"
        case .twoFingerRotateRight: return "rotate.right"
        case .twoFingerTap, .twoFingerDoubleTap, .threeFingerTap, .fourFingerTap, .fiveFingerTap: return "hand.tap"
        case .twoFingerClick, .threeFingerClick: return "hand.point.up.left.fill"
        case .twoFingerPressDragLeft, .twoFingerPressDragRight,
             .threeFingerPressDragLeft, .threeFingerPressDragRight: return "hand.draw"
        case .tipTapLeft, .tipTapRight, .tipTapMiddle,
             .tipTapThirdFingerLeft, .tipTapThirdFingerRight: return "hand.point.up.left.and.text"
        case .circleClockwise, .circleCounterClockwise: return "circle.dashed"
        case .drawTriangle: return "triangle"
        case .leftEdgeSlideUp, .leftEdgeSlideDown, .rightEdgeSlideUp, .rightEdgeSlideDown: return "rectangle.compress.vertical"
        case .cornerClickTopLeft, .cornerClickTopRight, .cornerClickBottomLeft, .cornerClickBottomRight: return "square.grid.2x2"
        case .middleClickTop, .middleClickBottom: return "rectangle.split.3x1"
        }
    }
}

enum GestureFamily: String, CaseIterable, Identifiable {
    case swipes
    case pinchRotate
    case tapsClicks
    case tipTaps
    case drawings
    case edgeSlides
    case zones
    case pressDrag

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch (self, language) {
        case (.swipes, .ru): return "Свайпы"
        case (.pinchRotate, .ru): return "Щипок и поворот"
        case (.tapsClicks, .ru): return "Касания и клики"
        case (.tipTaps, .ru): return "TipTap"
        case (.drawings, .ru): return "Рисунки"
        case (.edgeSlides, .ru): return "Края"
        case (.zones, .ru): return "Зоны"
        case (.pressDrag, .ru): return "Нажать и тянуть"
        case (.swipes, .en): return "Swipes"
        case (.pinchRotate, .en): return "Pinch & Rotate"
        case (.tapsClicks, .en): return "Taps & Clicks"
        case (.tipTaps, .en): return "TipTap"
        case (.drawings, .en): return "Drawings"
        case (.edgeSlides, .en): return "Edges"
        case (.zones, .en): return "Zones"
        case (.pressDrag, .en): return "Press Drag"
        }
    }

    var icon: String {
        switch self {
        case .swipes: return "hand.draw"
        case .pinchRotate: return "arrow.triangle.2.circlepath"
        case .tapsClicks: return "hand.tap"
        case .tipTaps: return "hand.point.up.left.and.text"
        case .drawings: return "pencil.and.scribble"
        case .edgeSlides: return "rectangle.compress.vertical"
        case .zones: return "square.grid.2x2"
        case .pressDrag: return "hand.point.up.left.fill"
        }
    }
}

enum DrawingGestureRecognizer {
    static func circleGesture(in points: [(x: Float, y: Float)]) -> GestureKind? {
        guard points.count >= 14 else { return nil }

        let xs = points.map(\.x)
        let ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return nil }

        let width = maxX - minX
        let height = maxY - minY
        let largestDimension = max(width, height)
        guard largestDimension > 0.07,
              min(width, height) / max(largestDimension, 0.001) > 0.42 else { return nil }

        let center = (x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        let radii = points.map { hypot($0.x - center.x, $0.y - center.y) }
        let averageRadius = radii.reduce(0, +) / Float(radii.count)
        guard averageRadius > 0.04, averageRadius < 0.32 else { return nil }

        let radialVariance = radii.reduce(Float(0)) { partial, radius in
            let difference = radius - averageRadius
            return partial + difference * difference
        } / Float(radii.count)
        let radialDeviation = sqrt(radialVariance)
        guard radialDeviation / averageRadius < 0.48,
              let firstRadius = radii.first,
              let lastRadius = radii.last,
              abs(firstRadius - lastRadius) / averageRadius < 0.72 else { return nil }

        var occupiedSectors = Set<Int>()
        for (point, radius) in zip(points, radii) where radius > averageRadius * 0.5 {
            var angle = atan2(point.y - center.y, point.x - center.x)
            if angle < 0 { angle += 2 * .pi }
            occupiedSectors.insert(min(Int(angle / (2 * .pi) * 8), 7))
        }
        guard occupiedSectors.count >= 7 else { return nil }

        var pathLength: Float = 0
        for index in 1..<points.count {
            pathLength += hypot(points[index].x - points[index - 1].x, points[index].y - points[index - 1].y)
        }
        guard pathLength > averageRadius * 4.8,
              pathLength < averageRadius * 15 else { return nil }

        var twiceSignedArea: Float = 0
        for index in 0..<points.count {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            twiceSignedArea += current.x * next.y - next.x * current.y
        }
        let contourArea = abs(twiceSignedArea) * 0.5
        let boundingArea = width * height
        guard contourArea / max(boundingArea, 0.0001) > 0.36 else { return nil }

        guard let start = points.first, let end = points.last,
              hypot(start.x - end.x, start.y - end.y) < max(averageRadius * 0.95, 0.075) else { return nil }

        var signedSweep: Float = 0
        var absoluteSweep: Float = 0
        var previousAngle = atan2(points[0].y - center.y, points[0].x - center.x)
        for point in points.dropFirst() {
            let angle = atan2(point.y - center.y, point.x - center.x)
            var delta = angle - previousAngle
            if delta > .pi { delta -= 2 * .pi }
            if delta < -.pi { delta += 2 * .pi }
            if abs(delta) < .pi * 0.55 {
                signedSweep += delta
                absoluteSweep += abs(delta)
            }
            previousAngle = angle
        }

        guard abs(signedSweep) > .pi * 1.68,
              abs(signedSweep) < .pi * 3.0,
              absoluteSweep > 0,
              abs(signedSweep) / absoluteSweep > 0.72 else { return nil }

        // Multitouch coordinates use an upward Y axis, matching the mathematical angle direction.
        return signedSweep < 0 ? .circleClockwise : .circleCounterClockwise
    }
}

enum TrackpadEdge {
    case left
    case right
}

enum EdgeSlideGestureRecognizer {
    static func gesture(
        side: TrackpadEdge,
        startY: Float,
        currentY: Float,
        minimumTravel: Float = 0.12
    ) -> GestureKind? {
        let travel = currentY - startY
        guard abs(travel) >= minimumTravel else { return nil }

        switch (side, travel > 0) {
        case (.left, true): return .leftEdgeSlideUp
        case (.left, false): return .leftEdgeSlideDown
        case (.right, true): return .rightEdgeSlideUp
        case (.right, false): return .rightEdgeSlideDown
        }
    }
}

enum TrackpadZoneGestureRecognizer {
    static func gesture(for position: (x: Float, y: Float)) -> GestureKind? {
        if position.x < 0.28 && position.y > 0.70 { return .cornerClickTopLeft }
        if position.x > 0.72 && position.y > 0.70 { return .cornerClickTopRight }
        if position.x < 0.28 && position.y < 0.30 { return .cornerClickBottomLeft }
        if position.x > 0.72 && position.y < 0.30 { return .cornerClickBottomRight }
        if position.x > 0.30 && position.x < 0.70 && position.y > 0.72 { return .middleClickTop }
        if position.x > 0.30 && position.x < 0.70 && position.y < 0.28 { return .middleClickBottom }
        return nil
    }
}

enum PressDragGestureRecognizer {
    static func gesture(fingerCount: Int, dx: Float, dy: Float, threshold: Float = 0.045) -> GestureKind? {
        guard fingerCount == 2 || fingerCount == 3,
              abs(dx) > threshold,
              abs(dx) > max(abs(dy) * 1.15, threshold) else { return nil }

        switch (fingerCount, dx < 0) {
        case (2, true): return .twoFingerPressDragLeft
        case (2, false): return .twoFingerPressDragRight
        case (3, true): return .threeFingerPressDragLeft
        case (3, false): return .threeFingerPressDragRight
        default: return nil
        }
    }
}

enum ActionKind: String, CaseIterable, Identifiable, Codable {
    case notification = "Show Notification"
    case openURL = "Open URL"
    case launchApp = "Launch App"
    case quitFrontmostApp = "Quit Frontmost App"
    case keyboardShortcut = "Send Shortcut"
    case systemAction = "System Action"

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch (self, language) {
        case (.notification, .ru): return "Показать уведомление"
        case (.openURL, .ru): return "Открыть ссылку"
        case (.launchApp, .ru): return "Запустить приложение"
        case (.quitFrontmostApp, .ru): return "Закрыть активное приложение"
        case (.keyboardShortcut, .ru): return "Нажать сочетание клавиш"
        case (.systemAction, .ru): return "Системное действие"
        default: return rawValue
        }
    }

    var icon: String {
        switch self {
        case .notification: return "bell"
        case .openURL: return "link"
        case .launchApp: return "app.badge"
        case .quitFrontmostApp: return "xmark.app"
        case .keyboardShortcut: return "command"
        case .systemAction: return "gearshape.2"
        }
    }

    var requiresValue: Bool {
        switch self {
        case .notification, .quitFrontmostApp:
            return false
        case .openURL, .launchApp, .keyboardShortcut, .systemAction:
            return true
        }
    }

    static var regularCases: [ActionKind] {
        allCases.filter { $0 != .systemAction }
    }
}

enum SystemActionCategory: String, CaseIterable, Identifiable {
    case session
    case soundAndMedia
    case display
    case navigation
    case screenshots

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch (self, language) {
        case (.session, .ru): return "Питание и сеанс"
        case (.soundAndMedia, .ru): return "Звук и медиа"
        case (.display, .ru): return "Экран и подсветка"
        case (.navigation, .ru): return "Навигация macOS"
        case (.screenshots, .ru): return "Снимки экрана"
        case (.session, .en): return "Power & Session"
        case (.soundAndMedia, .en): return "Sound & Media"
        case (.display, .en): return "Display & Backlight"
        case (.navigation, .en): return "macOS Navigation"
        case (.screenshots, .en): return "Screenshots"
        }
    }
}

enum SystemAction: String, CaseIterable, Identifiable {
    case lockScreen
    case startScreenSaver
    case sleepDisplay
    case sleepMac
    case logOut
    case restart
    case shutDown
    case volumeUp
    case volumeDown
    case toggleMute
    case playPause
    case nextTrack
    case previousTrack
    case brightnessUp
    case brightnessDown
    case keyboardBacklightUp
    case keyboardBacklightDown
    case missionControl
    case applicationWindows
    case showDesktop
    case launchpad
    case spotlight
    case notificationCenter
    case toggleDarkMode
    case screenshotFull
    case screenshotSelection

    var id: String { rawValue }

    var category: SystemActionCategory {
        switch self {
        case .lockScreen, .startScreenSaver, .sleepDisplay, .sleepMac, .logOut, .restart, .shutDown:
            return .session
        case .volumeUp, .volumeDown, .toggleMute, .playPause, .nextTrack, .previousTrack:
            return .soundAndMedia
        case .brightnessUp, .brightnessDown, .keyboardBacklightUp, .keyboardBacklightDown:
            return .display
        case .missionControl, .applicationWindows, .showDesktop, .launchpad, .spotlight,
             .notificationCenter, .toggleDarkMode:
            return .navigation
        case .screenshotFull, .screenshotSelection:
            return .screenshots
        }
    }

    func title(_ language: AppLanguage) -> String {
        switch (self, language) {
        case (.lockScreen, .ru): return "Заблокировать экран"
        case (.startScreenSaver, .ru): return "Запустить заставку"
        case (.sleepDisplay, .ru): return "Выключить дисплей"
        case (.sleepMac, .ru): return "Перевести Mac в режим сна"
        case (.logOut, .ru): return "Завершить сеанс"
        case (.restart, .ru): return "Перезагрузить Mac"
        case (.shutDown, .ru): return "Выключить Mac"
        case (.volumeUp, .ru): return "Увеличить громкость"
        case (.volumeDown, .ru): return "Уменьшить громкость"
        case (.toggleMute, .ru): return "Включить или выключить звук"
        case (.playPause, .ru): return "Воспроизведение / пауза"
        case (.nextTrack, .ru): return "Следующая композиция"
        case (.previousTrack, .ru): return "Предыдущая композиция"
        case (.brightnessUp, .ru): return "Увеличить яркость"
        case (.brightnessDown, .ru): return "Уменьшить яркость"
        case (.keyboardBacklightUp, .ru): return "Увеличить подсветку клавиатуры"
        case (.keyboardBacklightDown, .ru): return "Уменьшить подсветку клавиатуры"
        case (.missionControl, .ru): return "Mission Control"
        case (.applicationWindows, .ru): return "Окна активного приложения"
        case (.showDesktop, .ru): return "Показать рабочий стол"
        case (.launchpad, .ru): return "Launchpad / Приложения"
        case (.spotlight, .ru): return "Spotlight"
        case (.notificationCenter, .ru): return "Центр уведомлений"
        case (.toggleDarkMode, .ru): return "Переключить тёмную тему"
        case (.screenshotFull, .ru): return "Снимок всего экрана"
        case (.screenshotSelection, .ru): return "Снимок выбранной области"
        case (.lockScreen, .en): return "Lock Screen"
        case (.startScreenSaver, .en): return "Start Screen Saver"
        case (.sleepDisplay, .en): return "Turn Display Off"
        case (.sleepMac, .en): return "Put Mac to Sleep"
        case (.logOut, .en): return "Log Out"
        case (.restart, .en): return "Restart Mac"
        case (.shutDown, .en): return "Shut Down Mac"
        case (.volumeUp, .en): return "Volume Up"
        case (.volumeDown, .en): return "Volume Down"
        case (.toggleMute, .en): return "Toggle Mute"
        case (.playPause, .en): return "Play / Pause"
        case (.nextTrack, .en): return "Next Track"
        case (.previousTrack, .en): return "Previous Track"
        case (.brightnessUp, .en): return "Brightness Up"
        case (.brightnessDown, .en): return "Brightness Down"
        case (.keyboardBacklightUp, .en): return "Keyboard Backlight Up"
        case (.keyboardBacklightDown, .en): return "Keyboard Backlight Down"
        case (.missionControl, .en): return "Mission Control"
        case (.applicationWindows, .en): return "Application Windows"
        case (.showDesktop, .en): return "Show Desktop"
        case (.launchpad, .en): return "Launchpad / Apps"
        case (.spotlight, .en): return "Spotlight"
        case (.notificationCenter, .en): return "Notification Center"
        case (.toggleDarkMode, .en): return "Toggle Dark Mode"
        case (.screenshotFull, .en): return "Capture Entire Screen"
        case (.screenshotSelection, .en): return "Capture Selected Area"
        }
    }

    var icon: String {
        switch self {
        case .lockScreen: return "lock.display"
        case .startScreenSaver: return "sparkles.rectangle.stack"
        case .sleepDisplay: return "display"
        case .sleepMac: return "moon.zzz"
        case .logOut: return "rectangle.portrait.and.arrow.right"
        case .restart: return "restart"
        case .shutDown: return "power"
        case .volumeUp: return "speaker.plus"
        case .volumeDown: return "speaker.minus"
        case .toggleMute: return "speaker.slash"
        case .playPause: return "playpause"
        case .nextTrack: return "forward.end"
        case .previousTrack: return "backward.end"
        case .brightnessUp: return "sun.max"
        case .brightnessDown: return "sun.min"
        case .keyboardBacklightUp: return "light.max"
        case .keyboardBacklightDown: return "light.min"
        case .missionControl: return "rectangle.3.group"
        case .applicationWindows: return "rectangle.stack"
        case .showDesktop: return "macwindow.on.rectangle"
        case .launchpad: return "square.grid.3x3"
        case .spotlight: return "magnifyingglass"
        case .notificationCenter: return "bell.badge"
        case .toggleDarkMode: return "circle.lefthalf.filled"
        case .screenshotFull: return "camera.viewfinder"
        case .screenshotSelection: return "rectangle.dashed"
        }
    }

    var requiresConfirmation: Bool {
        switch self {
        case .logOut, .restart, .shutDown: return true
        default: return false
        }
    }
}

enum GestureTriggerModifier: String, CaseIterable, Identifiable, Codable, Sendable {
    case none
    case command

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch (self, language) {
        case (.none, .ru): return "Обычный жест"
        case (.command, .ru): return "⌘ + жест"
        case (.none, .en): return "Plain Gesture"
        case (.command, .en): return "⌘ + Gesture"
        }
    }

    func triggerTitle(for gesture: GestureKind, language: AppLanguage) -> String {
        switch self {
        case .none: return gesture.title(language)
        case .command: return "⌘ + \(gesture.title(language))"
        }
    }

    static func from(eventFlags: NSEvent.ModifierFlags) -> GestureTriggerModifier {
        eventFlags.contains(.command) ? .command : .none
    }

    static var currentSystemModifier: GestureTriggerModifier {
        CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand) ? .command : .none
    }
}

struct GestureRule: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var gesture: GestureKind
    var triggerModifier: GestureTriggerModifier
    var isEnabled: Bool
    var appBundleID: String?
    var actions: [PilotAction]

    init(
        id: UUID = UUID(),
        name: String,
        gesture: GestureKind,
        triggerModifier: GestureTriggerModifier = .none,
        isEnabled: Bool = true,
        appBundleID: String? = nil,
        actions: [PilotAction] = []
    ) {
        self.id = id
        self.name = name
        self.gesture = gesture
        self.triggerModifier = triggerModifier
        self.isEnabled = isEnabled
        self.appBundleID = appBundleID
        self.actions = actions
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, gesture, triggerModifier, isEnabled, appBundleID, actions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        gesture = try container.decode(GestureKind.self, forKey: .gesture)
        triggerModifier = try container.decodeIfPresent(GestureTriggerModifier.self, forKey: .triggerModifier) ?? .none
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        appBundleID = try container.decodeIfPresent(String.self, forKey: .appBundleID)
        actions = try container.decodeIfPresent([PilotAction].self, forKey: .actions) ?? []
    }

    func matches(gesture: GestureKind, modifier: GestureTriggerModifier, appBundleID: String?) -> Bool {
        isEnabled
            && self.gesture == gesture
            && triggerModifier == modifier
            && self.appBundleID == appBundleID
    }
}

struct PilotAction: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: ActionKind
    var title: String
    var value: String

    var systemAction: SystemAction? {
        guard kind == .systemAction else { return nil }
        return SystemAction(rawValue: value)
    }
}

struct PilotPreset: Codable {
    static let currentVersion = 5

    var version: Int
    var rules: [GestureRule]
    var appTargets: [AppTarget]

    init(
        version: Int = PilotPreset.currentVersion,
        rules: [GestureRule],
        appTargets: [AppTarget] = []
    ) {
        self.version = version
        self.rules = rules
        self.appTargets = appTargets
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case rules
        case appTargets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        rules = try container.decode([GestureRule].self, forKey: .rules)
        appTargets = try container.decodeIfPresent([AppTarget].self, forKey: .appTargets) ?? []
    }

    static let sample = PilotPreset(rules: [
        GestureRule(
            name: "Открыть Заметки",
            gesture: .twoFingerSwipeLeft,
            actions: [PilotAction(kind: .launchApp, title: "Заметки", value: "/System/Applications/Notes.app")]
        ),
        GestureRule(
            name: "Проверочное уведомление",
            gesture: .twoFingerPinchOut,
            actions: [PilotAction(kind: .notification, title: "TouchPilot", value: "Жест распознан")]
        )
    ])
}

struct AppTarget: Identifiable, Hashable, Codable {
    var id: String { bundleID ?? "all-apps" }
    let name: String
    let bundleID: String?
    let iconName: String
    var isEnabled: Bool

    init(name: String, bundleID: String?, iconName: String, isEnabled: Bool = true) {
        self.name = name
        self.bundleID = bundleID
        self.iconName = iconName
        self.isEnabled = isEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case name, bundleID, iconName, isEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        bundleID = try container.decodeIfPresent(String.self, forKey: .bundleID)
        iconName = try container.decodeIfPresent(String.self, forKey: .iconName) ?? "app"
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    static let allApps = AppTarget(name: "Все приложения", bundleID: nil, iconName: "globe")
    static let finder = AppTarget(name: "Finder", bundleID: "com.apple.finder", iconName: "face.smiling")
}

enum ConflictDetector {
    static func messages(
        for candidate: GestureRule,
        among rules: [GestureRule],
        openWindowShortcut: String,
        language: AppLanguage
    ) -> [String] {
        guard candidate.isEnabled else { return [] }
        var messages: [String] = []

        if let duplicate = rules.first(where: {
            $0.id != candidate.id
                && $0.isEnabled
                && $0.appBundleID == candidate.appBundleID
                && $0.gesture == candidate.gesture
                && $0.triggerModifier == candidate.triggerModifier
        }) {
            messages.append(language == .ru
                ? "Эта комбинация жеста уже используется правилом «\(duplicate.name)» в этом профиле."
                : "This gesture combination is already used by \"\(duplicate.name)\" in this profile.")
        }

        let appShortcut = canonicalShortcut(openWindowShortcut)
        if !appShortcut.isEmpty,
           candidate.actions.contains(where: {
               $0.kind == .keyboardShortcut && canonicalShortcut($0.value) == appShortcut
           }) {
            messages.append(language == .ru
                ? "Сочетание действия совпадает с командой открытия TouchPilot."
                : "An action shortcut matches the TouchPilot show/hide shortcut.")
        }

        return messages
    }

    static func canonicalShortcut(_ value: String) -> String {
        let parts = value.lowercased()
            .split(separator: "+")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let key = parts.last, !key.isEmpty else { return "" }
        var modifiers: [String] = []
        if parts.contains("ctrl") || parts.contains("control") { modifiers.append("ctrl") }
        if parts.contains("alt") || parts.contains("option") { modifiers.append("alt") }
        if parts.contains("shift") { modifiers.append("shift") }
        if parts.contains("cmd") || parts.contains("command") { modifiers.append("cmd") }
        return (modifiers + [key]).joined(separator: "+")
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case ru
    case en

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ru: return "Русский"
        case .en: return "English"
        }
    }
}

enum L {
    case openTouchPilot, pauseGestures, resumeGestures, quit
    case on, off, addGesture, gestures, actions, details, liveLog
    case noGestureSelected, chooseOrCreateGesture, name, gesture, enabled
    case type, title, message, url, appPath, shortcut, interfaceLanguage
    case newGesture, gestureDetected, ranAction

    func text(_ language: AppLanguage) -> String {
        switch (self, language) {
        case (.openTouchPilot, .ru): return "Открыть TouchPilot"
        case (.pauseGestures, .ru): return "Приостановить жесты"
        case (.resumeGestures, .ru): return "Включить жесты"
        case (.quit, .ru): return "Выход"
        case (.on, .ru): return "ВКЛ"
        case (.off, .ru): return "ВЫКЛ"
        case (.addGesture, .ru): return "Жест"
        case (.gestures, .ru): return "Жесты"
        case (.actions, .ru): return "Действия"
        case (.details, .ru): return "Настройка"
        case (.liveLog, .ru): return "Журнал"
        case (.noGestureSelected, .ru): return "Жест не выбран"
        case (.chooseOrCreateGesture, .ru): return "Выберите или создайте жест"
        case (.name, .ru): return "Название"
        case (.gesture, .ru): return "Жест"
        case (.enabled, .ru): return "Включено"
        case (.type, .ru): return "Тип"
        case (.title, .ru): return "Заголовок"
        case (.message, .ru): return "Сообщение"
        case (.url, .ru): return "Ссылка"
        case (.appPath, .ru): return "Путь к приложению"
        case (.shortcut, .ru): return "Сочетание клавиш"
        case (.interfaceLanguage, .ru): return "Язык"
        case (.newGesture, .ru): return "Новый жест"
        case (.gestureDetected, .ru): return "распознан"
        case (.ranAction, .ru): return "Выполнено"
        case (.openTouchPilot, .en): return "Open TouchPilot"
        case (.pauseGestures, .en): return "Pause Gestures"
        case (.resumeGestures, .en): return "Resume Gestures"
        case (.quit, .en): return "Quit"
        case (.on, .en): return "ON"
        case (.off, .en): return "OFF"
        case (.addGesture, .en): return "Gesture"
        case (.gestures, .en): return "Gestures"
        case (.actions, .en): return "Actions"
        case (.details, .en): return "Details"
        case (.liveLog, .en): return "Live Log"
        case (.noGestureSelected, .en): return "No gesture selected"
        case (.chooseOrCreateGesture, .en): return "Choose or create a gesture"
        case (.name, .en): return "Name"
        case (.gesture, .en): return "Gesture"
        case (.enabled, .en): return "Enabled"
        case (.type, .en): return "Type"
        case (.title, .en): return "Title"
        case (.message, .en): return "Message"
        case (.url, .en): return "URL"
        case (.appPath, .en): return "App path"
        case (.shortcut, .en): return "Shortcut"
        case (.interfaceLanguage, .en): return "Language"
        case (.newGesture, .en): return "New Gesture"
        case (.gestureDetected, .en): return "detected"
        case (.ranAction, .en): return "Ran"
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch (self, language) {
        case (.system, .ru): return "Авто"
        case (.light, .ru): return "Светлая"
        case (.dark, .ru): return "Тёмная"
        case (.system, .en): return "Auto"
        case (.light, .en): return "Light"
        case (.dark, .en): return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    func displayTitle(_ language: AppLanguage, effectiveAppearance: NSAppearance.Name?) -> String {
        guard self == .system else { return title(language) }
        let isDark = effectiveAppearance == .darkAqua || effectiveAppearance == .vibrantDark
        switch language {
        case .ru: return isDark ? "Авто: тёмная" : "Авто: светлая"
        case .en: return isDark ? "Auto: Dark" : "Auto: Light"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AccentMode: String, CaseIterable, Identifiable {
    case blue
    case coral

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch (self, language) {
        case (.blue, .ru): return "Синий"
        case (.coral, .ru): return "Коралл"
        case (.blue, .en): return "Blue"
        case (.coral, .en): return "Coral"
        }
    }
}

enum TouchPilotAccent {
    // Midpoint of the coral gradient used by the app icon. It keeps the UI
    // recognizably coral while feeling softer than the previous saturated red.
    private static let softCoral = NSColor(
        calibratedRed: 0.975,
        green: 0.45,
        blue: 0.40,
        alpha: 1.0
    )

    static var color: Color {
        color(for: AccentMode(rawValue: UserDefaults.standard.string(forKey: "TouchPilotAccentMode") ?? "") ?? .coral)
    }

    static var nsColor: NSColor {
        nsColor(for: AccentMode(rawValue: UserDefaults.standard.string(forKey: "TouchPilotAccentMode") ?? "") ?? .coral)
    }

    static func color(for mode: AccentMode) -> Color {
        switch mode {
        case .blue: return Color(nsColor: .systemBlue)
        case .coral: return Color(nsColor: softCoral)
        }
    }

    static func nsColor(for mode: AccentMode) -> NSColor {
        switch mode {
        case .blue: return .systemBlue
        case .coral: return softCoral
        }
    }
}

private struct TouchPilotAccentKey: EnvironmentKey {
    static let defaultValue = TouchPilotAccent.color
}

extension EnvironmentValues {
    var touchPilotAccent: Color {
        get { self[TouchPilotAccentKey.self] }
        set { self[TouchPilotAccentKey.self] = newValue }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "TouchPilotEnabled")
            monitor.isRecognitionEnabled = isEnabled
            refreshMenu?()
        }
    }
    @Published var rules: [GestureRule] {
        didSet {
            save()
            updatePressDragConfiguration()
        }
    }
    @Published var selectedRuleID: UUID?
    @Published var selectedActionID: UUID?
    @Published var showingGestureEditor = false
    @Published var showingActionEditor = false
    @Published var showingSystemActionPicker = false
    @Published var showingCleaningModeSettings = false
    @Published var showingOpenShortcutSettings = false
    @Published var showingTutorial = false
    @Published var log: [String] = []
    @Published var appTargets: [AppTarget] {
        didSet { save() }
    }
    @Published var selectedAppID: String = AppTarget.allApps.id
    @Published var lastActivatedRuleID: UUID?
    @Published var touchEngineStatus: String = "Движок касаний запускается"
    @Published var lastRawTouchAt: Date?
    @Published var rawTouchDeviceCount: Int = 0
    @Published var rawTouchFingerCount: Int = 0
    @Published var accessibilityTrusted: Bool = AXIsProcessTrusted()
    @Published var lastRecognizedGesture: String?
    @Published var lastActionStatus: String?
    @Published private(set) var isCleaningModeActive = false
    @Published private(set) var cleaningUnlockProgress = 0
    @Published var cleaningModeError: String?
    @Published var launchAtLogin: Bool
    @Published var isTestMode: Bool {
        didSet {
            UserDefaults.standard.set(isTestMode, forKey: "TouchPilotTestMode")
        }
    }
    @Published var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: "TouchPilotTheme")
            applyAppearance()
        }
    }
    @Published var accentMode: AccentMode {
        didSet {
            UserDefaults.standard.set(accentMode.rawValue, forKey: "TouchPilotAccentMode")
        }
    }
    @Published var swipeSensitivity: Double {
        didSet {
            let clamped = min(max(swipeSensitivity, 0.4), 2.0)
            if clamped != swipeSensitivity {
                swipeSensitivity = clamped
                return
            }
            UserDefaults.standard.set(swipeSensitivity, forKey: "TouchPilotSwipeSensitivity")
            monitor.swipeSensitivity = swipeSensitivity
        }
    }
    @Published var tapSensitivity: Double {
        didSet {
            let clamped = min(max(tapSensitivity, 0.4), 2.0)
            if clamped != tapSensitivity {
                tapSensitivity = clamped
                return
            }
            UserDefaults.standard.set(tapSensitivity, forKey: "TouchPilotTapSensitivity")
            monitor.tapSensitivity = tapSensitivity
        }
    }
    @Published var tipTapSensitivity: Double {
        didSet {
            let clamped = min(max(tipTapSensitivity, 0.4), 2.0)
            if clamped != tipTapSensitivity {
                tipTapSensitivity = clamped
                return
            }
            UserDefaults.standard.set(tipTapSensitivity, forKey: "TouchPilotTipTapSensitivity")
            monitor.tipTapSensitivity = tipTapSensitivity
        }
    }
    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "TouchPilotLanguage")
            refreshMenu?()
        }
    }
    @Published var openWindowShortcut: String {
        didSet {
            UserDefaults.standard.set(openWindowShortcut, forKey: "TouchPilotOpenWindowShortcut")
            refreshMenu?()
            openShortcutChanged?()
        }
    }

    var openWindow: (() -> Void)?
    var hideWindow: (() -> Void)?
    var refreshMenu: (() -> Void)?
    var openShortcutChanged: (() -> Void)?

    private let store = PresetStore()
    private lazy var monitor = GestureMonitor { [weak self] gesture, modifier in
        Task { @MainActor [weak self] in self?.handle(gesture, modifier: modifier) }
    } onStatus: { [weak self] status, deviceCount in
        Task { @MainActor [weak self] in
            self?.touchEngineStatus = status
            self?.rawTouchDeviceCount = deviceCount
        }
    } onRawTouch: { [weak self] fingerCount in
        Task { @MainActor [weak self] in
            self?.lastRawTouchAt = Date()
            self?.rawTouchFingerCount = fingerCount
        }
    }
    private let executor = ActionExecutor()
    private let cleaningLock = InputCleaningLock()
    private struct PendingActionSequence {
        let rules: [GestureRule]
        let dryRun: Bool
    }
    private var pendingActionSequences: [PendingActionSequence] = []
    private var isRunningActionSequence = false
    private var draftRuleID: UUID?

    init() {
        let legacyDefaults = UserDefaults(suiteName: "local.touchpilot.improved")
        func storedObject(forKey key: String) -> Any? {
            UserDefaults.standard.object(forKey: key) ?? legacyDefaults?.object(forKey: key)
        }
        func storedString(forKey key: String) -> String? {
            UserDefaults.standard.string(forKey: key) ?? legacyDefaults?.string(forKey: key)
        }

        isEnabled = storedObject(forKey: "TouchPilotEnabled") as? Bool ?? true
        let initialLanguage = AppLanguage(rawValue: storedString(forKey: "TouchPilotLanguage") ?? "") ?? .ru
        language = initialLanguage
        theme = AppTheme(rawValue: storedString(forKey: "TouchPilotTheme") ?? "") ?? .system
        accentMode = AccentMode(rawValue: storedString(forKey: "TouchPilotAccentMode") ?? "") ?? .coral
        openWindowShortcut = storedString(forKey: "TouchPilotOpenWindowShortcut") ?? "cmd+shift+o"
        launchAtLogin = SMAppService.mainApp.status == .enabled
        isTestMode = storedObject(forKey: "TouchPilotTestMode") as? Bool ?? false
        let storedSensitivity = storedObject(forKey: "TouchPilotSwipeSensitivity") as? Double ?? 1.0
        swipeSensitivity = min(max(storedSensitivity, 0.4), 2.0)
        let storedTapSensitivity = storedObject(forKey: "TouchPilotTapSensitivity") as? Double ?? 1.0
        tapSensitivity = min(max(storedTapSensitivity, 0.4), 2.0)
        let storedTipTapSensitivity = storedObject(forKey: "TouchPilotTipTapSensitivity") as? Double ?? 1.0
        tipTapSensitivity = min(max(storedTipTapSensitivity, 0.4), 2.0)
        let loadResult = store.load()
        let preset: PilotPreset
        var presetLoadWarning: String?
        var shouldPersistInitialPreset = true
        switch loadResult {
        case .loaded(let loadedPreset, _):
            preset = loadedPreset
        case .missing:
            preset = .sample
        case .unreadable(let sourceURL, let error):
            preset = .sample
            shouldPersistInitialPreset = false
            presetLoadWarning = initialLanguage == .ru
                ? "Файл настроек повреждён и не был перезаписан: \(sourceURL.path). Автосохранение отключено до успешного импорта настроек. \(error.localizedDescription)"
                : "The settings file is damaged and was not overwritten: \(sourceURL.path). Autosave is disabled until settings are imported successfully. \(error.localizedDescription)"
        }
        rules = preset.rules
        appTargets = Self.restoredAppTargets(from: preset)
        selectedRuleID = rules.first?.id
        showingTutorial = !(storedObject(forKey: "TouchPilotTutorialCompleted") as? Bool ?? false)
        lastActionStatus = presetLoadWarning
        if shouldPersistInitialPreset {
            store.save(PilotPreset(rules: rules, appTargets: appTargets))
        }
    }

    var selectedRule: GestureRule? {
        get { currentRules.first { $0.id == selectedRuleID } }
        set {
            guard let newValue, let index = rules.firstIndex(where: { $0.id == newValue.id }) else { return }
            rules[index] = newValue
        }
    }

    var selectedApp: AppTarget {
        appTargets.first { $0.id == selectedAppID } ?? .allApps
    }

    var currentRules: [GestureRule] {
        rules.filter { $0.appBundleID == selectedApp.bundleID }
    }

    var canRemoveSelectedProfile: Bool {
        selectedApp.bundleID != nil && selectedApp.id != AppTarget.finder.id
    }

    func conflicts(for rule: GestureRule) -> [String] {
        ConflictDetector.messages(
            for: rule,
            among: rules,
            openWindowShortcut: openWindowShortcut,
            language: language
        )
    }

    var selectedAction: PilotAction? {
        guard let rule = selectedRule else { return nil }
        return rule.actions.first { $0.id == selectedActionID }
    }

    func start() {
        applyAppearance()
        monitor.isRecognitionEnabled = isEnabled
        monitor.swipeSensitivity = swipeSensitivity
        monitor.tapSensitivity = tapSensitivity
        monitor.tipTapSensitivity = tipTapSensitivity
        updatePressDragConfiguration()
        monitor.start()
        refreshAccessibilityStatus()
    }

    func cycleTheme() {
        switch theme {
        case .system: theme = .light
        case .light: theme = .dark
        case .dark: theme = .system
        }
    }

    func toggleAccentMode() {
        accentMode = accentMode == .coral ? .blue : .coral
    }

    var accentColor: Color {
        TouchPilotAccent.color(for: accentMode)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            lastActionStatus = language == .ru
                ? (launchAtLogin ? "Автозапуск включён" : "Автозапуск выключен")
                : (launchAtLogin ? "Launch at login enabled" : "Launch at login disabled")
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            lastActionStatus = language == .ru
                ? "Не удалось изменить автозапуск: \(error.localizedDescription)"
                : "Could not change launch at login: \(error.localizedDescription)"
        }
    }

    func applyAppearance() {
        switch theme {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    func beginCreatingRule() {
        let rule = GestureRule(name: L.newGesture.text(language), gesture: .twoFingerSwipeRight, appBundleID: selectedApp.bundleID)
        rules.append(rule)
        draftRuleID = rule.id
        selectedRuleID = rule.id
        selectedActionID = nil
        showingGestureEditor = true
    }

    func beginEditingSelectedRule() {
        guard selectedRule != nil else { return }
        draftRuleID = nil
        showingGestureEditor = true
    }

    func cancelGestureEditing() {
        if let draftRuleID {
            rules.removeAll { $0.id == draftRuleID }
            self.draftRuleID = nil
            selectedRuleID = currentRules.first?.id
            selectedActionID = nil
        }
        showingGestureEditor = false
    }

    func saveGestureEditing(_ rule: GestureRule) {
        selectedRule = rule
        draftRuleID = nil
        showingGestureEditor = false
    }

    func deleteSelectedRule() {
        guard let selectedRuleID else { return }
        rules.removeAll { $0.id == selectedRuleID }
        self.selectedRuleID = currentRules.first?.id
        selectedActionID = nil
    }

    func selectApp(_ target: AppTarget) {
        selectedAppID = target.id
        selectedRuleID = currentRules.first?.id
        selectedActionID = nil
    }

    func setSelectedProfileEnabled(_ enabled: Bool) {
        guard selectedApp.bundleID != nil,
              let index = appTargets.firstIndex(where: { $0.id == selectedAppID }) else { return }
        appTargets[index].isEnabled = enabled
    }

    func removeSelectedProfile() {
        guard canRemoveSelectedProfile, let bundleID = selectedApp.bundleID else { return }
        rules.removeAll { $0.appBundleID == bundleID }
        appTargets.removeAll { $0.bundleID == bundleID }
        selectApp(.allApps)
    }

    func showTutorial() {
        cancelGestureEditing()
        showingActionEditor = false
        showingSystemActionPicker = false
        showingCleaningModeSettings = false
        showingOpenShortcutSettings = false
        showingTutorial = true
    }

    func showCleaningModeSettings() {
        refreshAccessibilityStatus()
        cleaningModeError = nil
        cancelGestureEditing()
        showingActionEditor = false
        showingSystemActionPicker = false
        showingOpenShortcutSettings = false
        showingTutorial = false
        showingCleaningModeSettings = true
    }

    func startCleaningMode() {
        refreshAccessibilityStatus()
        guard accessibilityTrusted else {
            cleaningModeError = language == .ru
                ? "Для блокировки ввода разрешите TouchPilot в разделе «Универсальный доступ»."
                : "Allow TouchPilot in Accessibility before locking input."
            requestAccessibilityPermission()
            return
        }
        guard !CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand) else {
            cleaningModeError = language == .ru
                ? "Отпустите обе клавиши Command перед запуском режима очистки."
                : "Release both Command keys before starting cleaning mode."
            return
        }

        cleaningModeError = nil
        let started = cleaningLock.start(
            language: language,
            onProgress: { [weak self] progress in
                self?.cleaningUnlockProgress = progress
            },
            onUnlocked: { [weak self] in
                guard let self else { return }
                isCleaningModeActive = false
                cleaningUnlockProgress = 0
                lastActionStatus = language == .ru
                    ? "Режим очистки выключен"
                    : "Cleaning mode disabled"
            }
        )

        guard started else {
            cleaningModeError = language == .ru
                ? "Не удалось заблокировать ввод. Проверьте разрешение «Универсальный доступ»."
                : "Could not lock input. Check the Accessibility permission."
            return
        }

        showingCleaningModeSettings = false
        isCleaningModeActive = true
        cleaningUnlockProgress = 0
        lastActionStatus = language == .ru ? "Режим очистки включён" : "Cleaning mode enabled"
    }

    func completeTutorial() {
        UserDefaults.standard.set(true, forKey: "TouchPilotTutorialCompleted")
        showingTutorial = false
    }

    func addApplicationTarget(url: URL) {
        let bundle = Bundle(url: url)
        guard let bundleID = bundle?.bundleIdentifier, !bundleID.isEmpty else {
            lastActionStatus = language == .ru
                ? "Приложение не добавлено: в пакете отсутствует bundle identifier"
                : "Application not added: the bundle has no bundle identifier"
            return
        }
        let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        let target = AppTarget(name: name, bundleID: bundleID, iconName: "app")
        if !appTargets.contains(where: { $0.id == target.id }) {
            appTargets.append(target)
        }
        selectApp(target)
    }

    func addAction(to ruleID: UUID, kind: ActionKind) {
        guard let index = rules.firstIndex(where: { $0.id == ruleID }) else { return }
        let action = PilotAction(kind: kind, title: kind.title(language), value: defaultValue(for: kind))
        rules[index].actions.append(action)
        selectedActionID = action.id
    }

    func addSystemAction(to ruleID: UUID, systemAction: SystemAction) {
        guard let index = rules.firstIndex(where: { $0.id == ruleID }) else { return }
        let action = PilotAction(
            kind: .systemAction,
            title: systemAction.title(language),
            value: systemAction.rawValue
        )
        rules[index].actions.append(action)
        selectedActionID = action.id
    }

    func updateAction(_ action: PilotAction) {
        guard let ruleIndex = rules.firstIndex(where: { $0.id == selectedRuleID }),
              let actionIndex = rules[ruleIndex].actions.firstIndex(where: { $0.id == action.id }) else { return }
        rules[ruleIndex].actions[actionIndex] = action
    }

    func deleteSelectedAction() {
        guard let ruleIndex = rules.firstIndex(where: { $0.id == selectedRuleID }),
              let selectedActionID else { return }
        rules[ruleIndex].actions.removeAll { $0.id == selectedActionID }
        self.selectedActionID = rules[ruleIndex].actions.first?.id
    }

    private func handle(_ gesture: GestureKind, modifier: GestureTriggerModifier) {
        guard isEnabled, !isCleaningModeActive else { return }
        let activeBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let activeName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        let triggerTitle = modifier.triggerTitle(for: gesture, language: language)
        lastRecognizedGesture = "\(triggerTitle) • \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium))"
        let globalMatches = rules.filter { rule in
            rule.matches(gesture: gesture, modifier: modifier, appBundleID: nil)
        }
        let profileEnabled = appTargets.first(where: { $0.bundleID == activeBundleID })?.isEnabled ?? true
        let profileMatches = profileEnabled ? rules.filter { rule in
            rule.matches(gesture: gesture, modifier: modifier, appBundleID: activeBundleID)
        } : []
        let matches = profileMatches.isEmpty ? globalMatches : profileMatches
        guard !matches.isEmpty else {
            lastActionStatus = language == .ru
                ? "Распознан «\(triggerTitle)», но для «\(activeName)» нет такого правила"
                : "Detected \"\(triggerTitle)\", but no matching rule exists for \"\(activeName)\""
            appendLog(lastActionStatus ?? "")
            return
        }

        appendLog("\(triggerTitle) \(L.gestureDetected.text(language))")
        pendingActionSequences.append(PendingActionSequence(rules: matches, dryRun: isTestMode))
        guard !isRunningActionSequence else { return }
        isRunningActionSequence = true
        Task { @MainActor [weak self] in
            await self?.drainActionSequences()
        }
    }

    private func drainActionSequences() async {
        while !pendingActionSequences.isEmpty {
            let sequence = pendingActionSequences.removeFirst()
            for rule in sequence.rules {
                lastActivatedRuleID = rule.id
                for action in rule.actions {
                    let result = await executor.perform(action, language: language, dryRun: sequence.dryRun)
                    lastActionStatus = result
                    appendLog("\(L.ranAction.text(language)): \(result) - \(rule.name)")
                }
                if lastActivatedRuleID == rule.id {
                    lastActivatedRuleID = nil
                }
            }
        }
        isRunningActionSequence = false
    }

    func testSelectedRule() {
        guard let rule = selectedRule else { return }
        let triggerTitle = rule.triggerModifier.triggerTitle(for: rule.gesture, language: language)
        lastRecognizedGesture = language == .ru ? "Тест: \(triggerTitle)" : "Test: \(triggerTitle)"
        if rule.actions.isEmpty {
            lastActionStatus = language == .ru ? "В правиле нет действий для проверки" : "The rule has no actions to test"
            appendLog(lastActionStatus ?? "")
            return
        }
        pendingActionSequences.append(PendingActionSequence(rules: [rule], dryRun: true))
        guard !isRunningActionSequence else { return }
        isRunningActionSequence = true
        Task { @MainActor [weak self] in
            await self?.drainActionSequences()
        }
    }

    private func defaultValue(for kind: ActionKind) -> String {
        switch kind {
        case .notification: return language == .ru ? "Жест распознан" : "Gesture detected"
        case .openURL: return "https://www.apple.com"
        case .launchApp: return "/System/Applications/Notes.app"
        case .quitFrontmostApp: return ""
        case .keyboardShortcut: return "cmd+space"
        case .systemAction: return SystemAction.lockScreen.rawValue
        }
    }

    private func save() {
        store.save(PilotPreset(rules: rules, appTargets: appTargets))
    }

    private func updatePressDragConfiguration() {
        monitor.pressDragTriggers = PressDragInterceptionPolicy.triggers(from: rules)
    }

    func exportGestureSettings() {
        do {
            let url = try store.exportToDocuments(PilotPreset(rules: rules, appTargets: appTargets))
            lastActionStatus = language == .ru
                ? "Настройки экспортированы: \(url.path)"
                : "Settings exported: \(url.path)"
            appendLog(lastActionStatus ?? "")
        } catch {
            lastActionStatus = language == .ru
                ? "Не удалось экспортировать настройки: \(error.localizedDescription)"
                : "Could not export settings: \(error.localizedDescription)"
            appendLog(lastActionStatus ?? "")
        }
    }

    func importGestureSettings() {
        do {
            let imported = try store.importFromDocuments()
            let preset = imported.preset
            store.allowSavingAfterRecovery()
            rules = preset.rules
            appTargets = Self.restoredAppTargets(from: preset)
            selectedRuleID = currentRules.first?.id ?? rules.first?.id
            selectedActionID = nil
            lastActionStatus = language == .ru
                ? "Настройки импортированы: \(imported.sourceURL.path)"
                : "Settings imported: \(imported.sourceURL.path)"
            appendLog(lastActionStatus ?? "")
        } catch {
            lastActionStatus = language == .ru
                ? "Не удалось импортировать настройки: \(error.localizedDescription)"
                : "Could not import settings: \(error.localizedDescription)"
            appendLog(lastActionStatus ?? "")
        }
    }

    private func appendLog(_ message: String) {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        log.insert("\(stamp)  \(message)", at: 0)
        if log.count > 80 { log.removeLast(log.count - 80) }
    }

    func refreshAccessibilityStatus() {
        accessibilityTrusted = AXIsProcessTrusted()
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        accessibilityTrusted = AXIsProcessTrustedWithOptions(options)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private static func restoredAppTargets(from preset: PilotPreset) -> [AppTarget] {
        var targets: [AppTarget] = [.allApps, .finder]
        var knownIDs = Set(targets.compactMap(\.bundleID))

        for target in preset.appTargets {
            guard let bundleID = target.bundleID,
                  !bundleID.isEmpty else { continue }
            if let existingIndex = targets.firstIndex(where: { $0.bundleID == bundleID }) {
                targets[existingIndex].isEnabled = target.isEnabled
                continue
            }
            targets.append(target)
            knownIDs.insert(bundleID)
        }

        for bundleID in preset.rules.compactMap(\.appBundleID) where !knownIDs.contains(bundleID) {
            let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            let bundle = appURL.flatMap(Bundle.init(url:))
            let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? appURL?.deletingPathExtension().lastPathComponent
                ?? bundleID
            targets.append(AppTarget(name: name, bundleID: bundleID, iconName: "app"))
            knownIDs.insert(bundleID)
        }

        return targets
    }
}

final class PresetStore {
    enum PresetSource {
        case current
        case legacy
    }

    enum LoadResult {
        case loaded(PilotPreset, PresetSource)
        case missing
        case unreadable(URL, Error)
    }

    enum StoreError: LocalizedError {
        case missingImportFiles([URL])

        var errorDescription: String? {
            switch self {
            case .missingImportFiles(let urls):
                return "Файл настроек не найден. Проверены пути: \(urls.map(\.path).joined(separator: ", "))"
            }
        }
    }

    private let fileManager: FileManager
    private let applicationSupportBaseURL: URL
    private let documentsBaseURL: URL
    private var savingBlockedByUnreadablePreset = false

    init(
        fileManager: FileManager = .default,
        applicationSupportBaseURL: URL? = nil,
        documentsBaseURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.applicationSupportBaseURL = applicationSupportBaseURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.documentsBaseURL = documentsBaseURL
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var folderURL: URL {
        applicationSupportBaseURL.appendingPathComponent("TouchPilot", isDirectory: true)
    }

    private var url: URL {
        folderURL.appendingPathComponent("preset.json")
    }

    private var legacyURL: URL {
        applicationSupportBaseURL
            .appendingPathComponent("TouchPilot-Improved", isDirectory: true)
            .appendingPathComponent("preset.json")
    }

    private var documentsFolderURL: URL {
        documentsBaseURL.appendingPathComponent("TouchPilot", isDirectory: true)
    }

    private var documentsPresetURL: URL {
        documentsFolderURL.appendingPathComponent("TouchPilotGestures.json")
    }

    private var legacyDocumentsPresetURL: URL {
        documentsBaseURL
            .appendingPathComponent("TouchPilot-Improved", isDirectory: true)
            .appendingPathComponent("TouchPilotGestures.json")
    }

    func load() -> LoadResult {
        for (sourceURL, source) in [(url, PresetSource.current), (legacyURL, PresetSource.legacy)] {
            guard fileManager.fileExists(atPath: sourceURL.path) else { continue }
            do {
                let data = try Data(contentsOf: sourceURL)
                let preset = try JSONDecoder().decode(PilotPreset.self, from: data)
                savingBlockedByUnreadablePreset = false
                return .loaded(preset, source)
            } catch {
                savingBlockedByUnreadablePreset = true
                return .unreadable(sourceURL, error)
            }
        }
        savingBlockedByUnreadablePreset = false
        return .missing
    }

    func save(_ preset: PilotPreset) {
        guard !savingBlockedByUnreadablePreset else { return }
        guard let data = try? JSONEncoder.pretty.encode(preset) else { return }
        try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    func allowSavingAfterRecovery() {
        savingBlockedByUnreadablePreset = false
    }

    func exportToDocuments(_ preset: PilotPreset) throws -> URL {
        try fileManager.createDirectory(at: documentsFolderURL, withIntermediateDirectories: true)
        let data = try JSONEncoder.pretty.encode(preset)
        try data.write(to: documentsPresetURL, options: .atomic)
        return documentsPresetURL
    }

    func importFromDocuments() throws -> (preset: PilotPreset, sourceURL: URL) {
        let candidates = [documentsPresetURL, legacyDocumentsPresetURL]
        guard let sourceURL = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }) else {
            throw StoreError.missingImportFiles(candidates)
        }
        let data = try Data(contentsOf: sourceURL)
        let preset = try JSONDecoder().decode(PilotPreset.self, from: data)
        return (preset, sourceURL)
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private typealias TPDeviceRef = UnsafeMutableRawPointer
private typealias TPContactCallback = @convention(c) (TPDeviceRef?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Void
private typealias TPDeviceCreateListFunc = @convention(c) () -> Unmanaged<CFArray>
private typealias TPRegisterContactFrameCallbackFunc = @convention(c) (TPDeviceRef, TPContactCallback) -> Void
private typealias TPDeviceStartFunc = @convention(c) (TPDeviceRef, Int32) -> Void

private final class MultitouchRuntime: @unchecked Sendable {
    let framework: UnsafeMutableRawPointer?
    let createDeviceList: TPDeviceCreateListFunc?
    let registerContactFrameCallback: TPRegisterContactFrameCallbackFunc?
    let startDevice: TPDeviceStartFunc?

    init() {
        framework = dlopen(
            "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
            RTLD_LAZY
        )
        createDeviceList = Self.loadSymbol("MTDeviceCreateList", from: framework, as: TPDeviceCreateListFunc.self)
        registerContactFrameCallback = Self.loadSymbol(
            "MTRegisterContactFrameCallback",
            from: framework,
            as: TPRegisterContactFrameCallbackFunc.self
        )
        startDevice = Self.loadSymbol("MTDeviceStart", from: framework, as: TPDeviceStartFunc.self)
    }

    deinit {
        if let framework {
            dlclose(framework)
        }
    }

    private static func loadSymbol<T>(_ name: String, from framework: UnsafeMutableRawPointer?, as type: T.Type) -> T? {
        guard let framework, let symbol = dlsym(framework, name) else { return nil }
        return unsafeBitCast(symbol, to: type)
    }
}

private final class GestureMonitorCallbackBridge: @unchecked Sendable {
    private let lock = NSLock()
    private weak var monitor: GestureMonitor?

    func install(_ monitor: GestureMonitor) {
        lock.lock()
        self.monitor = monitor
        lock.unlock()
    }

    func forward(rawTouches: UnsafeMutableRawPointer?, touchCount: Int, timestamp: Double) {
        lock.lock()
        let monitor = self.monitor
        lock.unlock()
        monitor?.handleRawTouchFrame(rawTouches: rawTouches, touchCount: touchCount, timestamp: timestamp)
    }
}

private let multitouchRuntime = MultitouchRuntime()
private let gestureMonitorCallbackBridge = GestureMonitorCallbackBridge()

private let tpTouchCallback: TPContactCallback = { _, touches, count, timestamp, _ in
    gestureMonitorCallbackBridge.forward(rawTouches: touches, touchCount: Int(count), timestamp: timestamp)
}

struct PressDragTrigger: Hashable, Sendable {
    let fingerCount: Int
    let modifier: GestureTriggerModifier
}

enum PressDragInterceptionPolicy {
    static func triggers(from rules: [GestureRule]) -> Set<PressDragTrigger> {
        Set(rules.lazy.compactMap { rule in
            guard rule.isEnabled, let fingerCount = rule.gesture.pressDragFingerCount else { return nil }
            return PressDragTrigger(fingerCount: fingerCount, modifier: rule.triggerModifier)
        })
    }

    static func shouldIntercept(
        fingerCount: Int,
        modifier: GestureTriggerModifier,
        configuredTriggers: Set<PressDragTrigger>
    ) -> Bool {
        configuredTriggers.contains(PressDragTrigger(fingerCount: fingerCount, modifier: modifier))
    }
}

final class GestureMonitor: @unchecked Sendable {
    private let callback: @Sendable (GestureKind, GestureTriggerModifier) -> Void
    private let statusCallback: @Sendable (String, Int) -> Void
    private let rawTouchCallback: @Sendable (Int) -> Void
    private let stateLock = NSRecursiveLock()
    private var storedSwipeSensitivity: Double = 1.0
    private var storedTapSensitivity: Double = 1.0
    private var storedTipTapSensitivity: Double = 1.0
    private var storedPressDragTriggers: Set<PressDragTrigger> = []
    private var storedRecognitionEnabled = true
    private var hasStarted = false
    var swipeSensitivity: Double {
        get { locked { storedSwipeSensitivity } }
        set { locked { storedSwipeSensitivity = newValue } }
    }
    var tapSensitivity: Double {
        get { locked { storedTapSensitivity } }
        set { locked { storedTapSensitivity = newValue } }
    }
    var tipTapSensitivity: Double {
        get { locked { storedTipTapSensitivity } }
        set { locked { storedTipTapSensitivity = newValue } }
    }
    var pressDragTriggers: Set<PressDragTrigger> {
        get { locked { storedPressDragTriggers } }
        set {
            locked { storedPressDragTriggers = newValue }
            refreshPressInterceptionOnMainQueue()
        }
    }
    var isRecognitionEnabled: Bool {
        get { locked { storedRecognitionEnabled } }
        set {
            locked { storedRecognitionEnabled = newValue }
            refreshPressInterceptionOnMainQueue()
        }
    }
    private var monitors: [Any] = []
    private var pressEventTap: CFMachPort?
    private var pressRunLoopSource: CFRunLoopSource?
    private var physicalButtonPressed = false
    private var interceptedPress = false
    private var lastInterceptedFingerCount: Int?
    private var pressInterceptionGraceUntil = Date.distantPast
    private var lastFire = Date.distantPast
    private var gestureSuppressedUntil = Date.distantPast
    private var lastPublicSwipeAt = Date.distantPast
    private var lastPublicSwipeGesture: GestureKind?
    private var devices: [TPDeviceRef] = []
    private var touchStride = 0
    private var currentFingers = 0
    private var peakFingers = 0
    private var lastObservedFingerCount = 0
    private var lastObservedFingerAt = Date.distantPast
    private var touchBegan: Date?
    private var sessionStartPositions: [Int32: (Float, Float)] = [:]
    private var sessionStartCentroid: (x: Float, y: Float)?
    private var sessionLastCentroid: (x: Float, y: Float)?
    private var sessionMinSpread: Float?
    private var sessionMaxSpread: Float?
    private var rawSwipeFired = false
    private var rawGestureConsumed = false
    private var swipeSessionEligible = false
    private var lastMultiFingerTouchAt = Date.distantPast
    private var previousPositions: [Int32: (Float, Float)] = [:]
    private var totalMovement: Float = 0
    private var centroidMovement: Float = 0
    private var lastTwoFingerTapTime: Date?
    private var doubleTapTimer: DispatchWorkItem?
    private var tipTapRestStartedAt: Date?
    private var tipTapRestPositions: [Int32: (x: Float, y: Float)] = [:]
    private var armedTipTap: (gesture: GestureKind, fingerCount: Int, startedAt: Date)?
    private var lastSingleFingerPos: (x: Float, y: Float)?
    private var wasPressed = false
    private var pressDragFingerCount: Int?
    private var pressDragStartCentroid: (x: Float, y: Float)?
    private var pressDragMaximumTravel: Float = 0
    private var pressDragFired = false
    private var circlePoints: [(x: Float, y: Float)] = []
    private var circleFired = false
    private var trianglePoints: [(x: Float, y: Float)] = []
    private var triangleFired = false
    private var edgeSlideStartY: Float?
    private var edgeSlideSide: TrackpadEdge?
    private var edgeSlideFingerID: Int32?

    init(
        callback: @escaping @Sendable (GestureKind, GestureTriggerModifier) -> Void,
        onStatus: @escaping @Sendable (String, Int) -> Void,
        onRawTouch: @escaping @Sendable (Int) -> Void
    ) {
        self.callback = callback
        self.statusCallback = onStatus
        self.rawTouchCallback = onRawTouch
        let storedStride = UserDefaults.standard.integer(forKey: "TouchPilotRawTouchStride")
        if Self.supportedTouchStrides.contains(storedStride) {
            touchStride = storedStride
        }
    }

    private func locked<T>(_ operation: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return operation()
    }

    func start() {
        locked { hasStarted = true }
        refreshPressInterception()
        let mask: NSEvent.EventTypeMask = [.scrollWheel, .magnify, .rotate]
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in self?.handle(event) } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        } as Any)
        startRawTouchMonitoring()
    }

    private func startPressInterception() {
        guard pressEventTap == nil else { return }
        let eventTypes: [CGEventType] = [
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp, .leftMouseDragged, .rightMouseDragged,
            .otherMouseDragged, .scrollWheel
        ]
        let eventMask = eventTypes.reduce(CGEventMask(0)) { mask, type in
            mask | (CGEventMask(1) << type.rawValue)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<GestureMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                return monitor.handlePressEventTap(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("[TouchPilot] Press-drag interception unavailable; Accessibility permission may be missing")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        pressEventTap = tap
        pressRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stopPressInterception() {
        stateLock.lock()
        physicalButtonPressed = false
        interceptedPress = false
        lastInterceptedFingerCount = nil
        pressInterceptionGraceUntil = .distantPast
        stateLock.unlock()

        if let source = pressRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = pressEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        pressRunLoopSource = nil
        pressEventTap = nil
    }

    private func refreshPressInterceptionOnMainQueue() {
        DispatchQueue.main.async { [weak self] in
            self?.refreshPressInterception()
        }
    }

    private func refreshPressInterception() {
        let shouldRun = locked {
            hasStarted && storedRecognitionEnabled && !storedPressDragTriggers.isEmpty
        }
        if shouldRun {
            startPressInterception()
        } else {
            stopPressInterception()
        }
    }

    private func handlePressEventTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        stateLock.lock()
        defer { stateLock.unlock() }

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let pressEventTap { CGEvent.tapEnable(tap: pressEventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            let eventModifier: GestureTriggerModifier = event.flags.contains(.maskCommand) ? .command : .none
            let recentFingers: Int
            if type == .rightMouseDown,
               PressDragInterceptionPolicy.shouldIntercept(
                   fingerCount: 2,
                   modifier: eventModifier,
                   configuredTriggers: storedPressDragTriggers
               ) {
                // macOS represents a physical two-finger click as a right click.
                recentFingers = 2
            } else if currentFingers > 0 {
                recentFingers = currentFingers
            } else if Date().timeIntervalSince(lastObservedFingerAt) < 0.35 {
                recentFingers = lastObservedFingerCount
            } else if Date() < pressInterceptionGraceUntil, let lastInterceptedFingerCount {
                recentFingers = lastInterceptedFingerCount
            } else {
                recentFingers = 0
            }
            guard PressDragInterceptionPolicy.shouldIntercept(
                fingerCount: recentFingers,
                modifier: eventModifier,
                configuredTriggers: storedPressDragTriggers
            ) else {
                return Unmanaged.passUnretained(event)
            }
            physicalButtonPressed = true
            interceptedPress = true
            lastInterceptedFingerCount = recentFingers
            return nil
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            guard interceptedPress else { return Unmanaged.passUnretained(event) }
            physicalButtonPressed = false
            interceptedPress = false
            pressInterceptionGraceUntil = Date().addingTimeInterval(0.55)
            return nil
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel:
            return interceptedPress ? nil : Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func startRawTouchMonitoring() {
        guard let createList = multitouchRuntime.createDeviceList,
              let register = multitouchRuntime.registerContactFrameCallback,
              let start = multitouchRuntime.startDevice else {
            NSLog("[TouchPilot] MultitouchSupport.framework is not available")
            statusCallback("Движок касаний недоступен", 0)
            return
        }

        gestureMonitorCallbackBridge.install(self)
        let deviceList = createList().takeRetainedValue()
        let count = CFArrayGetCount(deviceList)
        guard count > 0 else {
            NSLog("[TouchPilot] No multitouch devices found")
            statusCallback("Трекпад не найден", 0)
            return
        }

        for index in 0..<count {
            guard let device = CFArrayGetValueAtIndex(deviceList, index) else { continue }
            let deviceRef = UnsafeMutableRawPointer(mutating: device)
            register(deviceRef, tpTouchCallback)
            start(deviceRef, 0)
            devices.append(deviceRef)
        }
        NSLog("[TouchPilot] Raw multitouch monitoring active on \(devices.count) device(s)")
        statusCallback("Движок касаний активен", devices.count)
    }

    private func handle(_ event: NSEvent) {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard Date() >= gestureSuppressedUntil else { return }
        guard !physicalButtonPressed && NSEvent.pressedMouseButtons == 0 else { return }
        let gesture: GestureKind?
        switch event.type {
        case .scrollWheel:
            guard Date().timeIntervalSince(lastFire) > 0.28 else { return }
            guard recentFingerCountForPublicEvent() < 3 else { return }
            guard !isThreeFingerSystemSwipe(event) else {
                suppressSystemGestureConflict()
                return
            }
            gesture = swipeGesture(for: event)
        case .magnify:
            guard Date().timeIntervalSince(lastFire) > 0.16 else { return }
            guard recentFingerCountForPublicEvent() < 3 else {
                suppressSystemGestureConflict()
                return
            }
            gesture = event.magnification > 0.08 ? .twoFingerPinchOut : event.magnification < -0.08 ? .twoFingerPinchIn : nil
        case .rotate:
            guard Date().timeIntervalSince(lastFire) > 0.16 else { return }
            gesture = event.rotation > 8 ? .twoFingerRotateRight : event.rotation < -8 ? .twoFingerRotateLeft : nil
        default:
            gesture = nil
        }

        guard let gesture else { return }
        if isSwipe(gesture),
           let lastPublicSwipeGesture,
           oppositeSwipe(of: gesture) == lastPublicSwipeGesture,
           Date().timeIntervalSince(lastPublicSwipeAt) < 0.75 {
            return
        }
        if isSwipe(gesture) {
            lastPublicSwipeAt = Date()
            lastPublicSwipeGesture = gesture
        }
        lastFire = Date()
        gestureSuppressedUntil = Date().addingTimeInterval(0.65)
        callback(gesture, GestureTriggerModifier.from(eventFlags: event.modifierFlags))
    }

    private func isSwipe(_ gesture: GestureKind) -> Bool {
        switch gesture {
        case .twoFingerSwipeUp, .twoFingerSwipeDown, .twoFingerSwipeLeft, .twoFingerSwipeRight,
             .threeFingerSwipeUp, .threeFingerSwipeDown, .threeFingerSwipeLeft, .threeFingerSwipeRight,
             .fourFingerSwipeUp, .fourFingerSwipeDown, .fourFingerSwipeLeft, .fourFingerSwipeRight:
            return true
        default:
            return false
        }
    }

    private func oppositeSwipe(of gesture: GestureKind) -> GestureKind? {
        switch gesture {
        case .twoFingerSwipeUp: return .twoFingerSwipeDown
        case .twoFingerSwipeDown: return .twoFingerSwipeUp
        case .twoFingerSwipeLeft: return .twoFingerSwipeRight
        case .twoFingerSwipeRight: return .twoFingerSwipeLeft
        case .threeFingerSwipeUp: return .threeFingerSwipeDown
        case .threeFingerSwipeDown: return .threeFingerSwipeUp
        case .threeFingerSwipeLeft: return .threeFingerSwipeRight
        case .threeFingerSwipeRight: return .threeFingerSwipeLeft
        case .fourFingerSwipeUp: return .fourFingerSwipeDown
        case .fourFingerSwipeDown: return .fourFingerSwipeUp
        case .fourFingerSwipeLeft: return .fourFingerSwipeRight
        case .fourFingerSwipeRight: return .fourFingerSwipeLeft
        default: return nil
        }
    }

    private func swipeGesture(for event: NSEvent) -> GestureKind? {
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        guard max(abs(dx), abs(dy)) > 8 else { return nil }
        let fingers = max(recentFingerCountForPublicEvent(), 2)
        if abs(dx) > abs(dy) {
            return swipeGesture(fingers: fingers, horizontal: dx > 0 ? .right : .left)
        }
        return swipeGesture(fingers: fingers, vertical: dy > 0 ? .up : .down)
    }

    private func recentFingerCountForPublicEvent() -> Int {
        if currentFingers > 0 { return currentFingers }
        if Date().timeIntervalSince(lastObservedFingerAt) < 0.45 {
            return lastObservedFingerCount
        }
        return currentFingers
    }

    private func isThreeFingerSystemSwipe(_ event: NSEvent) -> Bool {
        guard currentFingers == 3 else { return false }
        return abs(event.scrollingDeltaX) > max(abs(event.scrollingDeltaY) * 1.25, 6)
    }

    private enum HorizontalDirection { case left, right }
    private enum VerticalDirection { case up, down }

    private func swipeGesture(fingers: Int, horizontal direction: HorizontalDirection) -> GestureKind? {
        switch (min(max(fingers, 2), 4), direction) {
        case (2, .left): return .twoFingerSwipeLeft
        case (2, .right): return .twoFingerSwipeRight
        case (3, .left): return .threeFingerSwipeLeft
        case (3, .right): return .threeFingerSwipeRight
        case (4, .left): return .fourFingerSwipeLeft
        case (4, .right): return .fourFingerSwipeRight
        default: return nil
        }
    }

    private func swipeGesture(fingers: Int, vertical direction: VerticalDirection) -> GestureKind? {
        switch (min(max(fingers, 2), 4), direction) {
        case (2, .up): return .twoFingerSwipeUp
        case (2, .down): return .twoFingerSwipeDown
        case (3, .up): return .threeFingerSwipeUp
        case (3, .down): return .threeFingerSwipeDown
        case (4, .up): return .fourFingerSwipeUp
        case (4, .down): return .fourFingerSwipeDown
        default: return nil
        }
    }

    private static let offsetFingerID = 24
    private static let offsetNormX = 32
    private static let offsetNormY = 36
    private static let offsetMajorAxis = 52
    private static let supportedTouchStrides = [80, 84, 88, 92, 96, 104, 112, 120, 128]
    private static let defaultTouchStride = 80

    func handleRawTouchFrame(rawTouches: UnsafeMutableRawPointer?, touchCount: Int, timestamp: Double) {
        stateLock.lock()
        defer { stateLock.unlock() }
        let previousFingers = currentFingers

        let touches = readTouches(rawTouches, touchCount: touchCount)
        currentFingers = touches.count
        rawTouchCallback(currentFingers)
        if currentFingers > 0 {
            lastObservedFingerCount = currentFingers
            lastObservedFingerAt = Date()
        }
        let pressed = physicalButtonPressed || NSEvent.pressedMouseButtons != 0

        if currentFingers > 0 && previousFingers == 0 {
            beginTouchSession(touches: touches)
        }
        if currentFingers > peakFingers { peakFingers = currentFingers }
        if currentFingers >= 2 {
            lastMultiFingerTouchAt = Date()
            armSwipeSessionIfNeeded(touches: touches)
            rebaseSwipeForAdditionalFingers(touches: touches, previousFingers: previousFingers)
        }
        trackMovement(touches)
        trackCentroid(touches)
        trackSpreadRange(touches)
        detectPressDrag(touches: touches, pressed: pressed)

        if currentFingers == 1, let first = touches.first {
            lastSingleFingerPos = (first.x, first.y)
            trackSingleFingerDrawing(first)
            trackEdgeSlide(first, pressed: pressed)
        } else {
            if currentFingers == 0, previousFingers == 1 {
                detectCircle()
                detectTriangle()
            }
            lastSingleFingerPos = nil
            resetDrawingState()
            edgeSlideStartY = nil
            edgeSlideSide = nil
            edgeSlideFingerID = nil
        }

        detectClickOnPress(fingerCount: currentFingers, pressed: pressed)
        detectTipTap(touches: touches, previousFingers: previousFingers)
        detectRawSwipeInProgress()
        detectRawSwipeOnEnd(previousFingers: previousFingers)
        detectRegularTap(previousFingers: previousFingers)

        wasPressed = pressed
    }

    private func beginTouchSession(touches: [(fingerID: Int32, x: Float, y: Float, majorAxis: Float)]) {
        touchBegan = Date()
        peakFingers = currentFingers
        totalMovement = 0
        centroidMovement = 0
        rawSwipeFired = false
        rawGestureConsumed = false
        swipeSessionEligible = currentFingers >= 2 && currentFingers <= 4
        sessionStartPositions.removeAll()
        for touch in touches where sessionStartPositions[touch.fingerID] == nil {
            sessionStartPositions[touch.fingerID] = (touch.x, touch.y)
        }
        sessionStartCentroid = centroid(of: touches)
        sessionLastCentroid = sessionStartCentroid
        let spread = spread(of: touches)
        sessionMinSpread = spread
        sessionMaxSpread = spread
        previousPositions.removeAll()
        circlePoints.removeAll()
        trianglePoints.removeAll()
        circleFired = false
        triangleFired = false
        resetPressDragState()
        resetTipTapRecognition()
    }

    private func armSwipeSessionIfNeeded(touches: [(fingerID: Int32, x: Float, y: Float, majorAxis: Float)]) {
        guard !swipeSessionEligible,
              currentFingers >= 2,
              currentFingers <= 4,
              let began = touchBegan,
              Date().timeIntervalSince(began) < 0.18,
              !rawGestureConsumed,
              let centroid = centroid(of: touches) else { return }

        swipeSessionEligible = true
        rawSwipeFired = false
        rawGestureConsumed = false
        peakFingers = max(peakFingers, currentFingers)
        sessionStartCentroid = centroid
        sessionLastCentroid = centroid
        let spread = spread(of: touches)
        sessionMinSpread = spread
        sessionMaxSpread = spread
        centroidMovement = 0
        sessionStartPositions.removeAll()
        for touch in touches where sessionStartPositions[touch.fingerID] == nil {
            sessionStartPositions[touch.fingerID] = (touch.x, touch.y)
        }
    }

    private func rebaseSwipeForAdditionalFingers(
        touches: [(fingerID: Int32, x: Float, y: Float, majorAxis: Float)],
        previousFingers: Int
    ) {
        guard swipeSessionEligible,
              currentFingers > previousFingers,
              currentFingers >= 3,
              currentFingers <= 4,
              !rawGestureConsumed,
              let center = centroid(of: touches) else { return }

        sessionStartCentroid = center
        sessionLastCentroid = center
        centroidMovement = 0
        sessionStartPositions.removeAll()
        previousPositions.removeAll()
        for touch in touches where sessionStartPositions[touch.fingerID] == nil {
            sessionStartPositions[touch.fingerID] = (touch.x, touch.y)
            previousPositions[touch.fingerID] = (touch.x, touch.y)
        }
        let currentSpread = spread(of: touches)
        sessionMinSpread = currentSpread
        sessionMaxSpread = currentSpread
    }

    private func readTouches(_ rawTouches: UnsafeMutableRawPointer?, touchCount: Int) -> [(fingerID: Int32, x: Float, y: Float, majorAxis: Float)] {
        guard let rawTouches, touchCount > 0, touchCount <= 20 else { return [] }
        if touchStride == 0 && touchCount >= 3 {
            touchStride = detectTouchStride(raw: rawTouches)
            UserDefaults.standard.set(touchStride, forKey: "TouchPilotRawTouchStride")
            NSLog("[TouchPilot] Safely detected raw touch stride: \(touchStride)")
        }
        let stride = touchStride > 0 ? touchStride : Self.defaultTouchStride
        return decodeTouches(rawTouches, touchCount: touchCount, stride: stride)
    }

    private func decodeTouches(
        _ rawTouches: UnsafeMutableRawPointer,
        touchCount: Int,
        stride: Int
    ) -> [(fingerID: Int32, x: Float, y: Float, majorAxis: Float)] {
        return (0..<touchCount).map { index in
            let offset = index * stride
            return (
                rawTouches.load(fromByteOffset: offset + Self.offsetFingerID, as: Int32.self),
                rawTouches.load(fromByteOffset: offset + Self.offsetNormX, as: Float.self),
                rawTouches.load(fromByteOffset: offset + Self.offsetNormY, as: Float.self),
                rawTouches.load(fromByteOffset: offset + Self.offsetMajorAxis, as: Float.self)
            )
        }.filter { $0.x >= 0 && $0.x <= 1.2 && $0.y >= 0 && $0.y <= 1.2 }
    }

    private func detectTouchStride(raw: UnsafeMutableRawPointer) -> Int {
        let frame0 = raw.load(fromByteOffset: 0, as: Int32.self)
        for candidate in Self.supportedTouchStrides {
            let frame1 = raw.load(fromByteOffset: candidate, as: Int32.self)
            let x = raw.load(fromByteOffset: candidate + Self.offsetNormX, as: Float.self)
            let y = raw.load(fromByteOffset: candidate + Self.offsetNormY, as: Float.self)
            if frame1 == frame0 && x >= 0 && x <= 1.5 && y >= 0 && y <= 1.5 {
                return candidate
            }
        }
        return Self.defaultTouchStride
    }

    private func trackMovement(_ touches: [(fingerID: Int32, x: Float, y: Float, majorAxis: Float)]) {
        var frameTouches: [Int32: (x: Float, y: Float)] = [:]
        for touch in touches where frameTouches[touch.fingerID] == nil {
            frameTouches[touch.fingerID] = (touch.x, touch.y)
        }

        for (fingerID, touch) in frameTouches {
            if let previous = previousPositions[fingerID] {
                totalMovement += abs(touch.x - previous.0) + abs(touch.y - previous.1)
            }
            previousPositions[fingerID] = (touch.x, touch.y)
        }
    }

    private func trackCentroid(_ touches: [(fingerID: Int32, x: Float, y: Float, majorAxis: Float)]) {
        guard let centroid = centroid(of: touches) else { return }
        if sessionStartCentroid == nil { sessionStartCentroid = centroid }
        if let previous = sessionLastCentroid {
            centroidMovement += abs(centroid.x - previous.x) + abs(centroid.y - previous.y)
        }
        if !swipeSessionEligible || currentFingers >= 2 {
            sessionLastCentroid = centroid
        }
    }

    private func trackSpreadRange(_ touches: [(fingerID: Int32, x: Float, y: Float, majorAxis: Float)]) {
        guard currentFingers >= 3, let spread = spread(of: touches), spread > 0.001 else { return }
        sessionMinSpread = min(sessionMinSpread ?? spread, spread)
        sessionMaxSpread = max(sessionMaxSpread ?? spread, spread)
    }

    private func centroid(of touches: [(fingerID: Int32, x: Float, y: Float, majorAxis: Float)]) -> (x: Float, y: Float)? {
        guard !touches.isEmpty else { return nil }
        var uniqueTouches: [Int32: (x: Float, y: Float)] = [:]
        for touch in touches where uniqueTouches[touch.fingerID] == nil {
            uniqueTouches[touch.fingerID] = (touch.x, touch.y)
        }
        let points = uniqueTouches.count < min(touches.count, 2)
            ? touches.map { ($0.x, $0.y) }
            : uniqueTouches.values.map { ($0.x, $0.y) }
        let count = Float(points.count)
        return (
            points.reduce(Float(0)) { $0 + $1.0 } / count,
            points.reduce(Float(0)) { $0 + $1.1 } / count
        )
    }

    private func spread(of touches: [(fingerID: Int32, x: Float, y: Float, majorAxis: Float)]) -> Float? {
        guard touches.count >= 3 else { return nil }
        var uniqueTouches: [Int32: (x: Float, y: Float)] = [:]
        for touch in touches where uniqueTouches[touch.fingerID] == nil {
            uniqueTouches[touch.fingerID] = (touch.x, touch.y)
        }
        let points = uniqueTouches.count < min(touches.count, 3)
            ? touches.map { ($0.x, $0.y) }
            : uniqueTouches.values.map { ($0.x, $0.y) }
        guard points.count >= 3 else { return nil }
        return averagePairwiseDistance(points)
    }

    private func detectClickOnPress(fingerCount: Int, pressed: Bool) {
        guard pressed && !wasPressed else { return }
        switch fingerCount {
        case 1:
            guard peakFingers <= 1,
                  centroidMovement < 0.035,
                  Date().timeIntervalSince(lastMultiFingerTouchAt) > 0.55 else { return }
            if let pos = lastSingleFingerPos,
               let gesture = TrackpadZoneGestureRecognizer.gesture(for: pos) {
                fire(gesture)
            }
        default:
            break
        }
    }

    private func detectPressDrag(
        touches: [(fingerID: Int32, x: Float, y: Float, majorAxis: Float)],
        pressed: Bool
    ) {
        if pressed && !wasPressed {
            guard (currentFingers == 2 || currentFingers == 3),
                  let center = centroid(of: touches) else {
                resetPressDragState()
                return
            }
            pressDragFingerCount = currentFingers
            pressDragStartCentroid = center
            pressDragMaximumTravel = 0
            pressDragFired = false
            swipeSessionEligible = false
            resetTipTapRecognition()
            return
        }

        if !pressed && wasPressed {
            if !pressDragFired,
               let fingerCount = pressDragFingerCount,
               pressDragMaximumTravel < 0.04 {
                switch fingerCount {
                case 2: fire(.twoFingerClick)
                case 3: fire(.threeFingerClick)
                default: break
                }
            }
            resetPressDragState()
            return
        }

        guard pressed,
              !pressDragFired,
              let fingerCount = pressDragFingerCount,
              currentFingers == fingerCount,
              let start = pressDragStartCentroid,
              let current = centroid(of: touches) else { return }

        let dx = current.x - start.x
        let dy = current.y - start.y
        pressDragMaximumTravel = max(pressDragMaximumTravel, hypot(dx, dy))
        let sensitivity = Float(sqrt(min(max(swipeSensitivity, 0.4), 2.0)))
        guard let gesture = PressDragGestureRecognizer.gesture(
            fingerCount: fingerCount,
            dx: dx,
            dy: dy,
            threshold: 0.045 / sensitivity
        ) else { return }

        pressDragFired = true
        fire(gesture)
    }

    private func resetPressDragState() {
        pressDragFingerCount = nil
        pressDragStartCentroid = nil
        pressDragMaximumTravel = 0
        pressDragFired = false
    }

    private func detectTipTap(touches: [(fingerID: Int32, x: Float, y: Float, majorAxis: Float)], previousFingers: Int) {
        let sensitivity = min(max(tipTapSensitivity, 0.4), 2.0)
        let responseScale = sqrt(sensitivity)
        let now = Date()
        let minRestTime = 0.12 / responseScale
        let minContactTime = 0.035 / responseScale
        let maxRestMovement = Float(0.06 * responseScale)
        let framePositions = uniqueTouchPositions(touches)

        if let armedTipTap {
            guard currentFingers == armedTipTap.fingerCount else {
                self.armedTipTap = nil
                updateTipTapRestState(framePositions: framePositions, now: now, maxMovement: maxRestMovement)
                return
            }
            if now.timeIntervalSince(armedTipTap.startedAt) >= minContactTime {
                fire(armedTipTap.gesture)
                resetTipTapRecognition()
            }
            return
        }

        if (previousFingers == 1 && currentFingers == 2)
            || (previousFingers == 2 && currentFingers == 3) {
            let baseCount = previousFingers
            if let restStartedAt = tipTapRestStartedAt,
               now.timeIntervalSince(restStartedAt) >= minRestTime,
               tipTapRestPositions.count == baseCount,
               let tappingFinger = touches.first(where: { tipTapRestPositions[$0.fingerID] == nil }),
               let gesture = tipTapGesture(
                   basePositions: tipTapRestPositions,
                   tappingX: tappingFinger.x,
                   sensitivityScale: responseScale
               ) {
                armedTipTap = (gesture, currentFingers, now)
                return
            }
        }

        updateTipTapRestState(
            framePositions: framePositions,
            now: now,
            maxMovement: maxRestMovement
        )
    }

    private func uniqueTouchPositions(
        _ touches: [(fingerID: Int32, x: Float, y: Float, majorAxis: Float)]
    ) -> [Int32: (x: Float, y: Float)] {
        var positions: [Int32: (x: Float, y: Float)] = [:]
        for touch in touches where positions[touch.fingerID] == nil {
            positions[touch.fingerID] = (touch.x, touch.y)
        }
        return positions
    }

    private func updateTipTapRestState(
        framePositions: [Int32: (x: Float, y: Float)],
        now: Date,
        maxMovement: Float
    ) {
        guard framePositions.count == 1 || framePositions.count == 2 else {
            tipTapRestStartedAt = nil
            tipTapRestPositions.removeAll()
            return
        }

        let sameFingers = Set(framePositions.keys) == Set(tipTapRestPositions.keys)
        let fingersMoved = sameFingers && framePositions.contains { fingerID, position in
            guard let start = tipTapRestPositions[fingerID] else { return true }
            return abs(position.x - start.x) + abs(position.y - start.y) > maxMovement
        }
        if !sameFingers || fingersMoved || tipTapRestStartedAt == nil {
            tipTapRestStartedAt = now
            tipTapRestPositions = framePositions
        }
    }

    private func tipTapGesture(
        basePositions: [Int32: (x: Float, y: Float)],
        tappingX: Float,
        sensitivityScale: Double
    ) -> GestureKind? {
        let xs = basePositions.values.map(\.x)
        guard let leftX = xs.min(), let rightX = xs.max() else { return nil }

        if basePositions.count == 1 {
            let minimumSeparation = Float(0.045 / sensitivityScale)
            let delta = tappingX - leftX
            guard abs(delta) >= minimumSeparation else { return nil }
            return delta < 0 ? .tipTapLeft : .tipTapRight
        }

        let sideMargin = Float(0.035 / sensitivityScale)
        if tappingX < leftX - sideMargin { return .tipTapThirdFingerLeft }
        if tappingX > rightX + sideMargin { return .tipTapThirdFingerRight }
        return .tipTapMiddle
    }

    private func resetTipTapRecognition() {
        armedTipTap = nil
        tipTapRestStartedAt = nil
        tipTapRestPositions.removeAll()
    }

    private func detectRegularTap(previousFingers: Int) {
        guard currentFingers == 0, previousFingers > 0, let began = touchBegan else { return }
        defer {
            touchBegan = nil
            peakFingers = 0
            sessionStartPositions.removeAll()
            sessionStartCentroid = nil
            sessionLastCentroid = nil
            sessionMinSpread = nil
            sessionMaxSpread = nil
            rawSwipeFired = false
            swipeSessionEligible = false
            centroidMovement = 0
            previousPositions.removeAll()
        }
        let clampedTapSensitivity = Float(min(max(tapSensitivity, 0.4), 2.0))
        let maxTapDuration = 0.50 + (0.22 * Double(clampedTapSensitivity))
        let maxTapMovement = 0.14 + (0.10 * clampedTapSensitivity)
        guard !rawSwipeFired,
              Date().timeIntervalSince(began) < maxTapDuration,
              centroidMovement < maxTapMovement else { return }

        if peakFingers == 2 {
            let now = Date()
            if let last = lastTwoFingerTapTime, now.timeIntervalSince(last) < 0.42 {
                doubleTapTimer?.cancel()
                doubleTapTimer = nil
                lastTwoFingerTapTime = nil
                fire(.twoFingerDoubleTap)
            } else {
                lastTwoFingerTapTime = now
                let work = DispatchWorkItem { [weak self] in
                    self?.lastTwoFingerTapTime = nil
                    self?.fire(.twoFingerTap)
                }
                doubleTapTimer = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.42, execute: work)
            }
            return
        }

        switch peakFingers {
        case 3: fire(.threeFingerTap)
        case 4: fire(.fourFingerTap)
        case 5: fire(.fiveFingerTap)
        default: break
        }
    }

    private func detectRawSwipeInProgress() {
        guard !rawSwipeFired,
              swipeSessionEligible,
              currentFingers >= 2,
              peakFingers >= 2,
              peakFingers <= 4,
              currentFingers == peakFingers,
              let began = touchBegan,
              Date().timeIntervalSince(began) > 0.05,
              Date().timeIntervalSince(began) < 1.15,
              let start = sessionStartCentroid,
              let current = sessionLastCentroid else { return }

        let dx = current.x - start.x
        let dy = current.y - start.y
        fireRawSwipeIfNeeded(dx: dx, dy: dy, baseThreshold: 0.06)
    }

    private func detectRawSwipeOnEnd(previousFingers: Int) {
        guard !rawSwipeFired,
              swipeSessionEligible,
              currentFingers == 0,
              previousFingers > 0,
              peakFingers >= 2,
              peakFingers <= 4,
              let began = touchBegan,
              Date().timeIntervalSince(began) < 1.15 else { return }

        var dx: Float = 0
        var dy: Float = 0
        var samples = 0

        for (fingerID, start) in sessionStartPositions {
            guard let end = previousPositions[fingerID] else { continue }
            dx += end.0 - start.0
            dy += end.1 - start.1
            samples += 1
        }

        if samples >= min(peakFingers, 2) {
            dx /= Float(samples)
            dy /= Float(samples)
        } else if let start = sessionStartCentroid, let end = sessionLastCentroid {
            dx = end.x - start.x
            dy = end.y - start.y
        } else {
            return
        }

        fireRawSwipeIfNeeded(dx: dx, dy: dy, baseThreshold: 0.055)
    }

    private func fireRawSwipeIfNeeded(dx: Float, dy: Float, baseThreshold: Float) {
        let threshold = baseThreshold / Float(min(max(swipeSensitivity, 0.4), 2.0))
        let distance = max(abs(dx), abs(dy))
        guard distance > threshold else { return }
        guard !isSystemGestureConflict(dx: dx, dy: dy) else {
            suppressSystemGestureConflict()
            return
        }
        guard rawSwipeLooksCoherent(dx: dx, dy: dy) else { return }

        if abs(dx) >= abs(dy) {
            if let gesture = swipeGesture(fingers: peakFingers, horizontal: dx > 0 ? .right : .left) {
                rawSwipeFired = true
                fire(gesture)
            }
        } else {
            if let gesture = swipeGesture(fingers: peakFingers, vertical: dy > 0 ? .up : .down) {
                rawSwipeFired = true
                fire(gesture)
            }
        }
    }

    private func isSystemGestureConflict(dx: Float, dy: Float) -> Bool {
        guard peakFingers >= 3 else { return false }

        if peakFingers == 3 && abs(dx) > max(abs(dy) * 1.15, 0.04) {
            return true
        }

        if verticalThreeFingerSwipeDominates(dx: dx, dy: dy) {
            return false
        }

        if !hasDominantSwipeAxis(dx: dx, dy: dy) {
            return true
        }

        if sessionSpreadRangeLooksLikePinch(dx: dx, dy: dy) {
            return true
        }

        let spread = rawSessionSpread()
        guard spread.start > 0.001, spread.end > 0.001 else { return false }
        let spreadChange = abs(spread.end - spread.start)
        if peakFingers >= 4 && swipeMovementDominatesSpread(dx: dx, dy: dy, spreadChange: spreadChange) {
            return false
        }
        return spreadChange > pinchSpreadThreshold(for: spread.start)
    }

    private func hasDominantSwipeAxis(dx: Float, dy: Float) -> Bool {
        let primary = max(abs(dx), abs(dy))
        let secondary = min(abs(dx), abs(dy))
        guard primary > 0.001 else { return false }
        let ratioLimit: Float = peakFingers >= 4 ? 0.58 : 0.42
        let absoluteLimit: Float = peakFingers >= 4 ? 0.04 : 0.026
        return secondary <= max(primary * ratioLimit, absoluteLimit)
    }

    private func swipeTravel(dx: Float, dy: Float) -> Float {
        max(abs(dx), abs(dy))
    }

    private func verticalThreeFingerSwipeDominates(dx: Float, dy: Float) -> Bool {
        guard peakFingers == 3 else { return false }
        let travel = abs(dy)
        return travel > 0.05 && travel > max(abs(dx) * 1.35, 0.045)
    }

    private func sessionSpreadRangeLooksLikePinch(dx: Float, dy: Float) -> Bool {
        guard let minSpread = sessionMinSpread,
              let maxSpread = sessionMaxSpread,
              minSpread > 0.001 else { return false }

        let spreadRange = maxSpread - minSpread
        if verticalThreeFingerSwipeDominates(dx: dx, dy: dy),
           swipeTravel(dx: dx, dy: dy) > max(spreadRange * 0.95, 0.05) {
            return false
        }
        if peakFingers >= 4 && swipeMovementDominatesSpread(dx: dx, dy: dy, spreadChange: spreadRange) {
            return false
        }
        return spreadRange > pinchSpreadThreshold(for: minSpread)
    }

    private func swipeMovementDominatesSpread(dx: Float, dy: Float, spreadChange: Float) -> Bool {
        guard peakFingers >= 4 else { return false }
        let travel = max(abs(dx), abs(dy))
        return travel > max(spreadChange * 0.85, 0.045)
    }

    private func pinchSpreadThreshold(for baseSpread: Float) -> Float {
        if peakFingers >= 4 {
            return max(Float(0.07), baseSpread * 0.30)
        }
        if peakFingers == 3 {
            return max(Float(0.04), baseSpread * 0.18)
        }
        return max(Float(0.028), baseSpread * 0.12)
    }

    private func rawSessionSpread() -> (start: Float, end: Float) {
        var startPoints: [(x: Float, y: Float)] = []
        var endPoints: [(x: Float, y: Float)] = []

        for (fingerID, start) in sessionStartPositions {
            guard let end = previousPositions[fingerID] else { continue }
            startPoints.append((start.0, start.1))
            endPoints.append((end.0, end.1))
        }

        guard startPoints.count >= 3, endPoints.count >= 3 else { return (0, 0) }
        let startSpread = averagePairwiseDistance(startPoints)
        let endSpread = averagePairwiseDistance(endPoints)
        return (startSpread, endSpread)
    }

    private func suppressSystemGestureConflict() {
        rawSwipeFired = true
        rawGestureConsumed = true
        lastFire = Date()
        gestureSuppressedUntil = Date().addingTimeInterval(0.55)
    }

    private func rawSwipeLooksCoherent(dx: Float, dy: Float) -> Bool {
        guard peakFingers >= 3 else { return true }
        guard hasDominantSwipeAxis(dx: dx, dy: dy) else { return false }
        guard !sessionSpreadRangeLooksLikePinch(dx: dx, dy: dy) else { return false }

        let vertical = abs(dy) > abs(dx)
        let averagePrimary = vertical ? dy : dx
        guard abs(averagePrimary) > 0.001 else { return false }

        var startPoints: [(x: Float, y: Float)] = []
        var endPoints: [(x: Float, y: Float)] = []
        var alignedVectors = 0
        var vectorCount = 0
        let minimumPrimary = max(abs(averagePrimary) * 0.24, 0.018)

        for (fingerID, start) in sessionStartPositions {
            guard let end = previousPositions[fingerID] else { continue }
            let vx = end.0 - start.0
            let vy = end.1 - start.1
            let primary = vertical ? vy : vx
            let secondary = vertical ? vx : vy
            vectorCount += 1
            startPoints.append((start.0, start.1))
            endPoints.append((end.0, end.1))

            let sameDirection = averagePrimary > 0 ? primary > minimumPrimary : primary < -minimumPrimary
            let secondaryLimit = max(abs(primary) * 1.05, 0.08)
            if sameDirection && abs(secondary) <= secondaryLimit {
                alignedVectors += 1
            }
        }

        guard vectorCount >= min(peakFingers, 3) else { return true }
        let requiredAligned = max(2, Int(ceil(Double(vectorCount) * 0.72)))
        guard alignedVectors >= requiredAligned else { return false }

        let startSpread = averagePairwiseDistance(startPoints)
        let endSpread = averagePairwiseDistance(endPoints)
        guard startSpread > 0.001, endSpread > 0.001 else { return true }
        let spreadChange = abs(endSpread - startSpread)
        let allowedSpreadChange = pinchSpreadThreshold(for: startSpread)
        guard spreadChange <= allowedSpreadChange else { return false }

        if peakFingers >= 3 {
            let startCenter = averagePoint(startPoints)
            let endCenter = averagePoint(endPoints)
            var radialChanges: [Float] = []
            for index in startPoints.indices where index < endPoints.count {
                let startRadius = hypot(startPoints[index].x - startCenter.x, startPoints[index].y - startCenter.y)
                let endRadius = hypot(endPoints[index].x - endCenter.x, endPoints[index].y - endCenter.y)
                radialChanges.append(endRadius - startRadius)
            }

            if radialChanges.count >= 3 {
                let averageRadialChange = radialChanges.reduce(0, +) / Float(radialChanges.count)
                let sameRadialDirection = radialChanges.filter {
                    averageRadialChange > 0 ? $0 > 0.009 : $0 < -0.009
                }.count
                let requiredRadialAgreement = max(3, Int(ceil(Double(radialChanges.count) * 0.72)))
                let radialLooksLikePinch = abs(averageRadialChange) > 0.012
                    && sameRadialDirection >= requiredRadialAgreement
                let swipeDominatesRadialMotion = peakFingers >= 4
                    && swipeTravel(dx: dx, dy: dy) > max(abs(averageRadialChange) * 1.8, 0.055)
                let verticalSwipeDominatesRadialMotion = verticalThreeFingerSwipeDominates(dx: dx, dy: dy)
                    && swipeTravel(dx: dx, dy: dy) > max(abs(averageRadialChange) * 1.45, 0.052)
                if radialLooksLikePinch && !swipeDominatesRadialMotion && !verticalSwipeDominatesRadialMotion {
                    return false
                }
            }
        }

        return true
    }

    private func averagePairwiseDistance(_ points: [(x: Float, y: Float)]) -> Float {
        guard points.count >= 2 else { return 0 }
        var total: Float = 0
        var count: Float = 0
        for i in 0..<(points.count - 1) {
            for j in (i + 1)..<points.count {
                total += hypot(points[i].x - points[j].x, points[i].y - points[j].y)
                count += 1
            }
        }
        return count > 0 ? total / count : 0
    }

    private func averagePoint(_ points: [(x: Float, y: Float)]) -> (x: Float, y: Float) {
        guard !points.isEmpty else { return (0, 0) }
        let count = Float(points.count)
        return (
            points.reduce(Float(0)) { $0 + $1.x } / count,
            points.reduce(Float(0)) { $0 + $1.y } / count
        )
    }

    private func trackSingleFingerDrawing(_ touch: (fingerID: Int32, x: Float, y: Float, majorAxis: Float)) {
        circlePoints.append((touch.x, touch.y))
        trianglePoints.append((touch.x, touch.y))
        if circlePoints.count > 360 { circlePoints.removeFirst(circlePoints.count - 360) }
        if trianglePoints.count > 180 { trianglePoints.removeFirst(trianglePoints.count - 180) }
    }

    private func detectCircle() {
        guard !circleFired,
              let gesture = DrawingGestureRecognizer.circleGesture(in: circlePoints) else { return }
        circleFired = true
        fire(gesture)
    }

    private func detectTriangle() {
        guard !triangleFired, !circleFired, trianglePoints.count >= 24 else { return }
        let xs = trianglePoints.map(\.x)
        let ys = trianglePoints.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return }
        let width = maxX - minX
        let height = maxY - minY
        let start = trianglePoints.first!
        let end = trianglePoints.last!
        let closed = hypot(start.x - end.x, start.y - end.y) < 0.13
        if width > 0.16 && height > 0.16 && closed {
            triangleFired = true
            fire(.drawTriangle)
        }
    }

    private func trackEdgeSlide(_ touch: (fingerID: Int32, x: Float, y: Float, majorAxis: Float), pressed: Bool) {
        guard pressed else {
            edgeSlideStartY = nil
            edgeSlideSide = nil
            edgeSlideFingerID = nil
            return
        }
        let side: TrackpadEdge?
        if touch.x < 0.16 { side = .left }
        else if touch.x > 0.84 { side = .right }
        else { side = nil }
        guard let side else {
            edgeSlideStartY = nil
            edgeSlideSide = nil
            edgeSlideFingerID = nil
            return
        }
        guard let startY = edgeSlideStartY,
              edgeSlideSide == side,
              edgeSlideFingerID == touch.fingerID else {
            edgeSlideStartY = touch.y
            edgeSlideSide = side
            edgeSlideFingerID = touch.fingerID
            return
        }
        guard let gesture = EdgeSlideGestureRecognizer.gesture(
            side: side,
            startY: startY,
            currentY: touch.y
        ) else { return }
        fire(gesture)
    }

    private func resetDrawingState() {
        circlePoints.removeAll()
        trianglePoints.removeAll()
        circleFired = false
        triangleFired = false
    }

    private func fire(_ gesture: GestureKind) {
        guard !rawGestureConsumed,
              Date() >= gestureSuppressedUntil,
              Date().timeIntervalSince(lastFire) > 0.18 else { return }
        rawGestureConsumed = true
        doubleTapTimer?.cancel()
        doubleTapTimer = nil
        lastTwoFingerTapTime = nil
        lastFire = Date()
        gestureSuppressedUntil = Date().addingTimeInterval(suppressionDuration(after: gesture))
        let modifier = GestureTriggerModifier.currentSystemModifier
        DispatchQueue.main.async { [callback] in
            callback(gesture, modifier)
        }
    }

    private func suppressionDuration(after gesture: GestureKind) -> TimeInterval {
        switch gesture {
        case .tipTapLeft, .tipTapRight, .tipTapMiddle,
             .tipTapThirdFingerLeft, .tipTapThirdFingerRight:
            return 0.32
        default:
            return 0.65
        }
    }
}

@MainActor
final class ActionExecutor {
    func perform(_ action: PilotAction, language: AppLanguage, dryRun: Bool = false) async -> String {
        if dryRun {
            return Self.dryRunDescription(for: action, language: language)
        }
        switch action.kind {
        case .notification:
            let body = action.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else {
                return language == .ru ? "Уведомление не отправлено: пустой текст" : "Notification skipped: empty message"
            }
            let content = UNMutableNotificationContent()
            content.title = action.title.isEmpty ? "TouchPilot" : action.title
            content.body = body
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            return await withCheckedContinuation { continuation in
                UNUserNotificationCenter.current().add(request) { error in
                    if let error {
                        continuation.resume(returning: language == .ru
                            ? "Уведомление не отправлено: \(error.localizedDescription)"
                            : "Notification not posted: \(error.localizedDescription)")
                    } else {
                        continuation.resume(returning: language == .ru ? "Отправлено уведомление" : "Posted notification")
                    }
                }
            }
        case .openURL:
            guard let url = normalizedURL(from: action.value) else {
                return language == .ru ? "Ссылка не открыта: неверный URL" : "URL not opened: invalid URL"
            }
            guard NSWorkspace.shared.open(url) else {
                return language == .ru ? "Ссылка не открыта" : "URL could not be opened"
            }
            return language == .ru ? "Открыта ссылка: \(url.absoluteString)" : "Opened URL: \(url.absoluteString)"
        case .launchApp:
            if action.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               action.title.localizedCaseInsensitiveContains("закры") {
                return quitFrontmostApplication(language: language)
            }
            return await launchApplication(from: action.value, language: language)
        case .quitFrontmostApp:
            return quitFrontmostApplication(language: language)
        case .keyboardShortcut:
            return await sendShortcut(action.value, language: language)
        case .systemAction:
            return await performSystemAction(action.value, language: language)
        }
    }

    static func dryRunDescription(for action: PilotAction, language: AppLanguage) -> String {
        let value = action.value.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = language == .ru ? "Тест — " : "Test — "
        switch action.kind {
        case .notification:
            return prefix + (language == .ru ? "уведомление: \(value.isEmpty ? "пустой текст" : value)" : "notification: \(value.isEmpty ? "empty message" : value)")
        case .openURL:
            return prefix + (language == .ru ? "открытие ссылки: \(value)" : "open URL: \(value)")
        case .launchApp:
            return prefix + (language == .ru ? "запуск приложения: \(value)" : "launch app: \(value)")
        case .quitFrontmostApp:
            return prefix + (language == .ru ? "закрытие активного приложения" : "quit frontmost app")
        case .keyboardShortcut:
            let shortcut = ShortcutRecorder.prettyString(from: value) ?? value
            return prefix + (language == .ru ? "сочетание клавиш: \(shortcut)" : "keyboard shortcut: \(shortcut)")
        case .systemAction:
            guard let systemAction = SystemAction(rawValue: value) else {
                return prefix + (language == .ru ? "неизвестное системное действие" : "unknown system action")
            }
            return prefix + systemAction.title(language)
        }
    }

    private func performSystemAction(_ value: String, language: AppLanguage) async -> String {
        guard let action = SystemAction(rawValue: value) else {
            return language == .ru
                ? "Системное действие не выполнено: неизвестная команда"
                : "System action not performed: unknown command"
        }

        if action.requiresConfirmation, !confirm(action, language: language) {
            return language == .ru
                ? "Отменено: \(action.title(language))"
                : "Cancelled: \(action.title(language))"
        }

        switch action {
        case .lockScreen:
            return await performShortcut("cmd+ctrl+q", for: action, language: language)
        case .startScreenSaver:
            let path = "/System/Library/CoreServices/ScreenSaverEngine.app"
            guard NSWorkspace.shared.open(URL(fileURLWithPath: path)) else {
                return failedSystemAction(action, language: language)
            }
            return completedSystemAction(action, language: language)
        case .sleepDisplay:
            return runCommand("/usr/bin/pmset", arguments: ["displaysleepnow"], action: action, language: language)
        case .sleepMac:
            return runAppleScript("tell application \"System Events\" to sleep", action: action, language: language)
        case .logOut:
            return runAppleScript("tell application \"System Events\" to log out", action: action, language: language)
        case .restart:
            return runAppleScript("tell application \"System Events\" to restart", action: action, language: language)
        case .shutDown:
            return runAppleScript("tell application \"System Events\" to shut down", action: action, language: language)
        case .volumeUp:
            return await postSystemKey(0, action: action, language: language)
        case .volumeDown:
            return await postSystemKey(1, action: action, language: language)
        case .toggleMute:
            return await postSystemKey(7, action: action, language: language)
        case .playPause:
            return await postSystemKey(16, action: action, language: language)
        case .nextTrack:
            return await postSystemKey(17, action: action, language: language)
        case .previousTrack:
            return await postSystemKey(18, action: action, language: language)
        case .brightnessUp:
            return await postSystemKey(2, action: action, language: language)
        case .brightnessDown:
            return await postSystemKey(3, action: action, language: language)
        case .keyboardBacklightUp:
            return await postSystemKey(21, action: action, language: language)
        case .keyboardBacklightDown:
            return await postSystemKey(22, action: action, language: language)
        case .missionControl:
            return openSystemApplication(
                paths: ["/System/Applications/Mission Control.app", "/Applications/Mission Control.app"],
                action: action,
                language: language
            )
        case .applicationWindows:
            return await performShortcut("ctrl+down", for: action, language: language)
        case .showDesktop:
            return await performShortcut("f11", for: action, language: language)
        case .launchpad:
            return await postSystemKey(13, action: action, language: language)
        case .spotlight:
            return await performShortcut("cmd+space", for: action, language: language)
        case .notificationCenter:
            return await performShortcut("fn+n", for: action, language: language)
        case .toggleDarkMode:
            let script = """
            tell application "System Events"
                tell appearance preferences to set dark mode to not dark mode
            end tell
            """
            return runAppleScript(script, action: action, language: language)
        case .screenshotFull:
            return await performShortcut("cmd+shift+3", for: action, language: language)
        case .screenshotSelection:
            return await performShortcut("cmd+shift+4", for: action, language: language)
        }
    }

    private func confirm(_ action: SystemAction, language: AppLanguage) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = action.title(language)
        alert.informativeText = language == .ru
            ? "Это действие может закрыть приложения и привести к потере несохранённых данных. Продолжить?"
            : "This action may quit apps and discard unsaved data. Continue?"
        alert.addButton(withTitle: language == .ru ? "Продолжить" : "Continue")
        alert.addButton(withTitle: language == .ru ? "Отмена" : "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func ensureAccessibilityPermission(language: AppLanguage) -> String? {
        guard !AXIsProcessTrusted() else { return nil }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        return language == .ru
            ? "разрешите TouchPilot в Универсальном доступе и повторите жест"
            : "allow TouchPilot in Accessibility, then repeat the gesture"
    }

    private func postSystemKey(_ keyType: Int, action: SystemAction, language: AppLanguage) async -> String {
        if let permissionError = ensureAccessibilityPermission(language: language) {
            return language == .ru
                ? "Не выполнено «\(action.title(language))»: \(permissionError)"
                : "Could not perform \"\(action.title(language))\": \(permissionError)"
        }

        for keyState in [0x0A, 0x0B] {
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(keyState << 8)),
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: (keyType << 16) | (keyState << 8),
                data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
        return completedSystemAction(action, language: language)
    }

    private func performShortcut(_ shortcut: String, for action: SystemAction, language: AppLanguage) async -> String {
        let result = await sendShortcut(shortcut, language: language)
        let failed = language == .ru ? result.hasPrefix("Сочетание не отправлено") : result.hasPrefix("Shortcut not sent")
        return failed ? result : completedSystemAction(action, language: language)
    }

    private func openSystemApplication(paths: [String], action: SystemAction, language: AppLanguage) -> String {
        guard let path = paths.first(where: { FileManager.default.fileExists(atPath: $0) }),
              NSWorkspace.shared.open(URL(fileURLWithPath: path)) else {
            return failedSystemAction(action, language: language)
        }
        return completedSystemAction(action, language: language)
    }

    private func runAppleScript(_ source: String, action: SystemAction, language: AppLanguage) -> String {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            let detail = error[NSAppleScript.errorMessage] as? String ?? "AppleScript error"
            return failedSystemAction(action, language: language, detail: detail)
        }
        return completedSystemAction(action, language: language)
    }

    private func runCommand(
        _ executable: String,
        arguments: [String],
        action: SystemAction,
        language: AppLanguage
    ) -> String {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardError = errorPipe
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let detail = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                return failedSystemAction(action, language: language, detail: detail)
            }
            return completedSystemAction(action, language: language)
        } catch {
            return failedSystemAction(action, language: language, detail: error.localizedDescription)
        }
    }

    private func completedSystemAction(_ action: SystemAction, language: AppLanguage) -> String {
        language == .ru ? "Выполнено: \(action.title(language))" : "Performed: \(action.title(language))"
    }

    private func failedSystemAction(_ action: SystemAction, language: AppLanguage, detail: String? = nil) -> String {
        let prefix = language == .ru
            ? "Не удалось выполнить: \(action.title(language))"
            : "Could not perform: \(action.title(language))"
        guard let detail, !detail.isEmpty else { return prefix }
        return "\(prefix) — \(detail)"
    }

    private func launchApplication(from value: String, language: AppLanguage) async -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return language == .ru ? "Приложение не открыто: не выбран файл" : "App not opened: no app selected"
        }

        if trimmed.contains(".") && !trimmed.contains("/") {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: trimmed) {
                return await openApplicationResult(at: appURL, language: language)
            }
        }

        let pathURL = URL(fileURLWithPath: NSString(string: trimmed).expandingTildeInPath)
        if FileManager.default.fileExists(atPath: pathURL.path) {
            return await openApplicationResult(at: pathURL, language: language)
        }

        if let appURL = applicationURL(named: trimmed) {
            return await openApplicationResult(at: appURL, language: language)
        }

        return language == .ru ? "Приложение не найдено: \(trimmed)" : "App not found: \(trimmed)"
    }

    private func openApplicationResult(at appURL: URL, language: AppLanguage) async -> String {
        let name = appURL.deletingPathExtension().lastPathComponent
        if appURL.lastPathComponent == "Finder.app" {
            let opened = NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()))
            return opened
                ? (language == .ru ? "Открыто приложение: \(name)" : "Opened app: \(name)")
                : (language == .ru ? "Не удалось открыть: \(name)" : "Could not open: \(name)")
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        return await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { app, error in
                if let error {
                    continuation.resume(returning: language == .ru
                        ? "Не удалось открыть \(name): \(error.localizedDescription)"
                        : "Could not open \(name): \(error.localizedDescription)")
                } else if app != nil {
                    continuation.resume(returning: language == .ru ? "Открыто приложение: \(name)" : "Opened app: \(name)")
                } else {
                    continuation.resume(returning: language == .ru ? "Не удалось открыть: \(name)" : "Could not open: \(name)")
                }
            }
        }
    }

    private func normalizedURL(from value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(trimmed)")
    }

    private func applicationURL(named name: String) -> URL? {
        let appName = name.hasSuffix(".app") ? name : "\(name).app"
        let folders = [
            "/Applications",
            "/System/Applications",
            "\(NSHomeDirectory())/Applications"
        ]
        for folder in folders {
            let url = URL(fileURLWithPath: folder).appendingPathComponent(appName)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private func quitFrontmostApplication(language: AppLanguage) -> String {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return language == .ru ? "Активное приложение не найдено" : "No frontmost app found"
        }
        if app.bundleIdentifier == Bundle.main.bundleIdentifier {
            NSApp.hide(nil)
            return language == .ru ? "TouchPilot скрыт" : "TouchPilot hidden"
        }
        let name = app.localizedName ?? app.bundleIdentifier ?? "Application"
        guard app.terminate() else {
            return language == .ru ? "Не удалось закрыть: \(name)" : "Could not quit: \(name)"
        }
        return language == .ru ? "Закрыто приложение: \(name)" : "Quit app: \(name)"
    }

    private func sendShortcut(_ value: String, language: AppLanguage) async -> String {
        let parts = value.lowercased().split(separator: "+").map(String.init)
        guard AXIsProcessTrusted() else {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            return language == .ru
                ? "Сочетание не отправлено: разрешите TouchPilot в Универсальном доступе и повторите жест"
                : "Shortcut not sent: allow TouchPilot in Accessibility, then repeat the gesture"
        }
        guard let key = parts.last, let keyCode = KeyCodes.keyCode(for: key) else {
            return language == .ru ? "Сочетание не отправлено: неизвестная клавиша" : "Shortcut not sent: unknown key"
        }

        let flags = shortcutFlags(from: parts)
        let wasFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
        if wasFrontmost {
            NSApp.hide(nil)
        }

        let delay: UInt64 = wasFrontmost ? 140_000_000 : 20_000_000
        try? await Task.sleep(nanoseconds: delay)
        await postShortcut(keyCode: keyCode, flags: flags)
        return language == .ru ? "Отправлено сочетание: \(value)" : "Sent shortcut: \(value)"
    }

    private func shortcutFlags(from parts: [String]) -> CGEventFlags {
        var flags = CGEventFlags()
        if parts.contains("cmd") || parts.contains("command") { flags.insert(.maskCommand) }
        if parts.contains("shift") { flags.insert(.maskShift) }
        if parts.contains("ctrl") || parts.contains("control") { flags.insert(.maskControl) }
        if parts.contains("alt") || parts.contains("option") { flags.insert(.maskAlternate) }
        if parts.contains("fn") { flags.insert(.maskSecondaryFn) }
        return flags
    }

    private func postShortcut(keyCode: CGKeyCode, flags: CGEventFlags) async {
        let source = CGEventSource(stateID: .hidSystemState)
        source?.localEventsSuppressionInterval = 0

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }

        down.flags = flags
        up.flags = flags
        down.setIntegerValueField(.eventSourceUserData, value: 0x54504b4559)
        up.setIntegerValueField(.eventSourceUserData, value: 0x54504b4559)
        down.post(tap: .cghidEventTap)
        try? await Task.sleep(nanoseconds: 35_000_000)
        up.post(tap: .cghidEventTap)
    }
}

enum KeyCodes {
    static let map: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19,
        "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28,
        "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38,
        "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47,
        "space": 49, "enter": 36, "return": 36, "tab": 48, "delete": 51, "backspace": 51,
        "escape": 53, "esc": 53, "left": 123, "right": 124, "down": 125, "up": 126,
        "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98,
        "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111, "f13": 105,
        "f14": 107, "f15": 113
    ]

    private static let inputByCode: [UInt16: String] = {
        var values: [UInt16: String] = [:]
        for (name, code) in map {
            values[UInt16(code)] = values[UInt16(code)] ?? name
        }
        values[36] = "return"
        values[49] = "space"
        values[51] = "delete"
        values[53] = "escape"
        return values
    }()

    private static let displayByCode: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space",
        51: "⌫", 53: "⎋", 96: "F5", 97: "F6", 98: "F7", 99: "F3",
        100: "F8", 101: "F9", 103: "F11", 105: "F13", 107: "F14",
        109: "F10", 111: "F12", 113: "F15", 115: "Home", 116: "⇞",
        117: "⌦", 118: "F4", 119: "End", 120: "F2", 121: "⇟",
        122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑"
    ]

    static func inputName(for keyCode: UInt16) -> String {
        inputByCode[keyCode] ?? "key\(keyCode)"
    }

    static func keyCode(for input: String) -> CGKeyCode? {
        if let code = map[input] {
            return code
        }
        if input.hasPrefix("key"), let value = UInt16(input.dropFirst(3)) {
            return CGKeyCode(value)
        }
        return nil
    }

    static func displayName(for keyCode: UInt16) -> String {
        displayByCode[keyCode] ?? "Key\(keyCode)"
    }

    static func displayName(forInputName input: String) -> String {
        if let code = map[input] {
            return displayName(for: UInt16(code))
        }
        return input.uppercased()
    }
}

enum CleaningUnlockUpdate: Equatable {
    case none
    case progress(Int)
    case unlocked
}

struct CleaningUnlockDetector {
    private(set) var progress = 0
    private var firstChordAt: Date?
    private var waitingForFullRelease = false
    private var unlockArmed = false
    private let maximumInterval: TimeInterval = 4

    mutating func update(leftCommandDown: Bool, rightCommandDown: Bool, at date: Date) -> CleaningUnlockUpdate {
        let bothReleased = !leftCommandDown && !rightCommandDown
        if unlockArmed {
            guard bothReleased else { return .none }
            reset()
            return .unlocked
        }

        if bothReleased {
            waitingForFullRelease = false
            return .none
        }

        guard leftCommandDown, rightCommandDown, !waitingForFullRelease else { return .none }
        waitingForFullRelease = true

        if progress == 1,
           let firstChordAt,
           date.timeIntervalSince(firstChordAt) <= maximumInterval {
            progress = 2
            unlockArmed = true
            return .progress(2)
        }

        progress = 1
        firstChordAt = date
        return .progress(1)
    }

    mutating func reset() {
        progress = 0
        firstChordAt = nil
        waitingForFullRelease = false
        unlockArmed = false
    }
}

@MainActor
final class InputCleaningLock {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var overlayWindows: [NSWindow] = []
    private var detector = CleaningUnlockDetector()
    private var language: AppLanguage = .ru
    private var onProgress: ((Int) -> Void)?
    private var onUnlocked: (() -> Void)?
    private var isActive = false
    private var leftCommandDown = false
    private var rightCommandDown = false

    func start(
        language: AppLanguage,
        onProgress: @escaping (Int) -> Void,
        onUnlocked: @escaping () -> Void
    ) -> Bool {
        stop()
        guard AXIsProcessTrusted() else { return false }

        self.language = language
        self.onProgress = onProgress
        self.onUnlocked = onUnlocked
        detector.reset()
        leftCommandDown = false
        rightCommandDown = false

        let mask = CGEventMask.max

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            MainActor.assumeIsolated {
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let lock = Unmanaged<InputCleaningLock>.fromOpaque(refcon).takeUnretainedValue()
                return lock.handleEvent(type: type, event: event)
            }
        }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else {
            stop()
            return false
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        guard let runLoopSource else {
            stop()
            return false
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        isActive = true
        showOverlays()
        return true
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return nil
        }

        guard isActive else { return Unmanaged.passUnretained(event) }
        if type == .flagsChanged {
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            switch keyCode {
            case 55: leftCommandDown.toggle()
            case 54: rightCommandDown.toggle()
            default: return nil
            }
            switch detector.update(
                leftCommandDown: leftCommandDown,
                rightCommandDown: rightCommandDown,
                at: Date()
            ) {
            case .none:
                break
            case .progress(let progress):
                onProgress?(progress)
                refreshOverlays(progress: progress)
            case .unlocked:
                DispatchQueue.main.async { [weak self] in self?.finishUnlock() }
            }
        }

        return nil
    }

    private func showOverlays() {
        overlayWindows = NSScreen.screens.map { screen in
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.setFrame(screen.frame, display: true)
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.backgroundColor = .black
            window.isOpaque = true
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: CleaningModeOverlayView(language: language, progress: 0))
            window.orderFrontRegardless()
            return window
        }
    }

    private func refreshOverlays(progress: Int) {
        for window in overlayWindows {
            window.contentView = NSHostingView(rootView: CleaningModeOverlayView(language: language, progress: progress))
        }
    }

    private func finishUnlock() {
        let completion = onUnlocked
        stop()
        completion?()
    }

    private func stop() {
        isActive = false
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        overlayWindows.forEach { $0.orderOut(nil) }
        overlayWindows.removeAll()
        detector.reset()
        leftCommandDown = false
        rightCommandDown = false
        onProgress = nil
        onUnlocked = nil
    }
}

struct CleaningModeOverlayView: View {
    let language: AppLanguage
    let progress: Int

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.03, green: 0.10, blue: 0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "sparkles")
                    .font(.system(size: 58, weight: .medium))
                    .foregroundStyle(.cyan)
                Text(language == .ru ? "Режим очистки" : "Cleaning Mode")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                Text(language == .ru
                     ? "Клавиатура и трекпад заблокированы"
                     : "Keyboard and trackpad are locked")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.72))

                HStack(spacing: 14) {
                    commandKey(language == .ru ? "Левый ⌘" : "Left ⌘")
                    Text("+").foregroundStyle(.white.opacity(0.55))
                    commandKey(language == .ru ? "Правый ⌘" : "Right ⌘")
                    Text("× 2")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.cyan)
                }

                Text(progress < 2
                     ? (language == .ru
                        ? "Нажмите обе клавиши Command одновременно два раза"
                        : "Press both Command keys together twice")
                     : (language == .ru ? "Отпустите обе клавиши" : "Release both keys"))
                    .font(.headline)
                    .foregroundStyle(.white)

                HStack(spacing: 10) {
                    ForEach(0..<2, id: \.self) { index in
                        Circle()
                            .fill(index < progress ? Color.cyan : Color.white.opacity(0.22))
                            .frame(width: 12, height: 12)
                    }
                }
            }
            .padding(40)
        }
    }

    private func commandKey(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 19, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .background(Color.white.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
    }
}

struct MainView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                toolbar
                HStack(spacing: 12) {
                    AppSidebarView()
                        .frame(width: 220)
                        .finderSidebarPane(cornerRadius: 22)
                    RuleListView()
                        .frame(width: 300)
                        .settingsPane()
                    if state.selectedRule != nil {
                        ActionListView()
                            .frame(width: 390)
                            .settingsPane()
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }

            editorOverlay
        }
        .background(TouchPilotStyle.windowBackground)
        .tint(state.accentColor)
        .environment(\.touchPilotAccent, state.accentColor)
        .preferredColorScheme(state.theme.preferredColorScheme)
    }

    @ViewBuilder
    private var editorOverlay: some View {
        if state.showingGestureEditor || state.showingActionEditor || state.showingSystemActionPicker || state.showingCleaningModeSettings || state.showingOpenShortcutSettings || state.showingTutorial {
            Color.black.opacity(colorScheme == .dark ? 0.46 : 0.28)
                .ignoresSafeArea()
                .transition(.opacity)

            if state.showingGestureEditor, let rule = state.selectedRule {
                GestureEditorSheet(rule: rule)
                    .environmentObject(state)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }

            if state.showingActionEditor, let action = state.selectedAction {
                ActionEditorSheet(action: action)
                    .environmentObject(state)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }

            if state.showingSystemActionPicker, let rule = state.selectedRule {
                SystemActionPickerSheet(ruleID: rule.id)
                    .environmentObject(state)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }

            if state.showingCleaningModeSettings {
                CleaningModeSettingsView()
                    .environmentObject(state)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }

            if state.showingOpenShortcutSettings {
                OpenShortcutSettingsView()
                    .environmentObject(state)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }

            if state.showingTutorial {
                TutorialView()
                    .environmentObject(state)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Label("TouchPilot", systemImage: "hand.point.up.braille.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(state.accentColor)
            Button {
                state.isEnabled.toggle()
            } label: {
                Label(state.isEnabled ? L.on.text(state.language) : L.off.text(state.language), systemImage: state.isEnabled ? "bolt.fill" : "pause.fill")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(state.isEnabled ? .green : .red)
            }
            .buttonStyle(.bordered)
            Spacer()
            toolbarIconCluster
                .padding(.trailing, 12)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var toolbarIconCluster: some View {
        HStack(spacing: 2) {
            Button {
                state.isTestMode.toggle()
            } label: {
                Image(systemName: "testtube.2")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 28, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(state.isTestMode ? .orange : .secondary)
            .help(state.language == .ru ? "Тестовый режим: действия не выполняются" : "Test mode: actions are simulated")

            Button {
                state.showCleaningModeSettings()
            } label: {
                Image(systemName: "keyboard.badge.ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 28, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.cyan)
            .help(state.language == .ru ? "Режим очистки клавиатуры и трекпада" : "Keyboard and trackpad cleaning mode")

            Button {
                state.showTutorial()
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 28, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(state.language == .ru ? "Обучение" : "Tutorial")

            Button {
                state.setLaunchAtLogin(!state.launchAtLogin)
            } label: {
                Image(systemName: state.launchAtLogin ? "power.circle.fill" : "power.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 28, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.green)
            .help(state.language == .ru ? "Автостарт" : "Launch at login")

            Button {
                state.toggleAccentMode()
            } label: {
                Image(systemName: "paintpalette.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 28, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(state.accentColor)
            .help(state.accentMode.title(state.language))

            Button {
                state.cycleTheme()
            } label: {
                Image(systemName: toolbarThemeIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 28, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.yellow)
            .help(state.theme.displayTitle(state.language, effectiveAppearance: NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(TouchPilotStyle.groupedCardBackground.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(TouchPilotStyle.subtleStroke, lineWidth: 1)
        )
    }

    private var toolbarThemeIcon: String {
        switch state.theme {
        case .system:
            return "circle.lefthalf.filled"
        case .light:
            return "sun.max.fill"
        case .dark:
            return "moon.fill"
        }
    }
}

struct TutorialView: View {
    @EnvironmentObject private var state: AppState
    @State private var page = 0

    private var pageCount: Int { 5 }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text(state.language == .ru ? "Знакомство с TouchPilot" : "Meet TouchPilot")
                    .font(.title2.weight(.bold))
                Spacer()
                Button(state.language == .ru ? "Пропустить" : "Skip") {
                    state.completeTutorial()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            tutorialContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? state.accentColor : Color.secondary.opacity(0.25))
                            .frame(width: index == page ? 22 : 7, height: 7)
                    }
                }
                Spacer()
                if page > 0 {
                    Button(state.language == .ru ? "Назад" : "Back") { page -= 1 }
                }
                Button(page == pageCount - 1
                       ? (state.language == .ru ? "Начать" : "Get Started")
                       : (state.language == .ru ? "Далее" : "Next")) {
                    if page == pageCount - 1 {
                        state.completeTutorial()
                    } else {
                        page += 1
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 650, height: 430)
        .floatingSheetChrome(cornerRadius: 24)
    }

    @ViewBuilder
    private var tutorialContent: some View {
        switch page {
        case 0:
            tutorialPage(
                title: state.language == .ru ? "Жест запускает цепочку действий" : "A gesture starts an action sequence",
                text: state.language == .ru
                    ? "Создайте правило, выберите жест и добавьте действия в нужном порядке."
                    : "Create a rule, choose a gesture, and add actions in the order you want.",
                icon: "hand.draw"
            ) {
                GestureMotionView(gesture: .threeFingerSwipeUp, animate: true)
                    .frame(width: 220, height: 130)
            }
        case 1:
            tutorialPage(
                title: state.language == .ru ? "Проверяйте без риска" : "Test without risk",
                text: state.language == .ru
                    ? "В тестовом режиме TouchPilot показывает, что было бы выполнено, но не открывает ссылки, программы и не отправляет клавиши."
                    : "Test mode reports what would happen without opening links or apps, quitting anything, or sending keys.",
                icon: "testtube.2"
            ) {
                Toggle(state.language == .ru ? "Тестовый режим" : "Test Mode", isOn: $state.isTestMode)
                    .toggleStyle(.switch)
                    .frame(width: 220)
            }
        case 2:
            tutorialPage(
                title: state.language == .ru ? "Профили для приложений" : "Profiles for applications",
                text: state.language == .ru
                    ? "Добавьте приложение кнопкой «+». Его правила имеют приоритет, а глобальные используются как запасные."
                    : "Add an app with the + button. Its rules take priority, while global rules act as fallbacks.",
                icon: "square.stack.3d.up.fill"
            ) {
                HStack(spacing: 18) {
                    Label("Finder", systemImage: "face.smiling")
                    Image(systemName: "arrow.right")
                    Label(state.language == .ru ? "Свои жесты" : "Own gestures", systemImage: "hand.tap.fill")
                }
                .font(.headline)
            }
        case 3:
            tutorialPage(
                title: state.language == .ru ? "Безопасная очистка Mac" : "Clean Your Mac Safely",
                text: state.language == .ru
                    ? "Кнопка с клавиатурой на верхней панели блокирует клавиши, трекпад, мышь и жесты TouchPilot на время очистки."
                    : "The keyboard button in the toolbar locks the keyboard, trackpad, mouse, and TouchPilot gestures while you clean.",
                icon: "keyboard.badge.ellipsis"
            ) {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        cleaningTutorialKey(state.language == .ru ? "Левый ⌘" : "Left ⌘")
                        Text("+").foregroundStyle(.secondary)
                        cleaningTutorialKey(state.language == .ru ? "Правый ⌘" : "Right ⌘")
                        Text("× 2")
                            .font(.headline)
                            .foregroundStyle(state.accentColor)
                    }
                    Text(state.language == .ru
                         ? "Нажмите вместе, отпустите и повторите для разблокировки"
                         : "Press together, release, and repeat to unlock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        default:
            tutorialPage(
                title: state.language == .ru ? "Конфликты видны сразу" : "Conflicts are visible immediately",
                text: state.language == .ru
                    ? "Оранжевый значок предупреждает о повторном жесте в профиле или конфликте горячей клавиши."
                    : "An orange badge warns about a duplicate gesture in a profile or a shortcut conflict.",
                icon: "exclamationmark.triangle.fill"
            ) {
                Label(
                    state.language == .ru ? "Исправьте конфликт перед использованием" : "Resolve the conflict before use",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
                .font(.headline)
            }
        }
    }

    private func cleaningTutorialKey(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func tutorialPage<Content: View>(
        title: String,
        text: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(state.accentColor)
            Text(title)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
            Text(text)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)
            content()
                .padding(16)
                .frame(maxWidth: 520, minHeight: 120)
                .background(TouchPilotStyle.groupedCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

enum TouchPilotStyle {
    static var windowBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    static var paneBackground: Color {
        Color(nsColor: .controlBackgroundColor).opacity(0.82)
    }

    static var groupedCardBackground: Color {
        Color(nsColor: .textBackgroundColor).opacity(0.76)
    }

    static var selectedRowBackground: Color {
        Color(nsColor: .separatorColor).opacity(0.22)
    }

    static var subtleStroke: Color {
        Color.secondary.opacity(0.12)
    }

    static var softShadow: Color {
        Color.black.opacity(0.06)
    }

    static var windowShadow: Color {
        Color.black.opacity(0.08)
    }
}

private struct FinderSidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        configure(view)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        view.isEmphasized = false
    }
}

private struct FloatingPanelMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        configure(view)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.material = .popover
        view.blendingMode = .withinWindow
        view.state = .followsWindowActiveState
        view.isEmphasized = true
    }
}

extension View {
    func finderSidebarPane(cornerRadius: CGFloat = 22) -> some View {
        self
            .background(FinderSidebarMaterial())
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(TouchPilotStyle.subtleStroke, lineWidth: 1)
            )
            .shadow(color: TouchPilotStyle.softShadow, radius: 14, x: 0, y: 7)
    }

    func settingsPane(cornerRadius: CGFloat = 16) -> some View {
        self
            .background(TouchPilotStyle.paneBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(TouchPilotStyle.subtleStroke, lineWidth: 1)
            )
            .shadow(color: TouchPilotStyle.softShadow, radius: 14, x: 0, y: 7)
    }

    func roundedWindowChrome(cornerRadius: CGFloat = 28) -> some View {
        self
            .background(TouchPilotStyle.windowBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: TouchPilotStyle.windowShadow, radius: 14, x: 0, y: 6)
    }

    func floatingSheetChrome(cornerRadius: CGFloat = 22) -> some View {
        self
            .background(FloatingPanelMaterial())
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.20), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.36), radius: 30, x: 0, y: 16)
            .padding(36)
            .background(Color.clear)
    }

    func floatingWindowChrome(cornerRadius: CGFloat = 22) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(TouchPilotStyle.windowBackground)
                    .shadow(color: TouchPilotStyle.windowShadow.opacity(0.55), radius: 16, x: 0, y: 7)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(TouchPilotStyle.subtleStroke, lineWidth: 1)
            )
    }

    func settingsCard(cornerRadius: CGFloat = 14) -> some View {
        self
            .background(TouchPilotStyle.groupedCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(TouchPilotStyle.subtleStroke, lineWidth: 1)
            )
            .shadow(color: TouchPilotStyle.softShadow, radius: 8, x: 0, y: 3)
    }
}

struct AppSidebarView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(state.language == .ru ? "Профили" : "Profiles")
                    .font(.headline)
                Spacer()
                Button { chooseApplication() } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.green)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(state.appTargets) { target in
                        AppTargetRow(
                            target: target,
                            selected: state.selectedAppID == target.id,
                            accent: state.accentColor
                        ) {
                            state.selectApp(target)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }

            Spacer()

            if state.selectedApp.bundleID != nil {
                VStack(spacing: 8) {
                    Toggle(
                        state.language == .ru ? "Профиль включён" : "Profile enabled",
                        isOn: Binding(
                            get: { state.selectedApp.isEnabled },
                            set: { state.setSelectedProfileEnabled($0) }
                        )
                    )
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    if state.canRemoveSelectedProfile {
                        Button(role: .destructive) {
                            state.removeSelectedProfile()
                        } label: {
                            Label(state.language == .ru ? "Удалить профиль" : "Delete profile", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(10)
            }
        }
        .background(Color.clear)
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            state.addApplicationTarget(url: url)
        }
    }
}

struct AppTargetRow: View {
    let target: AppTarget
    let selected: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: target.iconName)
                    .frame(width: 24)
                    .foregroundStyle(selected ? .white : .secondary)
                Text(target.name)
                    .lineLimit(1)
                    .foregroundStyle(selected ? .white : .primary)
                Spacer()
                if !target.isEnabled {
                    Image(systemName: "pause.circle.fill")
                        .foregroundStyle(selected ? Color.white.opacity(0.8) : .orange)
                }
            }
            .font(.system(size: 14, weight: selected ? .semibold : .regular))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? accent : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct RuleListView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                panelTitleContent(L.gestures.text(state.language), icon: "rectangle.stack.badge.play")
                Spacer()
                Text(state.selectedApp.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(state.currentRules) { rule in
                        RuleRow(
                            rule: rule,
                            selected: state.selectedRuleID == rule.id,
                            activeNow: state.lastActivatedRuleID == rule.id,
                            language: state.language,
                            accent: state.accentColor,
                            hasConflict: !state.conflicts(for: rule).isEmpty
                        ) {
                            state.selectedRuleID = rule.id
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }
            HStack {
                Button {
                    state.beginCreatingRule()
                } label: { Image(systemName: "plus") }
                Button { state.beginEditingSelectedRule() } label: { Image(systemName: "pencil") }
                    .disabled(state.selectedRuleID == nil)
                Button { state.deleteSelectedRule() } label: { Image(systemName: "trash") }
                    .disabled(state.selectedRuleID == nil)
                Spacer()
            }
            .padding(10)
        }
    }
}

struct RuleRow: View {
    let rule: GestureRule
    let selected: Bool
    let activeNow: Bool
    let language: AppLanguage
    let accent: Color
    let hasConflict: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: rule.gesture.icon)
                    .frame(width: 24)
                    .foregroundStyle(iconColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.name)
                        .lineLimit(1)
                        .foregroundStyle(selected ? .white : .primary)
                    Text(rule.triggerModifier.triggerTitle(for: rule.gesture, language: language))
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(selected ? Color.white.opacity(0.78) : .secondary)
                }
                Spacer()
                if hasConflict {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(selected ? .white : .orange)
                }
                Circle()
                    .fill(activeNow ? Color.green : (rule.isEnabled ? Color.green : Color.secondary.opacity(0.4)))
                    .frame(width: activeNow ? 10 : 7, height: activeNow ? 10 : 7)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var iconColor: Color {
        if selected { return .white }
        if activeNow { return .green }
        return rule.isEnabled ? accent : .secondary
    }

    private var backgroundColor: Color {
        if selected { return accent }
        if activeNow { return Color.green.opacity(0.12) }
        return .clear
    }
}

struct ActionListView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelTitle(L.actions.text(state.language), icon: "sparkles")
            if let rule = state.selectedRule {
                ActivationPanel(rule: rule)
                .padding(12)
                Divider()
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(rule.actions) { action in
                            ActionRow(
                                action: action,
                                selected: state.selectedActionID == action.id,
                                language: state.language,
                                accent: state.accentColor
                            ) {
                                state.selectedActionID = action.id
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
                HStack {
                    Menu {
                        Section(state.language == .ru ? "Обычные действия" : "Regular Actions") {
                            ForEach(ActionKind.regularCases) { kind in
                                Button {
                                    state.addAction(to: rule.id, kind: kind)
                                    state.showingActionEditor = true
                                } label: {
                                    Label(kind.title(state.language), systemImage: kind.icon)
                                }
                            }
                        }
                        Button {
                            state.showingActionEditor = false
                            state.showingSystemActionPicker = true
                        } label: {
                            Label(
                                state.language == .ru ? "Системные действия…" : "System Actions…",
                                systemImage: "gearshape.2"
                            )
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(state.accentColor)
                            .frame(width: 28, height: 24)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .accessibilityLabel(state.language == .ru ? "Добавить действие" : "Add action")
                    Button { state.showingActionEditor = true } label: { Image(systemName: "pencil") }
                        .disabled(state.selectedActionID == nil)
                    Button { state.deleteSelectedAction() } label: { Image(systemName: "trash") }
                        .disabled(state.selectedActionID == nil)
                    Button {
                        state.testSelectedRule()
                    } label: {
                        Image(systemName: "play.circle")
                    }
                    .disabled(rule.actions.isEmpty)
                    .help(state.language == .ru ? "Безопасно проверить действия" : "Safely test actions")
                    Spacer()
                    Button {
                        state.hideWindow?()
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .help(state.language == .ru ? "Свернуть в строку меню" : "Minimize to menu bar")
                }
                .padding(10)
            }
        }
    }
}

struct ActionRow: View {
    let action: PilotAction
    let selected: Bool
    let language: AppLanguage
    let accent: Color
    let handler: () -> Void

    var body: some View {
        Button(action: handler) {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .frame(width: 24)
                    .foregroundStyle(selected ? .white : accent)
                Text(primaryTitle)
                    .lineLimit(1)
                    .foregroundStyle(selected ? .white : .primary)
                Spacer(minLength: 12)
                Text(detailTitle)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1)
                    .foregroundStyle(selected ? .white : .primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? accent : TouchPilotStyle.selectedRowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var primaryTitle: String {
        if let systemAction = action.systemAction {
            return systemAction.title(language)
        }
        let trimmed = action.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? action.kind.title(language) : trimmed
    }

    private var iconName: String {
        action.systemAction?.icon ?? action.kind.icon
    }

    private var detailTitle: String {
        let trimmed = action.value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch action.kind {
        case .keyboardShortcut:
            return ShortcutRecorder.prettyString(from: trimmed) ?? trimmed
        case .launchApp:
            guard !trimmed.isEmpty else { return action.kind.title(language) }
            return URL(fileURLWithPath: NSString(string: trimmed).expandingTildeInPath)
                .deletingPathExtension()
                .lastPathComponent
        case .openURL, .notification:
            return trimmed.isEmpty ? action.kind.title(language) : trimmed
        case .quitFrontmostApp:
            return action.kind.title(language)
        case .systemAction:
            return action.systemAction?.category.title(language) ?? action.kind.title(language)
        }
    }
}

struct ActivationPanel: View {
    @EnvironmentObject private var state: AppState
    let rule: GestureRule
    @State private var animate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if state.lastActivatedRuleID == rule.id {
                Label(state.language == .ru ? "Жест распознан" : "Gesture detected", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.24), lineWidth: 1)
                        )
                    GestureMotionView(gesture: rule.gesture, animate: animate)
                        .scaleEffect(0.82)
                }
                .frame(width: 160, height: 104)

                VStack(alignment: .leading, spacing: 6) {
                    Label(state.language == .ru ? "Активация жеста" : "Gesture Activation", systemImage: "bolt.fill")
                        .font(.headline)
                        .foregroundStyle(state.accentColor)
                    Text(rule.triggerModifier.triggerTitle(for: rule.gesture, language: state.language))
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(2)
                    Text(state.language == .ru
                         ? "Когда этот жест распознан, TouchPilot выполнит действия ниже по порядку."
                         : "When this gesture is detected, TouchPilot runs the actions below in order.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            if rule.actions.isEmpty {
                Label(state.language == .ru ? "Действий пока нет" : "No actions yet", systemImage: "plus.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(rule.actions.enumerated()), id: \.element.id) { index, action in
                        HStack(spacing: 8) {
                            Text("\(index + 1)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(state.accentColor))
                            Image(systemName: action.systemAction?.icon ?? action.kind.icon)
                                .foregroundStyle(state.accentColor)
                                .frame(width: 18)
                            Text(action.systemAction?.title(state.language) ?? action.title)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(action.systemAction?.category.title(state.language) ?? action.kind.title(state.language))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(state.rawTouchDeviceCount > 0 ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(state.touchEngineStatus)
                        .font(.caption.weight(.medium))
                    Spacer()
                }
                if let lastRawTouchAt = state.lastRawTouchAt {
                    Text((state.language == .ru ? "Последнее касание: " : "Last touch: ")
                         + DateFormatter.localizedString(from: lastRawTouchAt, dateStyle: .none, timeStyle: .medium))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text((state.language == .ru ? "Пальцев сейчас: " : "Current fingers: ") + "\(state.rawTouchFingerCount)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if rule.gesture.family == .swipes {
                        Text((state.language == .ru ? "Чувствительность свайпов: " : "Swipe sensitivity: ")
                             + "\(Int((state.swipeSensitivity * 100).rounded()))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if rule.gesture.family == .tapsClicks {
                        Text((state.language == .ru ? "Чувствительность тапов: " : "Tap sensitivity: ")
                             + "\(Int((state.tapSensitivity * 100).rounded()))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if rule.gesture.family == .tipTaps {
                        Text((state.language == .ru ? "Чувствительность TipTap: " : "TipTap sensitivity: ")
                             + "\(Int((state.tipTapSensitivity * 100).rounded()))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(state.language == .ru ? "Коснитесь трекпада, чтобы проверить поток касаний." : "Touch the trackpad to test touch input.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let lastRecognizedGesture = state.lastRecognizedGesture {
                    Text((state.language == .ru ? "Последний жест: " : "Last gesture: ") + lastRecognizedGesture)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let lastActionStatus = state.lastActionStatus {
                    Text(lastActionStatus)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(lastActionStatus.localizedCaseInsensitiveContains("не ") || lastActionStatus.localizedCaseInsensitiveContains("not ") ? .orange : .green)
                        .lineLimit(3)
                }
                if !state.accessibilityTrusted {
                    Button {
                        state.requestAccessibilityPermission()
                    } label: {
                        Label(state.language == .ru ? "Разрешить универсальный доступ" : "Allow Accessibility", systemImage: "lock.open")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(12)
        .settingsCard()
        .onAppear { animate = true }
        .onChange(of: rule.gesture) { _, _ in
            animate = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                animate = true
            }
        }
    }
}

struct DetailView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelTitle(L.details.text(state.language), icon: "slider.horizontal.3")
            if let action = state.selectedAction {
                ActionEditor(action: action)
                    .padding(18)
            } else if let rule = state.selectedRule {
                RuleEditor(rule: rule)
                    .padding(18)
            } else {
                ContentUnavailableView(L.chooseOrCreateGesture.text(state.language), systemImage: "cursorarrow.click")
            }
            Spacer()
        }
    }
}

struct GestureEditorSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State var rule: GestureRule

    private var conflicts: [String] {
        state.conflicts(for: rule)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(state.language == .ru ? "Настройка жеста" : "Gesture Settings", systemImage: rule.gesture.icon)
                    .font(.title3.weight(.semibold))
                    .padding(.leading, 10)
                Spacer()
                Picker("", selection: $rule.triggerModifier) {
                    ForEach(GestureTriggerModifier.allCases) { modifier in
                        Text(modifier.title(state.language)).tag(modifier)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 250)
            }

            TextField(L.name.text(state.language), text: $rule.name)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(TouchPilotStyle.groupedCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(TouchPilotStyle.subtleStroke, lineWidth: 1)
                )
                .frame(height: 38)

            if !conflicts.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(conflicts, id: \.self) { conflict in
                        Label(conflict, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 10)
            }

            HStack(alignment: .top, spacing: 16) {
                GestureChooser(selectedGesture: $rule.gesture, showsPreview: false, columnWidth: 170, gestureColumnWidth: 216, columnSpacing: 6)
                    .frame(width: 392)
                    .frame(maxHeight: .infinity)

                GesturePreviewPanel(gesture: rule.gesture, language: state.language, isCompact: true)
                    .frame(width: 260)
                    .frame(maxHeight: .infinity)
                    .settingsPane(cornerRadius: 12)
            }
            .frame(height: 315)

            HStack {
                Button(state.language == .ru ? "Отмена" : "Cancel") { state.cancelGestureEditing() }
                    .keyboardShortcut(.cancelAction)
                Button(state.language == .ru ? "Свернуть" : "Minimize") {
                    state.cancelGestureEditing()
                    DispatchQueue.main.async {
                        state.hideWindow?()
                    }
                }
                .keyboardShortcut("m", modifiers: .command)
                Spacer()
                Button(state.language == .ru ? "Сохранить" : "Save") {
                    state.saveGestureEditing(ruleForSaving())
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }

            Button("") { state.cancelGestureEditing() }
                .keyboardShortcut("w", modifiers: .command)
                .frame(width: 0, height: 0)
                .hidden()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(width: 708, height: conflicts.isEmpty ? 485 : 520)
        .floatingSheetChrome(cornerRadius: 22)
    }

    private func ruleForSaving() -> GestureRule {
        var savedRule = rule
        let trimmedName = savedRule.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let placeholderNames = Set([L.newGesture.text(.ru), L.newGesture.text(.en), ""])
        if placeholderNames.contains(trimmedName) {
            savedRule.name = savedRule.triggerModifier.triggerTitle(for: savedRule.gesture, language: state.language)
        }
        return savedRule
    }
}

struct SwipeSensitivityControl: View {
    @EnvironmentObject private var state: AppState

    private var percentText: String {
        "\(Int((state.swipeSensitivity * 100).rounded()))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(state.language == .ru ? "Чувствительность свайпов" : "Swipe Sensitivity", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(percentText)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(state.accentColor)
            }

            AccentSensitivitySlider(
                value: $state.swipeSensitivity,
                range: 0.4...2.0,
                step: 0.05,
                accent: state.accentColor
            )

            HStack {
                Text(state.language == .ru ? "Точнее" : "Precise")
                Spacer()
                Text(state.language == .ru ? "Чувствительнее" : "More sensitive")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Text(state.language == .ru
                 ? "Если свайп срабатывает не с первого раза, поднимите шкалу. Если появляются случайные срабатывания, опустите."
                 : "Raise this if swipes need several tries. Lower it if accidental swipes appear.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .settingsCard()
    }
}

struct CompactSwipeSensitivityControl: View {
    @EnvironmentObject private var state: AppState

    private var percentText: String {
        "\(Int((state.swipeSensitivity * 100).rounded()))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(state.language == .ru ? "Чувствительность" : "Sensitivity", systemImage: "slider.horizontal.3")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(percentText)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(state.accentColor)
            }

            AccentSensitivitySlider(
                value: $state.swipeSensitivity,
                range: 0.4...2.0,
                step: 0.05,
                accent: state.accentColor
            )

            HStack {
                Text(state.language == .ru ? "Точнее" : "Precise")
                Spacer()
                Text(state.language == .ru ? "Легче" : "Easier")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .settingsCard(cornerRadius: 12)
    }
}

struct CompactTapSensitivityControl: View {
    @EnvironmentObject private var state: AppState

    private var percentText: String {
        "\(Int((state.tapSensitivity * 100).rounded()))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(state.language == .ru ? "Чувствительность тапов" : "Tap Sensitivity", systemImage: "hand.tap")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(percentText)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(state.accentColor)
            }

            AccentSensitivitySlider(
                value: $state.tapSensitivity,
                range: 0.4...2.0,
                step: 0.05,
                accent: state.accentColor
            )

            HStack {
                Text(state.language == .ru ? "Точнее" : "Precise")
                Spacer()
                Text(state.language == .ru ? "Легче" : "Easier")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .settingsCard(cornerRadius: 12)
    }
}

struct CompactTipTapSensitivityControl: View {
    @EnvironmentObject private var state: AppState

    private var percentText: String {
        "\(Int((state.tipTapSensitivity * 100).rounded()))%"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(state.language == .ru ? "Чувствительность TipTap" : "TipTap Sensitivity", systemImage: "hand.point.up.left.and.text")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(percentText)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(state.accentColor)
            }

            AccentSensitivitySlider(
                value: $state.tipTapSensitivity,
                range: 0.4...2.0,
                step: 0.05,
                accent: state.accentColor
            )

            HStack {
                Text(state.language == .ru ? "Точнее" : "Precise")
                Spacer()
                Text(state.language == .ru ? "Легче" : "Easier")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .settingsCard(cornerRadius: 12)
    }
}

struct AccentSensitivitySlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let accent: Color

    private let thumbDiameter: CGFloat = 15

    private var progress: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let travel = max(proxy.size.width - thumbDiameter, 1)
            let thumbOffset = travel * progress

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.20))
                    .frame(height: 4)
                    .padding(.horizontal, thumbDiameter / 2)

                Capsule()
                    .fill(accent)
                    .frame(width: max(thumbOffset, 1), height: 4)
                    .offset(x: thumbDiameter / 2)

                Circle()
                    .fill(accent)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.72), lineWidth: 1)
                    )
                    .shadow(color: accent.opacity(0.34), radius: 3, x: 0, y: 1)
                    .offset(x: thumbOffset)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        setValue(for: gesture.location.x, availableWidth: proxy.size.width)
                    }
            )
        }
        .frame(height: 18)
        .accessibilityElement()
        .accessibilityLabel("Sensitivity")
        .accessibilityValue("\(Int((value * 100).rounded()))%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value = min(value + step, range.upperBound)
            case .decrement:
                value = max(value - step, range.lowerBound)
            @unknown default:
                break
            }
        }
    }

    private func setValue(for locationX: CGFloat, availableWidth: CGFloat) {
        let travel = max(availableWidth - thumbDiameter, 1)
        let rawProgress = min(max((locationX - thumbDiameter / 2) / travel, 0), 1)
        let rawValue = range.lowerBound + Double(rawProgress) * (range.upperBound - range.lowerBound)
        let steppedValue = range.lowerBound
            + ((rawValue - range.lowerBound) / step).rounded() * step
        value = min(max(steppedValue, range.lowerBound), range.upperBound)
    }
}

struct CleaningModeSettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(
                state.language == .ru ? "Режим очистки" : "Cleaning Mode",
                systemImage: "keyboard.badge.ellipsis"
            )
            .font(.title3.weight(.semibold))

            Text(state.language == .ru
                 ? "Временно блокирует клавиатуру, трекпад, мышь и все жесты TouchPilot, чтобы можно было безопасно протереть Mac."
                 : "Temporarily locks the keyboard, trackpad, mouse, and all TouchPilot gestures so you can safely clean your Mac.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                Label(
                    state.language == .ru ? "Как разблокировать" : "How to unlock",
                    systemImage: "lock.open"
                )
                .font(.headline)

                HStack(spacing: 10) {
                    cleaningKey(state.language == .ru ? "Левый ⌘" : "Left ⌘")
                    Text("+").foregroundStyle(.secondary)
                    cleaningKey(state.language == .ru ? "Правый ⌘" : "Right ⌘")
                    Text("× 2")
                        .font(.headline)
                        .foregroundStyle(state.accentColor)
                }

                Text(state.language == .ru
                     ? "Нажмите обе клавиши Command одновременно, полностью отпустите их и повторите ещё раз."
                     : "Press both Command keys together, release both completely, then repeat once more.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TouchPilotStyle.groupedCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack(spacing: 8) {
                Image(systemName: state.accessibilityTrusted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .foregroundStyle(state.accessibilityTrusted ? .green : .orange)
                Text(state.accessibilityTrusted
                     ? (state.language == .ru ? "Универсальный доступ разрешён" : "Accessibility is allowed")
                     : (state.language == .ru ? "Требуется Универсальный доступ" : "Accessibility permission is required"))
                    .font(.caption.weight(.medium))
                Spacer()
                if !state.accessibilityTrusted {
                    Button(state.language == .ru ? "Разрешить" : "Allow") {
                        state.requestAccessibilityPermission()
                    }
                    .controlSize(.small)
                }
                Button(state.language == .ru ? "Проверить" : "Check") {
                    state.refreshAccessibilityStatus()
                }
                .controlSize(.small)
            }

            if let error = state.cleaningModeError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Spacer(minLength: 0)

            HStack {
                Button(state.language == .ru ? "Отмена" : "Cancel") {
                    state.showingCleaningModeSettings = false
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button(state.language == .ru ? "Начать очистку" : "Start Cleaning") {
                    state.startCleaningMode()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 570, height: 390)
        .floatingSheetChrome(cornerRadius: 22)
        .onAppear { state.refreshAccessibilityStatus() }
    }

    private func cleaningKey(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

struct OpenShortcutSettingsView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var shortcutRecorder = ShortcutRecorder()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(state.language == .ru ? "Открыть / скрыть окно" : "Show / Hide Window", systemImage: "keyboard")
                .font(.title3.weight(.semibold))

            ShortcutRecorderField(value: $state.openWindowShortcut, recorder: shortcutRecorder)

            HStack {
                Button(state.language == .ru ? "Сбросить" : "Reset") {
                    state.openWindowShortcut = "cmd+shift+o"
                }
                Spacer()
                Button(state.language == .ru ? "Готово" : "Done") {
                    state.showingOpenShortcutSettings = false
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(width: 460, height: 220)
        .floatingSheetChrome(cornerRadius: 22)
        .onDisappear { shortcutRecorder.stopRecording() }
    }
}

struct SystemActionPickerSheet: View {
    @EnvironmentObject private var state: AppState
    let ruleID: UUID
    @State private var selectedCategory: SystemActionCategory = .session
    @State private var selectedAction: SystemAction = .lockScreen

    private var visibleActions: [SystemAction] {
        SystemAction.allCases.filter { $0.category == selectedCategory }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "gearshape.2.fill")
                    .foregroundStyle(state.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.language == .ru ? "Системные действия" : "System Actions")
                        .font(.title3.weight(.semibold))
                    Text(state.language == .ru
                         ? "Выберите команду, которая будет выполнена при жесте."
                         : "Choose the command that will run when the gesture is detected.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 5) {
                    ForEach(SystemActionCategory.allCases) { category in
                        Button {
                            selectedCategory = category
                            if let first = SystemAction.allCases.first(where: { $0.category == category }) {
                                selectedAction = first
                            }
                        } label: {
                            HStack {
                                Text(category.title(state.language))
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.bold))
                                    .opacity(selectedCategory == category ? 1 : 0.35)
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(selectedCategory == category ? Color.white : Color.primary)
                            .background(selectedCategory == category ? state.accentColor : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
                .padding(8)
                .frame(width: 205, height: 250)
                .background(TouchPilotStyle.groupedCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 8
                    ) {
                        ForEach(visibleActions) { systemAction in
                            Button {
                                selectedAction = systemAction
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: systemAction.icon)
                                        .frame(width: 22)
                                        .foregroundStyle(selectedAction == systemAction ? Color.white : state.accentColor)
                                    Text(systemAction.title(state.language))
                                        .font(.system(size: 13, weight: .medium))
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(2)
                                    Spacer(minLength: 0)
                                    if selectedAction == systemAction {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.white)
                                    }
                                }
                                .padding(.horizontal, 11)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                .foregroundStyle(selectedAction == systemAction ? Color.white : Color.primary)
                                .background(selectedAction == systemAction ? state.accentColor : TouchPilotStyle.selectedRowBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 250)
                .background(TouchPilotStyle.groupedCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .frame(maxWidth: .infinity)

            HStack {
                if selectedAction.requiresConfirmation {
                    Label(
                        state.language == .ru ? "При запуске потребуется подтверждение" : "Confirmation will be required",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button(state.language == .ru ? "Отмена" : "Cancel") {
                    state.showingSystemActionPicker = false
                }
                .keyboardShortcut(.cancelAction)
                Button(state.language == .ru ? "Назначить" : "Assign") {
                    state.addSystemAction(to: ruleID, systemAction: selectedAction)
                    state.showingSystemActionPicker = false
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }

            Button("") { state.showingSystemActionPicker = false }
                .keyboardShortcut("w", modifiers: .command)
                .frame(width: 0, height: 0)
                .hidden()
        }
        .padding(18)
        .frame(width: 620, height: 425)
        .floatingSheetChrome(cornerRadius: 22)
    }
}

struct ActionEditorSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State var action: PilotAction
    @StateObject private var shortcutRecorder = ShortcutRecorder()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(editorTitle, systemImage: editorIcon)
                .font(.title3.weight(.semibold))

            Form {
                Picker(L.type.text(state.language), selection: $action.kind) {
                    ForEach(ActionKind.allCases) { kind in
                        Label(kind.title(state.language), systemImage: kind.icon).tag(kind)
                    }
                }
                switch action.kind {
                case .notification:
                    TextField(L.message.text(state.language), text: $action.value)
                case .openURL:
                    TextField(L.url.text(state.language), text: $action.value)
                case .launchApp:
                    AppPickerField(value: $action.value)
                case .quitFrontmostApp:
                    Text(state.language == .ru
                         ? "Закроет приложение, которое активно в момент выполнения жеста."
                         : "Quits the app that is active when the gesture runs.")
                        .foregroundStyle(.secondary)
                case .keyboardShortcut:
                    ShortcutRecorderField(value: $action.value, recorder: shortcutRecorder)
                case .systemAction:
                    Picker(state.language == .ru ? "Команда" : "Command", selection: $action.value) {
                        ForEach(SystemActionCategory.allCases) { category in
                            Section(category.title(state.language)) {
                                ForEach(SystemAction.allCases.filter { $0.category == category }) { systemAction in
                                    Label(systemAction.title(state.language), systemImage: systemAction.icon)
                                        .tag(systemAction.rawValue)
                                }
                            }
                        }
                    }
                    if selectedSystemAction?.requiresConfirmation == true {
                        Label(
                            state.language == .ru
                                ? "При выполнении TouchPilot попросит подтверждение."
                                : "TouchPilot will ask for confirmation before running this action.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(TouchPilotStyle.subtleStroke, lineWidth: 1)
            )

            HStack {
                Button(state.language == .ru ? "Отмена" : "Cancel") { state.showingActionEditor = false }
                    .keyboardShortcut(.cancelAction)
                Button(state.language == .ru ? "Свернуть" : "Minimize") {
                    state.showingActionEditor = false
                    DispatchQueue.main.async {
                        state.hideWindow?()
                    }
                }
                .keyboardShortcut("m", modifiers: .command)
                Spacer()
                Button(state.language == .ru ? "Сохранить" : "Save") {
                    action.title = selectedSystemAction?.title(state.language) ?? action.kind.title(state.language)
                    state.updateAction(action)
                    state.showingActionEditor = false
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            Button("") { state.showingActionEditor = false }
                .keyboardShortcut("w", modifiers: .command)
                .frame(width: 0, height: 0)
                .hidden()
        }
        .padding(18)
        .frame(width: 480, height: 360)
        .floatingSheetChrome(cornerRadius: 22)
        .onChange(of: action.kind) { _, newKind in
            action.title = newKind.title(state.language)
            action.value = defaultValue(for: newKind)
        }
        .onChange(of: action.value) { _, _ in
            if let selectedSystemAction {
                action.title = selectedSystemAction.title(state.language)
            }
        }
        .onDisappear { shortcutRecorder.stopRecording() }
    }

    private var selectedSystemAction: SystemAction? {
        action.systemAction
    }

    private var editorTitle: String {
        selectedSystemAction?.title(state.language) ?? action.kind.title(state.language)
    }

    private var editorIcon: String {
        selectedSystemAction?.icon ?? action.kind.icon
    }

    private func defaultValue(for kind: ActionKind) -> String {
        switch kind {
        case .notification: return state.language == .ru ? "Жест распознан" : "Gesture detected"
        case .openURL: return "https://www.apple.com"
        case .launchApp: return "/System/Applications/Notes.app"
        case .quitFrontmostApp: return ""
        case .keyboardShortcut: return "cmd+space"
        case .systemAction: return SystemAction.lockScreen.rawValue
        }
    }
}

struct AppPickerField: View {
    @EnvironmentObject private var state: AppState
    @Binding var value: String

    private var displayName: String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return state.language == .ru ? "Приложение не выбрано" : "No app selected"
        }
        let url = URL(fileURLWithPath: NSString(string: trimmed).expandingTildeInPath)
        return url.deletingPathExtension().lastPathComponent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(state.language == .ru ? "Приложение" : "Application")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Image(systemName: "app.badge")
                    .foregroundStyle(state.accentColor)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(value.isEmpty ? (state.language == .ru ? "Выберите .app через Finder" : "Choose an .app in Finder") : value)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button {
                    chooseApplication()
                } label: {
                    Label(state.language == .ru ? "Выбрать" : "Choose", systemImage: "folder")
                }
                .buttonStyle(.bordered)
            }
            .padding(10)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
        }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = state.language == .ru ? "Выберите приложение" : "Choose Application"
        panel.prompt = state.language == .ru ? "Выбрать" : "Choose"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            value = url.path
        }
    }
}

struct ShortcutRecorderField: View {
    @EnvironmentObject private var state: AppState
    @Binding var value: String
    @ObservedObject var recorder: ShortcutRecorder

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(state.language == .ru ? "Сочетание клавиш" : "Keyboard Shortcut")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(recorder.isRecording ? Color.red.opacity(0.08) : Color(nsColor: .textBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(recorder.isRecording ? Color.red : Color.secondary.opacity(0.24), lineWidth: recorder.isRecording ? 2 : 1)
                        )
                    if recorder.isRecording {
                        Label(state.language == .ru ? "Нажмите сочетание..." : "Press shortcut...", systemImage: "record.circle")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.red)
                    } else {
                        Text(ShortcutRecorder.prettyString(from: value) ?? (state.language == .ru ? "Не задано" : "Not set"))
                            .font(.system(size: 20, weight: .semibold, design: .monospaced))
                            .foregroundStyle(value.isEmpty ? .secondary : .primary)
                    }
                }
                .frame(height: 56)

                if recorder.isRecording {
                    Button {
                        recorder.stopRecording()
                    } label: {
                        Label(state.language == .ru ? "Стоп" : "Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button {
                        recorder.startRecording { shortcut in
                            value = shortcut.inputString
                        }
                    } label: {
                        Label(state.language == .ru ? "Записать" : "Record", systemImage: "record.circle")
                    }
                    .buttonStyle(.bordered)
                }
            }
            Text(state.language == .ru ? "Нажмите кнопку и введите комбинацию, например ⌘Space." : "Press Record, then type a shortcut such as ⌘Space.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct RecordedShortcut {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags

    var inputString: String {
        var parts: [String] = []
        if modifiers.contains(.command) { parts.append("cmd") }
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option) { parts.append("alt") }
        if modifiers.contains(.shift) { parts.append("shift") }
        parts.append(KeyCodes.inputName(for: keyCode))
        return parts.joined(separator: "+")
    }

    var displayString: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(KeyCodes.displayName(for: keyCode))
        return parts.joined()
    }
}

@MainActor
final class ShortcutRecorder: ObservableObject {
    @Published var isRecording = false
    private var localMonitor: Any?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var completion: ((RecordedShortcut) -> Void)?

    func startRecording(_ completion: @escaping (RecordedShortcut) -> Void) {
        stopRecording()
        self.completion = completion
        isRecording = true

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.capture(event: event)
            return nil
        }

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            MainActor.assumeIsolated {
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let recorder = Unmanaged<ShortcutRecorder>.fromOpaque(refcon).takeUnretainedValue()
                guard recorder.isRecording else { return Unmanaged.passUnretained(event) }

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = recorder.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                if type == .keyDown {
                    recorder.capture(event: event)
                    return nil
                }
                return Unmanaged.passUnretained(event)
            }
        }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: 1 << CGEventType.keyDown.rawValue,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        if let eventTap {
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            if let runLoopSource {
                CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
        }
    }

    func stopRecording() {
        completion = nil
        isRecording = false
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
    }

    private func capture(event: NSEvent) {
        guard event.keyCode != 53 else {
            stopRecording()
            return
        }
        finish(RecordedShortcut(
            keyCode: event.keyCode,
            modifiers: event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        ))
    }

    private func capture(event: CGEvent) {
        let flags = event.flags
        var modifiers: NSEvent.ModifierFlags = []
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }

        finish(RecordedShortcut(
            keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
            modifiers: modifiers
        ))
    }

    private func finish(_ shortcut: RecordedShortcut) {
        guard isRecording else { return }
        let completion = completion
        stopRecording()
        completion?(shortcut)
    }

    nonisolated static func prettyString(from value: String) -> String? {
        let parts = value.lowercased().split(separator: "+").map(String.init)
        guard let key = parts.last, !key.isEmpty else { return nil }
        var display = ""
        if parts.contains("ctrl") || parts.contains("control") { display += "⌃" }
        if parts.contains("alt") || parts.contains("option") { display += "⌥" }
        if parts.contains("shift") { display += "⇧" }
        if parts.contains("cmd") || parts.contains("command") { display += "⌘" }
        display += KeyCodes.displayName(forInputName: key)
        return display
    }

    static func matches(event: NSEvent, shortcut value: String) -> Bool {
        let parts = value.lowercased().split(separator: "+").map(String.init)
        guard let key = parts.last,
              let keyCode = KeyCodes.keyCode(for: key) else { return false }

        var expected: NSEvent.ModifierFlags = []
        if parts.contains("cmd") || parts.contains("command") { expected.insert(.command) }
        if parts.contains("ctrl") || parts.contains("control") { expected.insert(.control) }
        if parts.contains("alt") || parts.contains("option") { expected.insert(.option) }
        if parts.contains("shift") { expected.insert(.shift) }

        let actual = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return event.keyCode == keyCode && actual == expected
    }

    static func matches(event: CGEvent, shortcut value: String) -> Bool {
        let parts = value.lowercased().split(separator: "+").map(String.init)
        guard let key = parts.last,
              let keyCode = KeyCodes.keyCode(for: key) else { return false }

        var expected = CGEventFlags()
        if parts.contains("cmd") || parts.contains("command") { expected.insert(.maskCommand) }
        if parts.contains("ctrl") || parts.contains("control") { expected.insert(.maskControl) }
        if parts.contains("alt") || parts.contains("option") { expected.insert(.maskAlternate) }
        if parts.contains("shift") { expected.insert(.maskShift) }

        let actual = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        let eventKeyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        return eventKeyCode == keyCode && actual == expected
    }

    static func carbonHotKey(from value: String) -> (keyCode: UInt32, modifiers: UInt32)? {
        let parts = value.lowercased().split(separator: "+").map(String.init)
        guard let key = parts.last,
              let keyCode = KeyCodes.keyCode(for: key) else { return nil }

        var modifiers: UInt32 = 0
        if parts.contains("cmd") || parts.contains("command") { modifiers |= UInt32(cmdKey) }
        if parts.contains("ctrl") || parts.contains("control") { modifiers |= UInt32(controlKey) }
        if parts.contains("alt") || parts.contains("option") { modifiers |= UInt32(optionKey) }
        if parts.contains("shift") { modifiers |= UInt32(shiftKey) }

        return (UInt32(keyCode), modifiers)
    }
}

struct RuleEditor: View {
    @EnvironmentObject private var state: AppState
    @State var rule: GestureRule

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                TextField(L.name.text(state.language), text: $rule.name)
                    .textFieldStyle(.roundedBorder)
                Toggle(L.enabled.text(state.language), isOn: $rule.isEnabled)
                    .toggleStyle(.switch)
            }

            Picker(state.language == .ru ? "Триггер" : "Trigger", selection: $rule.triggerModifier) {
                ForEach(GestureTriggerModifier.allCases) { modifier in
                    Text(modifier.title(state.language)).tag(modifier)
                }
            }
            .pickerStyle(.segmented)

            GestureChooser(selectedGesture: $rule.gesture)
        }
        .onChange(of: rule) { _, newValue in state.selectedRule = newValue }
    }
}

struct GestureChooser: View {
    @EnvironmentObject private var state: AppState
    @Binding var selectedGesture: GestureKind
    var showsPreview = true
    var columnWidth: CGFloat = 238
    var gestureColumnWidth: CGFloat?
    var columnSpacing: CGFloat = 12
    @State private var selectedFamily: GestureFamily = .swipes

    private var gestures: [GestureKind] {
        GestureKind.allCases.filter { $0.family == selectedFamily }
    }

    var body: some View {
        HStack(spacing: columnSpacing) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(GestureFamily.allCases) { family in
                    Button {
                        selectedFamily = family
                        if !gesturesFor(family).contains(selectedGesture), let first = gesturesFor(family).first {
                            selectedGesture = first
                        }
                    } label: {
                        Label(family.title(state.language), systemImage: family.icon)
                            .font(.system(size: 12, weight: selectedFamily == family ? .semibold : .regular))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 7)
                            .foregroundStyle(selectedFamily == family ? .white : .primary)
                            .background(selectedFamily == family ? state.accentColor : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .frame(width: columnWidth)
            .frame(maxHeight: .infinity)
            .padding(10)
            .settingsPane(cornerRadius: 14)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(gestures) { gesture in
                        GestureChoiceRow(
                            gesture: gesture,
                            selected: selectedGesture == gesture,
                            language: state.language,
                            accent: state.accentColor
                        ) {
                            selectedGesture = gesture
                        }
                    }
                }
                .padding(10)
            }
            .frame(width: gestureColumnWidth ?? columnWidth)
            .frame(maxHeight: .infinity)
            .settingsPane(cornerRadius: 14)

            if showsPreview {
                GesturePreviewPanel(gesture: selectedGesture, language: state.language)
                    .frame(width: columnWidth)
                    .frame(maxHeight: .infinity)
                    .settingsPane(cornerRadius: 14)
            }
        }
        .onAppear {
            selectedFamily = selectedGesture.family
        }
        .onChange(of: selectedGesture) { _, newValue in
            selectedFamily = newValue.family
        }
    }

    private func gesturesFor(_ family: GestureFamily) -> [GestureKind] {
        GestureKind.allCases.filter { $0.family == family }
    }
}

struct GestureChoiceRow: View {
    let gesture: GestureKind
    let selected: Bool
    let language: AppLanguage
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: gesture.icon)
                    .frame(width: 24)
                    .foregroundStyle(selected ? .white : accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(gesture.title(language))
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(2)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(selected ? accent : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }
}

struct GesturePreviewPanel: View {
    @EnvironmentObject private var state: AppState
    let gesture: GestureKind
    let language: AppLanguage
    var isCompact = false
    @State private var animate = false

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 9 : 12) {
            Text(language == .ru ? "Вид жеста" : "Gesture Preview")
                .font(.headline)

            ZStack {
                RoundedRectangle(cornerRadius: isCompact ? 12 : 16)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: isCompact ? 12 : 16)
                            .stroke(Color.secondary.opacity(0.28), lineWidth: 1)
                    )
                GestureMotionView(gesture: gesture, animate: animate)
                    .id(gesture)
            }
            .frame(height: isCompact ? 118 : 170)

            Label(gesture.title(language), systemImage: gesture.icon)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)

            if !isCompact {
                Text(language == .ru
                     ? "Выберите жест слева. Это окно показывает, как его выполнить на трекпаде."
                     : "Choose a gesture on the left. This panel shows how to perform it on the trackpad.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if gesture.family == .swipes {
                CompactSwipeSensitivityControl()
            }
            if gesture.family == .tapsClicks {
                CompactTapSensitivityControl()
            }
            if gesture.family == .tipTaps {
                CompactTipTapSensitivityControl()
            }

            Spacer()
        }
        .padding(14)
        .background(Color.clear)
        .onAppear { animate = true }
        .onChange(of: gesture) { _, _ in
            animate = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                animate = true
            }
        }
    }
}

struct GestureMotionView: View {
    let gesture: GestureKind
    let animate: Bool

    var body: some View {
        switch gesture {
        case .twoFingerSwipeUp:
            SwipePreview(fingers: 2, dx: 0, dy: -42, animate: animate)
        case .twoFingerSwipeDown:
            SwipePreview(fingers: 2, dx: 0, dy: 42, animate: animate)
        case .twoFingerSwipeLeft:
            SwipePreview(fingers: 2, dx: -48, dy: 0, animate: animate)
        case .twoFingerSwipeRight:
            SwipePreview(fingers: 2, dx: 48, dy: 0, animate: animate)
        case .threeFingerSwipeUp:
            SwipePreview(fingers: 3, dx: 0, dy: -42, animate: animate)
        case .threeFingerSwipeDown:
            SwipePreview(fingers: 3, dx: 0, dy: 42, animate: animate)
        case .threeFingerSwipeLeft:
            SwipePreview(fingers: 3, dx: -48, dy: 0, animate: animate)
        case .threeFingerSwipeRight:
            SwipePreview(fingers: 3, dx: 48, dy: 0, animate: animate)
        case .fourFingerSwipeUp:
            SwipePreview(fingers: 4, dx: 0, dy: -42, animate: animate)
        case .fourFingerSwipeDown:
            SwipePreview(fingers: 4, dx: 0, dy: 42, animate: animate)
        case .fourFingerSwipeLeft:
            SwipePreview(fingers: 4, dx: -48, dy: 0, animate: animate)
        case .fourFingerSwipeRight:
            SwipePreview(fingers: 4, dx: 48, dy: 0, animate: animate)
        case .twoFingerPinchIn:
            PinchPreview(inward: true, animate: animate)
        case .twoFingerPinchOut:
            PinchPreview(inward: false, animate: animate)
        case .twoFingerRotateLeft:
            RotatePreview(clockwise: false, animate: animate)
        case .twoFingerRotateRight:
            RotatePreview(clockwise: true, animate: animate)
        case .twoFingerTap:
            TapPreview(fingers: 2, double: false, click: false, animate: animate)
        case .twoFingerDoubleTap:
            TapPreview(fingers: 2, double: true, click: false, animate: animate)
        case .twoFingerClick:
            TapPreview(fingers: 2, double: false, click: true, animate: animate)
        case .threeFingerTap:
            TapPreview(fingers: 3, double: false, click: false, animate: animate)
        case .threeFingerClick:
            TapPreview(fingers: 3, double: false, click: true, animate: animate)
        case .fourFingerTap:
            TapPreview(fingers: 4, double: false, click: false, animate: animate)
        case .fiveFingerTap:
            TapPreview(fingers: 5, double: false, click: false, animate: animate)
        case .tipTapLeft:
            TipTapPreview(direction: -1, animate: animate)
        case .tipTapRight:
            TipTapPreview(direction: 1, animate: animate)
        case .tipTapMiddle:
            TipTapPreview(direction: 0, restingFingers: 2, animate: animate)
        case .tipTapThirdFingerLeft:
            TipTapPreview(direction: -1, restingFingers: 2, animate: animate)
        case .tipTapThirdFingerRight:
            TipTapPreview(direction: 1, restingFingers: 2, animate: animate)
        case .circleClockwise:
            CirclePreview(clockwise: true)
        case .circleCounterClockwise:
            CirclePreview(clockwise: false)
        case .drawTriangle:
            TrianglePreview()
        case .leftEdgeSlideUp:
            EdgeSlidePreview(x: -78, up: true, animate: animate)
        case .leftEdgeSlideDown:
            EdgeSlidePreview(x: -78, up: false, animate: animate)
        case .rightEdgeSlideUp:
            EdgeSlidePreview(x: 78, up: true, animate: animate)
        case .rightEdgeSlideDown:
            EdgeSlidePreview(x: 78, up: false, animate: animate)
        case .cornerClickTopLeft:
            ZoneClickPreview(x: -68, y: -50, wide: false, animate: animate)
        case .cornerClickTopRight:
            ZoneClickPreview(x: 68, y: -50, wide: false, animate: animate)
        case .cornerClickBottomLeft:
            ZoneClickPreview(x: -68, y: 50, wide: false, animate: animate)
        case .cornerClickBottomRight:
            ZoneClickPreview(x: 68, y: 50, wide: false, animate: animate)
        case .middleClickTop:
            ZoneClickPreview(x: 0, y: -50, wide: true, animate: animate)
        case .middleClickBottom:
            ZoneClickPreview(x: 0, y: 50, wide: true, animate: animate)
        case .twoFingerPressDragLeft:
            PressDragPreview(fingers: 2, dx: -48, animate: animate)
        case .twoFingerPressDragRight:
            PressDragPreview(fingers: 2, dx: 48, animate: animate)
        case .threeFingerPressDragLeft:
            PressDragPreview(fingers: 3, dx: -48, animate: animate)
        case .threeFingerPressDragRight:
            PressDragPreview(fingers: 3, dx: 48, animate: animate)
        }
    }
}

struct FingerBubble: View {
    @Environment(\.touchPilotAccent) private var accent
    var size: CGFloat = 18
    var active = true

    var body: some View {
        Circle()
            .fill(accent.opacity(active ? 0.85 : 0.35))
            .frame(width: size, height: size)
            .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 1))
            .shadow(color: accent.opacity(active ? 0.35 : 0.12), radius: 5)
    }
}

struct SwipePreview: View {
    @Environment(\.touchPilotAccent) private var accent
    let fingers: Int
    let dx: CGFloat
    let dy: CGFloat
    let animate: Bool

    var body: some View {
        ZStack {
            ForEach(0..<fingers, id: \.self) { index in
                FingerBubble()
                    .offset(x: (CGFloat(index) - CGFloat(fingers - 1) / 2) * 18 + (animate ? dx : 0),
                            y: animate ? dy : 0)
            }
            Image(systemName: arrowName)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(accent.opacity(0.45))
                .offset(x: dx * 0.35, y: dy * 0.35)
        }
        .animation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true), value: animate)
    }

    private var arrowName: String {
        if abs(dx) > abs(dy) { return dx < 0 ? "arrow.left" : "arrow.right" }
        return dy < 0 ? "arrow.up" : "arrow.down"
    }
}

struct PinchPreview: View {
    @Environment(\.touchPilotAccent) private var accent
    let inward: Bool
    let animate: Bool

    var body: some View {
        let start: CGFloat = inward ? 46 : 18
        let end: CGFloat = inward ? 18 : 46
        ZStack {
            FingerBubble().offset(x: -(animate ? end : start), y: -(animate ? end : start) * 0.55)
            FingerBubble().offset(x: animate ? end : start, y: (animate ? end : start) * 0.55)
            Image(systemName: inward ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .foregroundStyle(accent.opacity(0.38))
        }
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: animate)
    }
}

struct RotatePreview: View {
    @Environment(\.touchPilotAccent) private var accent
    let clockwise: Bool
    let animate: Bool

    var body: some View {
        ZStack {
            FingerBubble().offset(y: -26)
            FingerBubble().offset(y: 26)
            Image(systemName: clockwise ? "arrow.clockwise" : "arrow.counterclockwise")
                .foregroundStyle(accent.opacity(0.38))
                .font(.system(size: 30))
        }
        .rotationEffect(.degrees(animate ? (clockwise ? 55 : -55) : 0))
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: animate)
    }
}

struct TapPreview: View {
    @Environment(\.touchPilotAccent) private var accent
    let fingers: Int
    let double: Bool
    let click: Bool
    let animate: Bool

    var body: some View {
        ZStack {
            ForEach(0..<fingers, id: \.self) { index in
                let x = CGFloat(index) * 16 - CGFloat(fingers - 1) * 8
                Circle()
                    .stroke(accent.opacity(animate ? 0 : 0.42), lineWidth: click ? 3 : 1.5)
                    .frame(width: animate ? 42 : 18, height: animate ? 42 : 18)
                    .offset(x: x)
                FingerBubble(active: animate)
                    .scaleEffect(animate ? 1 : 0.68)
                    .offset(x: x)
            }
            if double {
                Text("x2")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .offset(y: 38)
            }
        }
        .animation(.easeInOut(duration: double ? 0.38 : 0.65).repeatForever(autoreverses: true), value: animate)
    }
}

struct TipTapPreview: View {
    let direction: Int
    var restingFingers = 1
    let animate: Bool

    var body: some View {
        ZStack {
            if restingFingers == 2 {
                FingerBubble(size: 16, active: false).offset(x: -30)
                FingerBubble(size: 16, active: false).offset(x: 30)
                FingerBubble()
                    .offset(x: CGFloat(direction) * 62, y: animate ? 0 : -30)
            } else {
                FingerBubble(size: 16, active: false).offset(x: CGFloat(-direction) * 28)
                FingerBubble().offset(x: CGFloat(direction) * 28, y: animate ? 0 : -30)
            }
        }
        .animation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true), value: animate)
    }
}

struct CirclePreview: View {
    @Environment(\.touchPilotAccent) private var accent
    let clockwise: Bool

    var body: some View {
        TimelineView(.animation) { timeline in
            let period = 1.8
            let progress = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
            let angle = CGFloat(progress) * .pi * 2 * (clockwise ? 1 : -1) - .pi / 2
            ZStack {
                Circle()
                    .stroke(accent.opacity(0.22), lineWidth: 2)
                    .frame(width: 78, height: 78)
                Image(systemName: clockwise ? "arrow.clockwise" : "arrow.counterclockwise")
                    .foregroundStyle(accent.opacity(0.35))
                FingerBubble()
                    .offset(x: cos(angle) * 39, y: sin(angle) * 39)
            }
        }
    }
}

struct TrianglePreview: View {
    @Environment(\.touchPilotAccent) private var accent

    var body: some View {
        TimelineView(.animation) { timeline in
            let period = 2.2
            let p = CGFloat(timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period)
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let points = [
                    CGPoint(x: center.x, y: center.y - 44),
                    CGPoint(x: center.x + 48, y: center.y + 34),
                    CGPoint(x: center.x - 48, y: center.y + 34)
                ]
                var path = Path()
                path.move(to: points[0])
                path.addLine(to: points[1])
                path.addLine(to: points[2])
                path.closeSubpath()
                context.stroke(path, with: .color(accent.opacity(0.28)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                let segment = min(Int(p * 3), 2)
                let frac = p * 3 - CGFloat(segment)
                let a = points[segment]
                let b = points[(segment + 1) % 3]
                let finger = CGPoint(x: a.x + (b.x - a.x) * frac, y: a.y + (b.y - a.y) * frac)
                context.fill(Circle().path(in: CGRect(x: finger.x - 9, y: finger.y - 9, width: 18, height: 18)), with: .color(accent.opacity(0.85)))
            }
        }
    }
}

struct EdgeSlidePreview: View {
    @Environment(\.touchPilotAccent) private var accent
    let x: CGFloat
    let up: Bool
    let animate: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(accent.opacity(0.12))
                .frame(width: 26, height: 132)
                .offset(x: x)
            Image(systemName: up ? "arrow.up" : "arrow.down")
                .foregroundStyle(accent.opacity(0.38))
                .offset(x: x)
            FingerBubble()
                .offset(x: x, y: animate ? (up ? -50 : 50) : (up ? 50 : -50))
        }
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: false), value: animate)
    }
}

struct ZoneClickPreview: View {
    @Environment(\.touchPilotAccent) private var accent
    let x: CGFloat
    let y: CGFloat
    let wide: Bool
    let animate: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(accent.opacity(animate ? 0.24 : 0.1))
                .frame(width: wide ? 86 : 46, height: 34)
                .offset(x: x, y: y)
            FingerBubble(active: animate)
                .scaleEffect(animate ? 1 : 0.7)
                .offset(x: x, y: y)
        }
        .animation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true), value: animate)
    }
}

struct PressDragPreview: View {
    @Environment(\.touchPilotAccent) private var accent
    let fingers: Int
    let dx: CGFloat
    let animate: Bool

    var body: some View {
        ZStack {
            ForEach(0..<fingers, id: \.self) { index in
                FingerBubble(active: true)
                    .scaleEffect(0.92)
                    .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 2))
                    .offset(x: CGFloat(index) * 18 - CGFloat(fingers - 1) * 9 + (animate ? dx : 0))
            }
            Image(systemName: dx < 0 ? "arrow.left" : "arrow.right")
                .foregroundStyle(accent.opacity(0.4))
                .offset(x: dx * 0.35, y: 34)
        }
        .animation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true), value: animate)
    }
}

struct ActionEditor: View {
    @EnvironmentObject private var state: AppState
    @State var action: PilotAction

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                action.systemAction?.title(state.language) ?? action.kind.title(state.language),
                systemImage: action.systemAction?.icon ?? action.kind.icon
            )
                .font(.headline)
            Form {
            Picker(L.type.text(state.language), selection: $action.kind) {
                ForEach(ActionKind.allCases) { kind in
                    Label(kind.title(state.language), systemImage: kind.icon).tag(kind)
                }
            }
            switch action.kind {
            case .notification:
                TextField(L.message.text(state.language), text: $action.value)
            case .openURL:
                TextField(L.url.text(state.language), text: $action.value)
            case .launchApp:
                TextField(L.appPath.text(state.language), text: $action.value)
            case .quitFrontmostApp:
                Text(state.language == .ru
                     ? "Закроет приложение, которое активно в момент выполнения жеста."
                     : "Quits the app that is active when the gesture runs.")
                    .foregroundStyle(.secondary)
            case .keyboardShortcut:
                TextField(L.shortcut.text(state.language), text: $action.value)
            case .systemAction:
                Picker(state.language == .ru ? "Команда" : "Command", selection: $action.value) {
                    ForEach(SystemActionCategory.allCases) { category in
                        Section(category.title(state.language)) {
                            ForEach(SystemAction.allCases.filter { $0.category == category }) { systemAction in
                                Label(systemAction.title(state.language), systemImage: systemAction.icon)
                                    .tag(systemAction.rawValue)
                            }
                        }
                    }
                }
            }
            }
        }
        .formStyle(.grouped)
        .onChange(of: action.kind) { _, newKind in
            action.title = newKind.title(state.language)
            if newKind == .systemAction {
                action.value = SystemAction.lockScreen.rawValue
            }
        }
        .onChange(of: action.value) { _, _ in
            if let systemAction = action.systemAction {
                action.title = systemAction.title(state.language)
            }
        }
        .onChange(of: action) { _, newValue in state.updateAction(newValue) }
    }
}

struct LogView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelTitle(L.liveLog.text(state.language), icon: "waveform.path.ecg")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(state.log, id: \.self) { entry in
                        Text(entry)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
            }
        }
        .background(Color.clear)
    }
}

@ViewBuilder
func panelTitle(_ title: String, icon: String) -> some View {
    HStack(spacing: 8) {
        panelTitleContent(title, icon: icon)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .background(Color.clear)
}

@ViewBuilder
func panelTitleContent(_ title: String, icon: String) -> some View {
    PanelTitleContentView(title: title, icon: icon)
}

struct PanelTitleContentView: View {
    @Environment(\.touchPilotAccent) private var accent
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(accent)
            Text(title)
                .font(.headline)
            Spacer()
        }
    }
}
