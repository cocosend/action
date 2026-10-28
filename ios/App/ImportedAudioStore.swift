import Foundation

/// Only filenames created within this application's private ImportedAudio folder
/// are trusted. User-supplied absolute paths are never persisted.
struct ImportedAudio: Codable, Equatable, Sendable {
    let fileName: String
    let title: String
    let duration: Double
    let tempo: TempoEstimate?
    /// Optional offline timing hint. Null for legacy sessions or uncertain rhythm.
    let beatGrid: BeatGridEstimate?
    /// Optional migration-safe flag; true means the user chose tempo/phase.
    let manuallyAdjustedGrid: Bool?
    /// Up to eight independently saved Hot Cues, seconds measured from file start.
    /// Nil means this is a legacy manifest with no cue data.
    let hotCues: [Double?]?
    /// Most recently saved optional local file loop; never auto-resumes.
    let loop: FileLoopPlan?

    init(fileName: String, title: String, duration: Double,
         tempo: TempoEstimate? = nil, beatGrid: BeatGridEstimate? = nil,
         manuallyAdjustedGrid: Bool? = nil, hotCues: [Double?]? = nil,
         loop: FileLoopPlan? = nil) {
        self.fileName = fileName
        self.title = title
        self.duration = duration
        self.tempo = tempo
        self.beatGrid = beatGrid
        self.manuallyAdjustedGrid = manuallyAdjustedGrid
        self.hotCues = hotCues
        self.loop = loop
    }

    var isValid: Bool {
        !fileName.isEmpty && !fileName.contains("/") && !fileName.contains("\\") &&
        fileName != "." && fileName != ".." && !title.isEmpty &&
        duration.isFinite && duration > 0 && duration < 60 * 60 * 12 &&
        (tempo?.isValid ?? true) && (beatGrid?.isValid ?? true) &&
        (beatGrid == nil || tempo != nil) &&
        (manuallyAdjustedGrid != true || beatGrid != nil) &&
        (loop?.isValid(duration: duration) ?? true) &&
        (hotCues == nil || (hotCues?.count == 8 && hotCues?.allSatisfy { cue in
            guard let cue else { return true }
            return cue.isFinite && cue >= 0 && cue < duration
        } == true)) &&
        (beatGrid == nil || {
            guard let beatGrid, let tempo else { return false }
            return abs(60 / beatGrid.beatIntervalSeconds - tempo.bpm) <= tempo.bpm * 0.045
        }())
    }
}

struct ImportedAudioStore: Codable, Sendable {
    var decks: [ImportedAudio?] = [nil, nil]

    static var folder: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory,
                                             in: .userDomainMask)[0]
        return root.appendingPathComponent("MixAutoPro-ImportedAudio", isDirectory: true)
    }

    static var manifestURL: URL {
        folder.appendingPathComponent("deck-imports.json")
    }

    static func load() -> ImportedAudioStore {
        guard let data = try? Data(contentsOf: manifestURL),
              let store = try? JSONDecoder().decode(Self.self, from: data),
              store.decks.count == 2,
              store.decks.allSatisfy({ $0?.isValid ?? true })
        else { return Self() }
        return store
    }

    func save() throws {
        guard decks.count == 2, decks.allSatisfy({ $0?.isValid ?? true }) else {
            throw NSError(domain: "TrackBuilderImport", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid imported audio manifest"])
        }
        try FileManager.default.createDirectory(at: Self.folder,
                                                withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: Self.manifestURL, options: [.atomic])
    }

    static func fileURL(for audio: ImportedAudio) -> URL? {
        guard audio.isValid else { return nil }
        return folder.appendingPathComponent(audio.fileName)
    }
}
