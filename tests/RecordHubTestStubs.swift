import Foundation

@MainActor
final class SoundEngine {
    static let shared = SoundEngine()
    var lastPlayed: String?
    func play(_ name: String) { lastPlayed = name }
}

func appendAppLog(_ file: String, _ message: String) {
    // Test log stub
}

struct NoteLineStub {
    let speaker: String = ""
    let text: String = ""
}

struct NoteStub {
    let id: UUID = UUID()
    let lines: [NoteLineStub] = []
}

final class NoteTaker: ObservableObject {
    static let shared = NoteTaker()
    var isRecording: Bool = false
    var recording: NoteStub? = nil
    var startError: String? = nil
    var notes: [NoteStub] = []
    @discardableResult
    func start(mic: Bool = true, system: Bool = true, liveTranscript: Bool = true) async -> UUID? { nil }
    func stop() {}
    @discardableResult
    func stopAndExportAudio(for id: UUID? = nil, destination: URL? = nil) async -> URL? { nil }
    static func folder(for id: UUID) -> URL { URL(fileURLWithPath: "/tmp") }
    @discardableResult
    static func exportCombinedAudio(micURL: URL, systemURL: URL, outputURL: URL) async -> Bool { false }
}

final class MicCapture: @unchecked Sendable {
    func start(sink: @escaping @Sendable ([Float]) -> Void) -> Bool { true }
    func stop() {}
}

final class SystemAudioTap: @unchecked Sendable {
    func start(sink: @escaping @Sendable ([Float]) -> Void) throws {}
    func stop() {}
}

enum ChannelRecorder {
    static func rms(_ samples: ArraySlice<Float>) -> Float { 0 }
}
