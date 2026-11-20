import Foundation

/// Determines when activity during a waiting period is sustained enough to start work.
struct FlexibleWorkActivity {
    let waitingSince: Date
    private var firstInput: Date?
    private var lastInput: Date?

    init(waitingSince: Date) {
        self.waitingSince = waitingSince
    }

    mutating func isReady(lastInputAt input: Date?, now: Date) -> Bool {
        if let input, input >= waitingSince, input <= now, lastInput.map({ input > $0 }) ?? true {
            if lastInput.map({ input.timeIntervalSince($0) > 30 }) ?? true {
                firstInput = input
            }
            lastInput = input
        }
        guard let firstInput, let lastInput, now.timeIntervalSince(lastInput) <= 30 else { return false }
        return now.timeIntervalSince(firstInput) >= 60
    }
}
