import Foundation

/// Reads Claude Code 5h / 7d rate limits via the statusLine sidechannel trick:
///   1. Create a temp dir with a fake `settings.json` whose `statusLine`
///      command is a shell script that appends Claude's piped JSON payload
///      to a capture file.
///   2. Run claude inside `script` (BSD pty wrapper) so its TUI is happy
///      and statusLine actually fires.
///   3. Pipe in a timing-controlled stdin stream that wakes claude, sends a
///      tiny probe prompt, then `/exit` — the whole pipeline finishes on its own.
///   4. After the pipeline exits, parse the capture file for `rate_limits`.
enum ClaudeQuotaProbe {
    static let timeout: TimeInterval = 30

    static func fetch() async throws -> Quota {
        guard let claudeBinary = ProcessRunner.findBinary(candidates: AIProvider.claude.binaryCandidates) else {
            throw AIError.cliNotFound(.claude)
        }

        let fm = FileManager.default
        let tmpRoot = fm.temporaryDirectory
            .appendingPathComponent("drag-and-ask-claude-probe-\(UUID().uuidString)")
        try fm.createDirectory(at: tmpRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpRoot) }

        let statuslinePath = tmpRoot.appendingPathComponent("statusline.sh")
        let settingsPath = tmpRoot.appendingPathComponent("settings.json")
        let capturePath = tmpRoot.appendingPathComponent("capture.jsonl")
        try Data().write(to: capturePath)

        // statusline.sh — captures stdin payload (which contains rate_limits JSON).
        let statuslineContent = """
        #!/bin/sh
        payload="$(cat)"
        if [ -n "$payload" ]; then
            printf '%s\\n' "$payload" >> '\(capturePath.path)'
        fi
        printf 'drag-and-ask probe\\n'
        """
        try statuslineContent.write(to: statuslinePath, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: statuslinePath.path)

        // settings.json — points statusLine at our script.
        let settingsContent = """
        {
          "statusLine": {
            "type": "command",
            "command": "\(statuslinePath.path)"
          }
        }
        """
        try settingsContent.write(to: settingsPath, atomically: true, encoding: .utf8)

        // Shell pipeline:
        //   ( wait, send probe, wait for statusLine to fire, send /exit )
        //   | script (PTY) claude --tools '' --settings settings.json
        let pipeline = """
        (sleep 3; printf 'Return exactly: RLPROBE\\r'; sleep 14; printf '/exit\\r'; sleep 1) | \
        script -qFe /dev/null '\(claudeBinary.path)' --model haiku --tools '' --settings '\(settingsPath.path)' >/dev/null 2>&1
        """

        _ = try? await ProcessRunner.run(
            binary: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", pipeline],
            timeout: timeout
        )

        // Read capture file. Multiple JSON payloads may be appended.
        guard let data = try? Data(contentsOf: capturePath),
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty else {
            throw AIError.empty(.claude)
        }

        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }
            if let rl = obj["rate_limits"] as? [String: Any],
               let q = parse(rateLimits: rl) {
                return q
            }
            for (_, v) in obj {
                if let nested = v as? [String: Any],
                   let rl = nested["rate_limits"] as? [String: Any],
                   let q = parse(rateLimits: rl) {
                    return q
                }
            }
        }
        throw AIError.empty(.claude)
    }

    private static func parse(rateLimits: [String: Any]) -> Quota? {
        let five = rateLimits["five_hour"] as? [String: Any]
        let seven = rateLimits["seven_day"] as? [String: Any]

        func pct(_ d: [String: Any]?) -> Double? {
            if let n = d?["used_percentage"] as? NSNumber { return n.doubleValue }
            if let n = d?["usedPercentage"] as? NSNumber { return n.doubleValue }
            return nil
        }
        func resets(_ d: [String: Any]?) -> Date? {
            if let n = d?["resets_at"] as? NSNumber { return Date(timeIntervalSince1970: n.doubleValue) }
            if let s = d?["resets_at"] as? String {
                let f = ISO8601DateFormatter()
                return f.date(from: s)
            }
            return nil
        }

        guard pct(five) != nil || pct(seven) != nil else { return nil }

        return Quota(
            provider: .claude,
            primaryUsedPercent: pct(five),
            primaryWindowMinutes: 300,
            primaryResetsAt: resets(five),
            secondaryUsedPercent: pct(seven),
            secondaryWindowMinutes: 7 * 24 * 60,
            secondaryResetsAt: resets(seven),
            planType: nil,
            fetchedAt: Date()
        )
    }
}
