import Foundation

/// Acquisition times are distinct from the wall-clock time when a pass reaches
/// the main actor. Slow filesystem/IOKit queries must not re-date other sources.
struct SampleObservationTimes: Sendable {
    let cpu: Date
    let memory: Date
    let power: Date?
    let disk: Date?
    let thermal: Date?
}
