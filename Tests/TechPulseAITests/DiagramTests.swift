import Foundation
import Testing
@testable import TechPulseAI

@Suite("Architecture diagrams")
struct DiagramTests {
    typealias C = ArchitectureDiagram.Component
    typealias E = ArchitectureDiagram.Connection

    func diagram(_ ids: [String], _ edges: [(String, String)] = []) -> ArchitectureDiagram {
        ArchitectureDiagram(title: "T", components: ids.map { C(id: $0, name: $0.uppercased(), kind: "service", detail: "") },
                            connections: edges.map { E(from: $0.0, to: $0.1, label: "uses") })
    }

    @Test func validDiagramPassesAndIsSanitized() throws {
        let d = ArchitectureDiagram(title: " Shop ", components: [
            C(id: "api", name: "  API\u{0007} ", kind: "service", detail: "x"),
            C(id: "db", name: "DB", kind: "database", detail: ""),
        ], connections: [E(from: "api", to: "db", label: String(repeating: "r", count: 80))])
        let v = try DiagramValidator.validate(d)
        #expect(v.title == "Shop")
        #expect(v.components[0].name == "API")
        #expect(v.connections[0].label.count == 60)
    }

    @Test func rejectsStructuralProblems() {
        #expect(throws: DiagramValidationError.empty) { try DiagramValidator.validate(diagram([])) }
        #expect(throws: DiagramValidationError.tooManyComponents) {
            try DiagramValidator.validate(diagram((0..<13).map { "n\($0)" }))
        }
        let ids = (0..<5).map { "n\($0)" }
        let many = (0..<21).map { (ids[$0 % 5], ids[($0 + 1) % 5]) }
        #expect(throws: DiagramValidationError.tooManyConnections) { try DiagramValidator.validate(diagram(ids, many)) }
        #expect(throws: DiagramValidationError.invalidID("1bad")) { try DiagramValidator.validate(diagram(["1bad"])) }
        #expect(throws: DiagramValidationError.duplicateID("a")) { try DiagramValidator.validate(diagram(["a", "a"])) }
        #expect(throws: DiagramValidationError.danglingConnection("x")) { try DiagramValidator.validate(diagram(["a"], [("a", "x")])) }
        #expect(throws: DiagramValidationError.selfLoop("a")) { try DiagramValidator.validate(diagram(["a"], [("a", "a")])) }
    }

    @Test func mermaidEscapesLabelsAndIsWellFormed() {
        var d = diagram(["a", "b"], [("a", "b")])
        d.components[0].name = "Say \"hi\" <script>"
        d.connections[0].label = "reads"
        let src = MermaidGenerator.source(for: d)
        #expect(src.hasPrefix("flowchart TD"))
        #expect(src.contains("#quot;"))
        #expect(src.contains("n_a -->|\"reads\"| n_b"))
        #expect(!src.contains("<script"))
    }

    @Test func layoutTerminatesOnCycles() {
        let layers = DiagramLayout.layers(for: diagram(["a", "b", "c", "d"], [("a", "b"), ("b", "c"), ("c", "a"), ("c", "d")]))
        let flat = layers.flatMap { $0 }
        #expect(flat.sorted() == ["a", "b", "c", "d"])
    }

    @Test func layoutOrdersSourcesFirst() {
        #expect(DiagramLayout.layers(for: diagram(["c", "b", "a"], [("a", "b"), ("b", "c")])) == [["a"], ["b"], ["c"]])
    }

    @Test func textDescriptionListsComponentsAndConnections() {
        let d = ArchitectureDiagram(title: "T", components: [C(id: "api", name: "API", kind: "service", detail: ""),
                                                             C(id: "db", name: "DB", kind: "database", detail: "")],
                                    connections: [E(from: "api", to: "db", label: "reads")])
        let text = DiagramTextDescription.text(for: d)
        #expect(text.contains("API (service)"))
        #expect(text.contains("API → DB: reads"))
    }
}
