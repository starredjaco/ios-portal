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
        case 0: self = .home
            //case 1: self = .volumeUp
            //case 2: self = .volumeDown
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
        case apiNotConfigured
        
        var errorDescription: String? {
            switch self {
            case .invalidTool(let name, let message):
                "Invalid tool \(name ?? "unknown"): \(message)"
            case .noAppFound:
                "No app found to interact with, try to open an app first."
            case .apiNotConfigured:
                "No API key found"
            }
        }
    }
}

struct FocusedElement: Codable {
    let text: String
    let className: String
    let resourceId: String
}

struct PhoneState: Codable {
    let activity: String
    let keyboardShown: Bool
    let focusedElement: FocusedElement?
}

// tools
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
    
    @MainActor
    func fetchPhoneState() throws -> PhoneState {
        guard let app else {
            return PhoneState(activity: "most likely apple springboard", keyboardShown: false, focusedElement: nil)
        }
        
        var activity = self.bundleIdentifier ?? "unknown"
        let navBar = app.navigationBars.firstMatch
        if navBar.exists,
           !navBar.identifier.isEmpty {
            activity += " - \(navBar.identifier)"
        }
        let label = app.staticTexts.firstMatch
        if label.exists, !label.label.isEmpty {
            activity += " - \(label.label)"
        }
        
        let keyboardShown = app.keyboards.element.exists && app.keyboards.element.isHittable
        
        // Find the focused element and expose its current value in a structured form.
        let focusedElement = app.descendants(matching: .any).matching(NSPredicate(format: "hasKeyboardFocus == true")).firstMatch
        var focusedElementState: FocusedElement? = nil
        if focusedElement.exists {
            let rawValue = focusedElement.value as? String ?? ""
            let value = rawValue == focusedElement.placeholderValue ? "" : rawValue
            focusedElementState = FocusedElement(
                text: value,
                className: String(describing: focusedElement.elementType),
                resourceId: focusedElement.identifier
            )
        }
        
        return PhoneState(activity: activity, keyboardShown: keyboardShown, focusedElement: focusedElementState)
    }
    
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
    
    // TODO: vibecoded. this only shows bundle identifiers of apps launched in the testing session
    @MainActor
    func listApps() -> [String] {
        return ProcessInfo.processInfo.environment.keys
            .filter { $0.hasPrefix("DYLD_INSERT_ID_") }
            .map { String($0.dropFirst("DYLD_INSERT_ID_".count)) }
    }
    
    @MainActor
    func fetchAccessibilityTree() throws -> String {
        guard let app else {
            throw Error.noAppFound
        }
        
        return app.accessibilityTree()
    }

    @MainActor
    func fetchAccessibilityClickables() throws -> [AccessibilityTreeClickables.Node] {
        guard let app else {
            throw Error.noAppFound
        }
        return app.accessibilityClickables()
    }
    
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
    
    @MainActor
    @discardableResult
    func clearText(rect: String, timeout: TimeInterval = 30) throws -> ClearResponse {
        print("Clear text \(rect) timeout: \(timeout)s")
        guard let app else {
            throw Error.noAppFound
        }

        // Tap the element to focus it
        try tapElement(rect: rect, count: 1, longPress: false)

        // Wait for focus — acquisition is asynchronous in XCTest
        let focusedElement = app.descendants(matching: .any)
            .matching(NSPredicate(format: "hasKeyboardFocus == true")).firstMatch
        if !focusedElement.exists {
            _ = focusedElement.waitForExistence(timeout: 2)
        }
        guard focusedElement.exists else {
            throw Error.invalidTool(name: "clearText", message: "No element has keyboard focus after tapping.")
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        var totalDeleted = 0

        while true {
            // Check timeout
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            if elapsed > timeout {
                print("Clear timed out after \(String(format: "%.1f", elapsed))s")
                break
            }

            // Read current value
            let currentValue = focusedElement.value as? String ?? ""
            if currentValue.isEmpty || currentValue == focusedElement.placeholderValue {
                break  // Done
            }

            let countBefore = currentValue.count

            // Fast pass: tap bottom-right, bulk delete
            let endCoordinate = focusedElement.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.99))
            endCoordinate.tap()
            let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: countBefore)
            app.typeText(deleteString)

            // Check if fast pass made progress
            let afterFast = focusedElement.value as? String ?? ""
            if afterFast.isEmpty || afterFast == focusedElement.placeholderValue {
                totalDeleted += countBefore
                break  // Done
            }

            let deletedThisPass = countBefore - afterFast.count
            if deletedThisPass > 0 {
                totalDeleted += deletedThisPass
                continue  // Fast pass made progress, loop back for another
            }

            // Fast pass made no progress — try one single delete (reliable)
            app.typeText(XCUIKeyboardKey.delete.rawValue)
            let afterSingle = focusedElement.value as? String ?? ""
            let singleProgress = afterFast.count - afterSingle.count

            if singleProgress > 0 {
                totalDeleted += singleProgress
                continue  // Single delete worked, loop back to try fast again
            }

            // Neither fast nor single delete made progress — give up
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
    func enterText(rect: String, text: String) async throws {
        print("Enter Text \(rect) -> \(text)")
        guard let app else {
            throw Error.noAppFound
        }
        try tapElement(rect: rect, count: 1, longPress: false)

        // Check for focused element — works with both software and hardware keyboard
        let focusedElement = app.descendants(matching: .any).matching(NSPredicate(format: "hasKeyboardFocus == true")).firstMatch

        // If no focus yet, wait a moment and check again
        if !focusedElement.exists {
            _ = focusedElement.waitForExistence(timeout: 2)
        }
        guard focusedElement.exists else {
            throw Error.invalidTool(name: "enterText", message: "No element has keyboard focus after tapping.")
        }

        app.typeText(text)
    }

    @MainActor
    func enterText(_ text: String) throws {
        guard let app = self.app else {
            throw Error.noAppFound
        }
        print("Typing text into focused element: \(text.prefix(50))... (\(text.count) chars)")
        // Chunk long text to avoid XCTest assertion failures from stale element references
        let chunkSize = 100
        var offset = text.startIndex
        while offset < text.endIndex {
            let end = text.index(offset, offsetBy: chunkSize, limitedBy: text.endIndex) ?? text.endIndex
            let chunk = String(text[offset..<end])
            app.typeText(chunk)
            offset = end
        }
    }
    
    @MainActor
    func pressKey(key: XCUIDevice.Button) throws {
        print("Press Key \(key)")
        XCUIDevice.shared.press(key)
    }
    
    @MainActor
    func pressKeycode(_ keycode: Int) throws {
        // Map keycodes to iOS representations
        let keyMap: [Int: String] = [
            66: "\n",      // Enter/Return
            67: "\u{8}",   // Delete/Backspace
            61: "\t"       // Tab
        ]
        guard let keyString = keyMap[keycode] else {
            throw Error.invalidTool(name: "pressKeycode", message: "Unsupported keycode: \(keycode)")
        }
        guard let app = self.app else {
            throw Error.noAppFound
        }
        // Find the focused element
        let focusedElement = app.descendants(matching: .any).matching(NSPredicate(format: "hasKeyboardFocus == true")).firstMatch
        guard focusedElement.exists else {
            throw Error.invalidTool(name: "pressKeycode", message: "No element has keyboard focus.")
        }
        print("Typing key for keycode \(keycode): \(keyString)")
        focusedElement.typeText(keyString)
    }
    
    @MainActor
    func takeScreenshot() throws -> Data {
        let snapshot = XCUIScreen.main.screenshot()
        
        /*guard let app else {
         throw Error.noAppFound
         }
         let snapshot = app.screenshot()*/
        
        return snapshot.pngRepresentation
    }
    
    @MainActor
    func getScreenSize() throws -> ScreenSizeResponse {
        guard let app else {
            throw Error.noAppFound
        }
        let frame = app.windows.element(boundBy: 0).frame
        return ScreenSizeResponse(width: frame.width, height: frame.height)
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
        // Try to tap the navigation bar back button
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        if backButton.exists && backButton.isHittable {
            print("Tapping navigation bar back button")
            backButton.tap()
            return
        }
        // If not, try a right-edge swipe gesture (from left edge to right)
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
