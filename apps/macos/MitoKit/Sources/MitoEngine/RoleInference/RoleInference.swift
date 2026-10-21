public import MitoCore

public struct InferredRole: Hashable, Sendable {
    public let champion: ChampionID
    /// `nil` only when there are more enemies than free roles.
    public let role: Role?
    /// Mass of the assignments giving this champion `role` over all valid assignments.
    public let roleConfidence: Double
    /// Marginal probability of each free role across all valid assignments.
    public let roleProbabilities: [Role: Double]
    /// No games on any free role, so the distribution was uniform: treat `role` as low confidence.
    public let isUniformFallback: Bool
}

/// Enemy role inference; tie-break, overflow, and fallback rules are in `MITO_CONTEXT.md` §12.3.
public enum RoleInference {
    public static func infer(
        enemies: [ChampionID],
        takenRoles: Set<Role> = [],
        stats: some StatsProvider
    ) -> [InferredRole] {
        let freeRoles = Role.allCases.filter { !takenRoles.contains($0) }
        let games = enemies.map { stats.roleGames(for: $0) }
        let candidates = assignments(champions: enemies.count, roles: freeRoles.count)
        guard !candidates.isEmpty else { return [] }

        var probabilities = games.map { distribution($0, over: freeRoles, pseudocount: 0) }
        var masses = candidates.map { mass(of: $0, probabilities) }
        if !masses.contains(where: { $0 > 0 }) {
            probabilities = games.map { distribution($0, over: freeRoles, pseudocount: 1) }
            masses = candidates.map { mass(of: $0, probabilities) }
        }

        var bestIndex = 0
        for index in masses.indices where masses[index] > masses[bestIndex] {
            bestIndex = index
        }
        let best = candidates[bestIndex]
        let total = masses.reduce(0, +)

        return enemies.indices.map { champion in
            var marginals = Array(repeating: 0.0, count: freeRoles.count)
            for (assignment, mass) in zip(candidates, masses) {
                if let role = assignment[champion] { marginals[role] += mass / total }
            }
            return InferredRole(
                champion: enemies[champion],
                role: best[champion].map { freeRoles[$0] },
                roleConfidence: best[champion].map { marginals[$0] } ?? 0,
                roleProbabilities: Dictionary(uniqueKeysWithValues: zip(freeRoles, marginals)),
                isUniformFallback: !freeRoles.contains { games[champion][$0, default: 0] > 0 }
            )
        }
    }

    private static func distribution(
        _ games: [Role: Int], over roles: [Role], pseudocount: Int
    ) -> [Double] {
        let counts = roles.map { games[$0, default: 0] + pseudocount }
        guard counts.contains(where: { $0 > 0 }) else {
            return Array(repeating: 1 / Double(roles.count), count: roles.count)
        }
        let total = games.values.reduce(0, +) + pseudocount * Role.allCases.count
        return counts.map { Double($0) / Double(total) }
    }

    private static func mass(of assignment: [Int?], _ probabilities: [[Double]]) -> Double {
        zip(assignment, probabilities).reduce(1) { product, pair in
            product * (pair.0.map { pair.1[$0] } ?? 1)
        }
    }

    /// Enumeration order is the tie-break order; `nil` leaves a champion out when roles run short.
    private static func assignments(champions: Int, roles: Int) -> [[Int?]] {
        guard champions > 0 else { return [] }
        var result: [[Int?]] = []
        var current: [Int?] = []
        var used = Array(repeating: false, count: roles)

        func extend(unassignedLeft: Int) {
            guard current.count < champions else {
                result.append(current)
                return
            }
            for role in 0..<roles where !used[role] {
                used[role] = true
                current.append(role)
                extend(unassignedLeft: unassignedLeft)
                current.removeLast()
                used[role] = false
            }
            if unassignedLeft > 0 {
                current.append(nil)
                extend(unassignedLeft: unassignedLeft - 1)
                current.removeLast()
            }
        }

        extend(unassignedLeft: max(0, champions - roles))
        return result
    }
}
