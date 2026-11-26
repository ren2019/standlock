import Foundation
import Testing
@testable import StandLockCore

@Suite("Pause presentation")
struct PausePresentationTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    @Test
    func pauseIsQuietBeforeTheFinalTenSeconds() {
        let pause = PausePresentation.paused(resumeAt: start.addingTimeInterval(60))

        #expect(pause.menuBarDisplay(at: start.addingTimeInterval(49.99), reduceMotion: false)
                == .init(countdownSeconds: nil, iconLook: .paused))
    }

    @Test(arguments: [
        (remaining: 10.0, seconds: 10),
        (remaining: 9.5, seconds: 10),
        (remaining: 9.0, seconds: 9),
        (remaining: 8.0, seconds: 8),
        (remaining: 7.0, seconds: 7),
        (remaining: 6.0, seconds: 6),
        (remaining: 5.0, seconds: 5),
        (remaining: 4.0, seconds: 4),
        (remaining: 3.0, seconds: 3),
        (remaining: 2.0, seconds: 2),
        (remaining: 1.0, seconds: 1),
        (remaining: 0.01, seconds: 1),
    ])
    func countdownShowsEachRemainingSecond(remaining: TimeInterval, seconds: Int) {
        let resumeAt = start.addingTimeInterval(60)
        let pause = PausePresentation.paused(resumeAt: resumeAt)

        #expect(pause.menuBarDisplay(at: resumeAt.addingTimeInterval(-remaining), reduceMotion: false)?
                .countdownSeconds == seconds)
    }

    @Test
    func countdownAlternatesWithTheWorkingIcon() {
        let resumeAt = start.addingTimeInterval(10)
        let pause = PausePresentation.paused(resumeAt: resumeAt)

        #expect(pause.menuBarDisplay(at: start, reduceMotion: false)?.iconLook == .paused)
        #expect(pause.menuBarDisplay(at: start.addingTimeInterval(1), reduceMotion: false)?.iconLook == .working)
        #expect(pause.menuBarDisplay(at: start.addingTimeInterval(2), reduceMotion: false)?.iconLook == .paused)
    }

    @Test(arguments: [0.0, 1.0])
    func expiryEndsThePauseDisplay(elapsed: TimeInterval) {
        let resumeAt = start.addingTimeInterval(10)
        let pause = PausePresentation.paused(resumeAt: resumeAt)

        #expect(pause.menuBarDisplay(at: resumeAt.addingTimeInterval(elapsed), reduceMotion: false) == nil)
    }

    @Test
    func expiredCueAlternatesWithoutCountdownThenEnds() {
        let cueUntil = start.addingTimeInterval(10)
        let cue = PausePresentation.expired(cueUntil: cueUntil)

        #expect(cue.menuBarDisplay(at: start, reduceMotion: false)
                == .init(countdownSeconds: nil, iconLook: .paused))
        #expect(cue.menuBarDisplay(at: start.addingTimeInterval(1), reduceMotion: false)
                == .init(countdownSeconds: nil, iconLook: .working))
        #expect(cue.menuBarDisplay(at: start.addingTimeInterval(2), reduceMotion: false)
                == .init(countdownSeconds: nil, iconLook: .paused))
        #expect(cue.menuBarDisplay(at: cueUntil, reduceMotion: false) == nil)
    }

    @Test(arguments: [1.0, 5.0, 9.0])
    func reduceMotionKeepsThePausedIcon(elapsed: TimeInterval) {
        let resumeAt = start.addingTimeInterval(10)
        let pause = PausePresentation.paused(resumeAt: resumeAt)
        let cue = PausePresentation.expired(cueUntil: resumeAt)

        #expect(pause.menuBarDisplay(at: start.addingTimeInterval(elapsed), reduceMotion: true)?.iconLook == .paused)
        #expect(cue.menuBarDisplay(at: start.addingTimeInterval(elapsed), reduceMotion: true)?.iconLook == .paused)
    }
}
