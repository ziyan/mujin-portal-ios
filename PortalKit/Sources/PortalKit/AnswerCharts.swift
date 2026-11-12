import Foundation

/// AnswerChart is a chart the assistant writes in an answer, as a fenced block whose language is `chart`, with an optional
/// `title="..."` after it and the chart as JSON inside: `chartType` (bar, line or pie), `xAxis` and `yAxis` with a `label` and,
/// for the x axis, its categories in `data`, and `series`, each with a `name`, its `data` and, for a pie, its slices' `labels`.
public struct AnswerChart: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case bar
        case line
        case pie
    }

    public struct Series: Equatable, Sendable {
        public let name: String
        public let values: [Double]
        /// A pie's slice names; empty for a bar or line chart, whose categories are the x axis's.
        public let labels: [String]
    }

    public let kind: Kind
    public let title: String?
    public let xAxisLabel: String?
    public let yAxisLabel: String?
    public let categories: [String]
    public let series: [Series]

    /// One point of the chart: its category, the series it belongs to, and its value.
    public struct Point: Equatable, Sendable, Identifiable {
        public let category: String
        public let seriesName: String
        public let value: Double
        public var id: String { "\(seriesName)|\(category)" }
    }

    /// Every value with its category and series. A pie's categories are its labels.
    public var points: [Point] {
        series.flatMap { series in
            series.values.enumerated().map { index, value in
                let names = kind == .pie ? series.labels : categories
                return Point(category: index < names.count ? names[index] : "\(index + 1)", seriesName: series.name, value: value)
            }
        }
    }

    private static func number(_ value: Any) -> Double? {
        switch value {
        case let double as Double: double
        case let integer as Int: Double(integer)
        case let number as NSNumber: number.doubleValue
        default: nil
        }
    }

    /// The chart a fenced block holds, or nil when the block is not a chart or its JSON is not one, so it shows as code.
    public static func parse(language: String, text: String) -> AnswerChart? {
        let info = language.trimmingCharacters(in: .whitespaces)
        guard info == "chart" || info.hasPrefix("chart ") else { return nil }
        let title = info.range(of: #"title="([^"]*)""#, options: .regularExpression).map { range -> String in
            String(info[range].dropFirst("title=\"".count).dropLast())
        }
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
            let kind = (object["chartType"] as? String).flatMap(Kind.init(rawValue:)),
            let seriesList = object["series"] as? [[String: Any]], !seriesList.isEmpty
        else { return nil }
        let xAxis = object["xAxis"] as? [String: Any]
        let yAxis = object["yAxis"] as? [String: Any]
        let categories = (xAxis?["data"] as? [Any] ?? []).map { "\($0)" }
        let series = seriesList.enumerated().compactMap { index, entry -> Series? in
            let values = (entry["data"] as? [Any] ?? []).compactMap(number)
            guard !values.isEmpty else { return nil }
            return Series(
                name: entry["name"] as? String ?? "Series \(index + 1)", values: values, labels: (entry["labels"] as? [Any] ?? []).map { "\($0)" })
        }
        guard !series.isEmpty else { return nil }
        return AnswerChart(
            kind: kind, title: title.flatMap { $0.isEmpty ? nil : $0 }, xAxisLabel: xAxis?["label"] as? String, yAxisLabel: yAxis?["label"] as? String,
            categories: categories, series: series)
    }
}

/// AnswerMath keeps a formula readable where it cannot be drawn: inline math becomes inline code, by the same rule that decides what
/// is a formula (RichMath), so an amount of money such as "$5 and $10" is left as it is.
public enum AnswerMath {
    public static func inlineAsCode(_ text: String) -> String {
        guard text.contains("$") || text.contains("\\") else { return text }
        return RichMath.pieces(of: text).map { piece in
            switch piece {
            case .text(let words): words
            case .formula(let tex, _): tex.contains("`") ? tex : "`\(tex)`"
            }
        }.joined()
    }
}
