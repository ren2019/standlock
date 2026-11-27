import SwiftUI
import StandLockCore

struct TimerNumerals: View {
    let remainingSeconds: TimeInterval
    let totalDuration: TimeInterval
    let palette: BreakPalette
    let viewportHeight: CGFloat
    let reduceMotion: Bool
    let flexibleProgress: FlexibleBreakProgress?

    private var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return 1 - (remainingSeconds / totalDuration)
    }

    private func timeString(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var fontSize: CGFloat {
        min(220, viewportHeight * 0.22)
    }

    private var progressWidth: CGFloat {
        fontSize * 2.5
    }

    var body: some View {
        if let flexibleProgress {
            timerRing(for: flexibleProgress)
        } else {
            VStack(spacing: 12) {
                numerals(size: fontSize)
                progressBar
                    .frame(width: progressWidth)
            }
        }
    }

    private func numerals(size: CGFloat) -> some View {
        Text(timeString(remainingSeconds))
            .font(BreakTypography.timerNumerals(size: size))
            .monospacedDigit()
            .tracking(size * -0.02)
            .foregroundStyle(palette.ink)
            .contentTransition(.identity)
            .transaction { $0.animation = nil }
    }

    private func timerRing(for breakProgress: FlexibleBreakProgress) -> some View {
        let target = breakProgress.targetDuration
        let credited = breakProgress.creditedDuration
        let elapsed = max(credited, target - remainingSeconds)
        let fraction = target > 0 ? elapsed / target : 1
        let diameter = min(330, viewportHeight * 0.34)
        let status: LocalizedStringKey = remainingSeconds == 0 ? "Break complete" : "Remaining break time"

        return VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(palette.ink.opacity(0.16), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(palette.accent, lineWidth: 6)
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion || remainingSeconds == 0 ? nil : .linear(duration: 0.3), value: fraction)

                VStack(spacing: 4) {
                    Text(status)
                        .font(BreakTypography.label(size: 13, weight: .semibold))
                    numerals(size: diameter * 0.3)
                    Text("Rested \(timeString(elapsed)) / \(timeString(target))")
                        .font(BreakTypography.label(size: 13))
                        .monospacedDigit()
                }
                .foregroundStyle(palette.inkSoft)
            }
            .frame(width: diameter, height: diameter)
            .accessibilityElement(children: .combine)

            if credited > 0 {
                Text("Includes \(timeString(credited)) before the break screen")
                    .font(BreakTypography.label(size: 13))
                    .foregroundStyle(palette.inkSoft)
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(palette.paperEdge)
                    .frame(height: 1)
                Rectangle()
                    .fill(palette.ink)
                    .frame(width: geo.size.width * progress, height: 3)
                    .offset(y: -1)
            }
        }
        .frame(height: 3)
        .animation(reduceMotion ? nil : .linear(duration: 1), value: progress)
    }
}
