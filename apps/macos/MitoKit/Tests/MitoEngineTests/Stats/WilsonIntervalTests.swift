import Testing

@testable import MitoEngine

struct WilsonIntervalTests {
    @Test func evenSampleMatchesTheNinetyPercentReference() {
        // z = 1.6448536, z²/n = 0.0270554, center = (0.5 + 0.0135277) / 1.0270554 = 0.5,
        // half = z · √(0.0025 + 0.0000676) / 1.0270554 = 0.0811522.
        let interval = WilsonInterval(wins: 50, games: 100)

        #expect(isClose(interval.lower, 0.41884779611252954, within: wilsonTolerance))
        #expect(isClose(interval.upper, 0.5811522038874705, within: wilsonTolerance))
    }

    @Test func skewedSampleMatchesTheNinetyPercentReference() {
        let interval = WilsonInterval(wins: 81, games: 263)

        #expect(isClose(interval.lower, 0.2633136171884814, within: wilsonTolerance))
        #expect(isClose(interval.upper, 0.35656634960848815, within: wilsonTolerance))
    }

    @Test func largeSampleIsTightAroundTheRawRate() {
        let interval = WilsonInterval(wins: 523, games: 1_000)

        #expect(isClose(interval.lower, 0.4969930509152687, within: wilsonTolerance))
        #expect(isClose(interval.upper, 0.5488828298957025, within: wilsonTolerance))
    }

    @Test func noGamesSpansTheWholeRange() {
        let interval = WilsonInterval(wins: 0, games: 0)

        #expect(interval.lower == 0)
        #expect(interval.upper == 1)
    }

    @Test func noWinsHasALowerBoundOfExactlyZero() {
        let interval = WilsonInterval(wins: 0, games: 10)

        #expect(interval.lower == 0)
        #expect(isClose(interval.upper, 0.21294197008340685, within: wilsonTolerance))
    }

    @Test func allWinsHasAnUpperBoundOfExactlyOne() {
        let interval = WilsonInterval(wins: 10, games: 10)

        #expect(interval.upper == 1)
        #expect(isClose(interval.lower, 0.787058029916593, within: wilsonTolerance))
    }

    @Test func singleWinStaysInsideTheUnitRange() {
        let interval = WilsonInterval(wins: 1, games: 1)

        #expect(interval.upper == 1)
        #expect(isClose(interval.lower, 0.2698659487840544, within: wilsonTolerance))
    }

    @Test func moreGamesNarrowTheIntervalAtTheSameRate() {
        let small = WilsonInterval(wins: 6, games: 10)
        let large = WilsonInterval(wins: 600, games: 1_000)

        #expect(large.upper - large.lower < small.upper - small.lower)
    }
}
