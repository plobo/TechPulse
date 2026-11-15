import Foundation

enum DiagramValidationError: Error, Equatable, Sendable {
    case empty
    case tooManyComponents
    case tooManyConnections
    case invalidID(String)
    case duplicateID(String)
    case danglingConnection(String)
    case selfLoop(String)

    var reason: String {
        switch self {
        case .empty: "no components"
        case .tooManyComponents: "too many components"
        case .tooManyConnections: "too many connections"
        case let .invalidID(id): "invalid id \(id)"
        case let .duplicateID(id): "duplicate id \(id)"
        case let .danglingConnection(id): "unknown component \(id)"
        case let .selfLoop(id): "self-connection on \(id)"
        }
    }
}

enum DiagramValidator {
    static let maxComponents = 12
    static let maxConnections = 20
    static let maxLabelLength = 60

    /// Returns a sanitized copy, or throws. Never returns a partially valid diagram.
    static func validate(_ diagram: ArchitectureDiagram) throws -> ArchitectureDiagram {
        guard !diagram.components.isEmpty else { throw DiagramValidationError.empty }
        guard diagram.components.count <= maxComponents else { throw DiagramValidationError.tooManyComponents }
        guard diagram.connections.count <= maxConnections else { throw DiagramValidationError.tooManyConnections }

        var seen = Set<String>()
        let components = try diagram.components.map { component -> ArchitectureDiagram.Component in
            let id = component.id.trimmingCharacters(in: .whitespaces)
            guard id.wholeMatch(of: /[A-Za-z][A-Za-z0-9_]{0,31}/) != nil else { throw DiagramValidationError.invalidID(id) }
            guard seen.insert(id).inserted else { throw DiagramValidationError.duplicateID(id) }
            let name = clean(component.name)
            return .init(id: id, name: name.isEmpty ? id : name, kind: clean(component.kind), detail: clean(component.detail, limit: 120))
        }
        let connections = try diagram.connections.map { connection -> ArchitectureDiagram.Connection in
            let from = connection.from.trimmingCharacters(in: .whitespaces)
            let to = connection.to.trimmingCharacters(in: .whitespaces)
            for end in [from, to] where !seen.contains(end) { throw DiagramValidationError.danglingConnection(end) }
            guard from != to else { throw DiagramValidationError.selfLoop(from) }
            return .init(from: from, to: to, label: clean(connection.label))
        }
        return ArchitectureDiagram(title: clean(diagram.title), components: components, connections: connections)
    }

    static func clean(_ text: String, limit: Int = maxLabelLength) -> String {
        let scalars = text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let trimmed = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(limit))
    }
}

enum MermaidGenerator {
    static func source(for diagram: ArchitectureDiagram) -> String {
        var lines = ["flowchart TD"]
        for component in diagram.components {
            lines.append("    \(node(component.id))[\"\(escape(component.name))\"]")
        }
        for connection in diagram.connections {
            let label = escape(connection.label)
            lines.append(label.isEmpty ? "    \(node(connection.from)) --> \(node(connection.to))"
                                       : "    \(node(connection.from)) -->|\"\(label)\"| \(node(connection.to))")
        }
        return lines.joined(separator: "\n")
    }

    /// Prefixed so ids like `end` or `graph` can't collide with Mermaid keywords.
    static func node(_ id: String) -> String { "n_" + id }

    static func escape(_ text: String) -> String {
        DiagramValidator.clean(text, limit: .max)
            .replacingOccurrences(of: "#", with: "#35;")
            .replacingOccurrences(of: "\"", with: "#quot;")
            .replacingOccurrences(of: "<", with: "#lt;")
            .replacingOccurrences(of: ">", with: "#gt;")
            .replacingOccurrences(of: "|", with: "#124;")
    }
}

enum DiagramLayout {
    /// Longest-path layering; back-edges (cycles) are ignored so this always terminates.
    static func layers(for diagram: ArchitectureDiagram) -> [[String]] {
        let ids = diagram.components.map(\.id)
        var adjacency: [String: [String]] = [:]
        for edge in diagram.connections { adjacency[edge.from, default: []].append(edge.to) }

        // Find back-edges with an iterative DFS in component order.
        var state: [String: Int] = [:] // 1 = on stack, 2 = done
        var forward: [String: [String]] = [:]
        var order: [String] = [] // reverse postorder → topological
        for root in ids where state[root] == nil {
            var stack: [(String, Int)] = [(root, 0)]
            state[root] = 1
            while let (node, index) = stack.last {
                let next = adjacency[node] ?? []
                if index < next.count {
                    stack[stack.count - 1].1 += 1
                    let child = next[index]
                    switch state[child] {
                    case nil:
                        forward[node, default: []].append(child)
                        state[child] = 1
                        stack.append((child, 0))
                    case 2:
                        forward[node, default: []].append(child)
                    default:
                        break // back-edge: ignore
                    }
                } else {
                    state[node] = 2
                    order.append(node)
                    stack.removeLast()
                }
            }
        }

        var depth: [String: Int] = [:]
        for node in order.reversed() {
            let d = depth[node] ?? 0
            for child in forward[node] ?? [] { depth[child] = max(depth[child] ?? 0, d + 1) }
        }
        let maxDepth = depth.values.max() ?? 0
        return (0...maxDepth).map { level in ids.filter { (depth[$0] ?? 0) == level } }.filter { !$0.isEmpty }
    }
}

enum DiagramTextDescription {
    static func text(for diagram: ArchitectureDiagram) -> String {
        let names = Dictionary(diagram.components.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        var lines = ["Diagram: \(diagram.title)", "Components:"]
        lines += diagram.components.map { "• \($0.name) (\($0.kind))" + ($0.detail.isEmpty ? "" : " — \($0.detail)") }
        if !diagram.connections.isEmpty {
            lines.append("Connections:")
            lines += diagram.connections.map {
                "• \(names[$0.from] ?? $0.from) → \(names[$0.to] ?? $0.to)" + ($0.label.isEmpty ? "" : ": \($0.label)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
