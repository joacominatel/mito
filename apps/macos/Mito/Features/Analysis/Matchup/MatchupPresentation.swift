import Foundation
import MitoCore
import MitoEngine

/// What the Matchup tab shows for a subject (§20.2), worded in es-AR. The numbers come from
/// `MatchupAnalysis`; this only words them.
enum MatchupPresentation: Equatable {
    case aram
    case noChampion
    case noStats
    case ready(MatchupReport)

    init(subject: AnalysisSubject, locale: Locale = .current) {
        guard let role = subject.role else {
            self = .aram
            return
        }
        guard let champion = subject.champion else {
            self = .noChampion
            return
        }
        let opponent = subject.laneOpponent
        guard
            let analysis = MatchupAnalysis(
                champion: champion.id, role: role, opponent: opponent?.champion,
                stats: subject.stats)
        else {
            self = .noStats
            return
        }
        self = .ready(
            MatchupWording(
                champion: champion, role: role, opponent: opponent, names: subject.names,
                patch: subject.meta?.patch, locale: locale
            ).report(analysis))
    }
}

struct MatchupReport: Equatable {
    /// "Ahri vs Zed", or "Si elegís Ahri, contra Zed" for a recommendation.
    let title: String
    /// "Rival de línea: Zed (MID? 82 %)" or "Rival de línea desconocido".
    let opponent: String
    let hasOpponent: Bool
    let winrates: [WinrateBlock]
    let laneDiffs: LaneDiffsBlock?
    let curve: CurveChartData?
    let spikes: [Line]
    let claves: [Line]

    /// One spike or clave: a symbol in its tone, the text, and its sample.
    struct Line: Equatable, Identifiable {
        let id: Int
        let symbol: String
        let tone: Tone
        let text: String
        /// "revisado en 16.20" for a curated tip checked on an older patch.
        let note: String?
        /// `nil` when the line has no sample of its own.
        let sample: SampleLevel?
    }
}

struct WinrateBlock: Equatable, Identifiable {
    enum Kind: Hashable {
        case matchup
        case general
    }

    let id: Kind
    /// "Winrate contra Zed" / "Winrate general en MID".
    let title: String
    /// "52,3 %"; `nil` without a number to show.
    let value: String?
    /// "IC 90 %: 51,4 % – 53,2 %".
    let interval: String?
    /// Against the champion's general winrate, in winrate points.
    let delta: Double?
    let deltaCaption: String?
    /// "8.212 partidas".
    let games: String?
    let sample: SampleLevel?
    /// Why there is no number.
    let note: String?
}

struct LaneDiffsBlock: Equatable {
    struct Item: Equatable, Identifiable {
        /// "Oro @15".
        let id: String
        /// "+85" / "−85", the minus U+2212.
        let value: String
        let tone: Tone
    }

    let items: [Item]
    /// "412 partidas con timeline".
    let games: String
    let sample: SampleLevel
}

struct CurveChartData: Equatable {
    struct Series: Equatable, Identifiable {
        let id: ChampionID
        let name: String
        let points: [Point]
    }

    struct Point: Equatable, Identifiable {
        let id: DurationBucket
        /// "<20", "20–25", "40+".
        let label: String
        let winrate: Double
        /// "Ahri, de 20 a 25 minutos".
        let accessibilityLabel: String
        /// "52,3 %".
        let accessibilityValue: String
    }

    let series: [Series]
    /// The buckets any series has, in game-length order: Charts orders categories as it meets them.
    let axisLabels: [String]
    /// "Ahri escala mejor que Zed desde el minuto 35"; `nil` when nothing stands out.
    let summary: String?
    /// The lowest sample of the curves drawn.
    let sample: SampleLevel
}

/// The es-AR wording of one analysis.
struct MatchupWording {
    let champion: AnalysisSubject.Champion
    let role: Role
    let opponent: AnalysisSubject.LaneOpponent?
    let names: ReasonNames
    let patch: Patch?
    let locale: Locale

    var me: String { names.champion(champion.id) }
    var roleLabel: String { String(localized: role.shortLabel) }

    func report(_ analysis: MatchupAnalysis) -> MatchupReport {
        MatchupReport(
            title: title, opponent: opponentLine, hasOpponent: opponent != nil,
            winrates: winrates(analysis), laneDiffs: analysis.laneDiffs.map(laneDiffs),
            curve: curve(analysis), spikes: spikes(analysis.spikes),
            claves: analysis.claves.enumerated().map { clave($1, id: $0) })
    }

    // MARK: Header

    private var title: String {
        switch (opponent.map { names.champion($0.champion) }, champion.isRecommendation) {
        case (let rival?, false): String(localized: "\(me) vs \(rival)", table: "Matchup")
        case (let rival?, true):
            String(localized: "Si elegís \(me), contra \(rival)", table: "Matchup")
        case (nil, false): me
        case (nil, true): String(localized: "Si elegís \(me)", table: "Matchup")
        }
    }

    private var opponentLine: String {
        guard let opponent else {
            return String(localized: "Rival de línea desconocido", table: "Matchup")
        }
        let rival = names.champion(opponent.champion)
        let label = String(localized: opponent.role.role.shortLabel)
        switch opponent.role {
        case .assigned:
            return String(localized: "Rival de línea: \(rival) (\(label))", table: "Matchup")
        case .inferred(_, let probability):
            return String(
                localized: "Rival de línea: \(rival) (\(label)? \(percent(probability)))",
                table: "Matchup")
        case .guessed:
            return String(
                localized: "Rival de línea: \(rival) (\(label)?, sin datos)", table: "Matchup")
        }
    }

    // MARK: Winrate

    private func winrates(_ analysis: MatchupAnalysis) -> [WinrateBlock] {
        guard let opponent else { return [general(analysis.general)] }
        let matchup = matchup(analysis.matchup, against: names.champion(opponent.champion))
        // Without a matchup number, the general one is the reference.
        return analysis.matchup?.estimate == nil ? [matchup, general(analysis.general)] : [matchup]
    }

    private func matchup(_ winrate: SmoothedWinrate?, against rival: String) -> WinrateBlock {
        block(
            .matchup, winrate,
            title: String(localized: "Winrate contra \(rival)", table: "Matchup"),
            noData: String(localized: "Sin partidas de este cruce en el parche", table: "Matchup"))
    }

    private func general(_ winrate: SmoothedWinrate?) -> WinrateBlock {
        block(
            .general, winrate,
            title: String(localized: "Winrate general en \(roleLabel)", table: "Matchup"),
            noData: String(
                localized: "Sin partidas de \(me) en \(roleLabel) este parche", table: "Matchup"))
    }

    private func block(
        _ kind: WinrateBlock.Kind, _ winrate: SmoothedWinrate?, title: String, noData: String
    ) -> WinrateBlock {
        let estimate = winrate?.estimate
        let note: String? =
            switch (winrate, estimate) {
            case (nil, _): noData
            case (_?, nil):
                String(localized: "Pocas partidas para dar un número", table: "Matchup")
            case (_?, _?): nil
            }
        return WinrateBlock(
            id: kind, title: title, value: estimate.map { precisePercent($0.winrate) },
            interval: estimate.map {
                let lower = precisePercent($0.interval.lower)
                let upper = precisePercent($0.interval.upper)
                return String(localized: "IC 90 %: \(lower) – \(upper)", table: "Matchup")
            },
            delta: estimate?.delta,
            deltaCaption: estimate?.delta == nil
                ? nil : String(localized: "respecto del promedio de \(me)", table: "Matchup"),
            games: winrate.map {
                String(localized: "\(count($0.games)) partidas", table: "Matchup")
            },
            sample: winrate?.sample, note: note)
    }

    // MARK: Lane

    private func laneDiffs(_ diffs: LaneDiffs) -> LaneDiffsBlock {
        let gold = diffs.goldAt15.map {
            LaneDiffsBlock.Item(
                id: String(localized: "Oro @15", table: "Matchup"),
                value: signed($0, fractionDigits: 0), tone: tone($0, fractionDigits: 0))
        }
        let cs = diffs.csAt15.map {
            LaneDiffsBlock.Item(
                id: String(localized: "CS @15", table: "Matchup"),
                value: signed($0, fractionDigits: 1), tone: tone($0, fractionDigits: 1))
        }
        return LaneDiffsBlock(
            items: [gold, cs].compactMap(\.self),
            games: String(
                localized: "\(count(diffs.timelineGames)) partidas con timeline", table: "Matchup"),
            sample: diffs.sample)
    }

    // MARK: Curve

    private func curve(_ analysis: MatchupAnalysis) -> CurveChartData? {
        let curves = [analysis.curve, analysis.opponentCurve].compactMap(\.self)
        guard let sample = curves.map(\.sample).min() else { return nil }
        let buckets = Set(curves.flatMap { $0.points.map(\.bucket) })
        return CurveChartData(
            series: curves.map { curve in
                let name = names.champion(curve.champion)
                return CurveChartData.Series(
                    id: curve.champion, name: name,
                    points: curve.points.map { point in
                        CurveChartData.Point(
                            id: point.bucket, label: Self.axisLabel(point.bucket),
                            winrate: point.winrate,
                            accessibilityLabel: "\(name), \(spokenBucket(point.bucket))",
                            accessibilityValue: precisePercent(point.winrate))
                    })
            },
            axisLabels: DurationBucket.allCases.filter(buckets.contains).map(Self.axisLabel),
            summary: analysis.curveSummary.map(summary), sample: sample)
    }

    private func summary(_ summary: CurveSummary) -> String {
        let stronger = names.champion(summary.stronger)
        let minute = summary.phase.minute
        switch (summary.versus.map(names.champion), summary.phase) {
        case (let other?, .late):
            return String(
                localized: "\(stronger) escala mejor que \(other) desde el minuto \(minute)",
                table: "Matchup")
        case (let other?, .early):
            return String(
                localized: "\(stronger) es más fuerte que \(other) hasta el minuto \(minute)",
                table: "Matchup")
        case (nil, .late):
            return String(
                localized: "\(stronger) rinde más en partidas de \(minute) minutos o más",
                table: "Matchup")
        case (nil, .early):
            return String(
                localized: "\(stronger) rinde más en partidas de hasta \(minute) minutos",
                table: "Matchup")
        }
    }

    static func axisLabel(_ bucket: DurationBucket) -> String {
        switch (bucket.lowerMinutes, bucket.upperMinutes) {
        case (0, let upper?): "<\(upper)"
        case (let lower, let upper?): "\(lower)–\(upper)"
        case (let lower, nil): "\(lower)+"
        }
    }

    private func spokenBucket(_ bucket: DurationBucket) -> String {
        switch (bucket.lowerMinutes, bucket.upperMinutes) {
        case (0, let upper?): String(localized: "menos de \(upper) minutos", table: "Matchup")
        case (let lower, let upper?):
            String(localized: "de \(lower) a \(upper) minutos", table: "Matchup")
        case (let lower, nil): String(localized: "\(lower) minutos o más", table: "Matchup")
        }
    }

    // MARK: Spikes

    private func spikes(_ spikes: [SpikeComparison]) -> [MatchupReport.Line] {
        spikes.enumerated().compactMap { index, spike in
            spikeText(spike).map {
                MatchupReport.Line(
                    id: index, symbol: "bolt", tone: spikeTone(spike.first), text: $0, note: nil,
                    sample: spike.sample)
            }
        }
    }

    private func spikeText(_ spike: SpikeComparison) -> String? {
        let rival = opponent.map { names.champion($0.champion) }
        // "vos" reads as yours; a recommendation is named, since you have not picked it.
        let you =
            champion.isRecommendation ? me : String(localized: "vos", table: "Matchup")
        switch (spike.theirs.map(time), spike.mine.map(time), rival) {
        case (let theirs?, let mine?, let rival?):
            return versusSpike(spike.milestone, first: rival, at: theirs, second: you, at: mine)
        case (let theirs?, nil, let rival?):
            return singleSpike(spike.milestone, champion: rival, at: theirs)
        case (_, let mine?, _):
            return singleSpike(spike.milestone, champion: me, at: mine)
        default:
            return nil
        }
    }

    private func versusSpike(
        _ milestone: SpikeComparison.Milestone, first: String, at firstTime: String,
        second: String, at secondTime: String
    ) -> String {
        switch milestone {
        case .levelSix:
            String(
                localized: "\(first) llega a 6 a los \(firstTime), \(second) a los \(secondTime)",
                table: "Matchup")
        case .firstItem:
            String(
                localized:
                    "\(first) completa el 1.er legendario a los \(firstTime), \(second) a los \(secondTime)",
                table: "Matchup")
        case .secondItem:
            String(
                localized:
                    "\(first) completa el 2.º legendario a los \(firstTime), \(second) a los \(secondTime)",
                table: "Matchup")
        case .thirdItem:
            String(
                localized:
                    "\(first) completa el 3.er legendario a los \(firstTime), \(second) a los \(secondTime)",
                table: "Matchup")
        }
    }

    private func singleSpike(
        _ milestone: SpikeComparison.Milestone, champion: String, at time: String
    ) -> String {
        switch milestone {
        case .levelSix:
            String(localized: "\(champion) llega a 6 a los \(time)", table: "Matchup")
        case .firstItem:
            String(
                localized: "\(champion) completa el 1.er legendario a los \(time)",
                table: "Matchup")
        case .secondItem:
            String(
                localized: "\(champion) completa el 2.º legendario a los \(time)",
                table: "Matchup")
        case .thirdItem:
            String(
                localized: "\(champion) completa el 3.er legendario a los \(time)",
                table: "Matchup")
        }
    }

    private func spikeTone(_ first: MatchupSide?) -> Tone {
        switch first {
        case .you: .favorable
        case .opponent: .unfavorable
        case nil: .neutral
        }
    }

    // MARK: Claves

    private func clave(_ clave: Clave, id: Int) -> MatchupReport.Line {
        switch clave {
        case .curated(let tip):
            return MatchupReport.Line(
                id: id, symbol: "lightbulb", tone: .neutral, text: tip.text,
                note: tip.reviewedPatch == patch
                    ? nil
                    : String(
                        localized: "revisado en \(tip.reviewedPatch.rawValue)", table: "Matchup"),
                sample: nil)
        case .generated(let template, let sample):
            let (symbol, tone, text) = generated(template)
            return MatchupReport.Line(
                id: id, symbol: symbol, tone: tone, text: text, note: nil, sample: sample)
        }
    }

    private func generated(_ template: ClaveTemplate) -> (String, Tone, String) {
        let rival = opponent.map { names.champion($0.champion) } ?? ""
        switch template {
        case .matchup(let delta):
            let points = WinratePoints.text(delta, locale: locale)
            return delta > 0
                ? (
                    "arrow.up", .favorable,
                    String(
                        localized:
                            "El cruce te favorece (\(points) puntos de winrate): podés tomar la iniciativa en la línea",
                        table: "Matchup")
                )
                : (
                    "arrow.down", .unfavorable,
                    String(
                        localized:
                            "El cruce es difícil (\(points) puntos de winrate): priorizá farmear seguro",
                        table: "Matchup")
                )
        case .laneGold(let diff):
            let gold = abs(diff).formatted(.number.precision(.fractionLength(0)).locale(locale))
            return diff > 0
                ? (
                    "plus.circle", .favorable,
                    String(
                        localized:
                            "Se suele llegar al minuto 15 con \(gold) de oro a favor: hacé valer la ventaja",
                        table: "Matchup")
                )
                : (
                    "minus.circle", .unfavorable,
                    String(
                        localized:
                            "\(rival) suele sacar \(gold) de oro de ventaja al minuto 15: evitá los intercambios largos temprano",
                        table: "Matchup")
                )
        case .spike(let milestone, .you, let seconds):
            let at = time(seconds)
            let spike = milestoneName(milestone)
            return (
                "bolt.fill", .favorable,
                String(
                    localized:
                        "Llegás antes que \(rival) al \(spike) (\(at)): es tu momento para pelear",
                    table: "Matchup")
            )
        case .spike(let milestone, .opponent, let seconds):
            let at = time(seconds)
            let spike = milestoneName(milestone)
            return (
                "bolt", .unfavorable,
                String(
                    localized:
                        "\(rival) llega antes al \(spike) (\(at)): jugá seguro hasta entonces",
                    table: "Matchup")
            )
        case .powerCurve(let stronger, let phase):
            let minute = phase.minute
            switch (stronger, phase) {
            case (.you, .late):
                return (
                    "chart.line.uptrend.xyaxis", .favorable,
                    String(
                        localized:
                            "Escalás mejor que \(rival) desde el minuto \(minute): no hace falta forzar temprano",
                        table: "Matchup")
                )
            case (.opponent, .late):
                return (
                    "chart.line.downtrend.xyaxis", .unfavorable,
                    String(
                        localized:
                            "\(rival) escala mejor desde el minuto \(minute): buscá cerrar antes",
                        table: "Matchup")
                )
            case (.you, .early):
                return (
                    "chart.line.uptrend.xyaxis", .favorable,
                    String(
                        localized:
                            "Sos más fuerte que \(rival) hasta el minuto \(minute): aprovechá el arranque",
                        table: "Matchup")
                )
            case (.opponent, .early):
                return (
                    "chart.line.downtrend.xyaxis", .unfavorable,
                    String(
                        localized:
                            "\(rival) es más fuerte hasta el minuto \(minute): aguantá y escalá",
                        table: "Matchup")
                )
            }
        }
    }

    private func milestoneName(_ milestone: SpikeComparison.Milestone) -> String {
        switch milestone {
        case .levelSix: String(localized: "nivel 6", table: "Matchup")
        case .firstItem: String(localized: "1.er legendario", table: "Matchup")
        case .secondItem: String(localized: "2.º legendario", table: "Matchup")
        case .thirdItem: String(localized: "3.er legendario", table: "Matchup")
        }
    }

    // MARK: Numbers

    /// "52,3 %".
    private func precisePercent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(1)).locale(locale))
    }

    private func percent(_ value: Double) -> String { value.percentText(locale: locale) }

    private func count(_ value: Int) -> String { value.countText(locale: locale) }

    /// "7:10".
    private func time(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond).locale(locale))
    }

    /// Signed at `fractionDigits`; zero after rounding has no sign. The minus is U+2212.
    private func signed(_ value: Double, fractionDigits: Int) -> String {
        let magnitude = abs(value).formatted(
            .number.precision(.fractionLength(fractionDigits)).locale(locale))
        switch tone(value, fractionDigits: fractionDigits) {
        case .favorable: return "+" + magnitude
        case .unfavorable: return "\u{2212}" + magnitude
        case .neutral: return magnitude
        }
    }

    private func tone(_ value: Double, fractionDigits: Int) -> Tone {
        let scale = pow(10, Double(fractionDigits))
        let rounded = (value * scale).rounded() / scale
        return rounded > 0 ? .favorable : rounded < 0 ? .unfavorable : .neutral
    }
}
