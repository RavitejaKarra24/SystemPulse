import Foundation

/// Pure search and ranking rules shared by the process list and its tests.
struct ProcessQuery {
    enum SortMetric {
        case cpu, memory
    }

    let normalizedText: String
    private let terms: [String]

    init(_ text: String) {
        normalizedText = Self.normalize(text)
        terms = normalizedText.split(separator: " ").map(String.init)
    }

    var isSearching: Bool { !terms.isEmpty }

    func matches(_ group: ProcessGroup) -> Bool {
        guard isSearching else { return true }
        let fields =
            ([group.name]
            + group.processes.flatMap { process in
                [
                    process.name, String(process.id), process.executablePath,
                    process.bundlePath ?? "", process.bundleIdentifier ?? "",
                ]
            }).map(Self.normalize)
        // Each term may match a different field, e.g. an app name plus a PID.
        return terms.allSatisfy { term in fields.contains { $0.contains(term) } }
    }

    func apply(to groups: [ProcessGroup], sortBy metric: SortMetric) -> [ProcessGroup] {
        let ranked = groups.filter(matches).map { group in
            (
                group: group, cpu: group.totalCPU, memory: group.totalMemory,
                name: Self.normalize(group.name)
            )
        }
        return ranked.sorted { lhs, rhs in
            switch metric {
            case .cpu:
                let left = lhs.cpu.isFinite ? lhs.cpu : 0
                let right = rhs.cpu.isFinite ? rhs.cpu : 0
                if left != right { return left > right }
            case .memory:
                if lhs.memory != rhs.memory { return lhs.memory > rhs.memory }
            }
            if lhs.name != rhs.name { return lhs.name < rhs.name }
            return lhs.group.id < rhs.group.id
        }.map(\.group)
    }

    private static func normalize(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
    }
}
