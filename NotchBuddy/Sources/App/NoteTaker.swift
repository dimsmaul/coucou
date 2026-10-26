#if !APPSTORE
import AppKit
import AVFoundation
@preconcurrency import FluidAudio
import UniformTypeIdentifiers
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Who writes the summary of a call.
enum NoteSummaryEngine: String, CaseIterable, Identifiable {
    /// The Claude key of Settings → Chat (the transcript goes to Anthropic).
    case claude
    /// Apple Intelligence, on the Mac (macOS 26).
    case apple
    case off

    var id: String { rawValue }

    var label: String {
        switch self {
        case .claude: return String(localized: "notes.engine.claude")
        case .apple:  return String(localized: "notes.engine.apple")
        case .off:    return String(localized: "notes.engine.off")
        }
    }
}

/// The Notetaker: records a call (your microphone, and what the Mac plays for the other people),
/// shows a live transcript, then writes the whole transcript person by person with Parakeet and
/// FluidAudio's diarizer, and a summary with the to-dos. Everything is stored in
/// Application Support/NotchBuddy/Notes; the audio is deleted once the transcript is written.
/// No bot joins the call: the other people should be told it is recorded.
@MainActor
final class NoteTaker: ObservableObject {
    static let shared = NoteTaker()

    /// Newest first.
    @Published private(set) var notes: [Note] = []
    /// The note being recorded, with its live lines.
    @Published private(set) var recording: Note?
    @Published private(set) var micLevel: Float = 0
    @Published private(set) var systemLevel: Float = 0
    /// What went wrong when a recording could not start.
    @Published var startError: String?
    /// Notes whose transcript or summary is being written.
    @Published private(set) var working: Set<UUID> = []

    @Published var summaryEngine: NoteSummaryEngine {
        didSet { UserDefaults.standard.set(summaryEngine.rawValue, forKey: Self.engineKey) }
    }

    static let engineKey = "noteSummaryEngine"

    private var mic: MicCapture?
    private var tap: SystemAudioTap?
    private var micChannel: ChannelRecorder?
    private var systemChannel: ChannelRecorder?
    private var liveTask: Task<Void, Never>?
    /// Between the click and the microphone's permission: a second click starts nothing.
    private var starting = false
    /// The last app in front other than Coucou: the call app when you click Record in Coucou Flow.
    private var lastApp: String?
    private var appObserver: NSObjectProtocol?

    static var folder: URL { HookServer.supportDir.appendingPathComponent("Notes", isDirectory: true) }

    private init() {
        if let saved = UserDefaults.standard.string(forKey: Self.engineKey), let engine = NoteSummaryEngine(rawValue: saved) {
            summaryEngine = engine
        } else {
            summaryEngine = FlowCleanup.hasKey ? .claude : (Self.appleModelAvailable ? .apple : .off)
        }
        load()
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            let name = app.localizedName
            MainActor.assumeIsolated { NoteTaker.shared.lastApp = name }
        }
    }

    var isRecording: Bool { recording != nil }

    /// The pill's record button: starts or stops, and says what is missing.
    func toggleFromPill() {
        if isRecording { stop(); return }
        guard Parakeet.shared.isReady else {
            FlowDictation.shared.pill.announce(
                FlowAnnouncement(symbol: "arrow.down.circle.fill", tint: "#3B9EFF", text: String(localized: "notes.error.models"),
                                 action: String(localized: "hub.open-settings"))) {
                FlowHubController.shared.show(.settings)
            }
            return
        }
        Task { @MainActor in
            await self.start()
            if let error = self.startError {
                FlowDictation.shared.pill.announce(FlowAnnouncement(symbol: "exclamationmark.circle.fill", tint: "#FF6B6B", text: error))
            }
        }
    }

    // MARK: - Recording

    @discardableResult
    func start(mic: Bool = true, system: Bool = true, liveTranscript: Bool = true) async -> UUID? {
        if let current = recording { return current.id }
        guard !starting else { return nil }
        starting = true
        defer { starting = false }
        startError = nil
        if liveTranscript && !Parakeet.shared.isReady {
            startError = String(localized: "notes.error.models")
            return nil
        }
        if mic {
            guard await AVAudioApplication.requestRecordPermission() else {
                startError = String(localized: "notes.error.mic")
                return nil
            }
        }
        let now = Date()
        var note = Note(title: String(format: String(localized: "notes.default-title %@"),
                                      now.formatted(.dateTime.day().month(.abbreviated).hour().minute())),
                        start: now)
        let front = NSWorkspace.shared.frontmostApplication
        note.app = front?.bundleIdentifier == Bundle.main.bundleIdentifier ? lastApp : front?.localizedName
        let dir = Self.folder(for: note.id)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if mic {
                let micChannel = try ChannelRecorder(url: dir.appendingPathComponent("mic.wav"), label: "fr.louisraille.NotchBuddy.notetaker.mic")
                let micCapture = MicCapture()
                guard micCapture.start(sink: { micChannel.append($0) }) else {
                    startError = String(localized: "notes.error.mic")
                    try? FileManager.default.removeItem(at: dir)
                    return nil
                }
                self.mic = micCapture
                self.micChannel = micChannel
            }
            if system {
                let systemChannel = try ChannelRecorder(url: dir.appendingPathComponent("system.wav"), label: "fr.louisraille.NotchBuddy.notetaker.sys")
                let tap = SystemAudioTap()
                do {
                    try tap.start(sink: { systemChannel.append($0) })
                    self.tap = tap
                    self.systemChannel = systemChannel
                } catch {
                    // Without the Mac's sound, the call is noted from the microphone alone.
                    appendAppLog("nb.log", "[Notetaker] system audio unavailable: \(error.localizedDescription)")
                    self.tap = nil
                    self.systemChannel = nil
                }
            }
        } catch {
            startError = error.localizedDescription
            return nil
        }
        recording = note
        notes.insert(note, at: 0)
        save(note)
        if liveTranscript {
            FlowDictation.shared.pill.setNote(note.start)
            SoundEngine.shared.play("blip")
            startLiveLoop()
        }
        return note.id
    }

    /// Coucou quits during a call: the recordings are closed properly, and the transcript is
    /// written at the next launch.
    func shutdown() {
        guard var note = recording else { return }
        liveTask?.cancel()
        mic?.stop()
        tap?.stop()
        micChannel?.closeNow()
        systemChannel?.closeNow()
        note.end = Date()
        note.status = .processing
        recording = nil
        replace(note)
    }

    func stop() {
        Task { @MainActor in
            _ = await self.stopAndExportAudio()
        }
    }

    /// Stops recording, immediately exports combined audio to audio.m4a, optionally copies to destination, and starts transcription.
    @discardableResult
    func stopAndExportAudio(for id: UUID? = nil, destination: URL? = nil) async -> URL? {
        var note = recording
        if note == nil, let targetID = id ?? notes.first?.id {
            note = self.note(targetID)
        }
        guard var activeNote = note else { return nil }

        let isCurrentRecording = recording?.id == activeNote.id

        if isCurrentRecording {
            liveTask?.cancel()
            liveTask = nil
            mic?.stop()
            tap?.stop()
            mic = nil
            tap = nil
            let micChannel = self.micChannel, systemChannel = self.systemChannel
            self.micChannel = nil
            self.systemChannel = nil
            micLevel = 0
            systemLevel = 0
            activeNote.end = Date()
            activeNote.status = .processing
            recording = nil
            replace(activeNote)
            FlowDictation.shared.pill.setNote(nil)

            // Close audio channels and wait for samples to finish writing to disk
            await micChannel?.close()
            await systemChannel?.close()
        }

        let dir = Self.folder(for: activeNote.id)
        let micURL = dir.appendingPathComponent("mic.wav")
        let systemURL = dir.appendingPathComponent("system.wav")
        let audioM4A = dir.appendingPathComponent("audio.m4a")

        // Immediately export audio.m4a before running transcription
        let exported = await Self.exportCombinedAudio(micURL: micURL, systemURL: systemURL, outputURL: audioM4A)
        let resolvedURL: URL
        if FileManager.default.fileExists(atPath: audioM4A.path) {
            resolvedURL = audioM4A
        } else if FileManager.default.fileExists(atPath: micURL.path) {
            let fallbackWav = dir.appendingPathComponent("audio.wav")
            try? FileManager.default.copyItem(at: micURL, to: fallbackWav)
            resolvedURL = FileManager.default.fileExists(atPath: fallbackWav.path) ? fallbackWav : micURL
        } else if FileManager.default.fileExists(atPath: systemURL.path) {
            resolvedURL = systemURL
        } else {
            resolvedURL = audioM4A
        }

        if let dest = destination, FileManager.default.fileExists(atPath: resolvedURL.path) {
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: resolvedURL, to: dest)
        }

        // Process transcription & summary in background if was current recording
        if isCurrentRecording {
            let noteID = activeNote.id
            Task { @MainActor in
                await self.process(noteID)
            }
        }

        return destination ?? resolvedURL
    }

    /// Every second while recording: the levels, and the stretches ending on a pause go to Parakeet
    /// for the live transcript (the final one is written again from the whole recording).
    private func startLiveLoop() {
        liveTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.recording != nil else { return }
                self.micLevel = self.micChannel?.level ?? 0
                self.systemLevel = self.systemChannel?.level ?? 0
                for (channel, speaker) in [(self.micChannel, NoteBuilder.meID), (self.systemChannel, "others")] {
                    guard let channel, let chunk = channel.takeChunk() else { continue }
                    guard let text = try? await Parakeet.shared.transcribe(chunk.samples),
                          !text.trimmingCharacters(in: .whitespaces).isEmpty,
                          var note = self.recording else { continue }
                    let end = chunk.start + Double(chunk.samples.count) / ChannelRecorder.sampleRate
                    note.lines.append(NoteLine(speaker: speaker, start: chunk.start, end: end, text: text))
                    note.lines.sort { $0.start < $1.start }
                    self.recording = note
                }
            }
        }
    }

    // MARK: - Transcript

    /// Writes the transcript from the recordings, then the summary, then deletes the audio.
    func process(_ id: UUID) async {
        guard var note = self.note(id), !working.contains(id) else { return }
        working.insert(id)
        defer { working.remove(id) }
        let dir = Self.folder(for: id)
        let micURL = dir.appendingPathComponent("mic.wav")
        let systemURL = dir.appendingPathComponent("system.wav")
        let me = String(localized: "notes.me")
        do {
            guard FileManager.default.fileExists(atPath: micURL.path) else {
                throw NSError(domain: "Notetaker", code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: "notes.error.no-audio")])
            }
            let asr = try await Parakeet.shared.manager()
            let mine = try await Self.words(in: micURL, asr: asr)
            var theirs: [TimedWord] = []
            if FileManager.default.fileExists(atPath: systemURL.path) {
                theirs = try await Self.words(in: systemURL, asr: asr)
            }
            let built: (speakers: [NoteSpeaker], lines: [NoteLine])
            if theirs.count >= 5 {
                // A call: you on the microphone, the others on the Mac's sound.
                let turns = try await Self.diarize(systemURL)
                built = NoteBuilder.build(mine: mine, others: theirs, turns: turns, meName: me, personName: Self.personName)
            } else if mine.count >= 20 {
                // People around the Mac: one recording, the voices told apart.
                let turns = try await Self.diarize(micURL)
                if Set(turns.map(\.speaker)).count > 1 {
                    built = NoteBuilder.buildRoom(words: mine, turns: turns, personName: Self.personName)
                } else {
                    built = NoteBuilder.build(mine: mine, others: [], turns: [], meName: me, personName: Self.personName)
                }
            } else {
                built = NoteBuilder.build(mine: mine, others: theirs, turns: [], meName: me, personName: Self.personName)
            }
            // Renamed (or deleted) meanwhile: write onto what is there now.
            guard var current = self.note(id) else { return }
            current.speakers = built.speakers
            current.lines = built.lines
            current.status = .ready
            current.error = nil
            replace(current)
            note = current

            // Ensure audio.m4a exists for in-app playback and recording archive
            let audioM4A = dir.appendingPathComponent("audio.m4a")
            if !FileManager.default.fileExists(atPath: audioM4A.path) {
                await Self.exportCombinedAudio(micURL: micURL, systemURL: systemURL, outputURL: audioM4A)
            }

            // Only remove raw WAVs if audio.m4a was successfully saved
            if FileManager.default.fileExists(atPath: audioM4A.path) {
                try? FileManager.default.removeItem(at: micURL)
                try? FileManager.default.removeItem(at: systemURL)
            }
            appendAppLog("nb.log", "[Notetaker] transcript: \(note.lines.count) lines, \(note.speakers.count) speakers")
        } catch {
            appendAppLog("nb.log", "[Notetaker] transcript failed: \(error.localizedDescription)")
            guard var current = self.note(id) else { return }
            current.status = .failed
            current.error = error.localizedDescription
            replace(current)
            return
        }
        if summaryEngine != .off, !note.lines.isEmpty {
            await summarize(id)
        }
        // The notes are ready: the pill says so, with a way to open them.
        let title = self.note(id)?.title ?? note.title
        FlowDictation.shared.pill.announce(
            FlowAnnouncement(symbol: "checkmark.circle.fill", tint: "#34D399",
                             text: String(format: String(localized: "notes.ann.ready %@"), title),
                             action: String(localized: "notes.ann.open")), for: 12) {
            FlowHubController.shared.show(.notes)
        }
    }

    nonisolated static func personName(_ number: Int) -> String {
        String(format: String(localized: "notes.person %lld"), number)
    }

    /// Whether the recordings of a note are still there (a failed note can be tried again).
    func hasAudio(_ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: Self.folder(for: id).appendingPathComponent("mic.wav").path)
    }

    nonisolated private static func words(in url: URL, asr: AsrManager) async throws -> [TimedWord] {
        var decoder = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
        let result: ASRResult
        do {
            result = try await asr.transcribe(url, decoderState: &decoder)
        } catch ASRError.invalidAudioData {
            return []   // too short to hold words
        }
        let isRussianLocale = Locale.current.language.languageCode?.identifier == "ru"
        let words = buildWordTimings(from: result.tokenTimings ?? []).compactMap { item -> TimedWord? in
            let text = item.word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let hasCyrillic = text.unicodeScalars.contains { $0.value >= 0x0400 && $0.value <= 0x04FF }
            if hasCyrillic && !isRussianLocale { return nil }
            return TimedWord(text: text, start: item.startTime, end: item.endTime)
        }
        return words
    }

    nonisolated private static func diarize(_ url: URL) async throws -> [SpeakerTurn] {
        let diarizer = OfflineDiarizerManager()
        try await diarizer.prepareModels(directory: Parakeet.modelsRoot)
        let result = try await diarizer.process(url)
        return result.segments.map {
            SpeakerTurn(speaker: $0.speakerId, start: Double($0.startTimeSeconds), end: Double($0.endTimeSeconds))
        }
    }

    // MARK: - Summary

    static var appleModelAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) { return SystemLanguageModel.default.availability == .available }
        #endif
        return false
    }

    /// Writes (or writes again) the summary, key points and to-dos of a note.
    func summarize(_ id: UUID) async {
        guard let note = self.note(id), !note.lines.isEmpty else { return }
        working.insert(id)
        defer { working.remove(id) }
        let transcript = NoteBuilder.plainTranscript(note)
        let reply: String?
        switch summaryEngine {
        case .claude:
            let key = KeychainStore.shared.get("anthropic-api-key") ?? ""
            let model = AppState.shared.claudeModel.isEmpty ? AppState.defaultClaudeModel : AppState.shared.claudeModel
            reply = key.isEmpty ? nil : await Self.claudeSummary(transcript, key: key, model: model)
        case .apple:
            reply = await Self.appleSummary(transcript)
        case .off:
            reply = nil
        }
        guard let reply, var current = self.note(id) else { return }
        if let parsed = NoteBuilder.parseSummary(reply) {
            if let title = parsed.title, current.titleEdited != true { current.title = title }
            current.summary = parsed.summary
            current.keyPoints = parsed.keyPoints
            current.todos = parsed.todos
        } else {
            current.summary = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        replace(current)
    }

    nonisolated static let summaryInstructions = """
    You write the notes of a meeting from its transcript. Each line is "Name: words".
    Write in the language of the transcript. Invent nothing that was not said.
    Reply ONLY with JSON, no code block, in this exact shape:
    {"title": "a short title, 6 words at most", "summary": "2 to 4 sentences: what was decided and why", \
    "key_points": ["up to 6 short points"], "todos": [{"text": "the task", "owner": "the person's name as written in the transcript, or null", "due": "the deadline as said, or null"}]}
    """

    nonisolated private static func claudeSummary(_ transcript: String, key: String, model: String) async -> String? {
        func call(_ model: String) async -> String? {
            var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 120
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            let body: [String: Any] = [
                "model": model,
                "max_tokens": 2048,
                "system": summaryInstructions,
                "messages": [["role": "user", "content": "<transcript>\n\(transcript.prefix(400_000))\n</transcript>"]],
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
            request.httpBody = data
            guard let result = try? await URLSession.shared.data(for: request),
                  (result.1 as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any],
                  let content = json["content"] as? [[String: Any]] else { return nil }
            let text = content.compactMap { $0["text"] as? String }.joined()
            return text.isEmpty ? nil : text
        }
        if let text = await call(model) { return text }
        return await call(FlowCleanup.model)
    }

    /// Apple's on-device model has a small context: a long call is first noted in parts, then the
    /// notes of the parts are summarized.
    nonisolated private static func appleSummary(_ transcript: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            guard SystemLanguageModel.default.availability == .available else { return nil }
            let words = transcript.split(separator: " ")
            var material = transcript
            if words.count > 1_200 {
                var notes: [String] = []
                var index = 0
                while index < words.count {
                    let part = words[index..<min(words.count, index + 1_500)].joined(separator: " ")
                    index += 1_500
                    let session = LanguageModelSession(instructions: "Write short notes of this part of a meeting transcript: who said what, decisions, tasks. Keep the transcript's language and the people's names. Invent nothing.")
                    if let answer = try? await session.respond(to: part).content { notes.append(answer) }
                }
                material = notes.joined(separator: "\n\n")
            }
            let session = LanguageModelSession(instructions: summaryInstructions)
            return try? await session.respond(to: material).content
        }
        #endif
        return nil
    }

    // MARK: - Editing

    func note(_ id: UUID) -> Note? {
        if recording?.id == id { return recording }
        return notes.first { $0.id == id }
    }

    func rename(_ id: UUID, title: String) {
        guard var note = self.note(id) else { return }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t != note.title else { return }
        note.title = t
        note.titleEdited = true
        replace(note)
    }

    func rename(_ id: UUID, speaker: String, to name: String) {
        guard var note = self.note(id), let index = note.speakers.firstIndex(where: { $0.id == speaker }) else { return }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        note.speakers[index].name = n
        replace(note)
    }

    func toggle(_ id: UUID, todo: UUID) {
        guard var note = self.note(id), let index = note.todos.firstIndex(where: { $0.id == todo }) else { return }
        note.todos[index].done.toggle()
        replace(note)
    }

    func delete(_ id: UUID) {
        guard recording?.id != id, !working.contains(id) else { return }
        notes.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: Self.folder(for: id))
    }

    func markdown(_ note: Note) -> String {
        NoteBuilder.markdown(note, labels: .init(summary: String(localized: "notes.summary"),
                                                 keyPoints: String(localized: "notes.key-points"),
                                                 todos: String(localized: "notes.todos"),
                                                 transcript: String(localized: "notes.transcript")))
    }

    /// Asks where to save the note as a Markdown file.
    func export(_ note: Note) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = note.title.replacingOccurrences(of: "/", with: "-") + ".md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? markdown(note).write(to: url, atomically: true, encoding: .utf8)
    }

    func audioURL(for id: UUID) -> URL? {
        let dir = Self.folder(for: id)
        let m4a = dir.appendingPathComponent("audio.m4a")
        if FileManager.default.fileExists(atPath: m4a.path) { return m4a }
        let fallbackWav = dir.appendingPathComponent("audio.wav")
        if FileManager.default.fileExists(atPath: fallbackWav.path) { return fallbackWav }
        let mic = dir.appendingPathComponent("mic.wav")
        if FileManager.default.fileExists(atPath: mic.path) { return mic }
        return nil
    }

    @discardableResult
    static func exportCombinedAudio(micURL: URL, systemURL: URL, outputURL: URL) async -> Bool {
        let fm = FileManager.default
        let micSize = (try? fm.attributesOfItem(atPath: micURL.path)[.size] as? Int64) ?? 0
        let sysSize = (try? fm.attributesOfItem(atPath: systemURL.path)[.size] as? Int64) ?? 0
        let hasMic = fm.fileExists(atPath: micURL.path) && micSize > 100
        let hasSys = fm.fileExists(atPath: systemURL.path) && sysSize > 100
        guard hasMic || hasSys else { return false }

        // Prefer ffmpeg if available for superfast and robust mixing
        if let _ = ScreenRecorder.ffmpegPath {
            try? fm.removeItem(at: outputURL)
            var args: [String] = ["-y"]
            if hasMic && hasSys {
                args += ["-i", micURL.path, "-i", systemURL.path,
                         "-filter_complex", "[0:a][1:a]amix=inputs=2:duration=longest:dropout_transition=2[a]",
                         "-map", "[a]", "-c:a", "aac", "-b:a", "128k", outputURL.path]
            } else if hasMic {
                args += ["-i", micURL.path, "-c:a", "aac", "-b:a", "128k", outputURL.path]
            } else {
                args += ["-i", systemURL.path, "-c:a", "aac", "-b:a", "128k", outputURL.path]
            }

            let ok = await ScreenRecorder.runFFmpeg(arguments: args)
            if ok && fm.fileExists(atPath: outputURL.path) {
                let size = (try? fm.attributesOfItem(atPath: outputURL.path)[.size] as? Int64) ?? 0
                if size > 100 {
                    return true
                }
            }
        }

        // Native AVFoundation Fallback
        if hasMic && !hasSys {
            let micAsset = AVURLAsset(url: micURL)
            guard let exporter = AVAssetExportSession(asset: micAsset, presetName: AVAssetExportPresetAppleM4A) else {
                let fallbackWav = outputURL.deletingPathExtension().appendingPathExtension("wav")
                try? fm.copyItem(at: micURL, to: fallbackWav)
                return false
            }
            try? fm.removeItem(at: outputURL)
            exporter.outputURL = outputURL
            exporter.outputFileType = .m4a
            await exporter.export()
            if exporter.status == .completed && fm.fileExists(atPath: outputURL.path) {
                return true
            }
            let fallbackWav = outputURL.deletingPathExtension().appendingPathExtension("wav")
            try? fm.copyItem(at: micURL, to: fallbackWav)
            return false
        }

        // Both mic and system audio exist: mix using AVMutableComposition + AVMutableAudioMix
        let comp = AVMutableComposition()
        guard let micTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
              let sysTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return false
        }

        let micAsset = AVURLAsset(url: micURL)
        let sysAsset = AVURLAsset(url: systemURL)

        let mTracks = micAsset.tracks(withMediaType: .audio)
        if let mSrc = mTracks.first {
            try? micTrack.insertTimeRange(CMTimeRange(start: .zero, duration: micAsset.duration), of: mSrc, at: .zero)
        }

        let sTracks = sysAsset.tracks(withMediaType: .audio)
        if let sSrc = sTracks.first {
            try? sysTrack.insertTimeRange(CMTimeRange(start: .zero, duration: sysAsset.duration), of: sSrc, at: .zero)
        }

        let audioMix = AVMutableAudioMix()
        let p1 = AVMutableAudioMixInputParameters(track: micTrack)
        p1.setVolume(1.0, at: .zero)
        let p2 = AVMutableAudioMixInputParameters(track: sysTrack)
        p2.setVolume(1.0, at: .zero)
        audioMix.inputParameters = [p1, p2]

        try? fm.removeItem(at: outputURL)
        guard let exporter = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetAppleM4A) else { return false }
        exporter.outputURL = outputURL
        exporter.outputFileType = .m4a
        exporter.audioMix = audioMix
        await exporter.export()

        if exporter.status == .completed && fm.fileExists(atPath: outputURL.path) {
            return true
        }

        // Fallback: If mix export session failed, export mic alone
        if hasMic {
            let fallbackAsset = AVURLAsset(url: micURL)
            if let fallbackExp = AVAssetExportSession(asset: fallbackAsset, presetName: AVAssetExportPresetAppleM4A) {
                try? fm.removeItem(at: outputURL)
                fallbackExp.outputURL = outputURL
                fallbackExp.outputFileType = .m4a
                await fallbackExp.export()
                if fallbackExp.status == .completed && fm.fileExists(atPath: outputURL.path) {
                    return true
                }
            }
            let fallbackWav = outputURL.deletingPathExtension().appendingPathExtension("wav")
            try? fm.copyItem(at: micURL, to: fallbackWav)
        }
        return false
    }

    // MARK: - Files

    static func folder(for id: UUID) -> URL { folder.appendingPathComponent(id.uuidString, isDirectory: true) }

    private func replace(_ note: Note) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) { notes[index] = note } else { notes.insert(note, at: 0) }
        save(note)
    }

    private func save(_ note: Note) {
        do {
            let dir = Self.folder(for: note.id)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted]
            try encoder.encode(note).write(to: dir.appendingPathComponent("note.json"), options: .atomic)
        } catch {
            appendAppLog("nb.log", "[Notetaker] could not save a note: \(error.localizedDescription)")
        }
    }

    private func load() {
        guard let dirs = try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var loaded: [Note] = []
        for dir in dirs {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("note.json")),
                  var note = try? decoder.decode(Note.self, from: data) else { continue }
            // Coucou quit while recording or writing: the transcript is written again from the audio.
            if note.status == .recording || note.status == .processing {
                note.end = note.end ?? (try? dir.appendingPathComponent("mic.wav").resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                note.status = .processing
            }
            loaded.append(note)
        }
        notes = loaded.sorted { $0.start > $1.start }
        let pending = notes.filter { $0.status == .processing }.map(\.id)
        guard !pending.isEmpty else { return }
        guard Parakeet.shared.isReady else {
            // No models any more: shown as failed, with Retry once they are back.
            for id in pending {
                guard var note = self.note(id) else { continue }
                note.status = .failed
                note.error = String(localized: "notes.error.models")
                replace(note)
            }
            return
        }
        Task { @MainActor in
            for id in pending { await self.process(id) }
        }
    }
}
#endif
