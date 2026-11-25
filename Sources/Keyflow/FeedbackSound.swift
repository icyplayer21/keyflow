import AppKit

/// Settings ▸ Feedback ▸ Sound: a short, quiet system sound on a mistake.
/// Played without blocking typing; a sound still playing is not restarted.
@MainActor
enum FeedbackSound {
    private static let sound: NSSound? = {
        let sound = NSSound(named: "Tink")
        sound?.volume = 0.35
        return sound
    }()

    static func mistake() {
        guard let sound, !sound.isPlaying else { return }
        sound.play()
    }
}
