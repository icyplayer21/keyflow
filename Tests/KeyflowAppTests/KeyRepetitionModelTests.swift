import CoreGraphics
import Foundation
import Testing
@testable import Keyflow
import KeyflowCore

@MainActor
@Suite struct KeyRepetitionModelTests {
    private final class Clock { var now: Double = 1000 }

    private func key(_ c: Character, at time: Double = 0, repeat isRepeat: Bool = false,
                     command: Bool = false) -> KeyPress {
        KeyPress(keyCode: 0, characters: String(c), hasCommandOrControl: command, hasOption: false,
                 timestamp: time, isRepeat: isRepeat)
    }

    private func special(_ code: UInt16) -> KeyPress {
        KeyPress(keyCode: code, characters: nil, hasCommandOrControl: false, hasOption: false, timestamp: 0)
    }

    private func model(store: TrainingStore? = nil, defaults: UserDefaults? = nil, clock: Clock = Clock()) -> KeyRepetitionModel {
        KeyRepetitionModel(store: store, defaults: defaults, clock: { clock.now })
    }

    private func freshDefaults() -> UserDefaults {
        let name = "keyflow.tests.keyRepetition.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultsToFiftyContinuous() {
        let m = model()
        #expect(m.goal == 50)
        #expect(m.mode == .continuous)
        #expect(m.stage == .setup)
        #expect(m.showsKeyboard)
    }

    @Test func recommendedFingerComesFromTheMap() {
        #expect(KeyRepetitionModel.fingerName(for: "p") == "Right pinky")
        #expect(KeyRepetitionModel.fingerName(for: "f") == "Left index")
        #expect(KeyRepetitionModel.fingerName(for: "k") == "Right middle")
        #expect(KeyRepetitionModel.fingerName(for: "s") == "Left ring")
        for letter in KeyRepetitionCounter.letters {
            #expect(!KeyRepetitionModel.fingerName(for: letter).isEmpty)
        }
    }

    @Test func typingALetterInSetupChoosesItAndReturnStarts() {
        let m = model()
        #expect(m.handle(key("P")))
        #expect(m.letter == "p")
        #expect(m.displayLetter == "P")
        #expect(!m.handle(key("7")))
        #expect(m.letter == "p")
        #expect(m.handle(special(KeyPress.return)))
        #expect(m.stage == .training)
        #expect(m.counter.letter == "p")
    }

    @Test func goalIsClampedAndLockedDuringTraining() {
        let m = model()
        m.setGoal(3)
        #expect(m.goal == 5)
        m.setGoal(9999)
        #expect(m.goal == 500)
        m.setGoal(100)
        m.start()
        m.setGoal(25)
        #expect(m.goal == 100)
        #expect(m.counter.goal == 100)
        m.select("z")
        #expect(m.letter != "z")
    }

    @Test func choicesAreRemembered() {
        let defaults = freshDefaults()
        let m = model(defaults: defaults)
        m.select("j")
        m.setGoal(200)
        m.mode = .returnToHome
        m.showsKeyboard = false
        let again = model(defaults: defaults)
        #expect(again.letter == "j")
        #expect(again.goal == 200)
        #expect(again.mode == .returnToHome)
        #expect(!again.showsKeyboard)
    }

    @Test func holdingTheKeyCannotCompleteASession() {
        let m = model()
        m.select("p")
        m.setGoal(5)
        m.start()
        #expect(m.handle(key("p", at: 1)))
        for i in 0..<300 { _ = m.handle(key("p", at: 1 + Double(i) * 0.03, repeat: true)) }
        #expect(m.counter.correct == 1)
        #expect(m.stage == .training)
    }

    @Test func commandShortcutsAndNonTypingKeysAreNotAttempts() {
        let m = model()
        m.start()
        #expect(!m.handle(key("p", command: true)))
        #expect(!m.handle(special(KeyPress.delete)))
        #expect(m.counter.attempts == 0)
    }

    @Test func mistakesSoundAndShowWhatWasTyped() {
        let m = model()
        var sounds = 0
        m.onMistake = { sounds += 1 }
        m.select("p")
        m.start()
        _ = m.handle(key("o", at: 1))
        _ = m.handle(key("p", at: 2))
        #expect(sounds == 1)
        #expect(m.feedback?.outcome == .correct)
        #expect(m.recent.map(\.outcome) == [.incorrect, .correct])
        #expect(m.recent.first?.typed == "o")
        #expect(m.counter.incorrect == 1)
    }

    @Test func recentPressesStayShort() {
        let m = model()
        m.setGoal(100)
        m.start()
        for i in 0..<40 { _ = m.handle(key("f", at: Double(i))) }
        #expect(m.recent.count == KeyRepetitionModel.recentLimit)
    }

    @Test func escapePausesAndResumes() {
        let clock = Clock()
        let m = model(clock: clock)
        m.start()
        _ = m.handle(key("f", at: 1))
        #expect(m.handle(special(KeyPress.escape)))
        #expect(m.isPaused)
        _ = m.handle(key("f", at: 2))
        #expect(m.counter.correct == 1)
        #expect(m.handle(special(KeyPress.escape)))
        #expect(!m.isPaused)
        _ = m.handle(key("f", at: 3))
        #expect(m.counter.correct == 2)
    }

    @Test func tabRestartsWithoutSaving() throws {
        let store = try TrainingStore.inMemory()
        let m = model(store: store)
        m.start()
        for i in 0..<10 { _ = m.handle(key("f", at: Double(i))) }
        #expect(m.hasProgress)
        #expect(m.handle(special(KeyPress.tab)))
        #expect(m.counter.attempts == 0)
        #expect(m.stage == .training)
        #expect(store.keyRepetitionEvents.isEmpty)
    }

    @Test func exitReturnsToSetupWithoutSaving() throws {
        let store = try TrainingStore.inMemory()
        let m = model(store: store)
        m.start()
        _ = m.handle(key("f", at: 1))
        m.exit()
        #expect(m.stage == .setup)
        #expect(store.keyRepetitionEvents.isEmpty)
    }

    @Test func completingSavesOneSessionWithTheResult() throws {
        let store = try TrainingStore.inMemory()
        let m = model(store: store)
        m.select("p")
        m.setGoal(25)
        m.mode = .returnToHome
        m.start()
        var t = 100.0
        _ = m.handle(key("o", at: t))
        for _ in 0..<25 { t += 0.4; _ = m.handle(key("p", at: t)) }

        guard case .complete(let event) = m.stage else { Issue.record("not complete"); return }
        #expect(event.result.letter == "p")
        #expect(event.result.goal == 25)
        #expect(event.result.correct == 25)
        #expect(event.result.incorrect == 1)
        #expect(event.result.mode == .returnToHome)
        #expect(abs(event.result.accuracy - 25.0 / 26.0) < 1e-9)
        #expect(abs(event.result.duration - 10) < 1e-6)
        #expect(store.keyRepetitionEvents == [event])
        #expect(m.history.stats(for: "p")?.sessions == 1)
        // Presses after the end change nothing, and are swallowed so they
        // don't reach anything else in the window.
        #expect(m.handle(key("p", at: t + 1)))
        #expect(m.handle(key("x", at: t + 2)))
        #expect(!m.handle(special(KeyPress.tab)))
        #expect(store.keyRepetitionEvents.count == 1)
        // Return first skips the explosion, without starting anything.
        #expect(m.showsBurst)
        #expect(m.handle(special(KeyPress.return)))
        #expect(!m.showsBurst)
        guard case .complete = m.stage else { Issue.record("left the results"); return }
        // Then it repeats with the same key and goal.
        #expect(m.handle(special(KeyPress.return)))
        #expect(m.stage == .training)
        #expect(m.counter.goal == 25)
        #expect(m.counter.attempts == 0)
    }

    @Test func otherLearnHistoryIsUntouched() throws {
        let store = try TrainingStore.inMemory()
        let app = AppModel(store: try StatisticsStore.inMemory(), trainingStore: store, defaults: nil)
        app.learnMode = .keyRepetition
        app.keyRepetition.setGoal(5)
        app.keyRepetition.start()
        for i in 0..<5 { _ = app.keyRepetition.handle(key("f", at: Double(i))) }
        #expect(store.keyRepetitionEvents.count == 1)
        #expect(store.events.isEmpty)
        #expect(store.fingerFocusEvents.isEmpty)
        #expect(store.mechanicsEvents.isEmpty)
        #expect(app.store?.summaries.isEmpty == true)
    }

    @Test func appWiring() throws {
        let app = AppModel(store: nil, trainingStore: try TrainingStore.inMemory(), defaults: nil)
        #expect(LearnMode.allCases.contains(.keyRepetition))
        #expect(LearnMode.keyRepetition.title == "Key Repetition")
        // No new main destination.
        #expect(AppSection.allCases.count == 5)
        app.section = .muscleMemory
        app.learnMode = .keyRepetition
        #expect(!app.hasNextLearnExercise)
        app.learnShowsKeyboard = false
        #expect(!app.keyRepetition.showsKeyboard)
        app.resetSettings()
        #expect(app.keyRepetition.showsKeyboard)
        app.keyRepetition.start()
        _ = app.keyRepetition.handle(key("f", at: 1))
        app.restartCurrent()
        #expect(app.keyRepetition.counter.attempts == 0)
    }

    @Test func resetProgressClearsKeyRepetitionHistory() throws {
        let store = try TrainingStore.inMemory()
        let app = AppModel(store: try StatisticsStore.inMemory(), trainingStore: store, defaults: nil)
        app.keyRepetition.setGoal(5)
        app.keyRepetition.start()
        for i in 0..<5 { _ = app.keyRepetition.handle(key("f", at: Double(i))) }
        #expect(app.keyRepetition.history.keys.count == 1)
        try app.resetProgress()
        #expect(store.keyRepetitionEvents.isEmpty)
        #expect(app.keyRepetition.history.keys.isEmpty)
    }

    @Test func exportIncludesSessionsWithoutWPM() throws {
        let store = try TrainingStore.inMemory()
        try store.record(KeyRepetitionEvent(result: KeyRepetitionResult(letter: "p", goal: 50, correct: 50, incorrect: 2,
                                                                        mode: .continuous, duration: 30)))
        let data = try KeyflowExport(store: nil, trainingStore: store).json()
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let sessions = try #require(object["keyRepetition"] as? [[String: Any]])
        #expect(sessions.count == 1)
        #expect(sessions[0]["key"] as? String == "p")
        #expect(sessions[0]["correct"] as? Int == 50)
        #expect(sessions[0]["incorrect"] as? Int == 2)
        #expect(sessions[0]["mode"] as? String == "continuous")
        #expect(sessions[0].keys.contains { $0.lowercased().contains("wpm") } == false)
    }

    @Test func burstFollowsSavingAndClearsItself() throws {
        let store = try TrainingStore.inMemory()
        let m = model(store: store)
        m.setGoal(5)
        m.start()
        #expect(!m.showsBurst)
        for i in 0..<4 { _ = m.handle(key("f", at: Double(i))) }
        #expect(!m.showsBurst)
        _ = m.handle(key("f", at: 5))
        #expect(m.showsBurst)
        #expect(store.keyRepetitionEvents.count == 1, "saved before the explosion plays")
        #expect(m.handle(key("f", at: 6)))
        #expect(store.keyRepetitionEvents.count == 1)
        m.exit()
        #expect(!m.showsBurst)
    }
}

@MainActor
@Suite struct KeyRepetitionGrowthTests {
    private let area = CGSize(width: 1600, height: 1000)
    private let metrics = KeyRepetitionGrowth.Metrics(capHeight: 0.7, width: 0.7)

    @Test func heightFollowsTheOutlinedCurve() {
        #expect(abs(KeyRepetitionGrowth.heightShare(0) - 0.12) < 1e-9)
        #expect(abs(KeyRepetitionGrowth.heightShare(0.25) - 0.21125) < 1e-4)
        #expect(abs(KeyRepetitionGrowth.heightShare(0.5) - 0.378) < 1e-3)
        #expect(abs(KeyRepetitionGrowth.heightShare(0.75) - 0.594) < 1e-3)
        #expect(abs(KeyRepetitionGrowth.heightShare(1) - 0.85) < 1e-9)
    }

    @Test func growsEveryPressAndGetsSteeper() {
        for goal in [5, 25, 50, 67, 100, 200, 500] {
            var last = KeyRepetitionGrowth.fontSize(progress: 0, area: area, metrics: metrics)
            var lastStep: CGFloat = 0
            for press in 1...goal {
                let size = KeyRepetitionGrowth.fontSize(progress: Double(press) / Double(goal), area: area, metrics: metrics)
                #expect(size > last)
                #expect(size - last >= lastStep - 1e-6)
                lastStep = size - last
                last = size
            }
            #expect(abs(last - KeyRepetitionGrowth.endFontSize(area: area, metrics: metrics)) < 1e-6)
        }
    }

    @Test func widestLettersStillFitTheWindow() {
        let wide = KeyRepetitionGrowth.Metrics(capHeight: 0.7, width: 1.1)
        let narrow = CGSize(width: 700, height: 900)
        let size = KeyRepetitionGrowth.fontSize(progress: 1, area: narrow, metrics: wide)
        #expect(size * wide.width <= narrow.width * 0.9 + 1e-6)
        for letter in KeyRepetitionCounter.letters {
            let real = KeyRepetitionGrowth.Metrics.of(String(letter).uppercased())
            #expect(KeyRepetitionGrowth.endFontSize(area: narrow, metrics: real) * real.width <= narrow.width * 0.9 + 1e-6)
        }
    }

    @Test func colorWarmsButNeverReachesMistakeRed() {
        for dark in [true, false] {
            let start = KeyRepetitionGrowth.bottomColor(0, dark: dark)
            let end = KeyRepetitionGrowth.bottomColor(1, dark: dark)
            #expect(end.red - end.blue > start.red - start.blue)
            #expect(end.green > 0.4, "stays orange")
        }
        #expect(KeyRepetitionGrowth.topColor(0, dark: true).green > 0.9, "white on dark")
        #expect(KeyRepetitionGrowth.topColor(0, dark: false).green < 0.2, "ink on light")
    }

    @Test func glowAndTrembleWaitForTheFinalStretch() {
        #expect(KeyRepetitionGrowth.intensity(0.5) == 0)
        #expect(KeyRepetitionGrowth.intensity(0.9) == 0)
        #expect(abs(KeyRepetitionGrowth.intensity(0.95) - 0.5) < 1e-9)
        #expect(KeyRepetitionGrowth.intensity(1) == 1)
        #expect(KeyRepetitionGrowth.punch(1) > KeyRepetitionGrowth.punch(0))
    }

    @Test func sparksAreRepeatableAndFadeOut() {
        let a = KeyRepetitionParticle.make(count: 46, seed: 9)
        #expect(a == KeyRepetitionParticle.make(count: 46, seed: 9))
        for spark in a {
            #expect(spark.opacity(at: 0) == 1)
            #expect(spark.opacity(at: 1) == 0)
            let moved = spark.offset(at: 1, radius: 500)
            #expect(hypot(moved.width, moved.height) > 100)
        }
    }

    @Test func shardsCoverTheLetterAndFlyOutward() {
        let size = CGSize(width: 600, height: 800)
        let all = KeyRepetitionShard.make(columns: 12, rows: 16, size: size, seed: 3) { _ in true }
        #expect(all.count == 12 * 16 * 2)
        #expect(all == KeyRepetitionShard.make(columns: 12, rows: 16, size: size, seed: 3) { _ in true })
        // The triangles tile the box exactly.
        let area = all.reduce(0.0) { total, shard in
            let p = shard.points
            return total + abs((p[1].x - p[0].x) * (p[2].y - p[0].y) - (p[2].x - p[0].x) * (p[1].y - p[0].y)) / 2
        }
        #expect(abs(area - size.width * size.height) < 1)
        for shard in all {
            #expect(shard.opacity(at: 0) == 1)
            #expect(shard.opacity(at: 1) == 0)
            #expect(shard.scale(at: 1) < shard.scale(at: 0))
            let moved = shard.travel(at: 1, radius: 500)
            #expect(hypot(moved.width, moved.height) > 50)
            let outward = moved.width * shard.centroid.x + moved.height * shard.centroid.y
            if hypot(shard.centroid.x, shard.centroid.y) > 200 { #expect(outward > 0) }
        }
    }

    @Test func emptyPiecesAreDropped() {
        let size = CGSize(width: 600, height: 800)
        let left = KeyRepetitionShard.make(columns: 12, rows: 16, size: size, seed: 3) { $0.x < 0.25 }
        #expect(!left.isEmpty && left.count < 12 * 16)
    }

    @Test func endingSqueezesThenSnaps() {
        typealias Frame = KeyRepetitionBurstFrame
        #expect(Frame.squeezeScale(at: 0) == 1, "starts exactly as the growing letter ended")
        #expect(abs(Frame.squeezeScale(at: Frame.squeezeEnd) - 0.92) < 1e-6)
        #expect(Frame.squeezeScale(at: Frame.breakTime) > 1.05)
        #expect(Frame.heat(at: 0.05) == 0)
        #expect(Frame.heat(at: Frame.breakTime) == 1)
        #expect(abs(KeyRepetitionBurstView.duration - 1.1) < 1e-9)
    }

    @Test func everyLetterShatters() {
        for letter in KeyRepetitionCounter.letters {
            let art = KeyRepetitionLetterArt.make(letter: String(letter).uppercased(), fontSize: 400, dark: true, scale: 1, seed: 5)
            #expect((art?.pieces.count ?? 0) >= 60, "\(letter): \(art?.pieces.count ?? 0)")
        }
    }
}
