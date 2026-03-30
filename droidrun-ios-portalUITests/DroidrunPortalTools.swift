//
//  DroidrunPortal.swift
//  droidrun-ios-portal
//
//  Created by Timo Beckmann on 03.06.25.
//

import Foundation
import XCTest

extension XCUIDevice.Button {
    init?(rawValue: Int) {
        switch rawValue {
        case 1: self = .home
        #if !targetEnvironment(simulator)
        case 2: self = .volumeUp
        case 3: self = .volumeDown
        #endif
        case 4: self = .action
        case 5: self = .camera
        default: return nil
        }
    }
}

extension DroidrunPortalTools {
    enum Error: Swift.Error, LocalizedError {
        case invalidTool(name: String?, message: String)
        case noAppFound

        var errorDescription: String? {
            switch self {
            case .invalidTool(let name, let message):
                "Invalid tool \(name ?? "unknown"): \(message)"
            case .noAppFound:
                "No app found to interact with, try to open an app first."
            }
        }
    }
}

struct FocusedElement: Codable {
    let text: String
    let className: String
    let resourceId: String
}

final class DroidrunPortalTools: XCTestCase {
    var app: XCUIApplication?
    var bundleIdentifier: String?

    static let shared = DroidrunPortalTools()

    func reset() {
        self.bundleIdentifier = "com.apple.springboard"
        self.app = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        self.app?.activate()
        print("reset to homescreen")
    }

    // MARK: - State

    @MainActor
    func fetchStateFull() throws -> StateFullResponse {
        let a11yTree = try fetchAccessibilityTree()

        guard let app else {
            return StateFullResponse(
                a11y_tree: a11yTree,
                phone_state: StateFullPhoneState(
                    currentApp: "",
                    packageName: "",
                    keyboardVisible: false,
                    isEditable: false,
                    focusedElement: nil
                ),
                device_context: DeviceContext(
                    screen_bounds: ScreenBounds(width: 0, height: 0)
                )
            )
        }

        let frame = app.windows.element(boundBy: 0).frame

        // Build currentApp from nav bar title / first static text
        var currentApp = ""
        let navBar = app.navigationBars.firstMatch
        if navBar.exists, !navBar.identifier.isEmpty {
            currentApp = navBar.identifier
        }
        let label = app.staticTexts.firstMatch
        if label.exists, !label.label.isEmpty {
            if !currentApp.isEmpty { currentApp += " - " }
            currentApp += label.label
        }

        let keyboardVisible = app.keyboards.element.exists && app.keyboards.element.isHittable

        let focusedElementState = findFocusedElement()

        let editableTypes: Set<String> = ["TextField", "SecureTextField", "TextView", "SearchField"]
        let isEditable = focusedElementState != nil && editableTypes.contains(focusedElementState!.className)

        return StateFullResponse(
            a11y_tree: a11yTree,
            phone_state: StateFullPhoneState(
                currentApp: currentApp,
                packageName: "",
                keyboardVisible: keyboardVisible,
                isEditable: isEditable,
                focusedElement: focusedElementState
            ),
            device_context: DeviceContext(
                screen_bounds: ScreenBounds(width: frame.width, height: frame.height)
            )
        )
    }

    @MainActor
    private func findFocusedElement() -> FocusedElement? {
        guard let app else { return nil }
        let focused = app.descendants(matching: .any)
            .matching(NSPredicate(format: "hasKeyboardFocus == true")).firstMatch
        guard focused.exists else { return nil }

        let rawValue = focused.value as? String ?? ""
        let value = rawValue == focused.placeholderValue ? "" : rawValue
        return FocusedElement(
            text: value,
            className: Self.elementTypeName(focused.elementType),
            resourceId: focused.identifier
        )
    }

    private static func elementTypeName(_ type: XCUIElement.ElementType) -> String {
        switch type {
        case .textField:       return "TextField"
        case .secureTextField: return "SecureTextField"
        case .textView:        return "TextView"
        case .searchField:     return "SearchField"
        case .button:          return "Button"
        case .staticText:      return "StaticText"
        case .image:           return "Image"
        case .cell:            return "Cell"
        case .switch:          return "Switch"
        case .slider:          return "Slider"
        case .picker:          return "Picker"
        case .link:            return "Link"
        case .webView:         return "WebView"
        default:               return "Other(\(type.rawValue))"
        }
    }

    // MARK: - App management

    @MainActor
    func openApp(bundleIdentifier: String) throws {
        if bundleIdentifier == self.bundleIdentifier, app != nil {
            app?.activate()
            return
        }

        let app = XCUIApplication(bundleIdentifier: bundleIdentifier)

        if bundleIdentifier == "com.apple.springboard" {
            app.activate() // Avoid relaunching springboard since that locks the phone
        } else {
            app.launch()
        }

        self.bundleIdentifier = bundleIdentifier
        self.app = app
    }

    // MARK: - Accessibility

    @MainActor
    func fetchAccessibilityTree() throws -> String {
        guard let app else {
            throw Error.noAppFound
        }
        return app.accessibilityTree()
    }

    // MARK: - Gestures

    @MainActor
    func tapElement(rect coordinateString: String, count: Int?, longPress: Bool?) throws {
        print("Tap \(coordinateString) \(count ?? 1) times long: \(longPress ?? false)")
        guard let app else {
            throw Error.noAppFound
        }
        let coordinate = NSCoder.cgRect(for: coordinateString)
        let midPoint = CGPoint(x: coordinate.midX, y: coordinate.midY)
        let startCoordinate = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        let targetCoordinate = startCoordinate.withOffset(CGVector(dx: midPoint.x, dy: midPoint.y))
        if longPress == true {
            targetCoordinate.press(forDuration: 0.5)
        } else {
            if count == 2 {
                targetCoordinate.doubleTap()
            } else {
                targetCoordinate.tap()
            }
        }
    }

    @MainActor
    func swipe(x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat, duration: Double) throws {
        print("Swipe from (\(x1),\(y1)) to (\(x2),\(y2)) duration: \(duration)s")
        guard let app else {
            throw Error.noAppFound
        }
        let root = app.coordinate(withNormalizedOffset: .zero)
        let start = root.withOffset(CGVector(dx: x1, dy: y1))
        let end = root.withOffset(CGVector(dx: x2, dy: y2))
        start.press(forDuration: duration, thenDragTo: end)
    }

    // MARK: - Text input

    @MainActor
    @discardableResult
    func clearText(rect: String? = nil, timeout: TimeInterval = 30) throws -> ClearResponse {
        print("Clear text \(rect ?? "<focused>") timeout: \(timeout)s")
        guard let app else {
            throw Error.noAppFound
        }

        if let rect {
            try tapElement(rect: rect, count: 1, longPress: false)
        }

        let focusedElement = app.descendants(matching: .any)
            .matching(NSPredicate(format: "hasKeyboardFocus == true")).firstMatch
        if !focusedElement.exists {
            _ = focusedElement.waitForExistence(timeout: 2)
        }
        guard focusedElement.exists else {
            throw Error.invalidTool(name: "clearText", message: "No element has keyboard focus.")
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        var totalDeleted = 0

        while true {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            if elapsed > timeout {
                print("Clear timed out after \(String(format: "%.1f", elapsed))s")
                break
            }

            let currentValue = focusedElement.value as? String ?? ""
            if currentValue.isEmpty || currentValue == focusedElement.placeholderValue {
                break
            }

            let countBefore = currentValue.count

            let endCoordinate = focusedElement.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.99))
            endCoordinate.tap()
            let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: countBefore)
            app.typeText(deleteString)

            let afterFast = focusedElement.value as? String ?? ""
            if afterFast.isEmpty || afterFast == focusedElement.placeholderValue {
                totalDeleted += countBefore
                break
            }

            let deletedThisPass = countBefore - afterFast.count
            if deletedThisPass > 0 {
                totalDeleted += deletedThisPass
                continue
            }

            app.typeText(XCUIKeyboardKey.delete.rawValue)
            let afterSingle = focusedElement.value as? String ?? ""
            let singleProgress = afterFast.count - afterSingle.count

            if singleProgress > 0 {
                totalDeleted += singleProgress
                continue
            }

            print("No progress after fast + single delete, stopping")
            break
        }

        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        print("Cleared \(totalDeleted) chars in \(String(format: "%.1f", elapsed))ms")

        return ClearResponse(
            message: "cleared \(totalDeleted) characters",
            charactersDeleted: totalDeleted,
            method: "adaptive",
            durationMs: elapsed
        )
    }

    @MainActor
    func enterText(rect: String? = nil, text: String) async throws {
        print("Enter Text \(rect ?? "<focused>") -> \(text.prefix(50))... (\(text.count) chars)")
        guard let app else {
            throw Error.noAppFound
        }

        if let rect {
            try tapElement(rect: rect, count: 1, longPress: false)
        }

        let focused = app.descendants(matching: .any)
            .matching(NSPredicate(format: "hasKeyboardFocus == true")).firstMatch
        if !focused.exists {
            _ = focused.waitForExistence(timeout: 2)
        }
        guard focused.exists else {
            throw Error.invalidTool(name: "enterText", message: "No element has keyboard focus.")
        }

        let chunkSize = 100
        var offset = text.startIndex
        while offset < text.endIndex {
            let end = text.index(offset, offsetBy: chunkSize, limitedBy: text.endIndex) ?? text.endIndex
            app.typeText(String(text[offset..<end]))
            offset = end
        }
    }

    // MARK: - Device

    @MainActor
    func pressKey(key: XCUIDevice.Button) throws {
        print("Press Key \(key)")
        XCUIDevice.shared.press(key)
    }

    @MainActor
    func takeScreenshot() throws -> Data {
        let snapshot = XCUIScreen.main.screenshot()
        return snapshot.pngRepresentation
    }

    func getDate() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    @MainActor
    func back() throws {
        guard let app = self.app else {
            throw Error.noAppFound
        }
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        if backButton.exists && backButton.isHittable {
            print("Tapping navigation bar back button")
            backButton.tap()
            return
        }
        let window = app.windows.element(boundBy: 0)
        if window.exists {
            let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            print("Performing right-edge swipe gesture for back navigation")
            start.press(forDuration: 0.1, thenDragTo: end)
            return
        }
        throw Error.invalidTool(name: "back", message: "No back navigation available.")
    }
}
