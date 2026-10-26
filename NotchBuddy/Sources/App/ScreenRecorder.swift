#if !APPSTORE
import AppKit
import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit
import VideoToolbox

// MARK: - Enums & Models

public enum RecordingMode: String, CaseIterable, Identifiable, Sendable {
    case videoAndAudio = "Video + Audio"
    case audioOnly = "Audio Only"

    public var id: String { rawValue }
    public var icon: String {
        switch self {
        case .videoAndAudio: return "video.fill"
        case .audioOnly: return "waveform"
        }
    }
}

public enum RecordingTarget: Equatable, Sendable {
    case fullScreen(displayID: CGDirectDisplayID)
    case window(windowID: CGWindowID, title: String, appName: String)

    public var displayName: String {
        switch self {
        case .fullScreen: return "Full Screen"
        case .window(_, let title, let app):
            return title.isEmpty ? app : "\(app): \(title)"
        }
    }
}

public struct AvailableWindow: Identifiable, Equatable, Sendable {
    public let id: CGWindowID
    public let ownerName: String
    public let title: String
    public let bounds: CGRect

    public var displayName: String {
        title.isEmpty ? ownerName : "\(ownerName) — \(title)"
    }
}

// MARK: - Screen Recorder

@MainActor
public final class ScreenRecorder: NSObject, ObservableObject {
    public static let shared = ScreenRecorder()

    public enum VideoFormat: String, CaseIterable, Identifiable {
        case webm = "WebM"
        case mp4 = "MP4"

        public var id: String { rawValue }
        public var fileExtension: String {
            switch self {
            case .webm: return "webm"
            case .mp4: return "mp4"
            }
        }
    }

    // Configuration & Toggles
    @Published public var target: RecordingTarget = .fullScreen(displayID: CGMainDisplayID())
    @Published public var mode: RecordingMode = .videoAndAudio
    @Published public var videoFormat: VideoFormat = .webm
    @Published public var micEnabled: Bool = true
    @Published public var systemAudioEnabled: Bool = true
    @Published public var cameraPipEnabled: Bool = false
    @Published public var liveTranscriptEnabled: Bool = true
    @Published public var exportAsWebPForShortClips: Bool = false

    // Live Recording State
    @Published public private(set) var isRecording: Bool = false
    @Published public private(set) var isStopping: Bool = false
    @Published public private(set) var isPaused: Bool = false
    @Published public private(set) var elapsedSeconds: Int = 0
    @Published public private(set) var micLevel: Float = 0
    @Published public private(set) var systemLevel: Float = 0
    @Published public private(set) var lastRecordedURL: URL? = nil
    @Published public private(set) var lastNoteID: UUID? = nil
    @Published public private(set) var statusMessage: String? = nil
    @Published public private(set) var hasScreenRecordingPermission: Bool = CGPreflightScreenCaptureAccess()

    public func updatePermissionStatus() {
        let granted = CGPreflightScreenCaptureAccess()
        if self.hasScreenRecordingPermission != granted {
            self.hasScreenRecordingPermission = granted
        }
    }

    public func clearStatusMessage() {
        self.statusMessage = nil
    }

    // Private pipeline
    private var stream: SCStream?
    private var streamOutput: StreamOutputBridge?
    private var writerSession: AssetWriterSession?
    private var tempRawVideoURL: URL?
    private var timer: DispatchSourceTimer?
    private var recordingStartTime: Date?
    private var currentOutputURL: URL?
    private var isStarting = false
    private var activeNoteID: UUID?

    public static var recordingsFolder: URL {
        let fileManager = FileManager.default
        let moviesURL = fileManager.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Movies", isDirectory: true)
        let coucouFolder = moviesURL.appendingPathComponent("Coucou Recordings", isDirectory: true)

        if (try? fileManager.createDirectory(at: coucouFolder, withIntermediateDirectories: true)) != nil {
            return coucouFolder
        }

        let docsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Documents", isDirectory: true)
        let fallbackFolder = docsURL.appendingPathComponent("Coucou Recordings", isDirectory: true)
        try? fileManager.createDirectory(at: fallbackFolder, withIntermediateDirectories: true)
        return fallbackFolder
    }

    public static func openRecordingsFolder() {
        let folder = Self.recordingsFolder
        NSWorkspace.shared.open(folder)
    }

    public static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public static var hasScreenRecordingPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    public static func requestScreenRecordingPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    public static func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updatePermissionStatus()
            }
        }
    }

    // MARK: - Window Discovery

    /// Fetches all active application windows eligible for recording using ScreenCaptureKit with Quartz fallback.
    public static func fetchShareableWindows() async -> [AvailableWindow] {
        var results: [AvailableWindow] = []
        var seenIDs = Set<CGWindowID>()

        let excludedApps: Set<String> = [
            "Window Server", "Dock", "Coucou", "NotchBuddy",
            "Control Center", "SystemUIServer", "Spotlight", "loginwindow", "screencapture", "Notification Center",
            "WindowManager"
        ]

        // Only query ScreenCaptureKit if permission is already granted to prevent unprompted alerts
        if CGPreflightScreenCaptureAccess() {
            if let shareable = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) {
                for win in shareable.windows {
                    let app = win.owningApplication?.applicationName ?? ""
                    let title = win.title ?? ""
                    guard !excludedApps.contains(app) else { continue }
                    guard win.windowLayer <= 0 else { continue }
                    guard win.frame.width > 140 && win.frame.height > 90 else { continue }

                    seenIDs.insert(win.windowID)
                    results.append(AvailableWindow(
                        id: win.windowID,
                        ownerName: app.isEmpty ? "Application" : app,
                        title: title,
                        bounds: win.frame
                    ))
                }
            }
        }

        if results.isEmpty || results.count < 3 {
            let options = CGWindowListOption([.optionAll, .excludeDesktopElements])
            if let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
                for win in list {
                    guard let widNum = win[kCGWindowNumber as String] as? NSNumber else { continue }
                    let wid = CGWindowID(widNum.uint32Value)
                    guard !seenIDs.contains(wid) else { continue }

                    let owner = win[kCGWindowOwnerName as String] as? String ?? ""
                    let title = win[kCGWindowName as String] as? String ?? ""
                    let layer = win[kCGWindowLayer as String] as? Int ?? 0
                    let boundsDict = win[kCGWindowBounds as String] as? [String: Any] ?? [:]
                    let width = boundsDict["Width"] as? Double ?? 0
                    let height = boundsDict["Height"] as? Double ?? 0
                    let x = boundsDict["X"] as? Double ?? 0
                    let y = boundsDict["Y"] as? Double ?? 0

                    guard layer <= 0 else { continue }
                    guard !excludedApps.contains(owner) else { continue }
                    guard width > 140 && height > 90 else { continue }

                    seenIDs.insert(wid)
                    results.append(AvailableWindow(
                        id: wid,
                        ownerName: owner.isEmpty ? "Application" : owner,
                        title: title,
                        bounds: CGRect(x: x, y: y, width: width, height: height)
                    ))
                }
            }
        }

        // Sort: Group by App name ascending, then title
        return results.sorted { a, b in
            if a.ownerName.caseInsensitiveCompare(b.ownerName) == .orderedSame {
                return a.title.caseInsensitiveCompare(b.title) == .orderedAscending
            }
            return a.ownerName.caseInsensitiveCompare(b.ownerName) == .orderedAscending
        }
    }

    // MARK: - Recording Actions

    public func toggleRecording() async {
        if isRecording {
            await stopRecording()
        } else {
            await startRecording()
        }
    }

    public func startRecording() async {
        guard !isRecording, !isStarting else { return }

        // Check screen recording permission if recording video
        if mode == .videoAndAudio && !CGPreflightScreenCaptureAccess() {
            let granted = CGRequestScreenCaptureAccess()
            if !granted {
                Self.openScreenRecordingSettings()
                statusMessage = "Please enable Screen Recording permission in System Settings."
                return
            }
        }

        isStarting = true
        defer { isStarting = false }

        statusMessage = nil
        elapsedSeconds = 0

        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let ext = mode == .audioOnly ? "m4a" : videoFormat.fileExtension
        let fileURL = Self.recordingsFolder.appendingPathComponent("Record-\(timestamp).\(ext)")
        currentOutputURL = fileURL

        do {
            if mode == .audioOnly {
                try await startAudioOnlyRecording(destination: fileURL)
            } else {
                try await startVideoAndAudioRecording(destination: fileURL)
            }
        } catch {
            statusMessage = "Recording failed: \(error.localizedDescription)"
            currentOutputURL = nil
            isRecording = false
            stopTimer()
            appendAppLog("nb.log", "[ScreenRecorder] start failed: \(error)")
            return
        }

        isRecording = true
        recordingStartTime = Date()
        startTimer()
        SoundEngine.shared.play("blip")
        appendAppLog("nb.log", "[ScreenRecorder] started \(mode.rawValue) recording (\(videoFormat.rawValue)) to \(fileURL.lastPathComponent)")
    }

    public func stopRecording() async {
        guard isRecording, !isStopping else { return }
        isStopping = true
        defer {
            isStopping = false
            isRecording = false
        }
        stopTimer()

        appendAppLog("nb.log", "[ScreenRecorder] stopRecording initiated (mode=\(mode.rawValue), format=\(videoFormat.rawValue))...")

        if mode == .audioOnly {
            await stopAudioOnlyRecording()
        } else {
            await stopVideoAndAudioRecording()
        }

        if liveTranscriptEnabled {
            lastNoteID = activeNoteID ?? NoteTaker.shared.notes.first?.id

            // Save companion transcript text file alongside recording
            if let note = NoteTaker.shared.notes.first, let url = currentOutputURL {
                let txtURL = url.deletingPathExtension().appendingPathExtension("txt")
                let content = note.lines.map { line in
                    line.speaker.isEmpty ? line.text : "[\(line.speaker)] \(line.text)"
                }.joined(separator: "\n")
                if !content.isEmpty {
                    try? content.write(to: txtURL, atomically: true, encoding: String.Encoding.utf8)
                }
            }
        }

        // Verify that the output file exists on disk and has valid size
        if let fileURL = currentOutputURL, FileManager.default.fileExists(atPath: fileURL.path) {
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
            if fileSize > 0 {
                lastRecordedURL = currentOutputURL
                statusMessage = nil
                SoundEngine.shared.play("finish")
                appendAppLog("nb.log", "[ScreenRecorder] stopped recording. Saved to: \(fileURL.path) (\(fileSize) bytes)")
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            } else {
                lastRecordedURL = nil
                statusMessage = "Recording stopped, but file was 0 bytes."
                appendAppLog("nb.log", "[ScreenRecorder] stopped, but file was 0 bytes at \(fileURL.path)")
            }
        } else {
            lastRecordedURL = nil
            statusMessage = "Recording stopped, but no media file was created."
            appendAppLog("nb.log", "[ScreenRecorder] stopped, but file was missing at \(currentOutputURL?.path ?? "nil")")
        }
    }

    // MARK: - Video + Audio Implementation (ScreenCaptureKit + Audio Muxing)

    private func startVideoAndAudioRecording(destination: URL) async throws {
        let shareable = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = shareable.displays.first else {
            throw NSError(domain: "Coucou.ScreenRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "No active display detected."])
        }

        let filter: SCContentFilter
        var width: Int
        var height: Int

        switch target {
        case .fullScreen:
            filter = SCContentFilter(display: display, excludingWindows: [])
            width = display.width
            height = display.height
            appendAppLog("nb.log", "[ScreenRecorder] fullScreen recording at \(width)x\(height)")
        case .window(let wid, let winTitle, let appName):
            // 1. Search by exact windowID
            var targetWin = shareable.windows.first(where: { $0.windowID == wid })

            // 2. Fallback: Search by application name with valid window layer and size
            if targetWin == nil && !appName.isEmpty {
                targetWin = shareable.windows.first(where: {
                    ($0.owningApplication?.applicationName.caseInsensitiveCompare(appName) == .orderedSame) &&
                    $0.windowLayer <= 0 && $0.frame.width > 140 && $0.frame.height > 90
                })
            }

            // 3. Fallback: Search by window title
            if targetWin == nil && !winTitle.isEmpty {
                targetWin = shareable.windows.first(where: {
                    ($0.title?.localizedCaseInsensitiveContains(winTitle) == true) &&
                    $0.windowLayer <= 0 && $0.frame.width > 140 && $0.frame.height > 90
                })
            }

            guard let win = targetWin else {
                appendAppLog("nb.log", "[ScreenRecorder] target window '\(appName)' (ID: \(wid)) not found in shareable windows")
                throw NSError(domain: "Coucou.ScreenRecorder", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Selected window '\(appName)' could not be found. Please ensure the app is open."
                ])
            }

            // Activate target application to bring window into user focus and ensure surface is active
            if let app = NSWorkspace.shared.runningApplications.first(where: {
                $0.localizedName?.caseInsensitiveCompare(appName) == .orderedSame ||
                $0.bundleIdentifier == win.owningApplication?.bundleIdentifier
            }) {
                if #available(macOS 14.0, *) {
                    app.activate()
                } else {
                    app.activate(options: [.activateIgnoringOtherApps])
                }
            }

            filter = SCContentFilter(desktopIndependentWindow: win)
            var w = Int(win.frame.width)
            var h = Int(win.frame.height)
            if w % 2 != 0 { w -= 1 }
            if h % 2 != 0 { h -= 1 }
            width = max(320, w)
            height = max(240, h)
            appendAppLog("nb.log", "[ScreenRecorder] window recording target found: ID=\(win.windowID), app='\(appName)', title='\(win.title ?? "")', size=\(width)x\(height)")
        }

        // Force strictly even dimensions (Required for hardware encoding & QuickTime playback)
        if width % 2 != 0 { width -= 1 }
        if height % 2 != 0 { height -= 1 }
        width = max(320, width)
        height = max(240, height)

        // Stream config: 30 FPS, clean 32BGRA frames
        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.scalesToFit = true
        config.queueDepth = 5
        config.showsCursor = true

        let rawVideoURL = destination.deletingPathExtension().appendingPathExtension("temp_raw.mp4")
        self.tempRawVideoURL = rawVideoURL
        try? FileManager.default.removeItem(at: rawVideoURL)

        // Setup AVAssetWriter for hardware accelerated H.264 video
        let writer = try AVAssetWriter(outputURL: rawVideoURL, fileType: .mp4)

        let bitrate = 2_200_000 // 2.2 Mbps keeps files compact while text & UI stay razor sharp
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoMaxKeyFrameIntervalKey: 30
            ]
        ]
        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = true
        writer.add(vInput)

        // Start writer
        writer.startWriting()
        let session = AssetWriterSession(writer: writer, videoInput: vInput, audioInput: nil)
        self.writerSession = session

        // ScreenCaptureKit Stream & Handler
        let outputBridge = StreamOutputBridge { [weak session] sampleBuffer in
            session?.appendVideo(sampleBuffer)
        } audioHandler: { _ in }
        self.streamOutput = outputBridge

        let scStream = SCStream(filter: filter, configuration: config, delegate: nil)
        try scStream.addStreamOutput(outputBridge, type: .screen, sampleHandlerQueue: DispatchQueue(label: "coucou.screen.video"))
        try await scStream.startCapture()
        self.stream = scStream

        // Start Coucou audio engine (capturing Mic and System Audio Tap simultaneously)
        let noteID = await NoteTaker.shared.start(mic: micEnabled, system: systemAudioEnabled, liveTranscript: liveTranscriptEnabled)
        self.activeNoteID = noteID ?? NoteTaker.shared.recording?.id
        appendAppLog("nb.log", "[ScreenRecorder] started recording noteID=\(self.activeNoteID?.uuidString ?? "nil"), mic=\(micEnabled), sys=\(systemAudioEnabled), stt=\(liveTranscriptEnabled)")
    }

    private func stopVideoAndAudioRecording() async {
        if let s = stream {
            try? await s.stopCapture()
            self.stream = nil
        }

        await writerSession?.finish()
        self.writerSession = nil
        self.streamOutput = nil

        let targetNoteID = self.activeNoteID ?? NoteTaker.shared.recording?.id ?? NoteTaker.shared.notes.first?.id
        appendAppLog("nb.log", "[ScreenRecorder] stopping audio for noteID: \(targetNoteID?.uuidString ?? "nil")")

        // Stop audio capture and export mixed audio.m4a (Mic + System audio)
        var audioURL: URL? = nil
        if micEnabled || systemAudioEnabled {
            audioURL = await NoteTaker.shared.stopAndExportAudio(for: targetNoteID)
            appendAppLog("nb.log", "[ScreenRecorder] stopAndExportAudio returned: \(audioURL?.path ?? "nil")")
        } else {
            NoteTaker.shared.stop()
        }

        // Guaranteed audio fallback: if audioURL doesn't exist or is missing, search note folder
        if let nid = targetNoteID, (audioURL == nil || !FileManager.default.fileExists(atPath: audioURL!.path)) {
            let noteFolder = NoteTaker.folder(for: nid)
            let m4a = noteFolder.appendingPathComponent("audio.m4a")
            let mic = noteFolder.appendingPathComponent("mic.wav")
            let sys = noteFolder.appendingPathComponent("system.wav")
            if FileManager.default.fileExists(atPath: m4a.path) {
                audioURL = m4a
            } else if FileManager.default.fileExists(atPath: mic.path) || FileManager.default.fileExists(atPath: sys.path) {
                _ = await NoteTaker.exportCombinedAudio(micURL: mic, systemURL: sys, outputURL: m4a)
                if FileManager.default.fileExists(atPath: m4a.path) {
                    audioURL = m4a
                } else if FileManager.default.fileExists(atPath: mic.path) {
                    audioURL = mic
                }
            }
            appendAppLog("nb.log", "[ScreenRecorder] fallback resolved audioURL: \(audioURL?.path ?? "nil")")
        }

        self.lastNoteID = targetNoteID
        self.activeNoteID = nil

        guard let rawURL = tempRawVideoURL, FileManager.default.fileExists(atPath: rawURL.path),
              let finalURL = currentOutputURL else {
            appendAppLog("nb.log", "[ScreenRecorder] raw video missing at \(tempRawVideoURL?.path ?? "nil")")
            return
        }

        // Mux into WebM or MP4
        if videoFormat == .webm {
            let success = await Self.muxWebM(videoURL: rawURL, audioURL: audioURL, outputURL: finalURL)
            if !success {
                appendAppLog("nb.log", "[ScreenRecorder] webm mux failed, falling back to mp4")
                _ = await Self.muxMP4(videoURL: rawURL, audioURL: audioURL, outputURL: finalURL)
            }
        } else {
            _ = await Self.muxMP4(videoURL: rawURL, audioURL: audioURL, outputURL: finalURL)
        }

        // Clean up temporary video
        try? FileManager.default.removeItem(at: rawURL)
        tempRawVideoURL = nil
    }

    // MARK: - Muxing & Encoding (WebM + MP4)

    public static var ffmpegPath: String? {
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    @discardableResult
    public static func runFFmpeg(arguments: [String]) async -> Bool {
        guard let ffmpeg = ffmpegPath else { return false }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: ffmpeg)
                process.arguments = arguments
                process.standardOutput = Pipe()
                process.standardError = Pipe()
                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0)
                } catch {
                    appendAppLog("nb.log", "[ScreenRecorder] ffmpeg run failed: \(error.localizedDescription)")
                    continuation.resume(returning: false)
                }
            }
        }
    }

    private static func muxWebM(videoURL: URL, audioURL: URL?, outputURL: URL) async -> Bool {
        guard let _ = ffmpegPath else {
            appendAppLog("nb.log", "[ScreenRecorder] ffmpeg not available for muxWebM")
            return false
        }
        try? FileManager.default.removeItem(at: outputURL)

        var args = ["-y", "-i", videoURL.path]
        if let aURL = audioURL, FileManager.default.fileExists(atPath: aURL.path) {
            let aSize = (try? FileManager.default.attributesOfItem(atPath: aURL.path)[.size] as? Int64) ?? 0
            if aSize > 100 {
                args += ["-i", aURL.path]
                args += ["-c:v", "libvpx-vp9", "-crf", "30", "-b:v", "2000k", "-deadline", "realtime", "-cpu-used", "4"]
                args += ["-c:a", "libopus", "-b:a", "128k"]
                appendAppLog("nb.log", "[ScreenRecorder] muxWebM with audio: \(aURL.path) (\(aSize) bytes)")
            } else {
                args += ["-c:v", "libvpx-vp9", "-crf", "30", "-b:v", "2000k", "-deadline", "realtime", "-cpu-used", "4"]
                appendAppLog("nb.log", "[ScreenRecorder] muxWebM audio file too small: \(aSize) bytes")
            }
        } else {
            args += ["-c:v", "libvpx-vp9", "-crf", "30", "-b:v", "2000k", "-deadline", "realtime", "-cpu-used", "4"]
            appendAppLog("nb.log", "[ScreenRecorder] muxWebM without audio (audioURL was nil or missing)")
        }
        args.append(outputURL.path)

        let ok = await runFFmpeg(arguments: args)
        let exists = FileManager.default.fileExists(atPath: outputURL.path)
        let finalSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int64) ?? 0
        appendAppLog("nb.log", "[ScreenRecorder] muxWebM finished: ok=\(ok), exists=\(exists), size=\(finalSize) bytes")
        return ok && exists && finalSize > 0
    }

    private static func muxMP4(videoURL: URL, audioURL: URL?, outputURL: URL) async -> Bool {
        try? FileManager.default.removeItem(at: outputURL)
        let aSize = audioURL != nil ? ((try? FileManager.default.attributesOfItem(atPath: audioURL!.path)[.size] as? Int64) ?? 0) : 0
        let hasValidAudio = audioURL != nil && FileManager.default.fileExists(atPath: audioURL!.path) && aSize > 100

        if ffmpegPath != nil {
            var args = ["-y", "-i", videoURL.path]
            if hasValidAudio, let aURL = audioURL {
                args += ["-i", aURL.path, "-c:v", "copy", "-c:a", "aac", "-b:a", "128k"]
                appendAppLog("nb.log", "[ScreenRecorder] muxMP4 with audio: \(aURL.path) (\(aSize) bytes)")
            } else {
                args += ["-c:v", "copy"]
                appendAppLog("nb.log", "[ScreenRecorder] muxMP4 without audio")
            }
            args.append(outputURL.path)
            if await runFFmpeg(arguments: args) && FileManager.default.fileExists(atPath: outputURL.path) {
                return true
            }
        }

        // Native AVMutableComposition fallback
        let comp = AVMutableComposition()
        let videoAsset = AVURLAsset(url: videoURL)
        guard let vSrc = videoAsset.tracks(withMediaType: .video).first,
              let vTrack = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return false
        }
        let dur = videoAsset.duration
        try? vTrack.insertTimeRange(CMTimeRange(start: .zero, duration: dur), of: vSrc, at: .zero)

        if let aURL = audioURL, FileManager.default.fileExists(atPath: aURL.path) {
            let audioAsset = AVURLAsset(url: aURL)
            if let aSrc = audioAsset.tracks(withMediaType: .audio).first,
               let aTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                let aDur = min(dur, audioAsset.duration)
                try? aTrack.insertTimeRange(CMTimeRange(start: .zero, duration: aDur), of: aSrc, at: .zero)
            }
        }

        guard let exporter = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetPassthrough) else {
            return false
        }
        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        await exporter.export()
        return exporter.status == .completed && FileManager.default.fileExists(atPath: outputURL.path)
    }

    // MARK: - Audio Only Implementation (Powered by NoteTaker Audio Engine)

    private func startAudioOnlyRecording(destination: URL) async throws {
        await NoteTaker.shared.start()
        if let error = NoteTaker.shared.startError {
            throw NSError(domain: "Coucou.ScreenRecorder", code: 3, userInfo: [NSLocalizedDescriptionKey: error])
        }
    }

    private func stopAudioOnlyRecording() async {
        if let dest = currentOutputURL {
            _ = await NoteTaker.shared.stopAndExportAudio(destination: dest)
        } else {
            _ = await NoteTaker.shared.stopAndExportAudio()
        }
        lastNoteID = NoteTaker.shared.notes.first?.id
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        t.schedule(deadline: .now() + 1, repeating: .seconds(1))
        t.setEventHandler { [weak self] in
            guard let self = self, self.isRecording else { return }
            self.elapsedSeconds += 1
        }
        t.resume()
        timer = t
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }
}

// MARK: - Asset Writer Session

private final class AssetWriterSession: @unchecked Sendable {
    let writer: AVAssetWriter
    let videoInput: AVAssetWriterInput?
    let audioInput: AVAssetWriterInput?
    private let queue = DispatchQueue(label: "coucou.assetwriter", qos: .userInitiated)
    private var isSessionStarted = false
    private var sessionStartTime: CMTime? = nil
    private var lastVideoPTS: CMTime = .invalid

    init(writer: AVAssetWriter, videoInput: AVAssetWriterInput?, audioInput: AVAssetWriterInput?) {
        self.writer = writer
        self.videoInput = videoInput
        self.audioInput = audioInput
    }

    func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        queue.async { [self] in
            guard sampleBuffer.isValid else { return }
            guard writer.status == .writing else { return }
            guard let input = videoInput, input.isReadyForMoreMediaData else { return }

            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            guard pts.isValid && pts.flags.contains(.valid) else { return }

            if !isSessionStarted {
                writer.startSession(atSourceTime: pts)
                isSessionStarted = true
                sessionStartTime = pts
                lastVideoPTS = pts
                appendAppLog("nb.log", "[ScreenRecorder] video session started at pts: \(pts.seconds)")
            }

            guard isSessionStarted else { return }
            // Ensure PTS is strictly monotonic to prevent AVAssetWriter error -12142
            if lastVideoPTS.isValid && pts <= lastVideoPTS {
                return
            }
            lastVideoPTS = pts

            if !input.append(sampleBuffer) {
                appendAppLog("nb.log", "[ScreenRecorder] video append failed: \(String(describing: writer.error))")
            }
        }
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        queue.async { [self] in
            guard isSessionStarted else { return }
            guard sampleBuffer.isValid else { return }
            guard writer.status == .writing else { return }
            guard let input = audioInput, input.isReadyForMoreMediaData else { return }

            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            guard pts.isValid && pts.flags.contains(.valid) else { return }

            if let startTime = sessionStartTime, pts < startTime {
                return
            }

            if !input.append(sampleBuffer) {
                appendAppLog("nb.log", "[ScreenRecorder] audio append failed: \(String(describing: writer.error))")
            }
        }
    }

    func finish() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                videoInput?.markAsFinished()
                audioInput?.markAsFinished()
                if writer.status == .writing && isSessionStarted {
                    writer.finishWriting {
                        continuation.resume()
                    }
                } else {
                    writer.cancelWriting()
                    continuation.resume()
                }
            }
        }
    }
}

// MARK: - Stream Output Bridge

private final class StreamOutputBridge: NSObject, SCStreamOutput, @unchecked Sendable {
    private let videoHandler: (CMSampleBuffer) -> Void
    private let audioHandler: (CMSampleBuffer) -> Void

    init(videoHandler: @escaping (CMSampleBuffer) -> Void, audioHandler: @escaping (CMSampleBuffer) -> Void) {
        self.videoHandler = videoHandler
        self.audioHandler = audioHandler
        super.init()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        switch type {
        case .screen:
            guard CMSampleBufferGetImageBuffer(sampleBuffer) != nil else { return }

            if let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
               let attachments = attachmentsArray.first,
               let statusRaw = attachments[.status] as? Int,
               let status = SCFrameStatus(rawValue: statusRaw) {
                guard status == .complete else { return }
            }

            videoHandler(sampleBuffer)
        case .audio, .microphone:
            audioHandler(sampleBuffer)
        @unknown default:
            break
        }
    }
}
#endif
