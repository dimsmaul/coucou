import Foundation
import CoreGraphics
#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif

@main
@MainActor
struct MeetingDetectorTests {
    static func main() {
        print("Running MeetingDetector & ScreenRecorder tests…\n")

        testMeetingPlatformProperties()
        testMeetingSessionInit()
        testBrowserOwnersList()
        testRecordingModes()
        testRecordingTargets()
        testAvailableWindowModel()
        testRecordingsFolder()

        print("\nAll MeetingDetector & ScreenRecorder tests passed. ✓")
    }

    static func testMeetingPlatformProperties() {
        print("MeetingPlatform properties:")
        assert(MeetingPlatform.zoom.brandHex == "#2D8CFF", "Zoom brand color")
        assert(MeetingPlatform.googleMeet.brandHex == "#00AC47", "Meet brand color")
        assert(MeetingPlatform.teams.brandHex == "#5059C9", "Teams brand color")
        assert(MeetingPlatform.discord.brandHex == "#5865F2", "Discord brand color")
        assert(MeetingPlatform.slack.brandHex == "#E01E5A", "Slack brand color")
        assert(MeetingPlatform.webex.brandHex == "#00BCEB", "Webex brand color")

        assert(MeetingPlatform.zoom.iconName == "video.fill", "Zoom icon")
        assert(MeetingPlatform.googleMeet.iconName == "video.badge.waveform", "Meet icon")
        assert(MeetingPlatform.teams.iconName == "person.2.fill", "Teams icon")
        assert(MeetingPlatform.discord.iconName == "bubble.left.and.bubble.right.fill", "Discord icon")
        assert(MeetingPlatform.slack.iconName == "headphones", "Slack icon")
        assert(MeetingPlatform.webex.iconName == "video.circle.fill", "Webex icon")

        assert(MeetingPlatform.allCases.count >= 7, "All platform cases accounted for")
        print("  ✓ Platform enums and brand assets verified")
    }

    static func testMeetingSessionInit() {
        print("MeetingSession struct:")
        let session = MeetingSession(
            id: "test-session-123",
            platform: .zoom,
            windowTitle: "Sprint Planning - Zoom Meeting",
            windowID: 42,
            windowBounds: CGRect(x: 100, y: 100, width: 800, height: 600)
        )
        assert(session.id == "test-session-123", "Session ID")
        assert(session.platform == .zoom, "Platform match")
        assert(session.windowTitle == "Sprint Planning - Zoom Meeting", "Window title")
        assert(session.windowID == 42, "Window ID")
        assert(session.windowBounds?.width == 800, "Window bounds width")
        print("  ✓ MeetingSession initialization and properties verified")
    }

    static func testBrowserOwnersList() {
        print("Browser detection owners:")
        let owners = MeetingDetector.browserOwners
        assert(owners.contains("Google Chrome"), "Includes Chrome")
        assert(owners.contains("Arc"), "Includes Arc")
        assert(owners.contains("Safari"), "Includes Safari")
        assert(owners.contains("Microsoft Edge"), "Includes Edge")
        assert(owners.contains("Brave Browser"), "Includes Brave")
        assert(owners.contains("Firefox"), "Includes Firefox")
        print("  ✓ Supported browser owners list verified")
    }

    static func testRecordingModes() {
        print("RecordingMode enum:")
        let modes = RecordingMode.allCases
        assert(modes.contains(.videoAndAudio), "Includes videoAndAudio")
        assert(modes.contains(.audioOnly), "Includes audioOnly")
        assert(RecordingMode.videoAndAudio.rawValue == "Video + Audio", "Video + Audio display name")
        assert(RecordingMode.audioOnly.rawValue == "Audio Only", "Audio Only display name")
        assert(RecordingMode.videoAndAudio.icon == "video.fill", "Video icon")
        assert(RecordingMode.audioOnly.icon == "waveform", "Audio icon")
        print("  ✓ RecordingMode enum and UI tags verified")
    }

    static func testRecordingTargets() {
        print("RecordingTarget enum:")
        let full = RecordingTarget.fullScreen(displayID: 1)
        assert(full.displayName == "Full Screen", "Full Screen label")

        let win = RecordingTarget.window(windowID: 99, title: "Daily Standup", appName: "Zoom")
        assert(win.displayName == "Zoom: Daily Standup", "Window label with title")

        let winNoTitle = RecordingTarget.window(windowID: 100, title: "", appName: "Teams")
        assert(winNoTitle.displayName == "Teams", "Window label without title")
        print("  ✓ RecordingTarget display names verified")
    }

    static func testAvailableWindowModel() {
        print("AvailableWindow struct:")
        let w = AvailableWindow(id: 10, ownerName: "Zed", title: "Coucou", bounds: CGRect(x: 0, y: 0, width: 1200, height: 800))
        assert(w.displayName == "Zed — Coucou", "Window display name with title")

        let wEmpty = AvailableWindow(id: 11, ownerName: "Slack", title: "", bounds: .zero)
        assert(wEmpty.displayName == "Slack", "Window display name without title")
        print("  ✓ AvailableWindow model verified")
    }

    static func testRecordingsFolder() {
        print("ScreenRecorder recordingsFolder:")
        #if !APPSTORE
        let folder = ScreenRecorder.recordingsFolder
        assert(folder.lastPathComponent == "Coucou Recordings" || folder.lastPathComponent == "Recordings", "Folder name is Coucou Recordings")
        print("  ✓ Recordings folder verified at \(folder.path)")
        #endif
    }
}
