import Foundation

struct Quota: Sendable, Equatable {
    let provider: AIProvider
    let primaryUsedPercent: Double?     // typically 5h rolling window
    let primaryWindowMinutes: Int?
    let primaryResetsAt: Date?
    let secondaryUsedPercent: Double?   // typically 7-day window
    let secondaryWindowMinutes: Int?
    let secondaryResetsAt: Date?
    let planType: String?
    let fetchedAt: Date
}

actor QuotaTracker {
    static let shared = QuotaTracker()

    private var quotas: [AIProvider: Quota] = [:]

    func latest(for provider: AIProvider) -> Quota? { quotas[provider] }
    func set(_ quota: Quota) { quotas[quota.provider] = quota }
    func clear() { quotas.removeAll() }
}

enum QuotaFormat {
    /// "(5h) 23% reset 14:30 · (7d) 41% reset 5/20"
    static func short(_ q: Quota) -> String {
        var parts: [String] = []
        if let pct = q.primaryUsedPercent {
            let win = windowLabel(minutes: q.primaryWindowMinutes ?? 300)
            var s = "(\(win)) \(Int(pct.rounded()))%"
            if let r = q.primaryResetsAt { s += " · reset \(timeLabel(r))" }
            parts.append(s)
        }
        if let pct = q.secondaryUsedPercent {
            let win = windowLabel(minutes: q.secondaryWindowMinutes ?? 10_080)
            var s = "(\(win)) \(Int(pct.rounded()))%"
            if let r = q.secondaryResetsAt { s += " · reset \(dateLabel(r))" }
            parts.append(s)
        }
        return parts.joined(separator: "  ")
    }

    private static func windowLabel(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        if minutes < 60 * 60 { return "\(minutes / 60)h" }
        return "\(minutes / (60 * 24))d"
    }

    private static func timeLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    private static func dateLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d HH:mm"
        return f.string(from: d)
    }
}
