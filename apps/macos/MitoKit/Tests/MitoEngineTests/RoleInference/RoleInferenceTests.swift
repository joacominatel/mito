import MitoCore
import MitoTestSupport
import Testing

@testable import MitoEngine

struct RoleInferenceTests {
    private let aatrox = ChampionID(rawValue: 266)
    private let leeSin = ChampionID(rawValue: 64)
    private let ahri = ChampionID(rawValue: 103)
    private let jinx = ChampionID(rawValue: 222)
    private let thresh = ChampionID(rawValue: 412)
    private let newChampion = ChampionID(rawValue: 9_999)

    private func infer(
        _ enemies: [ChampionID],
        taken: Set<Role> = [],
        _ roleGames: [ChampionID: [Role: Int]]
    ) -> [InferredRole] {
        RoleInference.infer(
            enemies: enemies, takenRoles: taken,
            stats: InMemoryStatsProvider(roleGamesByChampion: roleGames))
    }

    private func isClose(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < 1e-9
    }

    @Test func assignsEachChampionItsMainRole() {
        let mains: [(ChampionID, Role)] = [
            (thresh, .utility), (jinx, .bottom), (ahri, .middle), (leeSin, .jungle), (aatrox, .top),
        ]
        let roleGames = Dictionary(
            uniqueKeysWithValues: mains.map { champion, main in
                (
                    champion,
                    Dictionary(
                        uniqueKeysWithValues: Role.allCases.map { ($0, $0 == main ? 900 : 25) })
                )
            })

        let result = infer(mains.map(\.0), roleGames)

        #expect(result.map(\.champion) == mains.map(\.0))
        #expect(result.map(\.role) == mains.map(\.1))
    }

    @Test func resolvesAContestedRoleByTheProductNotByPickOrder() {
        let result = infer(
            [ahri, jinx],
            [ahri: [.middle: 60, .top: 40], jinx: [.middle: 100]])

        #expect(result.map(\.role) == [.top, .middle])
    }

    @Test func fewerThanFiveChampionsSpreadProbabilityOverEveryFreeRole() {
        let result = infer(
            [ahri, jinx],
            [ahri: [.middle: 80, .top: 20], jinx: [.bottom: 90, .middle: 10]])

        #expect(result.map(\.role) == [.middle, .bottom])
        for inferred in result {
            #expect(Set(inferred.roleProbabilities.keys) == Set(Role.allCases))
            #expect(isClose(inferred.roleProbabilities.values.reduce(0, +), 1))
        }
    }

    @Test func neverAssignsARoleAlreadyTaken() {
        let result = infer([ahri], taken: [.middle], [ahri: [.middle: 90, .top: 10]])

        #expect(result.first?.role == .top)
        #expect(result.first?.roleProbabilities.keys.contains(.middle) == false)
    }

    @Test func championWithoutDataGetsAUniformDistributionAndIsFlagged() {
        let result = infer(
            [newChampion, jinx], taken: [.jungle, .utility], [jinx: [.bottom: 100]])

        let unknown = result[0]
        #expect(unknown.isUniformFallback)
        #expect(unknown.role == .top)
        #expect(isClose(unknown.roleConfidence, 0.5))
        #expect(isClose(unknown.roleProbabilities[.top] ?? 0, 0.5))
        #expect(isClose(unknown.roleProbabilities[.middle] ?? 0, 0.5))
        #expect(!result[1].isUniformFallback)
        #expect(result[1].role == .bottom)
    }

    @Test func championWhoseGamesAreAllOnTakenRolesFallsBackToUniform() {
        let result = infer([jinx], taken: [.bottom, .utility], [jinx: [.bottom: 100]])

        #expect(result.first?.isUniformFallback == true)
        #expect(result.first?.role == .top)
        for role in [Role.top, .jungle, .middle] {
            #expect(isClose(result.first?.roleProbabilities[role] ?? 0, 1.0 / 3))
        }
    }

    // Masses: (A top, B mid) = 0.6 * 0.7 = 0.42, (A mid, B top) = 0.4 * 0.3 = 0.12; total 0.54.
    @Test func confidenceIsTheChampionsShareOfAssignmentMass() {
        let result = infer(
            [aatrox, ahri], taken: [.jungle, .bottom, .utility],
            [aatrox: [.top: 60, .middle: 40], ahri: [.top: 30, .middle: 70]])

        #expect(result.map(\.role) == [.top, .middle])
        #expect(isClose(result[0].roleConfidence, 7.0 / 9))
        #expect(isClose(result[1].roleConfidence, 7.0 / 9))
        #expect(isClose(result[0].roleProbabilities[.middle] ?? 0, 2.0 / 9))
        #expect(isClose(result[1].roleProbabilities[.top] ?? 0, 2.0 / 9))
    }

    @Test func gamesOnTakenRolesDoNotChangeTheConfidence() {
        let result = infer(
            [aatrox, ahri], taken: [.jungle, .bottom, .utility],
            [aatrox: [.top: 60, .middle: 40, .jungle: 500], ahri: [.top: 30, .middle: 70]])

        #expect(isClose(result[0].roleConfidence, 7.0 / 9))
    }

    @Test func tiesGoToRoleDeclarationOrderThenChampionOrder() {
        let even: [Role: Int] = [.top: 50, .middle: 50]
        let roleGames = [aatrox: even, ahri: even]
        let taken: Set<Role> = [.jungle, .bottom, .utility]

        let forward = infer([aatrox, ahri], taken: taken, roleGames)
        let reversed = infer([ahri, aatrox], taken: taken, roleGames)

        #expect(forward.map(\.role) == [.top, .middle])
        #expect(reversed.map(\.role) == [.top, .middle])
        #expect(forward == infer([aatrox, ahri], taken: taken, roleGames))
        #expect(isClose(forward[0].roleConfidence, 0.5))
    }

    @Test func surplusEnemiesBeyondTheFreeRolesGoUnassigned() {
        let result = infer(
            [ahri, aatrox], taken: [.jungle, .middle, .bottom, .utility],
            [ahri: [.top: 10, .middle: 90], aatrox: [.top: 100]])

        #expect(result.map(\.role) == [nil, .top])
        #expect(result[0].roleConfidence == 0)
        #expect(isClose(result[0].roleProbabilities[.top] ?? 0, 0.1 / 1.1))
        #expect(isClose(result[1].roleConfidence, 1 / 1.1))
    }

    @Test func everyRoleTakenLeavesEveryEnemyUnassigned() {
        let result = infer([ahri, jinx], taken: Set(Role.allCases), [ahri: [.middle: 90]])

        #expect(result.map(\.role) == [nil, nil])
        #expect(result.allSatisfy { $0.roleProbabilities.isEmpty && $0.roleConfidence == 0 })
    }

    @Test func noEnemiesYieldsAnEmptyResult() {
        #expect(infer([], [ahri: [.middle: 90]]).isEmpty)
    }

    // Smoothed over 5 roles: Jinx bottom 101/105, middle 1/105; Ashe bottom 51/55, middle 1/55.
    @Test func jointlyImpossibleDraftFallsBackToSmoothedCounts() {
        let ashe = ChampionID(rawValue: 22)
        let result = infer(
            [jinx, ashe], taken: [.top, .jungle, .utility],
            [jinx: [.bottom: 100], ashe: [.bottom: 50]])

        #expect(result.map(\.role) == [.bottom, .middle])
        #expect(isClose(result[0].roleConfidence, 101.0 / 152))
        #expect(result.allSatisfy { !$0.isUniformFallback })
    }

    @Test func fiveChampionsAreResolvedByExhaustiveSearchOverEveryPermutation() {
        let champions = [aatrox, leeSin, ahri, jinx, thresh]
        let roleGames = Dictionary(
            uniqueKeysWithValues: champions.enumerated().map { offset, champion in
                (
                    champion,
                    Dictionary(
                        uniqueKeysWithValues: Role.allCases.enumerated().map { index, role in
                            (role, 10 + (offset * 7 + index * 13) % 40)
                        })
                )
            })

        let result = infer(champions, roleGames)

        #expect(Set(result.compactMap(\.role)) == Set(Role.allCases))
        for inferred in result {
            #expect(isClose(inferred.roleProbabilities.values.reduce(0, +), 1))
        }
        for role in Role.allCases {
            #expect(isClose(result.map { $0.roleProbabilities[role] ?? 0 }.reduce(0, +), 1))
        }
    }
}
