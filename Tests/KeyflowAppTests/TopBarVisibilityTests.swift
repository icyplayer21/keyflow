import Foundation
import Testing
@testable import Keyflow
import KeyflowCore

@MainActor
@Suite struct TopBarVisibilityTests {
    private func key(_ c: Character, at time: Double) -> KeyPress {
        KeyPress(keyCode: 1, characters: String(c), hasCommandOrControl: false, hasOption: false, timestamp: time)
    }

    @Test func fadesOnlyWhileAnExerciseRuns() {
        let bar = TopBarVisibility(keepsVisible: { false })
        bar.noteTyping(exerciseRunning: false)
        #expect(!bar.isFaded)
        bar.noteTyping(exerciseRunning: true)
        #expect(bar.isFaded)
        bar.noteTyping(exerciseRunning: false)
        #expect(!bar.isFaded)
    }

    @Test func returnsWhenTypingPauses() async throws {
        let bar = TopBarVisibility(idleDelay: .milliseconds(40), keepsVisible: { false })
        bar.noteTyping(exerciseRunning: true)
        #expect(bar.isFaded)
        // Other tests share the main actor, so allow for a late wake-up.
        for _ in 0..<150 where bar.isFaded { try await Task.sleep(for: .milliseconds(20)) }
        #expect(!bar.isFaded)
    }

    @Test func eachKeyRestartsTheWait() async throws {
        // Together the gaps outlast the wait, so it only holds if each key restarts it.
        let bar = TopBarVisibility(idleDelay: .milliseconds(1500), keepsVisible: { false })
        for _ in 0..<4 {
            bar.noteTyping(exerciseRunning: true)
            try await Task.sleep(for: .milliseconds(500))
            #expect(bar.isFaded)
        }
        bar.reveal()
    }

    @Test func aRealMouseMoveBringsItBackButAJitterDoesNot() {
        let bar = TopBarVisibility(keepsVisible: { false })
        bar.noteMouse(at: CGPoint(x: 100, y: 100))
        bar.noteTyping(exerciseRunning: true)
        bar.noteMouse(at: CGPoint(x: 102, y: 101))
        #expect(bar.isFaded, "a small nudge is ignored")
        bar.noteMouse(at: CGPoint(x: 112, y: 100))
        #expect(!bar.isFaded)
    }

    @Test func runningFollowsTheScreenYouAreOn() throws {
        let app = AppModel(store: try StatisticsStore.inMemory(), trainingStore: try TrainingStore.inMemory(), defaults: nil)
        app.section = .muscleMemory
        app.learnMode = .keyRepetition
        #expect(!app.isExerciseRunning)
        app.keyRepetition.start()
        #expect(app.isExerciseRunning)
        _ = app.keyRepetition.handle(key(app.keyRepetition.letter, at: 1))
        app.keyRepetition.pause()
        #expect(!app.isExerciseRunning, "paused")
        app.keyRepetition.resume()
        #expect(app.isExerciseRunning)
        app.section = .progress
        #expect(!app.isExerciseRunning, "another screen")
    }

    @Test func topBarTabsGetTheirPanelBelow() throws {
        for width in [920.0, 1100, 1600] {
            let bounds = CGRect(x: 0, y: 0, width: width, height: 640)
            // The first tab of a bar centred in the window.
            let tab = CGRect(x: width / 2 - 240, y: 12, width: 80, height: 26)
            let layout = try #require(TourLayout.make(target: tab, popover: CGSize(width: 300, height: 180), bounds: bounds))
            #expect(layout.side == .below)
            #expect(!layout.popover.intersects(layout.spotlight))
        }
    }
}
