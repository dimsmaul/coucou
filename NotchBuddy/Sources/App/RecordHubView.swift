#if !APPSTORE
import AppKit
import SwiftUI

// MARK: - Record Hub View

struct RecordHubView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var recorder = ScreenRecorder.shared
    @ObservedObject private var detector = MeetingDetector.shared
    @ObservedObject private var noteTaker = NoteTaker.shared

    @State private var availableWindows: [AvailableWindow] = []
    @State private var showingWindowPicker: Bool = false
    @State private var activeTab: RecordTab = .meeting
    @State private var lastSavedBannerVisible: Bool = false

    enum RecordTab: String, CaseIterable, Identifiable {
        case meeting = "Meeting"
        case screen = "Screen"
        case window = "Window"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .meeting: return "person.2.fill"
            case .screen: return "display"
            case .window: return "macwindow"
            }
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: nil) { EmptyView() }

            if showingWindowPicker {
                windowPickerContent
            } else if recorder.isRecording {
                activeRecordingContent
            } else {
                setupContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            recorder.updatePermissionStatus()
            loadWindows()
            // If an active meeting is already detected, start on meeting tab; otherwise screen tab is ready
            if detector.activeMeeting != nil {
                activeTab = .meeting
            }
        }
        .onChange(of: recorder.isRecording) { recording in
            if !recording && recorder.lastRecordedURL != nil {
                lastSavedBannerVisible = true
            }
        }
        .onReceive(detector.$activeMeeting) { meeting in
            if let m = meeting, let wid = m.windowID {
                if activeTab == .meeting {
                    recorder.target = .window(windowID: wid, title: m.windowTitle, appName: m.platform.rawValue)
                }
            }
        }
    }

    // MARK: - Setup Content

    private var setupContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top Row: Category Tabs (Meeting / Screen / Window) + Mode (Video / Audio) + Folder button
            HStack(spacing: 6) {
                // Category Pills (Meeting / Screen / Window)
                HStack(spacing: 2) {
                    ForEach(RecordTab.allCases) { tab in
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                activeTab = tab
                                handleTabSelection(tab)
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 8.5))
                                Text(tab.rawValue)
                                    .font(.system(size: 10, weight: activeTab == tab ? .semibold : .medium))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(activeTab == tab ? Color.white.opacity(0.14) : Color.clear)
                            .foregroundColor(activeTab == tab ? Color(hex: "#F5F6F8") : Color(hex: "#8E939C"))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(Color.white.opacity(0.04))
                .clipShape(Capsule())

                Spacer(minLength: 4)

                // Video vs Audio Only Switcher
                HStack(spacing: 2) {
                    ForEach(RecordingMode.allCases) { m in
                        Button(action: {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                recorder.mode = m
                            }
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: m.icon)
                                    .font(.system(size: 8))
                                Text(m == .videoAndAudio ? "Video" : "Audio")
                                    .font(.system(size: 9.5, weight: recorder.mode == m ? .semibold : .medium))
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(recorder.mode == m ? Color.white.opacity(0.14) : Color.clear)
                            .foregroundColor(recorder.mode == m ? Color(hex: "#F5F6F8") : Color(hex: "#6B7079"))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(Color.white.opacity(0.04))
                .clipShape(Capsule())

                // Video Format Switcher (WebM vs MP4)
                if recorder.mode == .videoAndAudio {
                    HStack(spacing: 2) {
                        ForEach(ScreenRecorder.VideoFormat.allCases) { fmt in
                            Button(action: {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    recorder.videoFormat = fmt
                                }
                            }) {
                                Text(fmt.rawValue)
                                    .font(.system(size: 9.5, weight: recorder.videoFormat == fmt ? .semibold : .medium))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(recorder.videoFormat == fmt ? Color(hex: "#3B82F6").opacity(0.35) : Color.clear)
                                    .foregroundColor(recorder.videoFormat == fmt ? Color(hex: "#F5F6F8") : Color(hex: "#6B7079"))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(2)
                    .background(Color.white.opacity(0.04))
                    .clipShape(Capsule())
                }

                // Recordings Folder Button
                Button(action: {
                    ScreenRecorder.openRecordingsFolder()
                }) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .padding(5)
                        .background(Color.white.opacity(0.04))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Open Coucou Recordings in Finder (~/Movies/Coucou Recordings)")
            }

            // Screen Recording Permission Warning (if needed)
            if recorder.mode == .videoAndAudio && !recorder.hasScreenRecordingPermission {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9.5))
                        .foregroundColor(Color(hex: "#F5A524"))

                    Text("Screen Recording permission required")
                        .font(.system(size: 9.5))
                        .foregroundColor(Color(hex: "#D5D7DB"))
                        .lineLimit(1)

                    Spacer()

                    Button(action: {
                        recorder.updatePermissionStatus()
                    }) {
                        Text("Recheck")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(Color(hex: "#F5F6F8"))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        ScreenRecorder.openScreenRecordingSettings()
                    }) {
                        Text("Settings")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Color(hex: "#0B0C0E"))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Color(hex: "#F5A524"))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(Color(hex: "#F5A524").opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            // Status or Error Message Banner
            if let msg = recorder.statusMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 9.5))
                        .foregroundColor(Color(hex: "#EF4444"))

                    Text(msg)
                        .font(.system(size: 9.5))
                        .foregroundColor(Color(hex: "#F5F6F8"))
                        .lineLimit(1)

                    Spacer()

                    Button(action: {
                        recorder.clearStatusMessage()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 7.5))
                            .foregroundColor(Color(hex: "#8E939C"))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(Color(hex: "#EF4444").opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            // Target Context Card
            targetCard

            // Bottom Action Row: Controls (Mic, Sound, STT, PIP) + Primary Action Button
            HStack(spacing: 8) {
                // Control Toggles
                HStack(spacing: 4) {
                    CoucouTogglePill(icon: "mic.fill", label: "Mic", isOn: $recorder.micEnabled, tint: "#22C55E")
                    CoucouTogglePill(icon: "speaker.wave.2.fill", label: "Sound", isOn: $recorder.systemAudioEnabled, tint: "#3B82F6")
                    CoucouTogglePill(icon: "text.badge.waveform", label: "STT", isOn: $recorder.liveTranscriptEnabled, tint: "#A855F7")

                    if recorder.mode == .videoAndAudio {
                        CoucouTogglePill(icon: "camera.fill", label: "PIP", isOn: $recorder.cameraPipEnabled, tint: "#F59E0B")
                    }
                }

                Spacer(minLength: 4)

                // Primary Start Button or Meeting Status
                primaryActionButton
            }

            // Optional: Last saved file quick notification
            if lastSavedBannerVisible, let url = recorder.lastRecordedURL {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundColor(Color(hex: "#22C55E"))

                    Text("Saved to Movies/Coucou Recordings: \(url.lastPathComponent)")
                        .font(.system(size: 9.5))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .lineLimit(1)

                    Spacer()

                    Button(action: {
                        ScreenRecorder.revealInFinder(url)
                    }) {
                        Text("Show in Finder")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Color(hex: "#F5F6F8"))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        withAnimation { lastSavedBannerVisible = false }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 7.5))
                            .foregroundColor(Color(hex: "#6B7079"))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .padding(.leading, 108)
        .padding(.trailing, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    // MARK: - Target Card

    @ViewBuilder
    private var targetCard: some View {
        switch activeTab {
        case .meeting:
            if let meeting = detector.activeMeeting {
                // Meeting Detected
                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color(hex: meeting.platform.brandHex))
                            .frame(width: 6, height: 6)
                        Text(meeting.platform.rawValue)
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundColor(Color(hex: meeting.platform.brandHex))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color(hex: meeting.platform.brandHex).opacity(0.12))
                    .clipShape(Capsule())

                    VStack(alignment: .leading, spacing: 1) {
                        Text(meeting.windowTitle)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: "#F5F6F8"))
                            .lineLimit(1)
                        Text("Active Meeting Detected • Ready to record")
                            .font(.system(size: 9.5))
                            .foregroundColor(Color(hex: "#8E939C"))
                    }

                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                // No Meeting Detected (Interactive State)
                HStack(spacing: 8) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#6B7079"))

                    VStack(alignment: .leading, spacing: 1.5) {
                        Text("Auto-detecting Google Meet, Zoom, Teams…")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(Color(hex: "#D5D7DB"))
                        Text("Or manually select your meeting window")
                            .font(.system(size: 9))
                            .foregroundColor(Color(hex: "#6B7079"))
                    }

                    Spacer()

                    Button(action: {
                        loadWindows()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showingWindowPicker = true
                        }
                    }) {
                        HStack(spacing: 3) {
                            Text("Pick Window…")
                                .font(.system(size: 9.5, weight: .semibold))
                        }
                        .foregroundColor(Color(hex: "#3B82F6"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(Color(hex: "#3B82F6").opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.025))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

        case .screen:
            HStack(spacing: 8) {
                Image(systemName: "display")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#8E939C"))

                VStack(alignment: .leading, spacing: 1) {
                    Text("Entire Screen (Primary Display)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: "#F5F6F8"))
                    Text("Records all display contents with audio")
                        .font(.system(size: 9.5))
                        .foregroundColor(Color(hex: "#8E939C"))
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

        case .window:
            HStack(spacing: 8) {
                Image(systemName: "macwindow")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#8E939C"))

                VStack(alignment: .leading, spacing: 1) {
                    Text(recorder.target.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: "#F5F6F8"))
                        .lineLimit(1)
                    Text("Selected application window")
                        .font(.system(size: 9.5))
                        .foregroundColor(Color(hex: "#8E939C"))
                }

                Spacer()

                Button(action: {
                    loadWindows()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showingWindowPicker = true
                    }
                }) {
                    HStack(spacing: 3) {
                        Text("Change Window…")
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                    .foregroundColor(Color(hex: "#3B82F6"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(Color(hex: "#3B82F6").opacity(0.12))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    // MARK: - Primary Action Button

    @ViewBuilder
    private var primaryActionButton: some View {
        Button(action: {
            Task { @MainActor in
                if activeTab == .meeting && detector.activeMeeting == nil {
                    loadWindows()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showingWindowPicker = true
                    }
                } else {
                    await recorder.startRecording()
                }
            }
        }) {
            HStack(spacing: 5) {
                Circle()
                    .fill(Color(hex: "#EF4444"))
                    .frame(width: 6, height: 6)
                Text(primaryActionTitle)
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 5.5)
            .background(Color(hex: "#F5F6F8"))
            .foregroundColor(Color(hex: "#0B0C0E"))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var primaryActionTitle: String {
        if recorder.mode == .audioOnly {
            return "Record Audio"
        }
        if activeTab == .meeting {
            return detector.activeMeeting != nil ? "Record Meeting" : "Select Meeting Window"
        }
        return "Record Video"
    }

    // MARK: - Window Picker View

    private var windowPickerContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header with back button
            HStack {
                Image(systemName: "macwindow")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#8E939C"))

                Text("Select Window to Record")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))

                Spacer()

                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showingWindowPicker = false
                    }
                }) {
                    Text("Done")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(hex: "#F5F6F8"))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            // Scrollable list of windows
            if availableWindows.isEmpty {
                VStack(spacing: 4) {
                    Spacer()
                    Text("No accessible windows found")
                        .font(.system(size: 10.5))
                        .foregroundColor(Color(hex: "#6B7079"))
                    Text("Grant Screen Recording permission to Coucou in System Settings")
                        .font(.system(size: 9))
                        .foregroundColor(Color(hex: "#4D5159"))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: 110)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 3) {
                        ForEach(availableWindows) { win in
                            Button(action: {
                                recorder.target = .window(windowID: win.id, title: win.title, appName: win.ownerName)
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showingWindowPicker = false
                                }
                            }) {
                                HStack(spacing: 7) {
                                    Image(systemName: "macwindow")
                                        .font(.system(size: 9))
                                        .foregroundColor(Color(hex: "#8E939C"))

                                    Text(win.ownerName)
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .foregroundColor(Color(hex: "#F5F6F8"))

                                    if !win.title.isEmpty {
                                        Text("— \(win.title)")
                                            .font(.system(size: 9.5))
                                            .foregroundColor(Color(hex: "#8E939C"))
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    if case .window(let id, _, _) = recorder.target, id == win.id {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(Color(hex: "#22C55E"))
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4.5)
                                .background(Color.white.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 115)
            }
        }
        .padding(.leading, 108)
        .padding(.trailing, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    // MARK: - Active Recording Content

    private var activeRecordingContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            // Status and timer
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(hex: "#EF4444"))
                        .frame(width: 7, height: 7)
                    Text("RECORDING")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color(hex: "#EF4444"))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Color(hex: "#EF4444").opacity(0.12))
                .clipShape(Capsule())

                Text(formatDuration(recorder.elapsedSeconds))
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#F5F6F8"))

                Text(recorder.mode.rawValue)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())

                Spacer()

                // Audio levels
                HStack(spacing: 6) {
                    if recorder.micEnabled {
                        CoucouAudioMeter(level: recorder.micLevel, color: Color(hex: "#22C55E"))
                    }
                    if recorder.systemAudioEnabled {
                        CoucouAudioMeter(level: recorder.systemLevel, color: Color(hex: "#3B82F6"))
                    }
                }
            }

            // Target or live transcript excerpt
            if recorder.liveTranscriptEnabled, let latest = noteTaker.recording?.lines.last {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "waveform")
                        .font(.system(size: 9))
                        .foregroundColor(Color(hex: "#A855F7"))
                    Text(latest.text)
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#D5D7DB"))
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "macwindow")
                        .font(.system(size: 9))
                        .foregroundColor(Color(hex: "#8E939C"))
                    Text(recorder.target.displayName)
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .lineLimit(1)
                    Spacer()
                }
            }

            // Stop button & Open folder
            HStack(spacing: 8) {
                Button(action: {
                    Task { @MainActor in
                        await recorder.stopRecording()
                    }
                }) {
                    HStack(spacing: 5) {
                        if recorder.isStopping {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.6)
                            Text("Saving…")
                                .font(.system(size: 11, weight: .semibold))
                        } else {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 8.5))
                            Text("Stop & Save Recording")
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5.5)
                    .background(Color(hex: "#EF4444").opacity(recorder.isStopping ? 0.6 : 1.0))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(recorder.isStopping)

                Button(action: {
                    ScreenRecorder.openRecordingsFolder()
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "folder")
                            .font(.system(size: 9))
                        Text("Recordings Folder")
                            .font(.system(size: 9.5))
                    }
                    .foregroundColor(Color(hex: "#8E939C"))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4.5)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 108)
        .padding(.trailing, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    // MARK: - Actions & Helpers

    private func handleTabSelection(_ tab: RecordTab) {
        switch tab {
        case .meeting:
            showingWindowPicker = false
            if let m = detector.activeMeeting, let wid = m.windowID {
                recorder.target = .window(windowID: wid, title: m.windowTitle, appName: m.platform.rawValue)
            } else {
                recorder.target = .fullScreen(displayID: CGMainDisplayID())
            }
        case .screen:
            showingWindowPicker = false
            recorder.target = .fullScreen(displayID: CGMainDisplayID())
        case .window:
            loadWindows()
            if case .fullScreen = recorder.target, let first = availableWindows.first {
                recorder.target = .window(windowID: first.id, title: first.title, appName: first.ownerName)
            }
            showingWindowPicker = true
        }
    }

    private func loadWindows() {
        Task { @MainActor in
            let wins = await ScreenRecorder.fetchShareableWindows()
            self.availableWindows = wins
            if case .window(let wid, _, _) = self.recorder.target {
                // Keep selected window if present
            } else if let first = wins.first {
                self.recorder.target = .window(windowID: first.id, title: first.title, appName: first.ownerName)
            }
        }
    }

    private func formatDuration(_ totalSeconds: Int) -> String {
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - Coucou Toggle Pill

private struct CoucouTogglePill: View {
    let icon: String
    let label: String
    @Binding var isOn: Bool
    let tint: String

    var body: some View {
        Button(action: { isOn.toggle() }) {
            HStack(spacing: 3) {
                Circle()
                    .fill(isOn ? Color(hex: tint) : Color.white.opacity(0.15))
                    .frame(width: 4.5, height: 4.5)
                Image(systemName: icon)
                    .font(.system(size: 8))
                Text(label)
                    .font(.system(size: 9, weight: .medium))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(isOn ? Color.white.opacity(0.09) : Color.white.opacity(0.03))
            .foregroundColor(isOn ? Color(hex: "#F5F6F8") : Color(hex: "#6B7079"))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Coucou Audio Meter

private struct CoucouAudioMeter: View {
    let level: Float
    let color: Color

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<4, id: \.self) { idx in
                let active = level > Float(idx) * 0.15
                RoundedRectangle(cornerRadius: 1)
                    .fill(active ? color : Color.white.opacity(0.1))
                    .frame(width: 2, height: CGFloat(3 + idx * 2))
            }
        }
    }
}
#endif
