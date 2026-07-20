import JKnowledge
import SwiftUI

/// Force-directed knowledge-graph explorer rendered with Canvas. Pan (drag the
/// background), zoom (pinch), drag nodes, search to highlight, and tap a node
/// to inspect it — its relations plus the memories it appears in.
struct GraphView: View {
    let reader: GraphReader
    var memoryStore: KnowledgeStore?
    /// Optional trailing control shown in the graph's own toolbar (e.g. the
    /// list/graph mode toggle) so the parent doesn't need a second header row.
    var accessory: AnyView? = nil

    @State private var snapshot = GraphReader.Snapshot(nodes: [], edges: [])
    @State private var positions: [String: CGPoint] = [:]
    @State private var velocities: [String: CGVector] = [:]
    @State private var selected: String?
    @State private var relatedMemories: [RetrievedFact] = []
    @State private var typeFilter: Set<String> = []
    @State private var layout: Task<Void, Never>?
    @State private var query = ""

    // View transform: world (simulation) space → screen space.
    @State private var zoom: CGFloat = 1
    @State private var baseZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var basePan: CGSize = .zero

    private enum DragMode: Equatable { case idle, node(String), pan }
    @State private var dragMode: DragMode = .idle

    var body: some View {
        VStack(spacing: 8) {
            controls

            if snapshot.nodes.isEmpty {
                JarvisEmptyState(
                    symbol: "point.3.connected.trianglepath.dotted",
                    title: "Your knowledge graph is empty",
                    message: "People, projects, and places from your conversations connect here as Jarvis learns about you."
                )
            } else {
                canvas
                if let selected, let node = snapshot.nodes.first(where: { $0.id == selected }) {
                    inspector(node)
                } else {
                    legend
                }
            }
        }
        .task { await reload() }
        .onChange(of: typeFilter) { _, _ in Task { await reload() } }
        .onChange(of: selected) { _, id in Task { await loadRelated(id) } }
        .onReceive(NotificationCenter.default.publisher(for: .jarvisGraphDidChange)) { _ in
            // Posted on the main actor by KnowledgeStore, so it is safe to reload here.
            Task { await reload() }
        }
        .onDisappear { layout?.cancel() }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.jarvisCaption)
                    .foregroundStyle(Color.jarvisTextTertiary)
                TextField("Find a node", text: $query)
                    .textFieldStyle(.plain)
                    .font(.jarvisCaption)
                    .foregroundStyle(Color.jarvisTextPrimary)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.jarvisCaption)
                            .foregroundStyle(Color.jarvisTextTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: JarvisRadius.control, style: .continuous).fill(Color.jarvisSurface))
            .frame(maxWidth: 200)

            Spacer()

            if zoom != 1 || pan != .zero {
                Button {
                    withAnimation(.snappy) { zoom = 1; baseZoom = 1; pan = .zero; basePan = .zero }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.jarvisTextSecondary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.jarvisSurfaceHover))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reset view")
            }

            Text("\(snapshot.nodes.count) nodes")
                .font(.jarvisFootnote).monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy, value: snapshot.nodes.count)
                .foregroundStyle(Color.jarvisTextTertiary)

            if let accessory { accessory }
        }
        .padding(.horizontal, 4)
    }

    private var canvas: some View {
        GeometryReader { geo in
            Canvas { context, size in
                drawEdges(context, size: size)
                drawNodes(context, size: size)
            }
            .contentShape(Rectangle())
            .onTapGesture { location in selectNode(near: location, in: geo.size) }
            .gesture(dragGesture(in: geo.size))
            .simultaneousGesture(magnifyGesture)
            .onAppear { startLayout(in: geo.size) }
            .onChange(of: geo.size) { _, newSize in startLayout(in: newSize) }
            .accessibilityHidden(true)
        }
    }

    /// One gesture handles both node-drag (press began on a node) and pan.
    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                switch dragMode {
                case .idle:
                    if let hit = nodeID(at: value.startLocation, in: size) {
                        layout?.cancel() // don't fight the finger
                        dragMode = .node(hit)
                    } else {
                        dragMode = .pan
                    }
                case .node(let id):
                    positions[id] = worldPoint(value.location, in: size)
                    velocities[id] = .zero
                case .pan:
                    pan = CGSize(width: basePan.width + value.translation.width,
                                 height: basePan.height + value.translation.height)
                }
            }
            .onEnded { _ in
                if case .node = dragMode {
                    startLayout(in: size, reseed: false) // let neighbors re-settle
                }
                basePan = pan
                dragMode = .idle
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoom = min(max(baseZoom * value.magnification, 0.4), 3)
            }
            .onEnded { _ in baseZoom = zoom }
    }

    // MARK: - Transform

    private func screenPoint(_ p: CGPoint, in size: CGSize) -> CGPoint {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        return CGPoint(x: (p.x - c.x) * zoom + c.x + pan.width,
                       y: (p.y - c.y) * zoom + c.y + pan.height)
    }

    private func worldPoint(_ s: CGPoint, in size: CGSize) -> CGPoint {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        return CGPoint(x: (s.x - pan.width - c.x) / zoom + c.x,
                       y: (s.y - pan.height - c.y) / zoom + c.y)
    }

    // MARK: - Inspector / legend

    /// Selected-node strip: name, kind, relations, and the memories it appears
    /// in — the click-through from graph back to memory.
    private func inspector(_ node: GraphReader.Node) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(kindColor(node.kind)).frame(width: 7, height: 7)
                Text(node.name)
                    .font(.jarvisRow)
                    .foregroundStyle(Color.jarvisTextPrimary)
                    .lineLimit(1)
                Text(node.kind)
                    .font(.jarvisFootnote)
                    .foregroundStyle(Color.jarvisTextTertiary)
                Spacer(minLength: 0)
                Button {
                    withAnimation(.snappy) { selected = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.jarvisCaption)
                        .foregroundStyle(Color.jarvisTextTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Deselect node")
            }
            ForEach(relations(of: node.id).prefix(3), id: \.self) { line in
                Text(line)
                    .font(.jarvisFootnote)
                    .foregroundStyle(Color.jarvisTextSecondary)
                    .lineLimit(1)
            }
            ForEach(relatedMemories) { memory in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "brain")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.jarvisTextTertiary)
                    Text(memory.text)
                        .font(.jarvisFootnote)
                        .foregroundStyle(Color.jarvisTextSecondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: JarvisRadius.card, style: .continuous).fill(Color.jarvisSurface))
        .transition(.opacity)
    }

    private func relations(of id: String) -> [String] {
        let names = Dictionary(snapshot.nodes.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        return snapshot.edges.filter { $0.source == id || $0.target == id }.map { edge in
            let relation = edge.relation.replacingOccurrences(of: "_", with: " ")
            return edge.source == id
                ? "\(relation) → \(names[edge.target] ?? "?")"
                : "\(names[edge.source] ?? "?") → \(relation)"
        }
    }

    private func loadRelated(_ id: String?) async {
        relatedMemories = []
        guard let id, let memoryStore,
              let node = snapshot.nodes.first(where: { $0.id == id }) else { return }
        let result = await memoryStore.retrieve(query: node.name, limit: 2)
        // A slow fetch for a previously selected node must not land under the
        // node the user has since selected.
        guard selected == id else { return }
        relatedMemories = result
    }

    /// Kind→color key doubling as filter chips: tap to isolate types.
    private var legend: some View {
        let kinds: [(String, String)] = [
            ("person", "People"), ("org", "Orgs"), ("project", "Projects"),
            ("place", "Places"), ("event", "Events"), ("topic", "Topics"), ("thing", "Things"),
        ]
        return HStack(spacing: 10) {
            ForEach(kinds, id: \.0) { kind, label in
                Button {
                    if typeFilter.contains(kind) {
                        typeFilter.remove(kind)
                    } else {
                        typeFilter.insert(kind)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Circle().fill(kindColor(kind)).frame(width: 6, height: 6)
                        Text(label).font(.jarvisFootnote)
                            .foregroundStyle(typeFilter.isEmpty || typeFilter.contains(kind)
                                ? Color.jarvisTextSecondary : Color.jarvisTextTertiary.opacity(0.5))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Filter \(label)")
            }
            Spacer()
            if !typeFilter.isEmpty {
                Button("All") { typeFilter = [] }
                    .buttonStyle(.plain).font(.jarvisFootnote)
                    .foregroundStyle(Color.jarvisAccent)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Drawing

    private var matchedIDs: Set<String> {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return Set(snapshot.nodes.filter { $0.name.localizedCaseInsensitiveContains(q) }.map(\.id))
    }

    /// The selected node plus its direct neighbors — everything else fades so a
    /// dense graph stays readable while inspecting one entity. Nil when nothing
    /// is selected (full graph shown).
    private var neighborhood: Set<String>? {
        guard let selected else { return nil }
        var ids: Set<String> = [selected]
        for edge in snapshot.edges {
            if edge.source == selected { ids.insert(edge.target) }
            if edge.target == selected { ids.insert(edge.source) }
        }
        return ids
    }

    private func drawEdges(_ context: GraphicsContext, size: CGSize) {
        let searching = !matchedIDs.isEmpty || !query.trimmingCharacters(in: .whitespaces).isEmpty
        let focused = neighborhood != nil
        for edge in snapshot.edges {
            guard let wa = positions[edge.source], let wb = positions[edge.target] else { continue }
            let a = screenPoint(wa, in: size), b = screenPoint(wb, in: size)
            let highlighted = selected == edge.source || selected == edge.target
            var path = Path()
            path.move(to: a)
            path.addLine(to: b)
            var opacity = edge.isCurrent ? (highlighted ? 0.7 : 0.22) : 0.1
            if searching, !highlighted { opacity *= 0.4 }
            if focused, !highlighted { opacity *= 0.25 }   // fade edges away from the focused node
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
        let matches = matchedIDs
        let searching = !query.trimmingCharacters(in: .whitespaces).isEmpty
        let focus = neighborhood
        for node in snapshot.nodes {
            guard let world = positions[node.id] else { continue }
            let p = screenPoint(world, in: size)
            // Skip nodes panned/zoomed out of view.
            guard p.x > -40, p.x < size.width + 40, p.y > -40, p.y < size.height + 40 else { continue }
            let isSelected = selected == node.id
            let isMatch = matches.contains(node.id)
            // Dim if a search excludes it, or a focused node's neighborhood does.
            let dimmed = (searching && !isMatch && !isSelected)
                || (focus.map { !$0.contains(node.id) } ?? false)
            let radius: CGFloat = (isSelected ? 7 : 5) * min(zoom, 1.6)
            let color = kindColor(node.kind).opacity(node.isCurrent ? 1 : 0.4)
            context.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)),
                         with: .color(color.opacity(dimmed ? 0.25 : 1)))
            if isMatch {
                context.stroke(
                    Path(ellipseIn: CGRect(x: p.x - radius - 3, y: p.y - radius - 3,
                                           width: (radius + 3) * 2, height: (radius + 3) * 2)),
                    with: .color(.white.opacity(0.8)), lineWidth: 1.2)
            }

            let label = context.resolve(
                Text(node.name).font(.system(size: isSelected ? 11 : 10, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.white.opacity(dimmed ? 0.2 : (isSelected ? 0.95 : 0.65)))
            )
            // Clamp labels inside the canvas so edge nodes stay readable.
            let measured = label.measure(in: size)
            let x = min(max(p.x, measured.width / 2 + 2), size.width - measured.width / 2 - 2)
            let y = max(p.y - radius - 7, measured.height / 2)
            context.draw(label, at: CGPoint(x: x, y: y))
        }
    }

    private func kindColor(_ kind: String) -> Color {
        switch kind {
        case "person": .jarvisAccent
        case "org": .orange
        case "project": .purple
        case "place": .jarvisSuccess
        case "event": .pink
        case "topic": .teal
        default: .gray // thing
        }
    }

    // MARK: - Layout

    private func startLayout(in size: CGSize, reseed: Bool = true) {
        layout?.cancel()
        if reseed { seedPositions(in: size) }
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
            // A node under the user's finger stays exactly where they put it.
            if case .node(let dragged) = dragMode, dragged == node.id { continue }
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
        withAnimation(.snappy) {
            if let hit = nodeID(at: location, in: size) {
                selected = (selected == hit) ? nil : hit
            } else {
                selected = nil
            }
        }
    }

    /// Screen-space hit test (points are transformed, so test in screen space).
    private func nodeID(at location: CGPoint, in size: CGSize) -> String? {
        var best: (id: String, dist: CGFloat)?
        for node in snapshot.nodes {
            guard let world = positions[node.id] else { continue }
            let p = screenPoint(world, in: size)
            let d = sqrt(pow(p.x - location.x, 2) + pow(p.y - location.y, 2))
            if d < 24, d < (best?.dist ?? .greatestFiniteMagnitude) {
                best = (node.id, d)
            }
        }
        return best?.id
    }

    private func reload() async {
        var loaded = await reader.snapshot()
        if !typeFilter.isEmpty {
            let nodes = loaded.nodes.filter { typeFilter.contains($0.kind) }
            let ids = Set(nodes.map(\.id))
            loaded = GraphReader.Snapshot(
                nodes: nodes,
                edges: loaded.edges.filter { ids.contains($0.source) && ids.contains($0.target) })
        }
        snapshot = loaded
        if let selected, !snapshot.nodes.contains(where: { $0.id == selected }) {
            self.selected = nil
        }
    }
}
