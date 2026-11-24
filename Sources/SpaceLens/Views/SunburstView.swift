import SwiftUI

/// One arc of the sunburst. `start` and `end` are fractions of a full turn.
struct Segment: Identifiable {
    let id: Int
    let node: FileNode?
    let label: String
    let size: Int64
    let depth: Int
    let start: Double
    let end: Double
    let color: Color
}

enum SunburstLayout {
    static let maxDepth = 5
    /// Arcs narrower than this (about 0.7°) are merged into a grey remainder.
    static let minSpan = 0.002

    static func color(start: Double, end: Double, depth: Int) -> Color {
        let hue = (start + end) / 2
        let d = Double(depth - 1)
        return Color(hue: hue, saturation: 0.66 - d * 0.04, brightness: 1.0 - d * 0.06)
    }

    static let otherColor = Color.white.opacity(0.13)

    /// Lays out the tree below `root`. Children are sorted largest first, so the walk
    /// stops at the first arc that is too thin: cost depends on what is visible, not on tree size.
    static func segments(for root: FileNode) -> [Segment] {
        var out: [Segment] = []
        guard root.size > 0 else { return out }
        add(root, depth: 1, start: 0, end: 1, into: &out)
        return out
    }

    private static func add(_ node: FileNode, depth: Int, start: Double, end: Double, into out: inout [Segment]) {
        guard node.size > 0 else { return }
        let scale = (end - start) / Double(node.size)
        var cursor = start
        for child in node.children {
            let span = Double(child.size) * scale
            if span < minSpan { break }
            let s = cursor
            let e = cursor + span
            cursor = e
            out.append(Segment(id: out.count, node: child, label: child.name, size: child.size, depth: depth,
                               start: s, end: e, color: color(start: s, end: e, depth: depth)))
            if child.isDir && depth < maxDepth {
                add(child, depth: depth + 1, start: s, end: e, into: &out)
            }
        }
        if end - cursor >= minSpan {
            let rest = Int64((end - cursor) / scale)
            out.append(Segment(id: out.count, node: nil, label: "Smaller items", size: rest, depth: depth,
                               start: cursor, end: end, color: otherColor))
        }
    }

    /// A single ring for the live view shown while a scan is running.
    static func segments(for top: [ScanProgress.Top]) -> [Segment] {
        let sorted = top.filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }
        let total = sorted.reduce(Int64(0)) { $0 + $1.bytes }
        guard total > 0 else { return [] }
        var out: [Segment] = []
        var cursor = 0.0
        for item in sorted {
            let span = Double(item.bytes) / Double(total)
            if span < minSpan { break }
            out.append(Segment(id: item.id, node: nil, label: item.name, size: item.bytes, depth: 1,
                               start: cursor, end: cursor + span,
                               // Keyed on the item, not its angle, so colours hold still as sizes grow.
                               color: Color(hue: (Double(item.id) * 0.618).truncatingRemainder(dividingBy: 1),
                                            saturation: 0.62, brightness: 0.96)))
            cursor += span
        }
        if 1 - cursor >= minSpan {
            out.append(Segment(id: -1, node: nil, label: "Smaller items", size: 0, depth: 1,
                               start: cursor, end: 1, color: otherColor))
        }
        return out
    }
}

struct SunburstGeometry {
    let center: CGPoint
    let hole: CGFloat
    let ring: CGFloat
    let rings: Int

    init(size: CGSize, rings: Int) {
        let radius = max(min(size.width, size.height) / 2 - 6, 10)
        center = CGPoint(x: size.width / 2, y: size.height / 2)
        hole = radius * (rings == 1 ? 0.62 : 0.30)
        ring = (radius - hole) / CGFloat(rings)
        self.rings = rings
    }

    func path(for s: Segment, grow: CGFloat = 0) -> Path {
        let inner = hole + ring * CGFloat(s.depth - 1) + 1.5
        let outer = hole + ring * CGFloat(s.depth) + grow
        let a0 = Angle.radians(s.start * 2 * .pi - .pi / 2)
        let a1 = Angle.radians(s.end * 2 * .pi - .pi / 2)
        var p = Path()
        p.addArc(center: center, radius: outer, startAngle: a0, endAngle: a1, clockwise: false)
        p.addArc(center: center, radius: inner, startAngle: a1, endAngle: a0, clockwise: true)
        p.closeSubpath()
        return p
    }

    /// Returns the ring (1-based) and turn fraction under a point; ring 0 is the centre hole.
    func locate(_ point: CGPoint) -> (depth: Int, fraction: Double)? {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let r = (dx * dx + dy * dy).squareRoot()
        if r < hole { return (0, 0) }
        let depth = Int((r - hole) / ring) + 1
        guard depth <= rings else { return nil }
        var angle = atan2(dy, dx) + .pi / 2
        if angle < 0 { angle += 2 * .pi }
        return (depth, Double(angle / (2 * .pi)))
    }
}

/// Draws the arcs. Pure drawing: it knows nothing about app state.
struct SunburstCanvas: View {
    let segments: [Segment]
    let rings: Int
    var highlighted: FileNode?
    var highlightedID: Int?

    var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, size in
            let geo = SunburstGeometry(size: size, rings: rings)
            var lit: Segment?
            for s in segments {
                let isLit = (s.node != nil && s.node === highlighted) || (highlightedID != nil && s.id == highlightedID)
                if isLit { lit = s; continue }
                let p = geo.path(for: s)
                ctx.fill(p, with: .color(s.color))
                ctx.stroke(p, with: .color(Theme.bg), lineWidth: 1)
            }
            if let lit {
                let p = geo.path(for: lit, grow: 5)
                ctx.fill(p, with: .color(lit.color))
                ctx.fill(p, with: .color(.white.opacity(0.22)))
                ctx.stroke(p, with: .color(.white.opacity(0.9)), lineWidth: 1.5)
            }
        }
    }
}

/// Interactive chart for a finished scan.
struct SunburstView: View {
    @Environment(AppState.self) private var state
    let target: ScanTarget
    let focus: FileNode
    let segments: [Segment]

    @State private var hoveredID: Int?

    var body: some View {
        GeometryReader { proxy in
            let geo = SunburstGeometry(size: proxy.size, rings: SunburstLayout.maxDepth)
            ZStack {
                SunburstCanvas(segments: segments, rings: SunburstLayout.maxDepth,
                               highlighted: state.hovered, highlightedID: hoveredID)
                centre(diameter: geo.hole * 2 - 10)
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case let .active(point):
                    let seg = segment(at: point, geo)
                    if seg?.id != hoveredID { hoveredID = seg?.id }
                    if seg?.node !== state.hovered { state.hovered = seg?.node }
                case .ended:
                    hoveredID = nil
                    state.hovered = nil
                }
            }
            .gesture(SpatialTapGesture().onEnded { tap in
                guard let hit = geo.locate(tap.location) else { return }
                if hit.depth == 0 {
                    if let parent = focus.parent { state.setFocus(parent, in: target) }
                } else if let node = segment(at: tap.location, geo)?.node {
                    hoveredID = nil
                    if node.isDir { state.setFocus(node, in: target) } else { state.reveal(node) }
                }
            })
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func segment(at point: CGPoint, _ geo: SunburstGeometry) -> Segment? {
        guard let hit = geo.locate(point), hit.depth > 0 else { return nil }
        return segments.first { $0.depth == hit.depth && hit.fraction >= $0.start && hit.fraction < $0.end }
    }

    private func centre(diameter: CGFloat) -> some View {
        let lit = segments.first { $0.id == hoveredID }
        return VStack(spacing: 3) {
            if focus.parent != nil {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.textDim)
            }
            Text(lit?.label ?? focus.name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(Fmt.bytes(lit?.size ?? focus.size))
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.accent)
                .contentTransition(.numericText())
            if let lit {
                Text(Fmt.percent(lit.size, of: focus.size))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textDim)
            } else {
                Text("\(Fmt.count(focus.fileCount)) files")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textDim)
            }
        }
        .padding(14)
        .frame(width: max(diameter, 40), height: max(diameter, 40))
        .background(Circle().fill(Theme.bgRaised).shadow(color: .black.opacity(0.5), radius: 14))
        .overlay(Circle().strokeBorder(Theme.stroke))
        .allowsHitTesting(false)
    }
}
