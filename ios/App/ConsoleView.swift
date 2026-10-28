import SwiftUI
import Combine
import UniformTypeIdentifiers

// Original approved Canva: Spectral Cockpit, first nine-slide design.
// Palette and placement remain fixed; no alternative redesign introduced.
private enum Spectral {
    static let bg = Color(red: 17/255, green: 18/255, blue: 20/255)
    static let panel = Color(red: 24/255, green: 26/255, blue: 29/255)
    static let raised = Color(red: 32/255, green: 35/255, blue: 40/255)
    static let rule = Color(red: 48/255, green: 52/255, blue: 58/255)
    static let ink = Color(red: 244/255, green: 244/255, blue: 245/255)
    static let muted = Color(red: 154/255, green: 158/255, blue: 166/255)
    static let a = Color(red: 78/255, green: 216/255, blue: 235/255)
    static let b = Color(red: 255/255, green: 134/255, blue: 92/255)
    static let auto = Color(red: 167/255, green: 134/255, blue: 248/255)
    static let warning = Color(red: 255/255, green: 203/255, blue: 85/255)
    static let spectrum: [Color] = [
        Color(red: 1, green: 0.29, blue: 0.27),
        Color(red: 1, green: 0.59, blue: 0.14),
        Color(red: 1, green: 0.84, blue: 0.22),
        Color(red: 0.91, green: 0.32, blue: 0.71),
        Color(red: 0.38, green: 0.92, blue: 0.84)
    ]
}

private enum ConsoleMode: String, CaseIterable, Identifiable {
    case wave = "WAVE"
    case mix = "MIX"
    case stems = "STEMS"
    case builder = "BUILDER"
    case fx = "FX"
    case auto = "AUTO"
    var id: String { rawValue }
}

struct ConsoleView: View {
    @EnvironmentObject private var audio: AudioController
    @State private var mode: ConsoleMode = .wave
    @State private var selectedDeck = 0
    @State private var hotCuePage = 0
    @State private var showingImporter = false
    @State private var importingInto = 0
    @State private var waveformZoom: Double = 1
    @State private var editingGridDeck = 0
    @State private var showingGridEditor = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Spectral.rule).frame(height: 1)
            Group {
                switch mode {
                case .wave: waveScreen
                case .mix: mixerScreen
                case .stems: stemsScreen
                case .builder: builderScreen
                case .fx: fxScreen
                case .auto: autoScreen
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            Rectangle().fill(Spectral.rule).frame(height: 1)
            controlRail
        }
        .background(Spectral.bg.ignoresSafeArea())
        .foregroundStyle(Spectral.ink)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingGridEditor) {
            BeatGridEditorSheet(deck: editingGridDeck)
                .environmentObject(audio)
                .presentationDetents([.medium, .large])
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.audio],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { audio.importAudioFile(url, into: importingInto) }
            case .failure(let error):
                audio.reportImportFailure(error) // Previous track remains loaded.
            }
        }
        .onReceive(Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()) { _ in
            if audio.playing { audio.refreshRealtimeStatus() }
        }
    }

    private func accent(_ deck: Int) -> Color { deck == 0 ? Spectral.a : Spectral.b }
    private func deckName(_ deck: Int) -> String { deck == 0 ? "A" : "B" }
    private func load(_ deck: Int) { importingInto = deck; showingImporter = true }

    private var header: some View {
        VStack(spacing: 9) {
            HStack(alignment: .center) {
                HStack(spacing: 7) {
                    Image(systemName: "waveform.path")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(Spectral.auto)
                    Text("TRACKBUILDER")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                    Text("/ MIXAUTO PRO")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Spectral.muted)
                }
                Spacer(minLength: 0)
                Button { mode = .auto } label: {
                    Text("AUTO")
                        .foregroundStyle(Spectral.auto)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Spectral.raised, in: Capsule())
                }
                .accessibilityLabel("Open Pattern AutoMix")
            }
            HStack(spacing: 10) {
                headerDeck(0)
                Rectangle().fill(Spectral.rule).frame(width: 1)
                headerDeck(1)
            }
            .frame(height: 67)
        }
        .padding(.horizontal, 13)
        .padding(.top, 9)
        .padding(.bottom, 10)
        .background(Spectral.panel)
    }

    private func headerDeck(_ deck: Int) -> some View {
        let meta = audio.fileDecks[deck]
        return Button { load(deck) } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [Spectral.raised, accent(deck).opacity(0.55),
                                                  Spectral.raised], startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                    .frame(width: 47, height: 52)
                    .overlay {
                        Text(deckName(deck))
                            .font(.system(size: 17, weight: .black, design: .rounded))
                    }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 3) {
                        Circle().fill(accent(deck)).frame(width: 5, height: 5)
                        Text("DECK \(deckName(deck))")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .foregroundStyle(accent(deck))
                    }
                    Text(meta?.title ?? (deck == 0 ? "Night Circuit" : "Retro Coast"))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(audio.importingDeck == deck ? "IMPORTING..." :
                        meta == nil ? "BANK \(TrackProject.bankNames[audio.project.bank[deck]]) · SYNTH" :
                        "FILE · \(timeString(meta!.duration))")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Spectral.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Load audio file") { load(deck) }
            if meta != nil {
                Button("Switch to original pattern") { audio.usePatternDeck(deck) }
            }
        }
        .accessibilityLabel("Load audio to Deck \(deckName(deck))")
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "--:--" }
        let t = Int(seconds)
        return String(format: "%02d:%02d", t / 60, t % 60)
    }

    private var waveScreen: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { deck in
                    HStack(spacing: 6) {
                        Text(deckName(deck))
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundStyle(accent(deck))
                        MiniWaveform(peaks: audio.waveforms[deck].peaks, color: accent(deck))
                            .frame(height: 22)
                        Text(audio.fileDecks[deck] == nil ? "BAR 1–4" : "FULL")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(Spectral.muted)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            HStack(spacing: 1) {
                ForEach(0..<2, id: \.self) { deck in
                    TimelineView(.periodic(from: .now, by: 0.0167)) { _ in
                        VerticalWaveform(waveform: audio.waveforms[deck],
                            progress: audio.deckProgress(deck),
                            isActive: audio.deckPlaying[deck],
                            accent: accent(deck), deck: deck,
                            isFile: audio.fileDecks[deck] != nil,
                            beatGrid: audio.fileDecks[deck]?.beatGrid,
                            hotCues: audio.fileDecks[deck]?.hotCues,
                            duration: audio.fileDecks[deck]?.duration,
                            zoom: waveformZoom)
                    }
                }
            }
            .background(Spectral.bg)
            fileCueStrip
            HStack {
                Text("PCM SIGNAL OVERVIEW · \(audio.fileDecks.contains(where: { $0 != nil }) ? "IMPORTED AUDIO" : "ORIGINAL PATTERNS")")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Spectral.muted)
                Spacer()
                if audio.fileDecks.contains(where: { $0 != nil }) {
                    Menu {
                        ForEach(0..<2, id: \.self) { deck in
                            if audio.fileDecks[deck] != nil {
                                Button("Adjust beat timing · Deck \(deckName(deck))") {
                                    editingGridDeck = deck
                                    showingGridEditor = true
                                }
                            }
                        }
                    } label: {
                        Text("GRID")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .frame(minWidth: 46, minHeight: 44)
                    }
                }
                if audio.fileDecks.contains(where: { $0 != nil }) {
                    Menu {
                        ForEach(0..<2, id: \.self) { deck in
                            if audio.fileDecks[deck] != nil {
                                Section("DECK \(deckName(deck)) · PCM LOOP") {
                                    if audio.loopingDeck[deck] {
                                        Button("EXIT LOOP · Deck \(deckName(deck))") {
                                            audio.exitFileLoop(deck)
                                        }
                                    }
                                    ForEach([4, 8, 16], id: \.self) { beats in
                                        Button("LOOP \(beats) BEATS · Deck \(deckName(deck))") {
                                            audio.activateFileLoop(deck, beats: beats)
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        Text(audio.loopingDeck.contains(true) ? "LOOP ON" : "LOOP")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundStyle(audio.loopingDeck.contains(true) ? Spectral.auto : Spectral.ink)
                            .frame(minWidth: 50, minHeight: 44)
                    }
                    .accessibilityLabel("File deck loop menu")
                }
                Button { waveformZoom = max(1, waveformZoom / 1.5) } label: {
                    Image(systemName: "minus.magnifyingglass")
                        .frame(width: 44, height: 35)
                }
                Button { waveformZoom = min(4, waveformZoom * 1.5) } label: {
                    Image(systemName: "plus.magnifyingglass")
                        .frame(width: 44, height: 35)
                }
            }
            .padding(.horizontal, 13)
            .background(Spectral.panel)
        }
    }

    /// Hot cues are only enabled for file decks. A tap jumps to a stored
    /// position; long-press exposes deliberate set/clear actions. There is
    /// no hidden time jump on a casual drag over a waveform.
    private var fileCueStrip: some View {
        Group {
            if audio.fileDecks.contains(where: { $0 != nil }) {
                HStack(spacing: 6) {
                    Menu {
                        Button("DECK A") { selectedDeck = 0 }
                        Button("DECK B") { selectedDeck = 1 }
                        Divider()
                        Button("HOT CUES 1–4") { hotCuePage = 0 }
                        Button("HOT CUES 5–8") { hotCuePage = 1 }
                    } label: {
                        Text("CUES · \(selectedDeck == 0 ? "A" : "B") \(hotCuePage == 0 ? "1–4" : "5–8")")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(accent(selectedDeck))
                            .frame(minWidth: 87, minHeight: 44)
                    }
                    .accessibilityLabel("Deck Hot Cues Menu")
                    ForEach(0..<4, id: \.self) { visibleSlot in
                        let slot = hotCuePage * 4 + visibleSlot
                        let present = audio.fileDecks[selectedDeck]?.hotCues?[slot] != nil
                        Button {
                            // One-touch performance: stored cue jumps; empty slot
                            // stores the current location. Long press edits/clears.
                            if present { audio.jumpHotCue(selectedDeck, slot: slot) }
                            else { audio.storeHotCue(selectedDeck, slot: slot) }
                        } label: {
                            Text("\(slot + 1)")
                                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                                .frame(maxWidth: .infinity).frame(minHeight: 48)
                                .background(present ? accent(selectedDeck).opacity(0.30) : Spectral.raised,
                                            in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8)
                                    .stroke(present ? accent(selectedDeck) : Spectral.rule, lineWidth: 1))
                        }
                        .contextMenu {
                            Button("Set Hot Cue \(slot + 1) at current position") {
                                audio.storeHotCue(selectedDeck, slot: slot)
                            }
                            if present {
                                Button("Clear Hot Cue \(slot + 1)", role: .destructive) {
                                    audio.clearHotCue(selectedDeck, slot: slot)
                                }
                            }
                        }
                        .disabled(audio.fileDecks[selectedDeck] == nil)
                        .accessibilityLabel("Deck \(deckName(selectedDeck)) hot cue \(slot + 1): \(present ? "jump" : "set")")
                    }
                }
                .padding(.horizontal, 10)
                .background(Spectral.panel)
            }
        }
    }

    private var controlRail: some View {
        VStack(spacing: 9) {
            HStack(spacing: 3) {
                ForEach(ConsoleMode.allCases.filter { $0 != .auto }) { tab in
                    Button { mode = tab } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .frame(maxWidth: .infinity).frame(height: 39)
                            .foregroundStyle(mode == tab ? Spectral.ink : Spectral.muted)
                            .background(mode == tab ? Spectral.raised : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 11))
                    }
                    .accessibilityAddTraits(mode == tab ? .isSelected : [])
                }
            }
            HStack(alignment: .firstTextBaseline) {
                bpmLabel(0)
                Spacer()
                Text("CROSSFADE")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Spectral.muted)
                Spacer()
                bpmLabel(1)
            }
            HStack(spacing: 8) {
                buttonPill("SYNC", deck: 0, enabled: false) { }
                buttonPill("CUE", deck: 0, enabled: audio.fileDecks[0] != nil) { audio.cueDeck(0) }
                Button { mode = .auto } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left.arrow.right")
                        Text("AUTO")
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Spectral.auto)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(Spectral.raised, in: RoundedRectangle(cornerRadius: 10))
                }
                buttonPill("CUE", deck: 1, enabled: audio.fileDecks[1] != nil) { audio.cueDeck(1) }
                buttonPill("SYNC", deck: 1, enabled: false) { }
            }
            HStack(spacing: 11) {
                playDeckButton(0)
                HStack(spacing: 4) {
                    Text("A").foregroundStyle(Spectral.a)
                    Slider(value: Binding(get: { audio.liveCrossfader },
                        set: { audio.setCrossfader($0) }), in: 0...1)
                        .tint(Spectral.ink)
                        .accessibilityLabel("Crossfader: A to B")
                    Text("B").foregroundStyle(Spectral.b)
                }
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .frame(maxWidth: .infinity)
                playDeckButton(1)
            }
            if let error = audio.errorMessage {
                Text(error)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Spectral.warning)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 13)
        .padding(.top, 9)
        .padding(.bottom, 8)
        .background(Spectral.panel)
    }

    private func bpmLabel(_ deck: Int) -> some View {
        VStack(alignment: deck == 0 ? .leading : .trailing, spacing: 2) {
            Text(audio.fileDecks[deck] == nil ? String(format: "%.1f", audio.bpm) :
                 audio.fileDecks[deck]?.tempo.map { String(format: "~%.1f", $0.bpm) } ?? "—")
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .monospacedDigit()
            Text(audio.fileDecks[deck] == nil ? "BPM · PATTERN" :
                 audio.analyzingTempo[deck] ? "BPM · ANALYZING" :
                 audio.fileDecks[deck]?.manuallyAdjustedGrid == true ? "BPM · MANUAL" :
                 audio.fileDecks[deck]?.tempo != nil ? "BPM · ESTIMATE" : "BPM · UNKNOWN")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Spectral.muted)
        }
    }

    private func buttonPill(_ text: String, deck: Int, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(enabled ? accent(deck) : Spectral.muted.opacity(0.5))
                .frame(maxWidth: .infinity).frame(height: 44)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(
                    enabled ? accent(deck).opacity(0.68) : Spectral.rule, lineWidth: 1))
        }
        .disabled(!enabled)
        .accessibilityLabel("Deck \(deckName(deck)) \(text)")
        .accessibilityHint(enabled ? "" : "Pattern decks share a clock; imported track BPM Sync is not implemented yet")
    }

    private func playDeckButton(_ deck: Int) -> some View {
        Button { audio.toggleDeckPlayback(deck) } label: {
            Image(systemName: audio.deckPlaying[deck] ? "pause.fill" : "play.fill")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Spectral.ink)
                .frame(width: 62, height: 58)
                .background(Spectral.raised, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(
                    audio.deckPlaying[deck] ? accent(deck) : Spectral.rule, lineWidth: 1.5))
        }
        .accessibilityLabel("\(audio.deckPlaying[deck] ? "Pause" : "Play") Deck \(deckName(deck))")
    }

    private var mixerScreen: some View {
        ScrollView {
            VStack(spacing: 12) {
                titleRow("MIX / THREE-BAND EQ", "A + B")
                HStack(alignment: .top, spacing: 10) {
                    ForEach(0..<2, id: \.self) { deck in
                        VStack(spacing: 13) {
                            Text("DECK \(deckName(deck))")
                                .font(.system(size: 14, weight: .heavy, design: .monospaced))
                                .foregroundStyle(accent(deck))
                            controlSlider(deck: deck, title: "FILTER", value: Binding(
                                get: { audio.project.deckFilter[deck] },
                                set: { audio.setDeckFilter(deck: deck, $0) }), range: 0...1)
                            controlSlider(deck: deck, title: "HIGH", value: eqBinding(deck, 2), range: -12...12)
                            controlSlider(deck: deck, title: "MID", value: eqBinding(deck, 1), range: -12...12)
                            controlSlider(deck: deck, title: "LOW", value: eqBinding(deck, 0), range: -12...12)
                            controlSlider(deck: deck, title: "GAIN", value: Binding(
                                get: { audio.project.deckGain[deck] },
                                set: { audio.setDeckGain(deck: deck, $0) }), range: 0...1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(Spectral.raised, in: RoundedRectangle(cornerRadius: 13))
                    }
                }
                HStack {
                    Text("MASTER")
                    Slider(value: Binding(get: { audio.gain },
                                          set: { audio.setGain($0) }), in: 0...1)
                        .tint(Spectral.auto)
                }
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                Text("REAL EQ · SYNTH C++ DSP + FILE AUDIO UNIT EQ")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Spectral.muted)
            }
            .padding(13)
        }
        .scrollIndicators(.hidden)
    }

    private func eqBinding(_ deck: Int, _ band: Int) -> Binding<Double> {
        Binding(get: { audio.project.deckEQ[deck][band] },
                set: { audio.setDeckEQ(deck: deck, band: band, value: $0) })
    }

    private func controlSlider(deck: Int, title: String, value: Binding<Double>,
                               range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).foregroundStyle(Spectral.muted)
                Spacer()
                Text(String(format: "%+.1f", value.wrappedValue))
                    .foregroundStyle(accent(deck))
            }
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            Slider(value: value, in: range)
                .tint(accent(deck))
                .accessibilityLabel("Deck \(deckName(deck)) \(title)")
        }
    }

    private var builderScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                titleRow("BUILDER / SEQUENCER", "16 STEPS")
                pickerForDeck
                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { bank in
                        Button { audio.selectBank(deck: selectedDeck, bank: bank) } label: {
                            Text("BANK \(TrackProject.bankNames[bank])")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .frame(maxWidth: .infinity).frame(height: 44)
                                .foregroundStyle(audio.project.bank[selectedDeck] == bank ? Spectral.bg : Spectral.ink)
                                .background(audio.project.bank[selectedDeck] == bank ? accent(selectedDeck) : Spectral.raised,
                                            in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }
                if audio.playing && audio.activeBank(deck: selectedDeck) != audio.project.bank[selectedDeck] {
                    Text("BANK CHANGE SCHEDULED · NEXT BAR")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Spectral.warning)
                }
                Text("SCROLL EACH ROW · TAP TO TOGGLE · HOLD FOR VELOCITY")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Spectral.muted)
                ForEach(0..<3, id: \.self) { voice in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(TrackProject.voiceNames[voice])
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                            Spacer()
                            Text("STEP 01–16")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(Spectral.muted)
                        }
                        ScrollView(.horizontal) {
                            HStack(spacing: 4) {
                                ForEach(0..<16, id: \.self) { step in
                                    let velocity = audio.stepVelocity(
                                        deck: selectedDeck, bank: audio.project.bank[selectedDeck],
                                        voice: voice, step: step)
                                    Button {
                                        audio.toggleStep(deck: selectedDeck,
                                                         bank: audio.project.bank[selectedDeck],
                                                         voice: voice, step: step)
                                    } label: {
                                        VStack(spacing: 2) {
                                            Text("\(step + 1)")
                                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                            Text(velocity == 0 ? "·" : "\(velocity)")
                                                .font(.system(size: 9, design: .monospaced))
                                        }
                                        .frame(width: 45, height: 48)
                                        .foregroundStyle(velocity > 0 ? Spectral.bg : Spectral.ink)
                                        .background(velocity > 0 ? accent(selectedDeck) : Spectral.raised,
                                                    in: RoundedRectangle(cornerRadius: 8))
                                    }
                                    .contextMenu {
                                        ForEach([0, 40, 70, 90, 110, 127], id: \.self) { v in
                                            Button(v == 0 ? "Mute step" : "Velocity \(v)") {
                                                audio.setVelocity(deck: selectedDeck,
                                                    bank: audio.project.bank[selectedDeck],
                                                    voice: voice, step: step, value: v)
                                            }
                                        }
                                    }
                                    .accessibilityLabel("\(TrackProject.voiceNames[voice]) step \(step + 1)")
                                    .accessibilityValue(velocity == 0 ? "Off" : "Velocity \(velocity)")
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                    .padding(9)
                    .background(Spectral.panel, in: RoundedRectangle(cornerRadius: 10))
                }
                HStack(spacing: 8) {
                    Text("BPM \(Int(audio.bpm))")
                    Slider(value: Binding(get: { audio.bpm },
                                          set: { audio.setBPM($0) }), in: 60...200, step: 1)
                        .tint(Spectral.auto)
                }
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                HStack(spacing: 8) {
                    Text("SWING \(Int(audio.swing * 100))%")
                    Slider(value: Binding(get: { audio.swing },
                                          set: { audio.setSwing($0) }), in: 0...0.75)
                        .tint(Spectral.auto)
                }
                .font(.system(size: 11, weight: .bold, design: .monospaced))
            }
            .padding(13)
        }
        .scrollIndicators(.hidden)
    }

    private var pickerForDeck: some View {
        Picker("TARGET DECK", selection: $selectedDeck) {
            Text("DECK A").tag(0)
            Text("DECK B").tag(1)
        }
        .pickerStyle(.segmented)
    }

    private var fxScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                titleRow("FX / LIVE PERFORMANCE", "SYNTH")
                pickerForDeck
                Text("TRIGGER ORIGINAL SYNTH VOICES")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Spectral.muted)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(0..<3, id: \.self) { voice in
                        Button { audio.triggerPad(deck: selectedDeck, voice: voice) } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                Image(systemName: voice == 0 ? "waveform.path" : "circle.hexagongrid.fill")
                                Spacer()
                                Text(["KICK", "HAT", "BASS"][voice])
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 104)
                            .padding(12)
                            .foregroundStyle(Spectral.ink)
                            .background(Spectral.raised, in: RoundedRectangle(cornerRadius: 13))
                            .overlay(RoundedRectangle(cornerRadius: 13)
                                .stroke(accent(selectedDeck).opacity(0.75), lineWidth: 1))
                        }
                        .accessibilityLabel("Trigger \(["Kick", "Hat", "Bass"][voice]) on deck \(deckName(selectedDeck))")
                    }
                }
                titleRow("ECHO / 375MS DELAY", "LIVE · A/B")
                HStack {
                    Text(String(format: "WET %.0f%%", audio.project.deckDelay[selectedDeck] * 100))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                    Slider(value: Binding(get: { audio.project.deckDelay[selectedDeck] },
                                          set: { audio.setDeckDelay(deck: selectedDeck, value: $0) }),
                           in: 0...0.5)
                        .tint(accent(selectedDeck))
                        .accessibilityLabel("Deck \(deckName(selectedDeck)) echo wet level")
                }
                Text("GATE / PHASER / RISER — PLANNED; NOT ACTIVE IN THIS BUILD")
                    .foregroundStyle(Spectral.warning)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
                titleRow("FILTER", "LIVE")
                Slider(value: Binding(get: { audio.project.deckFilter[selectedDeck] },
                                      set: { audio.setDeckFilter(deck: selectedDeck, $0) }),
                       in: 0...1)
                    .tint(accent(selectedDeck))
            }
            .padding(13)
        }
        .scrollIndicators(.hidden)
    }

    /// Actual mute/solo for original synthesized Kick/Hat/Bass only.
    /// Never imply that a loaded song has been separated into stems.
    private var stemsScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                titleRow("STEMS / ORIGINAL PATTERNS", "REAL CONTROL")
                pickerForDeck
                if audio.fileDecks[selectedDeck] != nil {
                    Image(systemName: "waveform.slash")
                        .font(.system(size: 38, weight: .ultraLight))
                        .foregroundStyle(Spectral.warning)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 24)
                    Text("IMPORTED AUDIO · STEMS UNAVAILABLE")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(Spectral.warning)
                    Text("This track is not separated into drums, bass, vocals or music. Switch this deck to an original pattern to use real Kick, Hat and Bass mute/solo controls.")
                        .font(.system(size: 13))
                        .foregroundStyle(Spectral.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { audio.usePatternDeck(selectedDeck) } label: {
                        Label("USE ORIGINAL PATTERN", systemImage: "waveform.path")
                            .font(.system(size: 12, weight: .heavy, design: .monospaced))
                            .frame(maxWidth: .infinity).frame(minHeight: 54)
                            .background(Spectral.raised, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .accessibilityLabel("Switch deck \(deckName(selectedDeck)) to original pattern")
                } else {
                    Text("CONTROL ORIGINAL SYNTH VOICES · NOT FILE SOURCE SEPARATION")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Spectral.muted)
                    ForEach(0..<3, id: \.self) { voice in
                        let muted = audio.project.patternMute[selectedDeck][voice]
                        let solo = audio.project.patternSolo[selectedDeck][voice]
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(voice == 0 ? Spectral.warning : voice == 1 ? Spectral.a : Spectral.b)
                                .frame(width: 4, height: 42)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(TrackProject.voiceNames[voice])
                                    .font(.system(size: 14, weight: .heavy, design: .monospaced))
                                Text(solo ? "SOLO ENABLED" : muted ? "MUTED" : "VOICE ACTIVE")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(Spectral.muted)
                            }
                            Spacer(minLength: 4)
                            Button { audio.togglePatternMute(deck: selectedDeck, voice: voice) } label: {
                                Text(muted ? "UNMUTE" : "MUTE")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .frame(minWidth: 58, minHeight: 48)
                                    .background(muted ? Spectral.warning.opacity(0.25) : Spectral.raised,
                                                in: RoundedRectangle(cornerRadius: 10))
                            }
                            .accessibilityLabel("\(muted ? "Unmute" : "Mute") \(TrackProject.voiceNames[voice]) on deck \(deckName(selectedDeck))")
                            Button { audio.togglePatternSolo(deck: selectedDeck, voice: voice) } label: {
                                Text(solo ? "UNSOLO" : "SOLO")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .frame(minWidth: 58, minHeight: 48)
                                    .background(solo ? accent(selectedDeck).opacity(0.32) : Spectral.raised,
                                                in: RoundedRectangle(cornerRadius: 10))
                            }
                            .accessibilityLabel("\(solo ? "Disable solo for" : "Solo") \(TrackProject.voiceNames[voice]) on deck \(deckName(selectedDeck))")
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 8)
                        .background(Spectral.panel, in: RoundedRectangle(cornerRadius: 12))
                    }
                    Text("SOLO TAKES PRIORITY OVER MUTE. ALL CHANGES ARE AUDIBLE AND SAVED.")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Spectral.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { mode = .builder } label: {
                        Label("OPEN PATTERN BUILDER", systemImage: "circle.grid.3x3.fill")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .frame(maxWidth: .infinity).frame(minHeight: 54)
                            .background(Spectral.raised, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
    }

    private var autoScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                titleRow("MIXAUTO / PHRASE PLAN", "PATTERN ONLY")
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DECK A")
                            .foregroundStyle(Spectral.a)
                        Text(audio.fileDecks[0]?.title ?? "Night Circuit")
                    }
                    Spacer()
                    Image(systemName: "arrow.left.arrow.right").foregroundStyle(Spectral.auto)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("DECK B").foregroundStyle(Spectral.b)
                        Text(audio.fileDecks[1]?.title ?? "Retro Coast")
                    }
                }
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                HStack {
                    Text("STATUS")
                        .foregroundStyle(Spectral.muted)
                    Spacer()
                    Text(audio.autoMixState == 1 ? "ARMED · NEXT BAR" :
                         audio.autoMixState == 2 ? "MIXING · 2 BARS" : "READY")
                        .foregroundStyle(Spectral.auto)
                }
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .padding(14)
                .background(Spectral.raised, in: RoundedRectangle(cornerRadius: 12))
                HStack(spacing: 7) {
                    ForEach(0..<16, id: \.self) { bar in
                        Capsule().fill(bar <= audio.activeStep() ? Spectral.auto : Spectral.rule)
                            .frame(height: 13)
                    }
                }
                HStack(spacing: 8) {
                    Button { audio.schedulePatternAutoMix(targetDeck: 0) } label: {
                        Text("MIX → A")
                            .frame(maxWidth: .infinity).frame(height: 54)
                            .background(Spectral.a, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(Spectral.bg)
                    }
                    Button { audio.schedulePatternAutoMix(targetDeck: 1) } label: {
                        Text("MIX → B")
                            .frame(maxWidth: .infinity).frame(height: 54)
                            .background(Spectral.b, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(Spectral.bg)
                    }
                }
                .font(.system(size: 13, weight: .black, design: .monospaced))
                Button { audio.cancelAutoMix() } label: {
                    Label("MANUAL TAKEOVER", systemImage: "hand.raised.fill")
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .frame(maxWidth: .infinity).frame(height: 54)
                        .background(Spectral.raised, in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(audio.autoMixState == 0)
                if audio.fileDecks[0] != nil && audio.fileDecks[1] != nil {
                    Rectangle().fill(Spectral.rule).frame(height: 1)
                    titleRow("TIMED FILE BLEND", "NOT BPM SYNC")
                    HStack(spacing: 8) {
                        Button { audio.beginTimedFileBlend(targetDeck: 0) } label: {
                            Text("BLEND → A")
                                .frame(maxWidth: .infinity).frame(height: 48)
                                .background(Spectral.a.opacity(0.3), in: RoundedRectangle(cornerRadius: 11))
                        }
                        Button { audio.beginTimedFileBlend(targetDeck: 1) } label: {
                            Text("BLEND → B")
                                .frame(maxWidth: .infinity).frame(height: 48)
                                .background(Spectral.b.opacity(0.3), in: RoundedRectangle(cornerRadius: 11))
                        }
                    }
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    if audio.timedBlendActive {
                        ProgressView(value: audio.timedBlendProgress)
                            .tint(Spectral.auto)
                        Button("TAKE OVER · MANUAL") { audio.cancelTimedBlend() }
                            .font(.system(size: 12, weight: .heavy, design: .monospaced))
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(Spectral.raised, in: RoundedRectangle(cornerRadius: 12))
                    }
                    if audio.fileDecks[0]?.beatGrid != nil && audio.fileDecks[1]?.beatGrid != nil {
                        HStack(spacing: 8) {
                            Button { audio.beginBeatHintBlend(targetDeck: 0) } label: {
                                Text("BEAT HINT → A")
                                    .frame(maxWidth: .infinity).frame(height: 48)
                                    .background(Spectral.a.opacity(0.17),
                                                in: RoundedRectangle(cornerRadius: 10))
                            }
                            Button { audio.beginBeatHintBlend(targetDeck: 1) } label: {
                                Text("BEAT HINT → B")
                                    .frame(maxWidth: .infinity).frame(height: 48)
                                    .background(Spectral.b.opacity(0.17),
                                                in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        if audio.beatHintArmed {
                            HStack {
                                Text(String(format: "BEAT-HINT START IN ~%.2f s", audio.beatHintCountdown))
                                    .foregroundStyle(Spectral.auto)
                                Spacer()
                                Button("CANCEL") { audio.cancelBeatHintBlend() }
                                    .foregroundStyle(Spectral.warning)
                            }
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .frame(minHeight: 48)
                        }
                    }
                    Text(audio.fileTempoCompatibility.text)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Spectral.warning)
                    Text("Timed blend is unwarped. Beat-hint option uses approximate beat-phase start only when both grids are credible, tempo drift is small, and one deck is cued; not phrase sync or time stretching.")
                        .font(.system(size: 10))
                        .foregroundStyle(Spectral.muted)
                }
                Text("MixAuto presently transitions between generated patterns on their shared sequencer clock. Imported audio BPM / beatgrid / phrase matching is NOT implemented.")
                    .foregroundStyle(Spectral.muted)
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
                Rectangle().fill(Spectral.rule).frame(height: 1)
                titleRow("LIVE MASTER RECORD", "REAL MIXER OUTPUT")
                Button { audio.toggleLiveRecording() } label: {
                    Label(audio.isRecordingLive ? "STOP & SAVE LIVE MIX" :
                          audio.savingLiveRecording ? "SAVING RECORDING ..." : "RECORD LIVE MASTER",
                          systemImage: audio.isRecordingLive ? "stop.circle.fill" :
                            "record.circle")
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .frame(maxWidth: .infinity).frame(height: 56)
                        .background(audio.isRecordingLive ? Color.red.opacity(0.85) : Spectral.raised,
                                    in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(audio.savingLiveRecording || (!audio.playing && !audio.isRecordingLive))
                if let record = audio.liveRecordingResult {
                    ShareLink(item: record.fileURL) {
                        Label(String(format: "SHARE LIVE WAV · %.1f SEC", record.durationSeconds),
                              systemImage: "square.and.arrow.up")
                    }
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    if record.droppedFrames > 0 {
                        Text("WARNING · DROPPED \(record.droppedFrames) PCM FRAMES")
                            .foregroundStyle(Spectral.warning)
                    }
                }
                Text("Records actual A+B master audio, including imported files. Audio export depends on device format; requires hardware QA.")
                    .font(.system(size: 10))
                    .foregroundStyle(Spectral.muted)
                Rectangle().fill(Spectral.rule).frame(height: 1)
                titleRow("OFFLINE EXPORT", "48kHz WAV")
                Button { audio.exportPatternMix() } label: {
                    Label(audio.isExporting ? "RENDERING ..." : "EXPORT 16s PATTERN MIX",
                          systemImage: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(Spectral.auto, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(Spectral.bg)
                }
                .disabled(audio.isExporting)
                if let url = audio.exportedURL {
                    ShareLink(item: url) { Label("SHARE WAV", systemImage: "square.and.arrow.up") }
                        .font(.system(size: 12, weight: .semibold))
                }
                Text("Export renders original patterns offline; it is not a live mix recording.")
                    .font(.system(size: 10))
                    .foregroundStyle(Spectral.muted)
            }
            .padding(13)
        }
        .scrollIndicators(.hidden)
    }

    private func titleRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .foregroundStyle(Spectral.ink)
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Spectral.muted)
        }
    }
}

/// Overview visualizes actual measured peak amplitudes, NOT a guessed beatgrid.
private struct MiniWaveform: View {
    let peaks: [Float]
    let color: Color
    var body: some View {
        Canvas { context, size in
            guard !peaks.isEmpty else { return }
            let bins = min(100, peaks.count)
            let w = size.width / CGFloat(bins)
            var bars = Path()
            for i in 0..<bins {
                let p = peaks[min(peaks.count - 1, i * peaks.count / bins)]
                let half = CGFloat(max(0.07, p)) * size.height * 0.46
                let x = CGFloat(i) * w + w * 0.5
                bars.move(to: CGPoint(x: x, y: size.height / 2 - half))
                bars.addLine(to: CGPoint(x: x, y: size.height / 2 + half))
            }
            context.stroke(bars, with: .color(color), lineWidth: max(0.8, w * 0.55))
        }
        .accessibilityLabel("Audio waveform overview")
    }
}

/// Scrolls measured PCM waveform beneath a stationary playhead. Five color
/// bands use signal-derived crossover energy, not a fabricated spectrogram
/// and not isolated instrumental stems.
private struct VerticalWaveform: View {
    let waveform: SpectralWaveform
    let progress: Double
    let isActive: Bool
    let accent: Color
    let deck: Int
    let isFile: Bool
    let beatGrid: BeatGridEstimate?
    let hotCues: [Double?]?
    let duration: Double?
    let zoom: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Spectral.bg
                Canvas { context, size in
                    let n = waveform.peaks.count
                    guard n > 0 else { return }
                    let span = (isFile ? 0.14 : 0.30) / max(1, zoom)
                    let lines = min(230, max(80, Int(size.height / 2.1)))
                    let stepHeight = size.height / CGFloat(lines)
                    var groups = [Path](repeating: Path(), count: Spectral.spectrum.count)
                    for i in 0..<lines {
                        // Actual PCM peak determines width; measured relative
                        // frequency-band energy determines *where* each color
                        // appears. No decorative amplitude-index color mapping.
                        let relative = (Double(i) / Double(lines) - 0.5) * span
                        let location = progress + relative
                        let wrapped = isFile ? min(0.999, max(0, location)) :
                            (location - floor(location))
                        let bin = min(n - 1, max(0, Int(wrapped * Double(n))))
                        let peak = waveform.peaks[bin]
                        let half = max(1.1, CGFloat(peak) * size.width * 0.46)
                        let y = (CGFloat(i) + 0.5) * stepHeight
                        let base = bin * Spectral.spectrum.count
                        guard base + Spectral.spectrum.count <= waveform.bands.count else { continue }
                        let magnitudes = (0..<Spectral.spectrum.count).map {
                            max(0, CGFloat(waveform.bands[base + $0]))
                        }
                        let sum = magnitudes.reduce(CGFloat.zero, +)
                        if sum <= 0.0001 { continue }
                        var accumulated = CGFloat.zero
                        for band in 0..<Spectral.spectrum.count {
                            let part = half * magnitudes[band] / sum
                            let inner = accumulated
                            let outer = accumulated + part
                            groups[band].move(to: CGPoint(x: size.width / 2 - outer, y: y))
                            groups[band].addLine(to: CGPoint(x: size.width / 2 - inner, y: y))
                            groups[band].move(to: CGPoint(x: size.width / 2 + inner, y: y))
                            groups[band].addLine(to: CGPoint(x: size.width / 2 + outer, y: y))
                            accumulated = outer
                        }
                    }
                    for (index, path) in groups.enumerated() {
                        context.stroke(path, with: .color(Spectral.spectrum[index]),
                                       lineWidth: max(1.0, stepHeight * 0.72))
                    }
                    // No imaginary bar lines for loaded files. If the
                    // accepted approximate beat phase is available, place
                    // hints at actual decoded sample-time positions only.
                    if let beatGrid, let duration, beatGrid.isValid, duration > 0 {
                        let start = max(0, (progress - span * 0.5) * duration)
                        let end = min(duration, (progress + span * 0.5) * duration)
                        let period = beatGrid.beatIntervalSeconds
                        let first = max(0, Int(ceil((start - beatGrid.firstBeatSeconds) / period)))
                        let count = min(250, max(0, Int(ceil((end - start) / period)) + 2))
                        // Keep the grid readable even at wide zoom levels.
                        let skip = max(1, Int(ceil(14 * Double(count) / max(1, Double(size.height)))))
                        var marks = Path()
                        for index in Swift.stride(from: 0, to: count, by: skip) {
                            let t = beatGrid.beatTime(first + index)
                            guard t >= start, t <= end else { continue }
                            let y = CGFloat(0.5 + (t / duration - progress) / span) * size.height
                            marks.move(to: CGPoint(x: 0, y: y))
                            marks.addLine(to: CGPoint(x: size.width, y: y))
                        }
                        context.stroke(marks, with: .color(Spectral.ink.opacity(0.22)), lineWidth: 0.8)
                    }
                    if let hotCues, let duration, duration > 0 {
                        var cueLines = Path()
                        for (slot, moment) in hotCues.enumerated() {
                            guard let moment, moment.isFinite else { continue }
                            let location = moment / duration
                            let local = 0.5 + (location - progress) / span
                            guard (0...1).contains(local) else { continue }
                            let y = CGFloat(local) * size.height
                            cueLines.move(to: CGPoint(x: 0, y: y))
                            cueLines.addLine(to: CGPoint(x: size.width, y: y))
                            context.draw(Text("C\(slot + 1)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(accent),
                                at: CGPoint(x: 20, y: max(10, min(size.height - 10, y - 10))))
                        }
                        context.stroke(cueLines, with: .color(accent.opacity(0.85)), lineWidth: 1.5)
                    }
                }
                // White bar marker and high-contrast red transport line.
                Rectangle()
                    .fill(Color(red: 1, green: 0.21, blue: 0.19))
                    .frame(height: 2)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                VStack {
                    HStack {
                        Text(deck == 0 ? "A" : "B")
                            .font(.system(size: 14, weight: .heavy, design: .monospaced))
                            .foregroundStyle(accent)
                        Spacer()
                        Image(systemName: isActive ? "waveform" : "pause.fill")
                            .foregroundStyle(isActive ? accent : Spectral.muted)
                    }
                    Spacer()
                    Text(isFile ? (beatGrid == nil ? "FILE · GRID UNAVAILABLE" :
                          beatGrid!.confidence == 0 ? "BEAT GRID · MANUAL" : "BEAT GRID · APPROX") : "PATTERN / FOUR BARS")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Spectral.muted)
                }
                .padding(11)
            }
            .overlay(Rectangle().stroke(Spectral.rule, lineWidth: 0.5))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Deck \(deck == 0 ? "A" : "B") waveform")
        .accessibilityValue("Position \(Int(progress * 100)) percent")
    }
}

/// Metadata-only correction sheet. It never modifies running playback,
/// so the approved two-deck transport remains stable while editing a grid.
private struct BeatGridEditorSheet: View {
    @EnvironmentObject private var audio: AudioController
    @Environment(\.dismiss) private var dismiss
    let deck: Int
    @State private var bpm: Double = 128
    @State private var phase: Double = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Deck \(deck == 0 ? "A" : "B") · MANUAL GRID") {
                    HStack {
                        Text("BPM")
                        Spacer()
                        Text(String(format: "%.1f", bpm)).monospacedDigit()
                    }
                    Stepper("Tempo", value: $bpm, in: 70...200, step: 0.1)
                    HStack {
                        Text("First beat offset")
                        Spacer()
                        Text(String(format: "%.3f s", phase)).monospacedDigit()
                    }
                    Slider(value: $phase, in: 0...max(0.01, 60 / bpm - 0.001))
                }
                Section {
                    Text("Corrects the displayed timing hints only. This does not start SYNC, time-stretch or alter the audio playback.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("BEAT GRID")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        audio.applyManualBeatGrid(deck: deck, bpm: bpm,
                                                  firstBeatSeconds: phase)
                        if audio.errorMessage == nil { dismiss() }
                    }
                }
            }
            .onAppear {
                bpm = min(200, max(70, audio.fileDecks[deck]?.tempo?.bpm ?? audio.bpm))
                let interval = 60 / bpm
                phase = min(interval - 0.001,
                            max(0, audio.fileDecks[deck]?.beatGrid?.firstBeatSeconds ?? 0))
            }
            .onChange(of: bpm) { value in
                // Editing tempo must not leave the phase slider with a
                // selected value outside the shorter beat interval.
                phase = min(phase, max(0, 60 / value - 0.001))
            }
        }
        .preferredColorScheme(.dark)
    }
}
