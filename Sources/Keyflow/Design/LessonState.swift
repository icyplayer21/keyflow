import KeyflowCore
import SwiftUI

/// How a Learn lesson (a category's stage) is shown everywhere in the app.
enum LessonState: Equatable {
    /// The previous stage is neither mastered nor skipped.
    case locked
    /// Open, nothing typed yet.
    case notStarted
    /// Rounds completed, not yet mastered.
    case inProgress(qualifying: Int)
    /// Passed over; does not count as mastered.
    case skipped
    case mastered

    init(status: StageStatus, progress: StageProgress) {
        switch status {
        case .locked: self = .locked
        case .mastered: self = .mastered
        case .skipped: self = .skipped
        case .available: self = progress.rounds > 0 ? .inProgress(qualifying: progress.qualifyingRounds) : .notStarted
        }
    }

    var symbol: String {
        switch self {
        case .locked: "lock"
        case .notStarted: "circle"
        case .inProgress: "circle.lefthalf.filled"
        case .skipped: "arrow.uturn.right.circle"
        case .mastered: "checkmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .locked: .secondary.opacity(0.6)
        case .notStarted, .skipped: .secondary
        case .inProgress: .accentColor
        case .mastered: DS.Palette.success
        }
    }

    var label: String {
        switch self {
        case .locked: "Locked"
        case .notStarted: "Not started"
        case .inProgress(let qualifying): "\(min(qualifying, MasteryTracker.requiredRounds)) of \(MasteryTracker.requiredRounds)"
        case .skipped: "Skipped"
        case .mastered: "Mastered"
        }
    }
}
