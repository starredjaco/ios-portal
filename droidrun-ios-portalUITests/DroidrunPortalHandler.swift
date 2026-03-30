//
//  DroidrunPortalHandler.swift
//  droidrun-ios-portal
//
//  Created by Timo Beckmann on 04.06.25.
//

import FlyingFox
import FlyingFoxMacros
import XCTest

struct InfoResponse: Encodable {
    let description: String
}

struct A11yResponse: Encodable {
    let accessibilityTree: String
}

struct AppsResponse: Encodable {
    let apps: [String]
}

struct LaunchAppBody: Decodable {
    let bundleIdentifier: String
}

struct LaunchAppResponse: Encodable {
    let message: String
}

struct TapBody: Decodable {
    let rect: String
    let count: Int?
    let longPress: Bool?
}

struct SwipeBody: Decodable {
    let x1: CGFloat
    let y1: CGFloat
    let x2: CGFloat
    let y2: CGFloat
    let durationMs: Double?  // milliseconds, defaults to 300
}

struct GestureResponse: Encodable {
    let message: String
}

struct TypeBody: Decodable {
    let rect: String?
    let text: String
    let clear: Bool?
}

struct ClearBody: Decodable {
    let rect: String?
}

struct ClearResponse: Encodable {
    let message: String
    let charactersDeleted: Int
    let method: String
    let durationMs: Double
}

struct KeyBody: Decodable {
    let key: Int
}

struct ScreenSizeResponse: Encodable {
    let width: CGFloat
    let height: CGFloat
}

struct DateResponse: Encodable {
    let date: String
}

// -- /state_full response types -----------------------------------------------

struct ScreenBounds: Encodable {
    let width: CGFloat
    let height: CGFloat
}

struct DeviceContext: Encodable {
    let screen_bounds: ScreenBounds
}

struct StateFullPhoneState: Encodable {
    let currentApp: String
    let packageName: String
    let keyboardVisible: Bool
    let isEditable: Bool
    let focusedElement: FocusedElement?
}

struct StateFullResponse: Encodable {
    let a11y_tree: String
    let phone_state: StateFullPhoneState
    let device_context: DeviceContext
}

@HTTPHandler
struct DroidrunPortalHandler {

    @JSONRoute("GET /")
    func info() throws -> InfoResponse {
        let description = XCUIDevice.shared.description
        return InfoResponse(description: description)
    }

    @JSONRoute("GET /state_full")
    func stateFull() async throws -> StateFullResponse {
        return try await DroidrunPortalTools.shared.fetchStateFull()
    }

    @JSONRoute("GET /vision/state")
    func fetchPhoneState() async throws -> PhoneState {
        return try await DroidrunPortalTools.shared.fetchPhoneState()
    }

    @JSONRoute("GET /vision/a11y")
    func fetchAccessibilityTree() async throws -> A11yResponse {
        let a11y = try await DroidrunPortalTools.shared.fetchAccessibilityTree()
        return A11yResponse(accessibilityTree: a11y)
    }

    @JSONRoute("GET /vision/apps")
    func fetchApps() async throws -> AppsResponse {
        let apps = await DroidrunPortalTools.shared.listApps()
        return AppsResponse(apps: apps)
    }

    @HTTPRoute("GET /vision/screenshot")
    func takeScreenshot() async throws -> HTTPResponse {
        let screenshot = try await DroidrunPortalTools.shared.takeScreenshot()
        return HTTPResponse(statusCode: .ok, headers: [.contentType: "image/png"], body: screenshot)
    }

    @JSONRoute("POST /inputs/launch")
    func launchApp(_ body: LaunchAppBody) async throws -> LaunchAppResponse {
        try await DroidrunPortalTools.shared.openApp(bundleIdentifier: body.bundleIdentifier)
        return LaunchAppResponse(message: "opened \(body.bundleIdentifier)")
    }

    @JSONRoute("POST /gestures/tap")
    func tapElement(_ body: TapBody) async throws -> GestureResponse {
        try await DroidrunPortalTools.shared.tapElement(rect: body.rect, count: body.count, longPress: body.longPress)
        return GestureResponse(message: "tapped element")
    }

    @JSONRoute("POST /gestures/swipe")
    func swipe(_ body: SwipeBody) async throws -> GestureResponse {
        let durationSec = (body.durationMs ?? 300) / 1000.0
        try await DroidrunPortalTools.shared.swipe(x1: body.x1, y1: body.y1, x2: body.x2, y2: body.y2, duration: durationSec)
        return GestureResponse(message: "swiped")
    }

    @JSONRoute("POST /inputs/type")
    func enterText(_ body: TypeBody) async throws -> GestureResponse {
        if body.clear == true {
            try await DroidrunPortalTools.shared.clearText(rect: body.rect)
        }
        try await DroidrunPortalTools.shared.enterText(rect: body.rect, text: body.text)
        return GestureResponse(message: "entered text")
    }

    @JSONRoute("POST /inputs/clear")
    func clearText(_ body: ClearBody) async throws -> ClearResponse {
        let result = try await DroidrunPortalTools.shared.clearText(rect: body.rect)
        return result
    }

    @JSONRoute("POST /inputs/key")
    func pressKey(_ body: KeyBody) async throws -> GestureResponse {
        guard let key = XCUIDevice.Button(rawValue: body.key) else {
            throw HTTPUnhandledError()
        }

        try await DroidrunPortalTools.shared.pressKey(key: key)
        return GestureResponse(message: "pressed key")
    }

    @JSONRoute("POST /gestures/back")
    func back() async throws -> GestureResponse {
        try await DroidrunPortalTools.shared.back()
        return GestureResponse(message: "navigated back")
    }

    @JSONRoute("GET /device/screen")
    func screenSize() async throws -> ScreenSizeResponse {
        return try await DroidrunPortalTools.shared.getScreenSize()
    }

    @JSONRoute("GET /device/date")
    func date() async throws -> DateResponse {
        return DateResponse(date: DroidrunPortalTools.shared.getDate())
    }

    @HTTPRoute("GET /debug")
    func debug(_ request: HTTPRequest) -> HTTPResponse {
        let text = DroidrunPortalTools.shared.app.debugDescription
        return HTTPResponse(statusCode: .accepted, body: text.data(using: .utf8) ?? Data())
    }
}
