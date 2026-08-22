import SwiftUI

/// Géométrie céleste locale, en repère est-nord-haut.
///
/// Passer par un vecteur plutôt que par un azimut en degrés n'est pas une
/// coquetterie : les conventions d'azimut diffèrent d'un ouvrage à l'autre — du
/// nord ou du sud, dans un sens ou dans l'autre — et une erreur de signe fait
/// tourner un Soleil à l'envers sans que rien ne plante. Un vecteur ne se
/// trompe pas de sens : l'est est l'est.
enum SolarGeometry {

    struct Vector: Equatable, Sendable {
        var east: Double
        var north: Double
        var up: Double
    }

    /// Direction du Soleil pour une déclinaison, un angle horaire et une
    /// latitude donnés. L'angle horaire vaut zéro au midi solaire, et il est
    /// négatif le matin.
    static func vector(declination: Double, hourAngle: Double, latitude: Double) -> Vector {
        let d = declination * .pi / 180
        let h = hourAngle * .pi / 180
        let f = latitude * .pi / 180
        return Vector(
            east: -cos(d) * sin(h),
            north: cos(f) * sin(d) - sin(f) * cos(d) * cos(h),
            up: sin(f) * sin(d) + cos(f) * cos(d) * cos(h))
    }

    /// Point du plan méridien, à une hauteur et une distance données.
    ///
    /// Le plan vertical nord-sud est celui où le Soleil passe à son plus haut.
    /// Y dresser une graduation donne un rapporteur posé exactement là où
    /// l'angle qu'on veut lire se produit.
    static func meridian(elevation: Double, latitude: Double, radius: Double = 1) -> Vector {
        let h = elevation * .pi / 180
        let side: Double = latitude >= 0 ? -1 : 1
        return Vector(east: 0, north: side * cos(h) * radius, up: sin(h) * radius)
    }

    static func horizon(azimuth: Double, radius: Double = 1) -> Vector {
        let a = azimuth * .pi / 180
        return Vector(east: sin(a) * radius, north: cos(a) * radius, up: 0)
    }
}

/// Caméra en perspective, posée bas et de biais.
///
/// Une axonométrie — le lointain de la même taille que le proche — se lit comme
/// un schéma technique. Une perspective se lit comme un objet : l'œil replace
/// le plan du sol tout seul. La différence n'est pas décorative, c'est ce qui
/// rend la coupole compréhensible sans légende.
///
/// Les trois réglages sont mesurés, pas choisis au jugé. À dix-sept degrés de
/// hauteur et trois rayons de distance, le cercle d'horizon se projette en une
/// ellipse dont la hauteur fait 0,31 fois la largeur, et son bord lointain se
/// voit 1,9 fois plus petit que le bord proche. Placée de biais — quarante
/// degrés à côté du méridien — la caméra détache la culmination du bord de
/// l'horizon, ce qu'une vue dans l'axe rendait impossible.
struct DomeCamera {
    static let pitch = 17.0
    static let distance = 3.1
    static let offset = 40.0

    let position: SolarGeometry.Vector
    let forward: SolarGeometry.Vector
    let right: SolarGeometry.Vector
    let up: SolarGeometry.Vector

    /// La caméra se place du côté opposé à la course du Soleil : au nord dans
    /// l'hémisphère nord, au sud dans l'autre. Sans quoi, sous l'équateur,
    /// l'arc passerait derrière l'objectif.
    init(latitude: Double) {
        let azimuth = ((latitude >= 0 ? 0.0 : 180.0) + Self.offset) * .pi / 180
        let pitch = Self.pitch * .pi / 180
        let camera = SolarGeometry.Vector(
            east: sin(azimuth) * cos(pitch) * Self.distance,
            north: cos(azimuth) * cos(pitch) * Self.distance,
            up: sin(pitch) * Self.distance)

        let target = SolarGeometry.Vector(east: 0, north: 0, up: 0.18)
        var f = SolarGeometry.Vector(east: target.east - camera.east,
                                     north: target.north - camera.north,
                                     up: target.up - camera.up)
        let length = max(1e-9, sqrt(f.east * f.east + f.north * f.north + f.up * f.up))
        f = SolarGeometry.Vector(east: f.east / length, north: f.north / length, up: f.up / length)

        // Droite = avant ∧ verticale, à plat ; haut = droite ∧ avant.
        var r = SolarGeometry.Vector(east: f.north, north: -f.east, up: 0)
        let rl = max(1e-9, sqrt(r.east * r.east + r.north * r.north))
        r = SolarGeometry.Vector(east: r.east / rl, north: r.north / rl, up: 0)

        self.position = camera
        self.forward = f
        self.right = r
        self.up = SolarGeometry.Vector(
            east: r.north * f.up - r.up * f.north,
            north: r.up * f.east - r.east * f.up,
            up: r.east * f.north - r.north * f.east)
    }

    /// Coordonnées sur le plan image, avant mise à l'échelle. `nil` pour ce qui
    /// passerait derrière l'objectif.
    func project(_ v: SolarGeometry.Vector) -> CGPoint? {
        let d = SolarGeometry.Vector(east: v.east - position.east,
                                     north: v.north - position.north,
                                     up: v.up - position.up)
        let z = d.east * forward.east + d.north * forward.north + d.up * forward.up
        guard z > 0.05 else { return nil }
        return CGPoint(
            x: (d.east * right.east + d.north * right.north + d.up * right.up) / z,
            y: (d.east * up.east + d.north * up.north + d.up * up.up) / z)
    }
}

/// Le dessin de la coupole.
///
/// Séparé de la vue pour une raison simple : c'est de la géométrie, et la
/// géométrie se vérifie. Une `View` SwiftUI ne se teste pas ; un projecteur et
/// un cadreur, si.
struct SkyDome {

    let latitude: Double
    let declination: Double
    let minuteOfDay: Double

    /// Un point de la course du jour.
    private struct Step {
        let minute: Double
        let vector: SolarGeometry.Vector
        let elevation: Double
        let arrival: AtmosphericSpectrum.Arrival
    }

    private var camera: DomeCamera { DomeCamera(latitude: latitude) }

    /// La course entière, échantillonnée toutes les quatre minutes.
    private var path: [Step] {
        stride(from: 0.0, through: 1440.0, by: 4).map { minute in
            let v = SolarGeometry.vector(declination: declination,
                                         hourAngle: minute / 4 - 180,
                                         latitude: latitude)
            let elevation = asin(max(-1, min(1, v.up))) / .pi * 180
            return Step(minute: minute, vector: v, elevation: elevation,
                        arrival: elevation > 0
                            ? AtmosphericSpectrum.relativeToZenith(solarElevation: elevation)
                            : .zero)
        }
    }

    /// Mise à l'échelle automatique.
    ///
    /// L'ampleur de l'arc change énormément entre un solstice tropical et un
    /// hiver nordique. Un facteur figé laisserait tantôt du vide, tantôt du
    /// hors-champ ; le cadrage se recalcule donc à chaque dessin.
    private func fitter(_ points: [CGPoint], size: CGSize,
                        padding: CGFloat) -> ((CGPoint) -> CGPoint)? {
        guard !points.isEmpty else { return nil }
        let xs = points.map(\.x), ys = points.map(\.y)
        guard let x0 = xs.min(), let x1 = xs.max(),
              let y0 = ys.min(), let y1 = ys.max() else { return nil }
        let scale = min((size.width - 2 * padding) / max(x1 - x0, 1e-6),
                        (size.height - 2 * padding) / max(y1 - y0, 1e-6))
        let ox = size.width / 2 - scale * (x0 + x1) / 2
        let oy = size.height / 2 + scale * (y0 + y1) / 2
        return { CGPoint(x: ox + scale * $0.x, y: oy - scale * $0.y) }
    }

    func draw(in context: GraphicsContext, size: CGSize) {
        let camera = self.camera
        let path = self.path

        var frameable: [CGPoint] = []
        for azimuth in stride(from: 0.0, to: 360.0, by: 10) {
            if let q = camera.project(SolarGeometry.horizon(azimuth: azimuth, radius: 1.14)) {
                frameable.append(q)
            }
        }
        for h in stride(from: 0.0, through: 90.0, by: 10) {
            if let q = camera.project(SolarGeometry.meridian(
                elevation: h, latitude: latitude, radius: 1.18)) { frameable.append(q) }
        }
        for step in path where step.vector.up > -0.35 {
            if let q = camera.project(step.vector) { frameable.append(q) }
        }
        guard let fit = fitter(frameable, size: size, padding: 26) else { return }
        func place(_ v: SolarGeometry.Vector) -> CGPoint? { camera.project(v).map(fit) }

        drawGround(context, place: place)
        drawProtractor(context, place: place)
        drawNight(context, path: path, place: place)
        drawRibbons(context, path: path, place: place)
        drawPeak(context, path: path, place: place)
        drawSun(context, path: path, place: place)
    }

    private func drawGround(_ context: GraphicsContext,
                            place: (SolarGeometry.Vector) -> CGPoint?) {
        var disc = Path()
        var started = false
        for azimuth in stride(from: 0.0, through: 360.0, by: 4) {
            guard let q = place(SolarGeometry.horizon(azimuth: azimuth)) else { continue }
            started ? disc.addLine(to: q) : disc.move(to: q)
            started = true
        }
        disc.closeSubpath()
        context.fill(disc, with: .color(.black.opacity(0.30)))
        context.stroke(disc, with: .color(.white.opacity(0.30)), lineWidth: 1.5)

        // Graduations d'azimut, et les points cardinaux en or.
        for azimuth in stride(from: 0.0, to: 360.0, by: 15) {
            guard let a = place(SolarGeometry.horizon(azimuth: azimuth)),
                  let b = place(SolarGeometry.horizon(azimuth: azimuth, radius: 1.10))
            else { continue }
            var tick = Path(); tick.move(to: a); tick.addLine(to: b)
            let major = azimuth.truncatingRemainder(dividingBy: 90) == 0
            context.stroke(tick, with: .color(.white.opacity(major ? 0.55 : 0.20)),
                           lineWidth: major ? 2 : 1)
            guard major, let label = place(
                SolarGeometry.horizon(azimuth: azimuth, radius: 1.26)) else { continue }
            let name = ["N", "E", "S", "O"][Int(azimuth / 90)]
            context.draw(Text(name).font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.gold), at: label)
        }
    }

    /// Le rapporteur dressé dans le plan du midi.
    private func drawProtractor(_ context: GraphicsContext,
                                place: (SolarGeometry.Vector) -> CGPoint?) {
        var arc = Path()
        var started = false
        for h in stride(from: 0.0, through: 90.0, by: 2) {
            guard let q = place(SolarGeometry.meridian(elevation: h, latitude: latitude))
            else { continue }
            started ? arc.addLine(to: q) : arc.move(to: q)
            started = true
        }
        context.stroke(arc, with: .color(.white.opacity(0.32)), lineWidth: 1.5)

        for h in [15.0, 30, 45, 60, 75, 90] {
            let isRule = h == 45
            guard let a = place(SolarGeometry.meridian(elevation: h, latitude: latitude)),
                  let b = place(SolarGeometry.meridian(elevation: h, latitude: latitude,
                                                       radius: isRule ? 1.11 : 1.06))
            else { continue }
            var tick = Path(); tick.move(to: a); tick.addLine(to: b)
            context.stroke(tick,
                           with: .color(isRule ? Theme.gold : .white.opacity(0.42)),
                           lineWidth: isRule ? 2.5 : 1.5)
            guard let label = place(SolarGeometry.meridian(
                elevation: h, latitude: latitude, radius: 1.21)) else { continue }
            context.draw(
                Text("\(Int(h))°")
                    .font(isRule ? .caption2.weight(.semibold) : .caption2)
                    .foregroundStyle(isRule ? Theme.gold : .white.opacity(0.55)),
                at: label)
        }
    }

    private func drawNight(_ context: GraphicsContext, path: [Step],
                           place: (SolarGeometry.Vector) -> CGPoint?) {
        var night = Path()
        var started = false
        for step in path {
            guard step.elevation <= 0, let q = place(step.vector) else { started = false; continue }
            started ? night.addLine(to: q) : night.move(to: q)
            started = true
        }
        context.stroke(night, with: .color(.white.opacity(0.26)),
                       style: StrokeStyle(lineWidth: 1.5, dash: [4, 6]))
    }

    /// Les deux rubans. C'est ici que se joue tout l'écran.
    private func drawRibbons(_ context: GraphicsContext, path: [Step],
                             place: (SolarGeometry.Vector) -> CGPoint?) {
        func ribbon(_ key: KeyPath<AtmosphericSpectrum.Arrival, Double>,
                    _ colour: Color, _ offset: CGFloat) {
            for index in 1..<path.count {
                let a = path[index - 1], b = path[index]
                guard a.elevation > 0, b.elevation > 0,
                      let p0 = place(a.vector), let p1 = place(b.vector) else { continue }
                let share = (a.arrival[keyPath: key] + b.arrival[keyPath: key]) / 2
                guard share > 0.002 else { continue }
                let dx = p1.x - p0.x, dy = p1.y - p0.y
                let length = max(1e-6, sqrt(dx * dx + dy * dy))
                let ox = -dy / length * offset, oy = dx / length * offset
                var segment = Path()
                segment.move(to: CGPoint(x: p0.x + ox, y: p0.y + oy))
                segment.addLine(to: CGPoint(x: p1.x + ox, y: p1.y + oy))
                context.stroke(segment,
                               with: .color(colour.opacity(0.25 + 0.75 * share)),
                               style: StrokeStyle(lineWidth: 5 * (0.45 + 0.55 * share),
                                                  lineCap: .round))
            }
        }
        ribbon(\.uva, Theme.uvaColour, -5)
        ribbon(\.uvb, Theme.uvbColour, 5)
    }

    /// La culmination, chiffrée. C'est elle qui décide de la journée : un hiver
    /// vitaminique n'est rien d'autre que cette valeur passée sous trente degrés.
    private func drawPeak(_ context: GraphicsContext, path: [Step],
                          place: (SolarGeometry.Vector) -> CGPoint?) {
        guard let peak = path.max(by: { $0.elevation < $1.elevation }),
              peak.elevation > 0, let q = place(peak.vector) else { return }

        if let foot = place(SolarGeometry.Vector(east: peak.vector.east,
                                                 north: peak.vector.north, up: 0)) {
            var drop = Path(); drop.move(to: q); drop.addLine(to: foot)
            context.stroke(drop, with: .color(.white.opacity(0.38)),
                           style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        }
        context.fill(Path(ellipseIn: CGRect(x: q.x - 3.5, y: q.y - 3.5, width: 7, height: 7)),
                     with: .color(.white.opacity(0.9)))
        context.draw(
            Text("max \(Format.degrees(peak.elevation))")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white),
            at: CGPoint(x: q.x, y: q.y - 14))
    }

    private func drawSun(_ context: GraphicsContext, path: [Step],
                         place: (SolarGeometry.Vector) -> CGPoint?) {
        let vector = SolarGeometry.vector(declination: declination,
                                          hourAngle: minuteOfDay / 4 - 180,
                                          latitude: latitude)
        let elevation = asin(max(-1, min(1, vector.up))) / .pi * 180
        guard elevation > 0, let q = place(vector) else { return }

        context.fill(Path(ellipseIn: CGRect(x: q.x - 16, y: q.y - 16, width: 32, height: 32)),
                     with: .color(Theme.vitaminD.opacity(0.22)))
        context.fill(Path(ellipseIn: CGRect(x: q.x - 8, y: q.y - 8, width: 16, height: 16)),
                     with: .color(Theme.vitaminD))
    }
}
