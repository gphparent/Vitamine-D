import Foundation
import Testing
@testable import VitamineD

struct SleepRoutineTests {

    private func profile(wake: Int, sleepHours: Double = 8) -> UserProfile {
        var profile = UserProfile.default
        profile.targetWakeMinuteOfDay = wake
        profile.sleepHours = sleepHours
        return profile
    }

    @Test("Le coucher se déduit du lever visé et de la durée souhaitée")
    func bedtimeFollowsFromWakeAndDuration() {
        let routine = SleepRoutine.make(profile: profile(wake: 7 * 60, sleepHours: 8))
        #expect(routine.wakeMinuteOfDay == 7 * 60)
        #expect(routine.bedtimeMinuteOfDay == 23 * 60)
    }

    @Test("Un coucher qui traverse minuit reste une heure d'horloge valable")
    func bedtimeWrapsAroundMidnight() {
        // Lever à 5 h, sept heures de sommeil : coucher à 22 h la veille.
        let early = SleepRoutine.make(profile: profile(wake: 5 * 60, sleepHours: 7))
        #expect(early.bedtimeMinuteOfDay == 22 * 60)

        // Lever à 9 h, six heures : coucher à 3 h du matin.
        let late = SleepRoutine.make(profile: profile(wake: 9 * 60, sleepHours: 6))
        #expect(late.bedtimeMinuteOfDay == 3 * 60)
    }

    @Test("Toutes les étapes tombent dans une journée d'horloge")
    func everyStepIsAValidClockTime() {
        for wake in stride(from: 0, to: 1440, by: 37) {
            for hours in [5.0, 6.5, 8.0, 10.0] {
                let routine = SleepRoutine.make(profile: profile(wake: wake, sleepHours: hours))
                #expect(routine.entries.count == SleepRoutineStep.allCases.count)
                let valid = routine.entries.allSatisfy {
                    (0..<1440).contains($0.minuteOfDay)
                }
                #expect(valid)
            }
        }
    }

    @Test("Les heures du soir se placent où la recherche les met")
    func eveningStepsSitWhereTheEvidenceSaysSo() throws {
        // Coucher à 23 h.
        let routine = SleepRoutine.make(profile: profile(wake: 7 * 60, sleepHours: 8))

        #expect(try #require(routine.minute(of: .caffeineCutoff)) == 15 * 60)
        #expect(try #require(routine.minute(of: .lastMeal)) == 20 * 60)
        #expect(try #require(routine.minute(of: .dimLights)) == 20 * 60 + 30)
        #expect(try #require(routine.minute(of: .warmBath)) == 21 * 60 + 30)
        #expect(try #require(routine.minute(of: .screensOff)) == 22 * 60)
        #expect(try #require(routine.minute(of: .bedtime)) == 23 * 60)
        #expect(try #require(routine.minute(of: .wake)) == 7 * 60)
        #expect(try #require(routine.minute(of: .morningLight)) == 7 * 60 + 15)
    }

    @Test("La pénombre tombe à la même heure que la carte du soir")
    func dimLightAgreesWithTheEveningCard() throws {
        // Deux chiffres qui se contrediraient seraient pires qu'un seul : la
        // routine et la carte du soir doivent lire la même constante.
        let subject = profile(wake: 6 * 60 + 30, sleepHours: 7.5)
        let routine = SleepRoutine.make(profile: subject)
        let plan = CircadianPlanner.phaseShift(current: subject.wakeMinuteOfDay,
                                               target: subject.targetWakeMinuteOfDay,
                                               sleepDuration: subject.sleepHours)

        #expect(try #require(routine.minute(of: .dimLights)) == plan.dimLightMinuteOfDay)
    }

    @Test("La liste se lit du premier rappel du soir au matin")
    func entriesReadForwardFromTheEvening() throws {
        let routine = SleepRoutine.make(profile: profile(wake: 7 * 60, sleepHours: 8))
        let order = routine.entries.map(\.step)

        let caffeine = try #require(order.firstIndex(of: .caffeineCutoff))
        let bedtime = try #require(order.firstIndex(of: .bedtime))
        let wake = try #require(order.firstIndex(of: .wake))
        let light = try #require(order.firstIndex(of: .morningLight))

        #expect(caffeine == 0)
        #expect(caffeine < bedtime)
        #expect(bedtime < wake)
        #expect(wake < light)
    }

    @Test("Chaque étape porte une raison et une force de preuve")
    func everyStepIsJustified() {
        for step in SleepRoutineStep.allCases {
            #expect(!step.title.isEmpty)
            #expect(!step.summary.isEmpty)
            #expect(!step.notificationBody.isEmpty)
            // Une justification d'une ligne serait un slogan, pas une raison.
            #expect(step.rationale.count > 200)
        }
    }

    @Test("Les rappels enregistrés survivent à un aller-retour d'encodage")
    func remindersRoundTripThroughStorage() throws {
        var subject = UserProfile.default
        subject.sleepReminders = [SleepRoutineStep.warmBath.rawValue,
                                  SleepRoutineStep.bedtime.rawValue]

        let data = try JSONEncoder().encode(subject)
        let restored = try JSONDecoder().decode(UserProfile.self, from: data)
        #expect(restored.sleepReminders == subject.sleepReminders)
    }

    @Test("Un profil enregistré sans rappels se relit sans en inventer")
    func legacyProfileHasNoReminders() throws {
        let json = #"{"skinType": 3, "age": 40}"#.data(using: .utf8)!
        let restored = try JSONDecoder().decode(UserProfile.self, from: json)
        #expect(restored.sleepReminders.isEmpty)
    }
}
