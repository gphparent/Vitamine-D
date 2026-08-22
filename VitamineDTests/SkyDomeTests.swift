import Foundation
import Testing
@testable import VitamineD

/// La géométrie de la coupole. Une `View` ne se teste pas, mais un vecteur
/// solaire et une caméra, si — et c'est là que se cachent les erreurs de signe
/// qui font tourner un Soleil à l'envers sans rien faire planter.
struct SkyDomeTests {

    /// Déclinaison approchée, comme celle qu'emploie le dessin.
    private func declination(_ dayOfYear: Double) -> Double {
        -23.44 * cos(2 * .pi * (dayOfYear + 10) / 365.25)
    }

    private func elevation(day: Double, minute: Double, latitude: Double) -> Double {
        let v = SolarGeometry.vector(declination: declination(day),
                                     hourAngle: minute / 4 - 180,
                                     latitude: latitude)
        return asin(max(-1, min(1, v.up))) / .pi * 180
    }

    // MARK: - Le Soleil est-il au bon endroit

    @Test("Les hauteurs de culmination sont celles de l'astronomie")
    func culminationsMatchAstronomy() {
        // Montréal : 90 − latitude ± déclinaison. Les trois dates de contrôle
        // sont vérifiables de tête, ce qui est précisément leur intérêt.
        #expect(abs(elevation(day: 172, minute: 720, latitude: 45.5) - 68) < 1.5)
        #expect(abs(elevation(day: 355, minute: 720, latitude: 45.5) - 21) < 1.5)
        #expect(abs(elevation(day: 80, minute: 720, latitude: 45.5) - 44.5) < 1.5)
        #expect(abs(elevation(day: 172, minute: 720, latitude: 0) - 66.5) < 1.5)
    }

    @Test("Le Soleil se lève à l'est et passe au sud dans l'hémisphère nord")
    func theSunRisesInTheEast() {
        let morning = SolarGeometry.vector(declination: declination(172),
                                           hourAngle: 480 / 4 - 180, latitude: 45.5)
        let evening = SolarGeometry.vector(declination: declination(172),
                                           hourAngle: 960 / 4 - 180, latitude: 45.5)
        #expect(morning.east > 0)
        #expect(evening.east < 0)

        // À midi solaire, plein sud au nord de l'équateur, plein nord au sud.
        let north = SolarGeometry.vector(declination: declination(172),
                                         hourAngle: 0, latitude: 45.5)
        let south = SolarGeometry.vector(declination: declination(355),
                                         hourAngle: 0, latitude: -33)
        #expect(north.north < 0)
        #expect(south.north > 0)
        #expect(abs(north.east) < 1e-9)
    }

    @Test("Sous la nuit polaire, le Soleil ne se lève jamais")
    func thePolarNightHasNoSun() {
        for minute in stride(from: 0.0, through: 1440.0, by: 30) {
            #expect(elevation(day: 355, minute: minute, latitude: 70) <= 0)
        }
        // Et six mois plus tard il ne se couche pas.
        for minute in stride(from: 0.0, through: 1440.0, by: 30) {
            #expect(elevation(day: 172, minute: minute, latitude: 70) > 0)
        }
    }

    @Test("Le vecteur solaire est unitaire")
    func theSolarVectorIsNormalised() {
        for day in stride(from: 1.0, through: 365.0, by: 29) {
            for minute in stride(from: 0.0, through: 1440.0, by: 120) {
                let v = SolarGeometry.vector(declination: declination(day),
                                             hourAngle: minute / 4 - 180,
                                             latitude: 45.5)
                let norm = sqrt(v.east * v.east + v.north * v.north + v.up * v.up)
                #expect(abs(norm - 1) < 1e-9)
            }
        }
    }

    // MARK: - La caméra

    @Test("La base de la caméra est orthonormée")
    func theCameraBasisIsOrthonormal() {
        for latitude in [-60.0, -33, 0, 45.5, 70] {
            let camera = DomeCamera(latitude: latitude)
            func norm(_ v: SolarGeometry.Vector) -> Double {
                sqrt(v.east * v.east + v.north * v.north + v.up * v.up)
            }
            func dot(_ a: SolarGeometry.Vector, _ b: SolarGeometry.Vector) -> Double {
                a.east * b.east + a.north * b.north + a.up * b.up
            }
            #expect(abs(norm(camera.forward) - 1) < 1e-9)
            #expect(abs(norm(camera.right) - 1) < 1e-9)
            #expect(abs(norm(camera.up) - 1) < 1e-9)
            #expect(abs(dot(camera.forward, camera.right)) < 1e-9)
            #expect(abs(dot(camera.forward, camera.up)) < 1e-9)
            #expect(abs(dot(camera.right, camera.up)) < 1e-9)
        }
    }

    @Test("La perspective est réelle : le lointain est plus petit que le proche")
    func theProjectionIsPerspective() throws {
        // C'est ce qui distingue cette vue d'un schéma technique. En
        // axonométrie, ce rapport vaudrait exactement un.
        let camera = DomeCamera(latitude: 45.5)
        let near = try #require(camera.project(SolarGeometry.horizon(azimuth: 40)))
        let far = try #require(camera.project(SolarGeometry.horizon(azimuth: 220)))
        let spanNear = abs(near.x) + abs(near.y)
        let spanFar = abs(far.x) + abs(far.y)
        #expect(spanNear > spanFar)
    }

    @Test("L'horizon se projette en une ellipse aussi écrasée que voulu")
    func theHorizonIsFlattenedAsIntended() throws {
        // 0,31 : la valeur relevée sur la référence visuelle. Une caméra plus
        // haute rendrait l'anneau presque circulaire et l'on perdrait la
        // sensation de se tenir dessous.
        let camera = DomeCamera(latitude: 45.5)
        let points = stride(from: 0.0, to: 360.0, by: 5).compactMap {
            camera.project(SolarGeometry.horizon(azimuth: $0))
        }
        let xs = points.map(\.x), ys = points.map(\.y)
        let width = try #require(xs.max()) - (try #require(xs.min()))
        let height = try #require(ys.max()) - (try #require(ys.min()))
        #expect(abs(height / width - 0.31) < 0.03)
    }

    @Test("La culmination se détache du bord lointain de l'horizon")
    func thePeakClearsTheHorizonRing() throws {
        // La raison d'être de la caméra de biais. Dans l'axe du méridien, ce
        // dégagement tomberait à presque rien et l'angle deviendrait
        // impossible à lire — c'était le défaut signalé.
        for (latitude, day, minimum) in [(45.5, 172.0, 0.20), (45.5, 355.0, 0.05),
                                         (-33.0, 355.0, 0.20), (0.0, 172.0, 0.20)] {
            let camera = DomeCamera(latitude: latitude)
            let peak = stride(from: 0.0, through: 1440.0, by: 4)
                .map { elevation(day: day, minute: $0, latitude: latitude) }
                .max() ?? 0
            let top = try #require(camera.project(
                SolarGeometry.meridian(elevation: peak, latitude: latitude)))
            let edge = try #require(camera.project(
                SolarGeometry.horizon(azimuth: latitude >= 0 ? 180 : 0)))
            #expect(top.y - edge.y > minimum)
        }
    }

    @Test("Toute la coupole reste devant l'objectif")
    func nothingFallsBehindTheCamera() {
        for latitude in [-60.0, 0, 45.5, 70] {
            let camera = DomeCamera(latitude: latitude)
            for elevation in stride(from: 0.0, through: 90.0, by: 15) {
                for azimuth in stride(from: 0.0, to: 360.0, by: 15) {
                    let c = cos(elevation * .pi / 180)
                    let v = SolarGeometry.Vector(
                        east: sin(azimuth * .pi / 180) * c,
                        north: cos(azimuth * .pi / 180) * c,
                        up: sin(elevation * .pi / 180))
                    #expect(camera.project(v) != nil)
                }
            }
        }
    }

    @Test("La caméra bascule de l'autre côté sous l'équateur")
    func theCameraFollowsTheHemisphere() {
        // Sans quoi l'arc du jour passerait derrière l'objectif.
        #expect(DomeCamera(latitude: 45.5).position.north > 0)
        #expect(DomeCamera(latitude: -33).position.north < 0)
    }
}
