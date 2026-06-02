import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Complex Number

struct Complex {
    var re: Double
    var im: Double
    init(_ re: Double, _ im: Double = 0) { self.re = re; self.im = im }

    var magnitude: Double { (re*re + im*im).squareRoot() }
    var magnitudeSquared: Double { re*re + im*im }
    var angle: Double { atan2(im, re) }

    static func +(l: Complex, r: Complex) -> Complex { Complex(l.re+r.re, l.im+r.im) }
    static func -(l: Complex, r: Complex) -> Complex { Complex(l.re-r.re, l.im-r.im) }
    static func *(l: Complex, r: Complex) -> Complex {
        Complex(l.re*r.re - l.im*r.im, l.re*r.im + l.im*r.re)
    }
    static func /(l: Complex, r: Complex) -> Complex {
        let d = r.magnitudeSquared
        guard d > 1e-300 else { return Complex(.infinity, .infinity) }
        return Complex((l.re*r.re + l.im*r.im)/d, (l.im*r.re - l.re*r.im)/d)
    }
    static func +(l: Complex, r: Double) -> Complex { Complex(l.re+r, l.im) }
    static func -(l: Complex, r: Double) -> Complex { Complex(l.re-r, l.im) }
    static func *(l: Complex, r: Double) -> Complex { Complex(l.re*r, l.im*r) }
    static func polar(r: Double, theta: Double) -> Complex { Complex(r*cos(theta), r*sin(theta)) }
}

// MARK: - Engine

struct SCE {
    static func norm(_ Z: Complex, z0: Double = 50) -> Complex { Complex(Z.re/z0, Z.im/z0) }
    static func gamma(_ zn: Complex) -> Complex { (zn - 1.0) / (zn + 1.0) }
    static func zFromGamma(_ g: Complex) -> Complex { (Complex(1,0)+g) / (Complex(1,0)-g) }
    static func Y(_ z: Complex) -> Complex { Complex(1,0) / z }
    static func tLine(_ g: Complex, theta: Double) -> Complex {
        g * Complex.polar(r: 1, theta: -2*theta)
    }
    static func screen(_ g: Complex, _ c: CGPoint, _ r: CGFloat) -> CGPoint {
        CGPoint(x: c.x + CGFloat(g.re)*r, y: c.y - CGFloat(g.im)*r)
    }
    /// Convert a screen point back to Γ
    static func gammaFromScreen(_ pt: CGPoint, _ c: CGPoint, _ r: CGFloat) -> Complex {
        Complex(Double((pt.x - c.x) / r), Double((c.y - pt.y) / r))
    }
}

// MARK: - Marker

struct Marker: Identifiable {
    let id = UUID()
    var idx: Int; var g: Complex; var zn: Complex; var z0: Double
    var Z: Complex  { Complex(zn.re*z0, zn.im*z0) }
    var yn: Complex { SCE.Y(zn) }
    var swr: Double { let m = g.magnitude; return m < 1 ? (1+m)/(1-m) : .infinity }
}

// MARK: - Component Type for Frequency Sweep

enum ComponentType: String, CaseIterable, Identifiable {
    case seriesL   = "Series L"
    case seriesC   = "Series C"
    case parallelL = "Parallel L"
    case parallelC = "Parallel C"
    var id: String { rawValue }
}

// MARK: - Matching Solution

struct MatchSolution: Identifiable {
    var id = UUID()
    var label: String
    var steps: [String]
    var shuntB: Double
    var seriesX: Double
}

// MARK: - ViewModel

final class VM: ObservableObject {
    @Published var loadR = 20.0,  loadX  = 50.0
    @Published var shuntB = 1.15, seriesX = -1.1
    @Published var tLineDeg = 55.0
    @Published var showY = true, showTLine = true
    let z0 = 50.0

    // Feature 1: Interactive tap/drag
    @Published var dragGamma: Complex? = nil

    // Feature 2: Frequency sweep
    @Published var sweepEnabled = false
    @Published var componentType: ComponentType = .seriesL
    @Published var componentValue: Double = 10.0   // nH or pF
    @Published var freqStart: Double = 100.0        // MHz
    @Published var freqEnd: Double   = 3000.0       // MHz
    @Published var freqPoints: Int   = 60

    // Feature 4: Matching wizard
    @Published var wizardEnabled = false
    @Published var wizardSolutions: [MatchSolution] = []

    var markers: [Marker] {
        var ms = [Marker]()
        // ① load
        let zn1 = SCE.norm(Complex(loadR, loadX), z0: z0)
        ms.append(Marker(idx: 0, g: SCE.gamma(zn1), zn: zn1, z0: z0))
        // ② shunt B (Y domain)
        let yn2 = Complex(SCE.Y(zn1).re, SCE.Y(zn1).im + shuntB)
        let zn2 = SCE.Y(yn2)
        ms.append(Marker(idx: 1, g: SCE.gamma(zn2), zn: zn2, z0: z0))
        // ③ series X
        let zn3 = Complex(zn2.re, zn2.im + seriesX)
        ms.append(Marker(idx: 2, g: SCE.gamma(zn3), zn: zn3, z0: z0))
        // ④ T-line
        if showTLine {
            let g4 = SCE.tLine(SCE.gamma(zn3), theta: tLineDeg * .pi/180)
            ms.append(Marker(idx: 3, g: g4, zn: SCE.zFromGamma(g4), z0: z0))
        }
        return ms
    }

    func trajectory(c: CGPoint, r: CGFloat) -> [[CGPoint]] {
        guard markers.count >= 3 else { return [] }
        let N = 150
        var segs = [[CGPoint]]()
        let zn1 = SCE.norm(Complex(loadR, loadX), z0: z0)
        let yn1 = SCE.Y(zn1)
        // ①→② shunt B arc
        segs.append((0...N).map { i in
            let yn = Complex(yn1.re, yn1.im + shuntB * Double(i)/Double(N))
            return SCE.screen(SCE.gamma(SCE.Y(yn)), c, r)
        })
        // ②→③ series X arc
        let zn2 = SCE.Y(Complex(yn1.re, yn1.im + shuntB))
        segs.append((0...N).map { i in
            let zn = Complex(zn2.re, zn2.im + seriesX * Double(i)/Double(N))
            return SCE.screen(SCE.gamma(zn), c, r)
        })
        // ③→④ T-line arc
        if showTLine, markers.count == 4 {
            let g3 = markers[2].g; let tot = tLineDeg * .pi/180
            segs.append((0...N).map { i in
                SCE.screen(SCE.tLine(g3, theta: tot * Double(i)/Double(N)), c, r)
            })
        }
        return segs
    }

    // MARK: Feature 2 — Frequency Sweep points
    func sweepPoints(c: CGPoint, r: CGFloat) -> [CGPoint] {
        guard sweepEnabled, freqEnd > freqStart, freqPoints > 1 else { return [] }
        let n = freqPoints
        let fStart = freqStart * 1e6  // Hz
        let fEnd   = freqEnd   * 1e6  // Hz
        let valSI: Double
        switch componentType {
        case .seriesL, .parallelL:
            valSI = componentValue * 1e-9   // nH → H
        case .seriesC, .parallelC:
            valSI = componentValue * 1e-12  // pF → F
        }
        let zLoad = Complex(loadR, loadX)

        return (0..<n).compactMap { i in
            let t = Double(i) / Double(n - 1)
            let freq = fStart + t * (fEnd - fStart)
            let omega = 2 * Double.pi * freq

            let zTotal: Complex
            switch componentType {
            case .seriesL:
                // Series inductor: Z_total = Z_load + jωL (normalized)
                let jXl = Complex(0, omega * valSI)
                zTotal = zLoad + jXl
            case .seriesC:
                // Series capacitor: Z_total = Z_load + 1/(jωC) = Z_load - j/(ωC)
                let jXc = Complex(0, -1.0 / (omega * valSI))
                zTotal = zLoad + jXc
            case .parallelL:
                // Parallel inductor: Y_total = Y_load + 1/(jωL)
                let yLoad = SCE.Y(zLoad)
                let yL = Complex(0, -1.0 / (omega * valSI))
                zTotal = SCE.Y(yLoad + yL)
            case .parallelC:
                // Parallel capacitor: Y_total = Y_load + jωC
                let yLoad = SCE.Y(zLoad)
                let yC = Complex(0, omega * valSI)
                zTotal = SCE.Y(yLoad + yC)
            }

            guard zTotal.re.isFinite, zTotal.im.isFinite else { return nil }
            let zn = SCE.norm(zTotal, z0: z0)
            let g  = SCE.gamma(zn)
            guard g.magnitude <= 2.0 else { return nil }
            return SCE.screen(g, c, r)
        }
    }

    // MARK: Feature 4 — Matching Wizard
    func computeMatching() {
        let RL = loadR
        let XL = loadX

        guard RL > 0 else { wizardSolutions = []; return }

        var sols = [MatchSolution]()

        // Normalised component values — the UI sliders use normalised B and X
        // so we compute normalised shuntB and seriesX to feed back.
        // Reference: classic L-network design for RL→z0 matching
        // See Pozar "Microwave Engineering" ch 5

        func fmtX(_ v: Double) -> String { String(format: "%+.4f Ω", v) }
        func fmtB(_ v: Double) -> String { String(format: "%+.6f S", v) }
        func fmtNX(_ v: Double) -> String { String(format: "%+.4f (norm)", v) }
        func fmtNB(_ v: Double) -> String { String(format: "%+.4f (norm)", v) }

        if RL > z0 {
            // Topology A (shunt B at load, series X toward source)
            // Q = sqrt(RL/z0 - 1)
            let Q = (RL/z0 - 1.0).squareRoot()
            // Two sign choices for Q
            for sign in [1.0, -1.0] {
                let Bs = sign * Q / RL             // shunt susceptance (S)
                let Xs = sign * Q * z0 - XL        // series reactance (Ω) net of load X
                // Normalise for UI: shuntB is in normalised admittance (×z0),
                // seriesX is in normalised impedance (×/z0)
                let normB = Bs * z0
                let normX = Xs / z0
                let label = sign > 0 ? "L-net A (Q=+\(String(format:"%.3f",Q)))" : "L-net A (Q=−\(String(format:"%.3f",Q)))"
                sols.append(MatchSolution(
                    label: label,
                    steps: [
                        "Shunt B = \(fmtB(Bs))  [\(fmtNB(normB)) norm]",
                        "Series X = \(fmtX(Xs))  [\(fmtNX(normX)) norm]"
                    ],
                    shuntB: normB,
                    seriesX: normX
                ))
            }
        } else {
            // Topology B (series X at load, shunt B toward source)
            // Q = sqrt(z0/RL - 1)
            let Q = (z0/RL - 1.0).squareRoot()
            for sign in [1.0, -1.0] {
                let Xs = sign * Q * RL - XL
                let Bs = sign * Q / z0
                let normB = Bs * z0
                let normX = Xs / z0
                let label = sign > 0 ? "L-net B (Q=+\(String(format:"%.3f",Q)))" : "L-net B (Q=−\(String(format:"%.3f",Q)))"
                sols.append(MatchSolution(
                    label: label,
                    steps: [
                        "Series X = \(fmtX(Xs))  [\(fmtNX(normX)) norm]",
                        "Shunt B = \(fmtB(Bs))  [\(fmtNB(normB)) norm]"
                    ],
                    shuntB: normB,
                    seriesX: normX
                ))
            }
        }
        wizardSolutions = sols
    }

    // MARK: Apply load from tap/drag Γ
    func applyGamma(_ g: Complex) {
        guard g.magnitude < 1.0 else { return }
        let zn = SCE.zFromGamma(g)
        guard zn.re.isFinite, zn.im.isFinite else { return }
        loadR = min(max(zn.re * z0, 0.1), 1000.0)
        loadX = min(max(zn.im * z0, -1000.0), 1000.0)
    }
}

// MARK: - Grid Values

private let rAll: [Double] = [
    0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9,
    1, 1.2, 1.4, 1.6, 1.8, 2, 2.5, 3, 4, 5, 10, 20
]
private let rKey: Set<Double> = [0, 0.2, 0.5, 1, 2, 5]

private let xAll: [Double] = [
    0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9,
    1, 1.2, 1.4, 1.6, 1.8, 2, 2.5, 3, 4, 5, 10, 20
]
private let xKey: Set<Double> = [0.2, 0.5, 1, 2, 5]

// MARK: - Smith Canvas View

struct SmithCanvas: View {
    @ObservedObject var vm: VM

    // Layout state captured during rendering so gestures use consistent coords
    @State private var canvasCenter: CGPoint = .zero
    @State private var canvasRadius: CGFloat = 1.0

    private let zC = Color(red: 0.85, green: 0.42, blue: 0.42)
    private let yC = Color(red: 0.42, green: 0.62, blue: 0.92)
    private let seg: [Color] = [
        Color(red: 0.25, green: 0.52, blue: 1.0),
        Color(red: 0.25, green: 0.52, blue: 1.0),
        Color(red: 0.20, green: 0.80, blue: 0.42)
    ]

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let c    = CGPoint(x: geo.size.width/2, y: geo.size.height/2)
            let r    = side * 0.47

            ZStack {
                Canvas { ctx, size in
                    bg(ctx, c, r)
                    if vm.showY { yGrid(ctx, c, r) }
                    zGrid(ctx, c, r)
                    ring(ctx, c, r)
                    traj(ctx, c, r)
                    sweepTrace(ctx, c, r)
                    markers(ctx, c, r)
                    if let dg = vm.dragGamma {
                        crosshair(ctx, gamma: dg, c: c, r: r)
                    }
                }
                .background(Color(white: 0.04))
                .onAppear {
                    canvasCenter = c
                    canvasRadius = r
                }
                .onChange(of: geo.size) { _ in
                    canvasCenter = c
                    canvasRadius = r
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { val in
                            let g = SCE.gammaFromScreen(val.location, c, r)
                            vm.dragGamma = g
                            vm.applyGamma(g)
                        }
                        .onEnded { val in
                            let g = SCE.gammaFromScreen(val.location, c, r)
                            vm.applyGamma(g)
                            vm.dragGamma = nil
                        }
                )
            }
        }
    }

    // MARK: Crosshair overlay while dragging
    private func crosshair(_ ctx: GraphicsContext, gamma: Complex, c: CGPoint, r: CGFloat) {
        guard gamma.magnitude <= 1.0 else { return }
        let pt = SCE.screen(gamma, c, r)
        let arm: CGFloat = 12
        let col = Color.yellow.opacity(0.85)

        var h = Path()
        h.move(to: CGPoint(x: pt.x - arm, y: pt.y))
        h.addLine(to: CGPoint(x: pt.x + arm, y: pt.y))
        var v = Path()
        v.move(to: CGPoint(x: pt.x, y: pt.y - arm))
        v.addLine(to: CGPoint(x: pt.x, y: pt.y + arm))
        ctx.stroke(h, with: .color(col), lineWidth: 1.2)
        ctx.stroke(v, with: .color(col), lineWidth: 1.2)

        var circle = Path()
        circle.addEllipse(in: CGRect(x: pt.x-5, y: pt.y-5, width: 10, height: 10))
        ctx.stroke(circle, with: .color(col), lineWidth: 1.5)
    }

    // MARK: Frequency sweep trace
    private func sweepTrace(_ ctx: GraphicsContext, _ c: CGPoint, _ r: CGFloat) {
        guard vm.sweepEnabled else { return }
        let pts = vm.sweepPoints(c: c, r: r)
        guard pts.count > 1 else { return }
        var p = Path()
        p.move(to: pts[0])
        pts.dropFirst().forEach { p.addLine(to: $0) }
        ctx.stroke(p, with: .color(Color.orange),
                   style: StrokeStyle(lineWidth: 2.0, dash: [6, 4]))
        // Start/end dots
        var dot0 = Path(); dot0.addEllipse(in: CGRect(x: pts[0].x-4, y: pts[0].y-4, width: 8, height: 8))
        ctx.fill(dot0, with: .color(Color.orange))
        if let last = pts.last {
            var dotN = Path(); dotN.addEllipse(in: CGRect(x: last.x-4, y: last.y-4, width: 8, height: 8))
            ctx.fill(dotN, with: .color(Color.orange.opacity(0.5)))
        }
    }

    // MARK: Background disk + real axis
    private func bg(_ ctx: GraphicsContext, _ c: CGPoint, _ r: CGFloat) {
        var disk = Path(); disk.addEllipse(in: rc(c, r))
        ctx.fill(disk, with: .color(Color(white: 0.04)))
        var ax = Path()
        ax.move(to: CGPoint(x: c.x-r, y: c.y))
        ax.addLine(to: CGPoint(x: c.x+r, y: c.y))
        ctx.stroke(ax, with: .color(.gray.opacity(0.3)), lineWidth: 0.4)
    }

    // MARK: Outer ring + SWR reference circles
    private func ring(_ ctx: GraphicsContext, _ c: CGPoint, _ r: CGFloat) {
        var p = Path(); p.addEllipse(in: rc(c, r))
        ctx.stroke(p, with: .color(Color(white: 0.72)), lineWidth: 1.2)
        for m in [1.0/3, 0.5, 2.0/3] {
            var s = Path(); s.addEllipse(in: rc(c, r * CGFloat(m)))
            ctx.stroke(s, with: .color(Color(white: 0.28)), lineWidth: 0.3)
        }
    }

    // MARK: Z grid
    private func zGrid(_ ctx: GraphicsContext, _ c: CGPoint, _ r: CGFloat) {
        var clip = Path(); clip.addEllipse(in: rc(c, r))
        for rv in rAll {
            let key = rKey.contains(rv)
            let cr  = CGFloat(rv / (rv + 1))
            let rr  = CGFloat(1.0 / (rv + 1))
            var p   = Path()
            p.addEllipse(in: CGRect(x: c.x+(cr-rr)*r, y: c.y-rr*r, width: rr*r*2, height: rr*r*2))
            ctx.stroke(p, with: .color(zC.opacity(key ? 0.70 : 0.28)),
                       lineWidth: key ? 0.65 : 0.30)
        }
        for x in xAll {
            drawXArc(ctx, x:  x, c: c, r: r, clip: clip)
            drawXArc(ctx, x: -x, c: c, r: r, clip: clip)
        }
        for (rv, txt) in [(0.0,"0"),(0.2,"0.2"),(0.5,"0.5"),(1.0,"1"),(2.0,"2"),(5.0,"5")] {
            let gx  = rv == 0 ? -1.0 : (2*rv/(rv+1) - 1.0)
            let pt  = SCE.screen(Complex(gx, 0), c, r)
            let fs  = max(7.0, Double(r) * 0.038)
            ctx.draw(Text(txt).font(.system(size: fs, design: .monospaced))
                        .foregroundColor(.gray.opacity(0.6)),
                     at: CGPoint(x: pt.x, y: pt.y - r*0.04))
        }
    }

    private func drawXArc(_ ctx: GraphicsContext, x: Double, c: CGPoint, r: CGFloat, clip: Path) {
        let key = xKey.contains(abs(x))
        let rr  = CGFloat(abs(1.0 / x))
        let cy  = CGFloat(1.0 / x)
        var arc = Path()
        arc.addEllipse(in: CGRect(
            x: c.x + (1.0 - rr) * r,
            y: c.y - (cy + rr) * r,
            width:  rr * r * 2,
            height: rr * r * 2
        ))
        var ctx2 = ctx; ctx2.clip(to: clip)
        ctx2.stroke(arc, with: .color(zC.opacity(key ? 0.58 : 0.20)),
                    lineWidth: key ? 0.60 : 0.28)
    }

    // MARK: Y grid
    private func yGrid(_ ctx: GraphicsContext, _ c: CGPoint, _ r: CGFloat) {
        var clip = Path(); clip.addEllipse(in: rc(c, r))
        for gv in rAll where gv > 0 {
            let key = rKey.contains(gv)
            let cr  = CGFloat(-gv / (gv + 1))
            let rr  = CGFloat(1.0 / (gv + 1))
            var p   = Path()
            p.addEllipse(in: CGRect(x: c.x+(cr-rr)*r, y: c.y-rr*r, width: rr*r*2, height: rr*r*2))
            ctx.stroke(p, with: .color(yC.opacity(key ? 0.55 : 0.18)),
                       lineWidth: key ? 0.55 : 0.25)
        }
        for b in xAll {
            drawBArc(ctx, b:  b, c: c, r: r, clip: clip)
            drawBArc(ctx, b: -b, c: c, r: r, clip: clip)
        }
    }

    private func drawBArc(_ ctx: GraphicsContext, b: Double, c: CGPoint, r: CGFloat, clip: Path) {
        let key = xKey.contains(abs(b))
        let rr  = CGFloat(abs(1.0 / b))
        let cy  = CGFloat(-1.0 / b)
        var arc = Path()
        arc.addEllipse(in: CGRect(
            x: c.x + (-1.0 - rr) * r,
            y: c.y - (cy + rr) * r,
            width:  rr * r * 2,
            height: rr * r * 2
        ))
        var ctx2 = ctx; ctx2.clip(to: clip)
        ctx2.stroke(arc, with: .color(yC.opacity(key ? 0.42 : 0.14)),
                    lineWidth: key ? 0.52 : 0.25)
    }

    // MARK: Trajectory arcs
    private func traj(_ ctx: GraphicsContext, _ c: CGPoint, _ r: CGFloat) {
        let segs = vm.trajectory(c: c, r: r)
        for (i, s) in segs.enumerated() {
            guard s.count > 1 else { continue }
            var p = Path(); p.move(to: s[0])
            s.dropFirst().forEach { p.addLine(to: $0) }
            let col = seg[min(i, seg.count-1)]
            ctx.stroke(p, with: .color(col),
                       style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            if s.count >= 2 { arrow(ctx, from: s[s.count-2], to: s.last!, col: col) }
        }
    }

    private func arrow(_ ctx: GraphicsContext, from a: CGPoint, to b: CGPoint, col: Color) {
        let dx = b.x-a.x, dy = b.y-a.y
        let l  = (dx*dx+dy*dy).squareRoot(); guard l > 0 else { return }
        let ux = dx/l, uy = dy/l; let s: CGFloat = 9
        var p = Path()
        p.move(to: CGPoint(x: b.x-s*ux+s*0.5*uy, y: b.y-s*uy-s*0.5*ux))
        p.addLine(to: b)
        p.addLine(to: CGPoint(x: b.x-s*ux-s*0.5*uy, y: b.y-s*uy+s*0.5*ux))
        ctx.stroke(p, with: .color(col), lineWidth: 1.8)
    }

    // MARK: Markers ①②③④
    private func markers(_ ctx: GraphicsContext, _ c: CGPoint, _ r: CGFloat) {
        let syms = ["①","②","③","④"]
        let dot  = max(5.0, r * 0.024)
        for m in vm.markers {
            let pt = SCE.screen(m.g, c, r)
            var glow = Path(); glow.addEllipse(in: CGRect(x:pt.x-dot*1.9,y:pt.y-dot*1.9,width:dot*3.8,height:dot*3.8))
            ctx.fill(glow, with: .color(Color.cyan.opacity(0.15)))
            var d = Path(); d.addEllipse(in: CGRect(x:pt.x-dot,y:pt.y-dot,width:dot*2,height:dot*2))
            ctx.fill(d, with: .color(.cyan))
            ctx.stroke(d, with: .color(.white), lineWidth: 1)
            let fs = max(11.0, Double(r) * 0.048)
            ctx.draw(Text(syms[m.idx]).font(.system(size: fs, weight: .bold)).foregroundColor(.cyan),
                     at: CGPoint(x: pt.x+dot*2.4, y: pt.y-dot*1.6))
        }
    }

    private func rc(_ c: CGPoint, _ r: CGFloat) -> CGRect {
        CGRect(x: c.x-r, y: c.y-r, width: r*2, height: r*2)
    }
}

// MARK: - Feature 3: Export / Share

#if canImport(UIKit)
/// UIViewControllerRepresentable wrapper for UIActivityViewController
struct ActivityViewControllerWrapper: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ShareButton: View {
    @ObservedObject var vm: VM
    @State private var showShare = false
    @State private var renderedImage: UIImage? = nil

    var body: some View {
        Button {
            renderAndShare()
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .padding(10)
                .background(Circle().fill(Color(white: 0.15).opacity(0.85)))
        }
        .sheet(isPresented: $showShare) {
            if let img = renderedImage {
                ActivityViewControllerWrapper(image: img)
            }
        }
    }

    private func renderAndShare() {
        let exportVM = vm  // capture reference

        // Build a 1024×1024 canvas for export
        let exportSize = CGSize(width: 1024, height: 1024)
        let renderer  = ImageRenderer(content:
            SmithCanvas(vm: exportVM)
                .frame(width: exportSize.width, height: exportSize.height)
                .preferredColorScheme(.dark)
        )
        renderer.scale = 1.0
        renderer.proposedSize = ProposedViewSize(exportSize)

        if let uiImage = renderer.uiImage {
            renderedImage = uiImage
            showShare = true
        }
    }
}
#endif

// MARK: - Marker Row

struct MarkerRow: View {
    let m: Marker
    private let syms  = ["①","②","③","④"]
    private let names = ["Load ZL","After Shunt B","After Series X","After T-Line"]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text(syms[m.idx]).font(.title3.bold()).foregroundColor(.cyan)
                Text(names[min(m.idx, names.count-1)]).font(.caption.bold()).foregroundColor(.cyan.opacity(0.8))
            }
            row("|Γ|", String(format: "%.4f",  m.g.magnitude))
            row("∠Γ",  String(format: "%.1f°", m.g.angle * 180 / .pi))
            row("Zn",  fmt(m.zn))
            row("Z",   fmt(m.Z) + " Ω")
            row("Yn",  fmt(m.yn))
            row("SWR", m.swr.isInfinite ? "∞" : String(format: "%.2f", m.swr))
        }
        .padding(7)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color(white: 0.13)))
    }

    private func row(_ l: String, _ v: String) -> some View {
        HStack(spacing: 0) {
            Text(l + ": ").font(.system(size: 10, design: .monospaced)).foregroundColor(.gray)
                .frame(width: 34, alignment: .leading)
            Text(v).font(.system(size: 10, design: .monospaced)).foregroundColor(.white)
        }
    }

    private func fmt(_ c: Complex) -> String {
        String(format: "%.3f %@ j%.3f", c.re, c.im >= 0 ? "+" : "−", abs(c.im))
    }
}

// MARK: - Slider Row

struct SliderRow: View {
    let label: String; @Binding var value: Double
    let range: ClosedRange<Double>; let fmt: String
    var color: Color = .cyan
    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(label).font(.system(size: 11, design: .monospaced)).foregroundColor(.gray)
                Spacer()
                Text(String(format: fmt, value)).font(.system(size: 11, design: .monospaced)).foregroundColor(color)
            }
            Slider(value: $value, in: range).tint(color)
        }
    }
}

// MARK: - Matching Solution Card

struct MatchSolutionCard: View {
    let sol: MatchSolution
    let onApply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(sol.label)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.orange)
                Spacer()
                Button("Apply") { onApply() }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.orange))
            }
            ForEach(sol.steps, id: \.self) { step in
                Text(step)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color(white: 0.14)))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.orange.opacity(0.35), lineWidth: 0.8))
    }
}

// MARK: - Controls Panel

struct ControlsPanel: View {
    @ObservedObject var vm: VM
    private let blue  = Color(red: 0.25, green: 0.52, blue: 1.0)
    private let green = Color(red: 0.20, green: 0.80, blue: 0.42)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                // Legend
                HStack(spacing: 14) {
                    dot(blue,  "①→② Shunt B")
                    dot(blue,  "②→③ Series X")
                    dot(green, "③→④ T-Line")
                }.font(.system(size: 10)).foregroundColor(.white.opacity(0.75))
                div()
                // Toggles
                lbl("Display")
                Toggle("Admittance (Y) Grid", isOn: $vm.showY).font(.system(size: 12)).foregroundColor(.white)
                Toggle("T-Line segment ④",   isOn: $vm.showTLine).font(.system(size: 12)).foregroundColor(.white)
                div()
                // Load
                lbl("① Load  (Z₀ = 50 Ω)")
                note("Tap/drag on chart to set load point")
                SliderRow(label: "R (Ω)", value: $vm.loadR, range: 1...500,    fmt: "%.0f Ω")
                SliderRow(label: "X (Ω)", value: $vm.loadX, range: -300...300, fmt: "%.0f Ω")
                div()
                // Shunt B
                lbl("① → ② Shunt Susceptance")
                note("Constant-g arc  •  +B = capacitive shunt")
                SliderRow(label: "ΔB (norm)", value: $vm.shuntB,  range: -5...5, fmt: "%.3f", color: blue)
                div()
                // Series X
                lbl("② → ③ Series Reactance")
                note("Constant-r arc  •  +X = series inductor")
                SliderRow(label: "ΔX (norm)", value: $vm.seriesX, range: -5...5, fmt: "%.3f", color: blue)
                // T-line
                if vm.showTLine {
                    div()
                    lbl("③ → ④ Transmission Line")
                    note("Constant-|Γ| rotation toward generator")
                    SliderRow(label: "θ (°)", value: $vm.tLineDeg, range: 0...360, fmt: "%.1f°", color: green)
                }
                div()

                // MARK: Frequency Sweep section
                HStack {
                    lbl("Frequency Sweep")
                    Spacer()
                    Toggle("", isOn: $vm.sweepEnabled)
                        .labelsHidden()
                        .tint(.orange)
                }
                if vm.sweepEnabled {
                    note("Dashed orange trace shows impedance vs frequency")
                    Picker("Component", selection: $vm.componentType) {
                        ForEach(ComponentType.allCases) { ct in
                            Text(ct.rawValue).tag(ct)
                        }
                    }
                    .pickerStyle(.segmented)
                    .colorMultiply(Color.orange.opacity(0.8))

                    let valLabel: String = (vm.componentType == .seriesL || vm.componentType == .parallelL) ? "Value (nH)" : "Value (pF)"
                    let valRange: ClosedRange<Double> = (vm.componentType == .seriesL || vm.componentType == .parallelL)
                        ? 0.1...1000.0 : 0.1...1000.0
                    SliderRow(label: valLabel, value: $vm.componentValue, range: valRange,
                              fmt: "%.1f", color: .orange)
                    SliderRow(label: "f start (MHz)", value: $vm.freqStart, range: 1...10000,
                              fmt: "%.0f MHz", color: .orange)
                    SliderRow(label: "f end (MHz)",   value: $vm.freqEnd,   range: 1...10000,
                              fmt: "%.0f MHz", color: .orange)
                }
                div()

                // MARK: Matching Wizard section
                HStack {
                    lbl("Matching Wizard")
                    Spacer()
                    Toggle("", isOn: $vm.wizardEnabled)
                        .labelsHidden()
                        .tint(.yellow)
                }
                if vm.wizardEnabled {
                    note("L-network solutions to match load to Z₀=50Ω")
                    Button {
                        vm.computeMatching()
                    } label: {
                        HStack {
                            Image(systemName: "wand.and.stars")
                            Text("Compute Solutions")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.yellow))
                    }

                    ForEach(vm.wizardSolutions) { sol in
                        MatchSolutionCard(sol: sol) {
                            vm.shuntB  = sol.shuntB
                            vm.seriesX = sol.seriesX
                        }
                    }
                }
                div()

                // Readouts
                lbl("Marker Readouts")
                ForEach(vm.markers) { m in MarkerRow(m: m) }
            }
            .padding(12)
        }
        .background(Color(white: 0.09))
    }

    private func dot(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) { Circle().fill(c).frame(width: 8, height: 8); Text(t) }
    }
    @ViewBuilder private func lbl(_ t: String) -> some View {
        Text(t).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundColor(.cyan)
    }
    @ViewBuilder private func note(_ t: String) -> some View {
        Text(t).font(.system(size: 10)).foregroundColor(.gray)
    }
    @ViewBuilder private func div() -> some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
    }
}

// MARK: - Root View

struct ContentView: View {
    @StateObject private var vm = VM()

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height

            if landscape {
                let ctrlW: CGFloat = min(310, geo.size.width * 0.36)
                HStack(spacing: 0) {
                    chartArea(width: geo.size.width - ctrlW, height: geo.size.height)
                    ControlsPanel(vm: vm)
                        .frame(width: ctrlW, height: geo.size.height)
                }
            } else {
                let chartH: CGFloat = geo.size.width
                VStack(spacing: 0) {
                    chartArea(width: geo.size.width, height: chartH)
                    ControlsPanel(vm: vm)
                        .frame(width: geo.size.width,
                               height: max(0, geo.size.height - chartH))
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func chartArea(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            SmithCanvas(vm: vm)
                .frame(width: width, height: height)
            #if canImport(UIKit)
            ShareButton(vm: vm)
                .padding(10)
            #endif
        }
        .frame(width: width, height: height)
    }
}
