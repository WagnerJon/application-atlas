import SwiftUI

struct SankeyView: View {
    let applications: [Application]
    let categories: [ApplicationCategory]
    let selectedStatus: ApplicationStatus?
    let onSelectStatus: (ApplicationStatus) -> Void
    var body: some View {
        let pipeline = ApplicationPipeline(applications, categories: categories)
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("The bigger picture").font(.title3.weight(.semibold))
                    Text("Every application, from opportunity to outcome.").foregroundStyle(.secondary)
                }
                Spacer()
                Text("APPLICATION JOURNEYS").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
            }
            if applications.isEmpty {
                ContentUnavailableView("Your story starts here", systemImage: "point.3.connected.trianglepath.dotted", description: Text("Add your first application to see your pipeline take shape."))
                    .frame(height: 280)
            } else {
                GeometryReader { geometry in
                    ScrollView(.horizontal) {
                        let width = max(geometry.size.width, Double(pipeline.columnCount) * 210)
                        PipelineDrawing(pipeline: pipeline, total: applications.count, width: width, selectedStatus: selectedStatus, onSelectStatus: onSelectStatus)
                            .frame(width: width, height: pipeline.drawingHeight)
                    }
                }.frame(height: pipeline.drawingHeight + 15)
                Text("Click a status to show all applications that reached it. Ribbons follow recorded steps; widths represent counts. Scroll sideways for longer journeys.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(24).background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
}
private struct PositionedNode {
    let node: PipelineNode
    let x: Double
    let y: Double
    let height: Double
}
private struct PipelineDrawing: View {
    let pipeline: ApplicationPipeline
    let total: Int
    let width: Double
    let selectedStatus: ApplicationStatus?
    let onSelectStatus: (ApplicationStatus) -> Void
    var positions: [PositionedNode] {
        let scale = 220.0 / Double(max(total, 1))
        let spacing = (width - 180) / Double(max(pipeline.columnCount - 1, 1))
        var result: [PositionedNode] = []
        for column in 0..<pipeline.columnCount {
            var y = 40.0
            for node in pipeline.nodes where node.column == column {
                let height = Double(node.count) * scale
                result.append(PositionedNode(node: node, x: 8 + Double(column) * spacing, y: y, height: height))
                y += height + 24
            }
        }
        return result
    }
    var body: some View {
        let positioned = positions
        let lookup = Dictionary(uniqueKeysWithValues: positioned.map { ($0.node.id, $0) })
        let scale = 220.0 / Double(max(total, 1))
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                var outgoing: [String: Double] = [:]
                var incoming: [String: Double] = [:]
                for edge in pipeline.edges {
                    guard let source = lookup[edge.source], let target = lookup[edge.destination] else { continue }
                    let thickness = Double(edge.count) * scale
                    let from = CGPoint(x: source.x + 8, y: source.y + (outgoing[edge.source] ?? 0))
                    let to = CGPoint(x: target.x, y: target.y + (incoming[edge.destination] ?? 0))
                    let path = ribbon(from: from, to: to, thickness: thickness)
                    let dimmed = selectedStatus != nil && source.node.status != selectedStatus && target.node.status != selectedStatus
                    context.fill(path, with: .color(target.node.color.opacity(dimmed ? 0.08 : 0.26)))
                    outgoing[edge.source, default: 0] += thickness
                    incoming[edge.destination, default: 0] += thickness
                }
            }.accessibilityHidden(true)
            ForEach(0..<pipeline.columnCount, id: \.self) { column in
                Text(column == 0 ? "TOTAL" : column == 1 ? "CATEGORY" : "STEP \(column - 1)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
                    .offset(x: 8 + Double(column) * (width - 180) / Double(max(pipeline.columnCount - 1, 1)), y: 3)
            }
            ForEach(positioned, id: \.node.id) { position in
                let node = position.node
                if let status = node.status {
                    Button { onSelectStatus(status) } label: { nodeLabel(position) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(node.label), step \(node.column - 1), \(node.count) applications")
                        .accessibilityHint("Filter the list to all applications that reached \(node.label)")
                        .help("Show all applications that reached \(node.label)")
                        .offset(x: position.x, y: position.y)
                } else {
                    nodeLabel(position).offset(x: position.x, y: position.y)
                }
            }
        }
    }
    private func nodeLabel(_ position: PositionedNode) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(position.node.color)
                .frame(width: 8, height: position.height)
            HStack(spacing: 5) {
                if let icon = position.node.icon { CategoryIconView(icon: icon) }
                Text(position.node.label).lineLimit(1).truncationMode(.tail).help(position.node.label)
                Text("\(position.node.count)").fontWeight(.bold)
            }.font(.system(size: 11)).padding(5)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(position.node.status != nil && selectedStatus == position.node.status ? position.node.color : .clear, lineWidth: 2))
        }.frame(width: 172, height: position.height, alignment: .leading).contentShape(Rectangle())
    }
    private func ribbon(from: CGPoint, to: CGPoint, thickness: Double) -> Path {
        let middle = (from.x + to.x) / 2
        var path = Path()
        path.move(to: from)
        path.addCurve(to: to, control1: CGPoint(x: middle, y: from.y), control2: CGPoint(x: middle, y: to.y))
        path.addLine(to: CGPoint(x: to.x, y: to.y + thickness))
        path.addCurve(to: CGPoint(x: from.x, y: from.y + thickness), control1: CGPoint(x: middle, y: to.y + thickness), control2: CGPoint(x: middle, y: from.y + thickness))
        path.closeSubpath()
        return path
    }
}
