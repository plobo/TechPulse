import Foundation

/// Structured architecture diagram proposed by the model. Validate before use.
struct ArchitectureDiagram: Codable, Sendable, Hashable {
    struct Component: Codable, Sendable, Hashable, Identifiable {
        var id: String
        var name: String
        var kind: String
        var detail: String
    }

    struct Connection: Codable, Sendable, Hashable {
        var from: String
        var to: String
        var label: String
    }

    var title: String
    var components: [Component]
    var connections: [Connection]
}
