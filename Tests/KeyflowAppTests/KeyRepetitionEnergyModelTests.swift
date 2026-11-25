import Foundation
import Testing
@testable import Keyflow
import KeyflowCore

@MainActor
@Suite struct KeyRepetitionEnergyModelTests {
    private final class Clock { var now: Double = 1000 }

    private func key(_ c: Character, at time: Double, repeat isRepeat: Bool = false) -> KeyPress {
        KeyPress(keyCode: 1, characters: String(c), hasCommandOrControl: false, hasOption: false,
                 timestamp: time, isRepeat: isRepeat)
    }

    private func started(_ clock: Clock, goal: Int = 10) -> KeyRepetitionModel {
        let m = KeyRepetitionModel(clock: { clock.now })
        m.select("p")
        m.setGoal(goal)
        m.start()
        return m
    }

    private func press(_ m: KeyRepetitionModel, _ clock: Clock, _ c: Character = "p", gap: Double = 0.5, count: Int = 1) {
        for _ in 0..<count {
            clock.now += gap
            _ = m.handle(key(c, at: clock.now))
        }
    }

    @Test func shrinkingNeverChangesTheCount() {
        let clock = Clock()
        let m = started(clock)
        press(m, clock, count: 5)
        #expect(m.letterLevel() == 0.5)
        clock.now += 60
        #expect(m.letterLevel() == 0)
        #expect(m.counter.correct == 5)
        #expect(m.counter.incorrect == 0)
    }

    @Test func wrongKeysAndHeldKeysRestoreNothing() {
        let clock = Clock()
        let m = started(clock)
        press(m, clock, count: 5)
        clock.now += 60
        press(m, clock, "o", count: 3)
        #expect(m.letterLevel() == 0)
        clock.now += 0.1
        _ = m.handle(key("p", at: clock.now, repeat: true))
        #expect(m.letterLevel() == 0)
        #expect(m.counter.correct == 5)
    }

    @Test func pausingFreezesTheLetter() {
        let clock = Clock()
        let m = started(clock)
        press(m, clock, count: 5)
        m.pause()
        clock.now += 60
        #expect(m.letterLevel() == 0.5)
        m.resume()
        #expect(m.letterLevel() == 0.5)
    }

    @Test func keepingPaceEndsAtFullPower() {
        let clock = Clock()
        let m = started(clock)
        press(m, clock, count: 10)
        #expect(m.finalLevel == 1)
        #expect(m.showsBurst)
    }

    @Test func slowingDownStillFinishesAtTheGoalWithASmallerBlast() {
        let clock = Clock()
        let m = started(clock)
        press(m, clock, count: 9)
        clock.now += 60
        press(m, clock)
        guard case .complete(let event) = m.stage else { Issue.record("did not finish"); return }
        #expect(event.result.correct == 10)
        #expect(m.finalLevel < 1 && m.finalLevel > 0.3)
    }

    @Test func aNewSessionStartsFresh() {
        let clock = Clock()
        let m = started(clock, goal: 5)
        press(m, clock, count: 5)
        m.start()
        #expect(m.letterLevel() == 0)
        #expect(m.finalLevel == 1)
    }

    @Test func blastScalesWithFinalSize() {
        typealias Frame = KeyRepetitionBurstFrame
        #expect(Frame.blastScale(1) == 1)
        #expect(Frame.blastScale(0.5) < 1 && Frame.blastScale(0.5) > Frame.blastScale(0))
        #expect(Frame.blastScale(0) > 0)
    }
}
