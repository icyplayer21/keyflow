import Testing
@testable import KeyflowCore

@Suite struct KeyRepetitionEnergyTests {
    /// `count` correct presses out of `goal`, `gap` seconds apart, from time 0.
    private func pressed(_ count: Int, goal: Int = 10, gap: Double = 0.5) -> KeyRepetitionEnergy {
        var energy = KeyRepetitionEnergy()
        for press in 1...count { energy.press(earned: Double(press) / Double(goal), at: Double(press - 1) * gap) }
        return energy
    }

    @Test func noShrinkingWhileSettlingIn() {
        let energy = pressed(2)
        #expect(energy.graceSeconds == nil)
        #expect(energy.level(at: 1000) == 0.2)
    }

    @Test func steadyPressesKeepTheFullEarnedSize() {
        var energy = KeyRepetitionEnergy()
        for press in 1...10 {
            energy.press(earned: Double(press) / 10, at: Double(press) * 0.5)
            #expect(abs(energy.level(at: Double(press) * 0.5) - Double(press) / 10) < 1e-9)
        }
    }

    @Test func waitFollowsTheUsersOwnRhythmWithinLimits() {
        #expect(pressed(5, gap: 0.5).graceSeconds == 1)
        #expect(pressed(5, gap: 0.1).graceSeconds == KeyRepetitionEnergy.minimumGrace)
        #expect(pressed(5, gap: 5).graceSeconds == KeyRepetitionEnergy.maximumGrace)
    }

    @Test func shrinksGentlyThenFasterDownToStartingSize() {
        let energy = pressed(5)              // last press at 2, wait 1
        #expect(energy.level(at: 3) == 0.5)
        let first = 0.5 - energy.level(at: 4)
        let second = energy.level(at: 4) - energy.level(at: 5)
        #expect(first > 0 && second > first)
        #expect(energy.level(at: 6) == 0)
        #expect(energy.level(at: 600) == 0)
    }

    @Test func aPressWinsBackPartOfTheLossAndItsOwnStep() {
        var energy = pressed(5)
        energy.press(earned: 0.6, at: 100)   // fully drained: lost 0.5
        #expect(abs(energy.level(at: 100) - 0.3) < 1e-9)
        energy.press(earned: 0.7, at: 100.1)
        #expect(abs(energy.level(at: 100.1) - 0.52) < 1e-9)
    }

    @Test func pauseFreezesTheSizeAndTheWait() {
        var energy = pressed(5)
        energy.pause(at: 3.5)
        let frozen = energy.level(at: 3.5)
        #expect(energy.level(at: 500) == frozen)
        energy.resume(at: 500)
        #expect(abs(energy.level(at: 500) - frozen) < 1e-9)
        #expect(energy.level(at: 501) < frozen)
    }
}
