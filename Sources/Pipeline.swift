import SwiftUI

struct PipelineNode: Identifiable {
    let id: String
    let column: Int
    let label: String
    let status: ApplicationStatus?
    let color: Color
    var count: Int
    var icon: CategoryIcon? = nil
}
struct PipelineEdge: Identifiable {
    var id: String { source + ">" + destination }
    let source: String
    let destination: String
    var count: Int
}
struct ApplicationPipeline {
    let nodes: [PipelineNode]
    let edges: [PipelineEdge]
    var columnCount: Int { (nodes.map(\.column).max() ?? 1) + 1 }
    var drawingHeight: Double {
        let largestColumn = Dictionary(grouping: nodes, by: \.column).values.map(\.count).max() ?? 0
        return max(410, 260 + Double(max(0, largestColumn - 1)) * 24)
    }
    init(_ applications: [Application], categories: [ApplicationCategory] = ApplicationCategory.defaults) {
        var nodes: [String: PipelineNode] = [:]
        var edges: [String: PipelineEdge] = [:]
        for application in applications {
            var path = [PipelineNode(id: "all", column: 0, label: "All applications", status: nil, color: .teal, count: 0),
                        PipelineNode(id: "category:\(application.kind.rawValue)", column: 1, label: categories.first { $0.id == application.kind.rawValue }?.name ?? application.kind.rawValue, status: nil, color: application.kind.color, count: 0, icon: categories.first { $0.id == application.kind.rawValue }?.effectiveIcon ?? .symbol(application.kind.icon))]
            for (index, event) in application.history.enumerated() {
                path.append(PipelineNode(id: "\(index + 2):\(event.status.rawValue)", column: index + 2, label: event.status.rawValue, status: event.status, color: event.status.color, count: 0))
            }
            for node in path {
                var updated = nodes[node.id] ?? node
                updated.count += 1
                nodes[node.id] = updated
            }
            for pair in zip(path, path.dropFirst()) {
                var edge = PipelineEdge(source: pair.0.id, destination: pair.1.id, count: 0)
                edge.count = (edges[edge.id]?.count ?? 0) + 1
                edges[edge.id] = edge
            }
        }
        self.nodes = nodes.values.sorted { left, right in
            if left.column != right.column { return left.column < right.column }
            if left.column == 1 {
                let a = categories.firstIndex { "category:\($0.id)" == left.id } ?? Int.max
                let b = categories.firstIndex { "category:\($0.id)" == right.id } ?? Int.max
                if a != b { return a < b }
            }
            let a = left.status.flatMap { ApplicationStatus.allCases.firstIndex(of: $0) } ?? 0
            let b = right.status.flatMap { ApplicationStatus.allCases.firstIndex(of: $0) } ?? 0
            return a == b ? left.id < right.id : a < b
        }
        self.edges = edges.values.sorted { $0.id < $1.id }
    }
}
