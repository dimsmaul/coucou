import AppKit
import CoreGraphics
import Foundation
#if canImport(ScreenCaptureKit)
@preconcurrency import ScreenCaptureKit
#endif

// MARK: - Meeting Platform

public enum MeetingPlatform: String, CaseIterable, Identifiable, Sendable {
    case zoom = "Zoom"
    case googleMeet = "Google Meet"
    case teams = "Microsoft Teams"
    case discord = "Discord"
    case slack = "Slack Huddle"
    case webex = "Webex"
    case generic = "Meeting"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .zoom: return "video.fill"
        case .googleMeet: return "video.badge.waveform"
        case .teams: return "person.2.fill"
        case .discord: return "bubble.left.and.bubble.right.fill"
        case .slack: return "headphones"
        case .webex: return "video.circle.fill"
        case .generic: return "video"
        }
    }

    public var brandHex: String {
        switch self {
        case .zoom: return "#2D8CFF"
        case .googleMeet: return "#00AC47"
        case .teams: return "#5059C9"
        case .discord: return "#5865F2"
        case .slack: return "#E01E5A"
        case .webex: return "#00BCEB"
        case .generic: return "#FF6B6B"
        }
    }
}

// MARK: - Meeting Session

public struct MeetingSession: Identifiable, Equatable, Sendable {
    public let id: String
    public let platform: MeetingPlatform
    public let windowTitle: String
    public let windowID: CGWindowID?
    public let windowBounds: CGRect?
    public let detectedAt: Date

    public init(
        id: String = UUID().uuidString,
        platform: MeetingPlatform,
        windowTitle: String,
        windowID: CGWindowID? = nil,
        windowBounds: CGRect? = nil,
        detectedAt: Date = Date()
    ) {
        self.id = id
        self.platform = platform
        self.windowTitle = windowTitle
        self.windowID = windowID
        self.windowBounds = windowBounds
        self.detectedAt = detectedAt
    }
}

// MARK: - Meeting Detector

@MainActor
public final class MeetingDetector: ObservableObject {
    public static let shared = MeetingDetector()

    @Published public private(set) var activeMeeting: MeetingSession? = nil
    @Published public var dismissedMeetingId: String? = nil

    private var pollerTimer: DispatchSourceTimer?
    private var isRunning = false

    public static let browserOwners = [
        "Google Chrome", "Arc", "Safari", "Microsoft Edge", "Brave Browser", "Firefox",
        "Chrome", "Brave", "Edge", "Vivaldi", "Opera", "Orion", "Zen Browser", "Chromium"
    ]

    private init() {}

    /// Starts polling for active conferencing meetings every 2 seconds.
    public func start() {
        guard !isRunning else { return }
        isRunning = true

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + 1, repeating: .milliseconds(2000), leeway: .milliseconds(300))
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                guard let self = self, self.isRunning else { return }
                let detected = await Self.detectCurrentMeeting()
                if let detected = detected {
                    // If dismissed this exact session, don't re-alert
                    if self.dismissedMeetingId != detected.id {
                        if self.activeMeeting != detected {
                            self.activeMeeting = detected
                        }
                    }
                } else {
                    self.activeMeeting = nil
                    self.dismissedMeetingId = nil
                }
            }
        }
        timer.resume()
        pollerTimer = timer
    }

    public func stop() {
        pollerTimer?.cancel()
        pollerTimer = nil
        isRunning = false
    }

    public func dismissCurrent() {
        if let id = activeMeeting?.id {
            dismissedMeetingId = id
        }
        activeMeeting = nil
    }

    /// Performs an immediate inspection of open windows across all spaces to check for meetings.
    @MainActor
    public static func detectCurrentMeeting() async -> MeetingSession? {
        #if !APPSTORE
        if CGPreflightScreenCaptureAccess() {
            if let shareable = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) {
                for win in shareable.windows {
                    let owner = win.owningApplication?.applicationName ?? ""
                    let bundle = win.owningApplication?.bundleIdentifier ?? ""
                    let title = win.title ?? ""
                    let wid = win.windowID
                    let bounds = win.frame
                    guard bounds.width > 260 && bounds.height > 180 && win.windowLayer <= 0 else { continue }

                    if let session = evaluateCandidate(owner: owner, bundle: bundle, title: title, wid: wid, bounds: bounds) {
                        return session
                    }
                }
            }
        }
        #endif

        return detectCurrentMeetingSync()
    }

    /// Synchronous Quartz fallback inspecting all open windows across all desktops.
    public static func detectCurrentMeetingSync() -> MeetingSession? {
        let options = CGWindowListOption([.optionAll, .excludeDesktopElements])
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for win in list {
            let owner = win[kCGWindowOwnerName as String] as? String ?? ""
            let title = win[kCGWindowName as String] as? String ?? ""
            let wid = (win[kCGWindowNumber as String] as? NSNumber)?.uint32Value
            let layer = win[kCGWindowLayer as String] as? Int ?? 0
            guard layer <= 0 else { continue }
            let boundsDict = win[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let width = boundsDict["Width"] as? Double ?? 0
            let height = boundsDict["Height"] as? Double ?? 0
            let x = boundsDict["X"] as? Double ?? 0
            let y = boundsDict["Y"] as? Double ?? 0
            let bounds = CGRect(x: x, y: y, width: width, height: height)
            guard width > 260 && height > 180 else { continue }

            if let session = evaluateCandidate(owner: owner, bundle: "", title: title, wid: wid ?? 0, bounds: bounds) {
                return session
            }
        }

        return nil
    }

    private static func evaluateCandidate(owner: String, bundle: String, title: String, wid: CGWindowID, bounds: CGRect) -> MeetingSession? {
        let lowerOwner = owner.lowercased()
        let lowerTitle = title.lowercased()
        let lowerBundle = bundle.lowercased()

        // 1. Google Meet (Native PWA, Chrome shortcut, or Browser Tab)
        let isMeetApp = lowerOwner.contains("meet") || lowerBundle.contains("google.meet") || (lowerBundle.contains("chrome.app") && lowerTitle.contains("meet"))
        let isBrowser = browserOwners.contains(where: { lowerOwner.contains($0.lowercased()) }) || lowerBundle.contains("browser") || lowerBundle.contains("chrome")
        let isMeetTitle = lowerTitle.contains("meet.google.com") ||
                          lowerTitle.contains("google meet") ||
                          lowerTitle.contains("meet -") ||
                          lowerTitle.contains("meet –") ||
                          lowerTitle.contains("meet:") ||
                          lowerTitle.contains("rapat -") ||
                          lowerTitle.contains("rapat –")

        if isMeetApp || (isBrowser && isMeetTitle) {
            let clean = title.replacingOccurrences(of: " – Google Chrome", with: "")
                             .replacingOccurrences(of: " - Google Chrome", with: "")
                             .replacingOccurrences(of: " - Brave", with: "")
                             .replacingOccurrences(of: " — Safari", with: "")
                             .replacingOccurrences(of: " - Arc", with: "")
            return MeetingSession(id: "meet_\(wid)", platform: .googleMeet, windowTitle: clean.isEmpty ? "Google Meet" : clean, windowID: wid, windowBounds: bounds)
        }

        // 2. Zoom
        if lowerOwner.contains("zoom") || lowerBundle.contains("zoom") {
            let isMeeting = lowerTitle.contains("meeting") ||
                            lowerTitle.contains("webinar") ||
                            (!title.isEmpty && title != "Zoom Workplace" && title != "Zoom" && title != "Settings") ||
                            (bounds.width > 400 && bounds.height > 300)
            if isMeeting {
                return MeetingSession(id: "zoom_\(wid)", platform: .zoom, windowTitle: title.isEmpty ? "Zoom Meeting" : title, windowID: wid, windowBounds: bounds)
            }
        }

        // 3. Microsoft Teams
        if lowerOwner.contains("teams") || lowerBundle.contains("teams") {
            let isMeeting = lowerTitle.contains("meeting") ||
                            lowerTitle.contains("call") ||
                            lowerTitle.contains("teams") ||
                            (bounds.width > 400 && bounds.height > 300)
            if isMeeting {
                return MeetingSession(id: "teams_\(wid)", platform: .teams, windowTitle: title.isEmpty ? "Teams Meeting" : title, windowID: wid, windowBounds: bounds)
            }
        }

        // 4. Discord
        if lowerOwner.contains("discord") || lowerBundle.contains("discord") {
            if lowerTitle.contains("voice") || lowerTitle.contains("video") || lowerTitle.contains("call") || lowerTitle.contains("stream") || lowerTitle.contains("#") || lowerTitle.contains("@") {
                return MeetingSession(id: "discord_\(wid)", platform: .discord, windowTitle: title.isEmpty ? "Discord Call" : title, windowID: wid, windowBounds: bounds)
            }
        }

        // 5. Slack
        if lowerOwner.contains("slack") || lowerBundle.contains("slack") {
            if lowerTitle.contains("huddle") || lowerTitle.contains("call") {
                return MeetingSession(id: "slack_\(wid)", platform: .slack, windowTitle: title.isEmpty ? "Slack Huddle" : title, windowID: wid, windowBounds: bounds)
            }
        }

        // 6. WhatsApp Call
        if lowerOwner.contains("whatsapp") || lowerBundle.contains("whatsapp") {
            if lowerTitle.contains("call") || lowerTitle.contains("panggilan") || (bounds.width < 800 && bounds.height < 600 && !title.isEmpty && title != "WhatsApp") {
                return MeetingSession(id: "whatsapp_\(wid)", platform: .generic, windowTitle: title.isEmpty ? "WhatsApp Call" : title, windowID: wid, windowBounds: bounds)
            }
        }

        // 7. FaceTime
        if lowerOwner.contains("facetime") || lowerBundle.contains("facetime") {
            return MeetingSession(id: "facetime_\(wid)", platform: .generic, windowTitle: title.isEmpty ? "FaceTime" : title, windowID: wid, windowBounds: bounds)
        }

        // 8. Cisco Webex
        if lowerOwner.contains("webex") || lowerBundle.contains("webex") {
            if lowerTitle.contains("meeting") || lowerTitle.contains("call") || (bounds.width > 400 && bounds.height > 300) {
                return MeetingSession(id: "webex_\(wid)", platform: .webex, windowTitle: title.isEmpty ? "Webex Meeting" : title, windowID: wid, windowBounds: bounds)
            }
        }

        return nil
    }
}
