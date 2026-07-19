import JMemory
import SwiftUI

/// Force-directed knowledge-graph explorer rendered with Canvas. Simple spring
/// layout run on a timer; tap a node to highlight its relations.
struct GraphView: View {
    let reader: GraphReader

    @State private var snapshot = GraphReader.Snapshot(nodes: [], edges: [])
    @State private var positions: [String: CGPoint] = [:]
    @State private var velocities: [String: CGVector] = [:]
    @State private var selected: String?
    @State private var includeHistory = false
    @State private var layout: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Toggle("Show history", isOn: $includeHistory)
                    .toggleStyle(.switch).controlSize(.mini)
                    .font(.jarvisCaption).foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text("\(snapshot.nodes.count) nodes")
                    .font(.jarvisFootnote).monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: snapshot.nodes.count)
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(.horizontal, 4)

            if snapshot.nodes.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 24, weight: .light)).foregroundStyle(.white.opacity(0.55))
                    Text("Your knowledge graph will grow as you talk to Jarvis")
                        .font(.jarvisCaption).foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                }
                Spacer()
            } else {
                canvas
                legend
            }
        }
        .task { await reload() }
        .onChange(of: includeHistory) { _, _ in Task { await reload() } }
        .onDisappear { layout?.cancel() }
    }

    private var canvas: some View {
        GeometryReader { geo in
            Canvas { context, size in
                drawEdges(context, size: size)
                drawNodes(context, size: size)
            }
            .contentShape(Rectangle())
            .onTapGesture { location in selectNode(near: location, in: geo.size) }
            .onAppear { startLayout(in: geo.size) }
            .onChange(of: geo.size) { _, newSize in startLayout(in: newSize) }
            .accessibilityHidden(true)
        }
    }

    /// Tiny kind→color key so the node colors are decodable at a glance.
    private var legend: some View {
        let kinds: [(String, String)] = [
            ("person", "People"), ("org", "Orgs"), ("project", "Projects"),
            ("place", "Places"), ("artifact", "Artifacts"), ("other", "Other"),
        ]
        return HStack(spacing: 10) {
            ForEach(kinds, id: \.0) { kind, label in
                HStack(spacing: 4) {
                    Circle().fill(kindColor(kind)).frame(width: 6, height: 6)
                    Text(label).font(.jarvisFootnote).foregroundStyle(.white.opacity(0.55))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Drawing

    private func drawEdges(_ context: GraphicsContext, size: CGSize) {
        for edge in snapshot.edges {
            guard let a = positions[edge.source], let b = positions[edge.target] else { continue }
            let highlighted = selected == edge.source || selected == edge.target
            var path = Path()
            path.move(to: a)
            path.addLine(to: b)
            let opacity = edge.isCurrent ? (highlighted ? 0.7 : 0.22) : 0.1
            context.stroke(path, with: .color(.white.opacity(opacity)), lineWidth: highlighted ? 1.5 : 0.8)

            if highlighted {
                let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                context.draw(
                    Text(edge.relation.replacingOccurrences(of: "_", with: " "))
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6)),
                    at: mid
                )
            }
        }
    }

    private func drawNodes(_ context: GraphicsContext, size: CGSize) {
        for node in snapshot.nodes {
            guard let p = positions[node.id] else { continue }
            let isSelected = selected == node.id
            let radius: CGFloat = isSelected ? 7 : 5
            let color = kindColor(node.kind).opacity(node.isCurrent ? 1 : 0.4)
            context.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)),
                         with: .color(color))
            context.draw(
                Text(node.name).font(.system(size: isSelected ? 11 : 10, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.white.opacity(isSelected ? 0.95 : 0.65)),
                at: CGPoint(x: p.x, y: p.y - radius - 7)
            )
        }
    }

    private func kindColor(_ kind: String) -> Color {
        switch kind {
        case "person": .jarvisAccent
        case "org": .orange
        case "project": .purple
        case "place": .jarvisSuccess
        case "artifact": .pink
        default: .teal
        }
    }

    // MARK: - Layout

    private func startLayout(in size: CGSize) {
        layout?.cancel()
        seedPositions(in: size)
        layout = Task {
            // Stop as soon as the simulation settles (kinetic energy below a
            // per-node threshold) instead of always burning 600 iterations.
            let threshold = max(CGFloat(snapshot.nodes.count) * 0.02, 0.05)
            for iteration in 0..<600 {
                if Task.isCancelled { return }
                let energy = await MainActor.run { step(in: size) }
                if iteration > 10, energy < threshold { return }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private func seedPositions(in size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        for (i, node) in snapshot.nodes.enumerated() where positions[node.id] == nil {
            let angle = Double(i) / Double(max(snapshot.nodes.count, 1)) * 2 * .pi
            positions[node.id] = CGPoint(x: center.x + cos(angle) * 80, y: center.y + sin(angle) * 80)
            velocities[node.id] = .zero
        }
    }

    /// One tick of a basic spring/repulsion simulation. Returns the total
    /// kinetic energy, so the layout loop can stop once it converges.
    @discardableResult
    private func step(in size: CGSize) -> CGFloat {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        var forces: [String: CGVector] = [:]

        for node in snapshot.nodes { forces[node.id] = .zero }

        // Repulsion between all nodes.
        let nodes = snapshot.nodes
        for i in 0..<nodes.count {
            for j in (i + 1)..<nodes.count {
                guard let a = positions[nodes[i].id], let b = positions[nodes[j].id] else { continue }
                let dx = a.x - b.x, dy = a.y - b.y
                let dist = max(sqrt(dx * dx + dy * dy), 1)
                let force = 1200 / (dist * dist)
                let fx = dx / dist * force, fy = dy / dist * force
                forces[nodes[i].id]?.dx += fx; forces[nodes[i].id]?.dy += fy
                forces[nodes[j].id]?.dx -= fx; forces[nodes[j].id]?.dy -= fy
            }
        }

        // Spring attraction along edges.
        for edge in snapshot.edges {
            guard let a = positions[edge.source], let b = positions[edge.target] else { continue }
            let dx = b.x - a.x, dy = b.y - a.y
            let dist = max(sqrt(dx * dx + dy * dy), 1)
            let force = (dist - 70) * 0.02
            let fx = dx / dist * force, fy = dy / dist * force
            forces[edge.source]?.dx += fx; forces[edge.source]?.dy += fy
            forces[edge.target]?.dx -= fx; forces[edge.target]?.dy -= fy
        }

        var energy: CGFloat = 0
        for node in snapshot.nodes {
            guard var p = positions[node.id], var v = velocities[node.id], let f = forces[node.id] else { continue }
            // Gentle pull to center + damping.
            v.dx = (v.dx + f.dx + (center.x - p.x) * 0.005) * 0.85
            v.dy = (v.dy + f.dy + (center.y - p.y) * 0.005) * 0.85
            p.x = min(max(p.x + v.dx, 12), size.width - 12)
            p.y = min(max(p.y + v.dy, 20), size.height - 12)
            positions[node.id] = p
            velocities[node.id] = v
            energy += v.dx * v.dx + v.dy * v.dy
        }
        return energy
    }

    private func selectNode(near location: CGPoint, in size: CGSize) {
        let hit = snapshot.nodes.min { a, b in
            distance(positions[a.id], location) < distance(positions[b.id], location)
        }
        if let hit, distance(positions[hit.id], location) < 24 {
            selected = (selected == hit.id) ? nil : hit.id
        } else {
            selected = nil
        }
    }

    private func distance(_ p: CGPoint?, _ q: CGPoint) -> CGFloat {
        guard let p else { return .greatestFiniteMagnitude }
        return sqrt(pow(p.x - q.x, 2) + pow(p.y - q.y, 2))
    }

    private func reload() async {
        snapshot = await reader.snapshot(includeHistory: includeHistory)
    }
}
