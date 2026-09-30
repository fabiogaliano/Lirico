import Foundation
import QuartzCore

extension DispatchQueue {
    static let lyricsDisplay = DispatchQueue(label: "LyricsDisplay")
}

extension CAMediaTimingFunction {
    // Immutable once created; CAMediaTimingFunction just isn't marked Sendable.
    nonisolated(unsafe) static let swiftOut = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.2, 1)
}
