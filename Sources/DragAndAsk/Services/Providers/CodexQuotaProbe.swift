import Foundation

/// Reads Codex CLI's 5h / weekly quota by running `codex app-server` inside a
/// shell pipeline that pre-feeds it the JSON-RPC initialize + account/rateLimits
/// requests, then closes stdin so the server exits cleanly. We capture stdout
/// after the pipeline finishes and parse the JSON response. No async pipe
/// handlers — simpler and crash-proof.
enum CodexQuotaProbe {
    static let timeout: TimeInterval = 20

    static func fetch() async throws -> Quota {
        guard let codexBinary = ProcessRunner.findBinary(candidates: AIProvider.codex.binaryCandidates) else {
            throw AIError.cliNotFound(.codex)
        }

        let init1 = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"drag-and-ask","version":"0.1"}}}"#
        let init2 = #"{"jsonrpc":"2.0","id":2,"method":"account/rateLimits/read","params":{}}"#

        // (printf init1; printf init2; sleep 5) | codex app-server 2>/dev/null | head -5
        // The sleep keeps stdin open long enough for codex to respond; `head -5`
        // closes the pipeline once we have the lines we care about.
        let pipeline =
            "(printf '%s\\n' '\(init1)'; printf '%s\\n' '\(init2)'; sleep 5) | "
            + "'\(codexBinary.path)' app-server 2>/dev/null | head -5"

        let (stdout, stderr, status) = try await ProcessRunner.run(
            binary: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", pipeline],
            timeout: timeout
        )

        // status can be non-zero because head closing the pipe yields SIGPIPE on the upstream;
        // we treat the run as successful if we can parse the rate-limits response.
        _ = status; _ = stderr

        for line in stdout.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            guard let data = trimmed.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            if let id = obj["id"] as? Int, id == 2,
               let result = obj["result"] as? [String: Any],
               let rateLimits = result["rateLimits"] as? [String: Any] {
                if let q = parse(rateLimits: rateLimits) { return q }
            }
        }
        throw AIError.empty(.codex)
    }

    private static func parse(rateLimits: [String: Any]) -> Quota? {
        let primary = rateLimits["primary"] as? [String: Any]
        let secondary = rateLimits["secondary"] as? [String: Any]

        func pct(_ d: [String: Any]?) -> Double? {
            (d?["usedPercent"] as? NSNumber)?.doubleValue
        }
        func mins(_ d: [String: Any]?) -> Int? {
            (d?["windowDurationMins"] as? NSNumber)?.intValue
        }
        func resets(_ d: [String: Any]?) -> Date? {
            guard let ts = (d?["resetsAt"] as? NSNumber)?.doubleValue else { return nil }
            return Date(timeIntervalSince1970: ts)
        }

        return Quota(
            provider: .codex,
            primaryUsedPercent: pct(primary),
            primaryWindowMinutes: mins(primary),
            primaryResetsAt: resets(primary),
            secondaryUsedPercent: pct(secondary),
            secondaryWindowMinutes: mins(secondary),
            secondaryResetsAt: resets(secondary),
            planType: rateLimits["planType"] as? String,
            fetchedAt: Date()
        )
    }
}
