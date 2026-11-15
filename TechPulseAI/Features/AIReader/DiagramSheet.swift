import SwiftUI
import UIKit

struct DiagramSheet: View {
    @State private var viewModel: DiagramViewModel
    @State private var copied = false
    @Environment(\.dismiss) private var dismiss

    init(article: Article, dependencies: AppDependencies, library: LibraryStore) {
        _viewModel = State(initialValue: DiagramViewModel(article: article, dependencies: dependencies, library: library))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    content
                }
                .padding(Spacing.l)
            }
            .background(Palette.screenBackground)
            .navigationTitle("Architecture Diagram")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await viewModel.load() }
        }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.state {
        case .idle:
            Text("Propose the components and data flow described by this article. The diagram is generated on device and checked before it’s drawn.")
                .font(.footnote).foregroundStyle(.secondary)
            generateButton(title: "Generate Diagram")
        case .loading:
            ProgressView("Designing on device…")
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle")
            generateButton(title: "Try Again", force: true)
        case let .loaded(artifact):
            if let diagram = artifact.diagram { loaded(artifact, diagram) }
        }
    }

    private func generateButton(title: String, force: Bool = false) -> some View {
        Button { Task { await viewModel.generate(force: force) } } label: {
            Label(title, systemImage: "sparkles").frame(maxWidth: .infinity, minHeight: Layout.minTouchTarget)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!viewModel.isEnabled)
        .accessibilityIdentifier("ai.diagram.generate")
    }

    private func loaded(_ artifact: AIArtifact, _ diagram: ArchitectureDiagram) -> some View {
        let mermaid = MermaidGenerator.source(for: diagram)
        return VStack(alignment: .leading, spacing: Spacing.l) {
            AILabelsRow(provider: artifact.provider, basis: artifact.basis, isSampleData: viewModel.isSampleData)
            Text(diagram.title).font(.headline)
            DiagramCanvas(diagram: diagram)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(DiagramTextDescription.text(for: diagram))
            DisclosureGroup("Text version") {
                Text(DiagramTextDescription.text(for: diagram))
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("ai.diagram.text")
            HStack {
                Button {
                    UIPasteboard.general.string = mermaid
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy Mermaid", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .accessibilityIdentifier("ai.diagram.copy")
                Spacer()
                ShareLink(item: mermaid) { Label("Share", systemImage: "square.and.arrow.up") }
            }
            .buttonStyle(.bordered)
            HStack {
                Button { Task { await viewModel.generate(force: true) } } label: { Label("Regenerate", systemImage: "arrow.clockwise") }
                Spacer()
                ShareLink(item: AIReport.text(for: artifact)) { Label("Report a Problem", systemImage: "exclamationmark.bubble") }
            }
            .font(.footnote)
        }
    }
}

/// Native, non-interactive drawing of a validated diagram (layered boxes and arrows).
struct DiagramCanvas: View {
    let diagram: ArchitectureDiagram
    private let boxSize = CGSize(width: 120, height: 52)
    private let rowGap: CGFloat = 48
    private let colGap: CGFloat = 16

    var body: some View {
        let layers = DiagramLayout.layers(for: diagram)
        let widest = layers.map(\.count).max() ?? 1
        // Extra room on the right for curved edges that skip layers.
        let width = CGFloat(widest) * boxSize.width + CGFloat(max(widest - 1, 0)) * colGap + 16 + boxSize.width
        let height = CGFloat(layers.count) * boxSize.height + CGFloat(max(layers.count - 1, 0)) * rowGap + 16
        let positions = positions(layers: layers, width: width)
        let names = Dictionary(diagram.components.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        ScrollView(.horizontal, showsIndicators: true) {
            Canvas { context, _ in
                let layerStep = boxSize.height + rowGap
                for edge in diagram.connections {
                    guard let from = positions[edge.from], let to = positions[edge.to] else { continue }
                    var path = Path()
                    let start: CGPoint, end: CGPoint, labelPoint: CGPoint, tangentFrom: CGPoint
                    if to.y > from.y && to.y - from.y <= layerStep + 1 {
                        // Adjacent layers: straight line bottom → top.
                        start = CGPoint(x: from.x, y: from.y + boxSize.height / 2)
                        end = CGPoint(x: to.x, y: to.y - boxSize.height / 2)
                        path.move(to: start)
                        path.addLine(to: end)
                        tangentFrom = start
                        labelPoint = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
                    } else {
                        // Skips layers or points upward: curve around the right side so it never crosses boxes.
                        start = CGPoint(x: from.x + boxSize.width / 2, y: from.y)
                        end = CGPoint(x: to.x + boxSize.width / 2, y: to.y)
                        let bulge = max(start.x, end.x) + boxSize.width * 0.6
                        let control = CGPoint(x: bulge, y: (start.y + end.y) / 2)
                        path.move(to: start)
                        path.addQuadCurve(to: end, control: control)
                        tangentFrom = control
                        labelPoint = CGPoint(x: (max(start.x, end.x) + bulge) / 2 + 6, y: control.y)
                    }
                    context.stroke(path, with: .color(.secondary), lineWidth: 1.5)
                    context.fill(arrowHead(at: end, from: tangentFrom), with: .color(.secondary))
                    if !edge.label.isEmpty {
                        let label = context.resolve(Text(edge.label).font(.caption2).foregroundStyle(.secondary))
                        let size = label.measure(in: CGSize(width: 120, height: 40))
                        let rect = CGRect(x: labelPoint.x - size.width / 2 - 3, y: labelPoint.y - size.height / 2 - 1,
                                          width: size.width + 6, height: size.height + 2)
                        context.fill(RoundedRectangle(cornerRadius: 4).path(in: rect), with: .color(Palette.cardBackground))
                        context.draw(label, at: labelPoint)
                    }
                }
                for (id, center) in positions {
                    let rect = CGRect(x: center.x - boxSize.width / 2, y: center.y - boxSize.height / 2,
                                      width: boxSize.width, height: boxSize.height)
                    let shape = RoundedRectangle(cornerRadius: 10).path(in: rect)
                    context.fill(shape, with: .color(Color.accentColor.opacity(0.15)))
                    context.stroke(shape, with: .color(.accentColor), lineWidth: 1)
                    let component = names[id]
                    context.draw(Text(component?.name ?? id).font(.caption.weight(.semibold)),
                                 at: CGPoint(x: center.x, y: center.y - 7))
                    context.draw(Text(component?.kind ?? "").font(.caption2).foregroundStyle(.secondary),
                                 at: CGPoint(x: center.x, y: center.y + 10))
                }
            }
            .frame(width: max(width, 280), height: height)
        }
        .background(Palette.cardBackground, in: RoundedRectangle(cornerRadius: Radius.card))
    }

    private func positions(layers: [[String]], width: CGFloat) -> [String: CGPoint] {
        var result: [String: CGPoint] = [:]
        let canvasWidth = max(width, 280)
        for (row, ids) in layers.enumerated() {
            let rowWidth = CGFloat(ids.count) * boxSize.width + CGFloat(max(ids.count - 1, 0)) * colGap
            let startX = (canvasWidth - rowWidth) / 2 + boxSize.width / 2
            let y = 8 + boxSize.height / 2 + CGFloat(row) * (boxSize.height + rowGap)
            for (col, id) in ids.enumerated() {
                result[id] = CGPoint(x: startX + CGFloat(col) * (boxSize.width + colGap), y: y)
            }
        }
        return result
    }

    private func arrowHead(at tip: CGPoint, from start: CGPoint) -> Path {
        let angle = atan2(tip.y - start.y, tip.x - start.x)
        let length: CGFloat = 8
        var path = Path()
        path.move(to: tip)
        path.addLine(to: CGPoint(x: tip.x - length * cos(angle - .pi / 7), y: tip.y - length * sin(angle - .pi / 7)))
        path.addLine(to: CGPoint(x: tip.x - length * cos(angle + .pi / 7), y: tip.y - length * sin(angle + .pi / 7)))
        path.closeSubpath()
        return path
    }
}
