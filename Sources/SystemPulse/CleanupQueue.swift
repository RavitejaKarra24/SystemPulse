import Foundation

struct DiskTrashReview: Identifiable, Equatable, Sendable {
    let id: UUID
    let scanRevision: UInt64
    let item: DiskItem
}

struct CleanupReview: Identifiable, Equatable, Sendable {
    let id: UUID
    let scanRevision: UInt64
    let items: [DiskItem]
    var logicalBytes: UInt64 { CleanupQueue.totalBytes(items) }
}

struct CleanupItemResult: Identifiable, Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        case movedToTrash
        case failed(String)
        case notAttempted(String)

        var message: String {
            switch self {
            case .movedToTrash: return "Moved to Trash"
            case .failed(let message): return "Failed · \(message)"
            case .notAttempted(let message): return "Not attempted · \(message)"
            }
        }
    }
    let item: DiskItem
    let outcome: Outcome
    var id: String { item.id }
}

enum CleanupQueue {
    static let limit = 50
    static func totalBytes(_ items: [DiskItem]) -> UInt64 {
        items.reduce(0) { total, item in
            let sum = total.addingReportingOverflow(item.bytes)
            return sum.overflow ? UInt64.max : sum.partialValue
        }
    }
}

/// Sendable synchronous filesystem client, always called from a detached worker
/// for reviewed batches. Tests replace it; no real Trash requests are needed.
struct CleanupTrashClient: Sendable {
    let move: @Sendable (DiskItem) -> CleanupItemResult.Outcome
    static let live = Self(move: { item in
        DiskScanner.moveToTrash(item: item)
    })
}
