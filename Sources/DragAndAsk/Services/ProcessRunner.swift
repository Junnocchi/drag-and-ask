import Foundation

/// Shared subprocess plumbing used by all three CLI providers.
enum ProcessRunner {
    static let defaultTimeout: TimeInterval = 240

    /// Strip characters that crash NSConcreteTask at launch (NUL, lone surrogates, etc.).
    static func sanitizeForArg(_ s: String) -> String {
        let scalars = s.unicodeScalars.filter { scalar in
            let v = scalar.value
            if v == 0 { return false }
            if v < 0x09 || (v > 0x0D && v < 0x20) { return false }
            if v == 0x7F { return false }
            return true
        }
        return String(String.UnicodeScalarView(scalars))
    }

    static func findBinary(candidates: [String]) -> URL? {
        let fm = FileManager.default
        for path in candidates {
            if fm.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    static func run(
        binary: URL,
        arguments: [String],
        timeout: TimeInterval = defaultTimeout
    ) async throws -> (stdout: String, stderr: String, status: Int32) {
        let cleanArgs = arguments.map { sanitizeForArg($0) }

        let env: [String: String] = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:\(NSHomeDirectory())/.local/bin:\(NSHomeDirectory())/.npm-global/bin:/usr/bin:/bin",
            "HOME": NSHomeDirectory(),
            "USER": NSUserName(),
            "LANG": "en_US.UTF-8",
            "LC_ALL": "en_US.UTF-8",
            "CI": "1"
        ]

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(String, String, Int32), Error>) in
            let process = Process()
            process.executableURL = binary
            process.arguments = cleanArgs
            process.currentDirectoryURL = URL(fileURLWithPath: "/tmp")
            process.environment = env

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            if let devNull = FileHandle(forReadingAtPath: "/dev/null") {
                process.standardInput = devNull
            }

            let outQueue = DispatchQueue(label: "drag-and-ask.runner.stdout")
            let errQueue = DispatchQueue(label: "drag-and-ask.runner.stderr")
            nonisolated(unsafe) var outBuf = Data()
            nonisolated(unsafe) var errBuf = Data()

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let d = handle.availableData
                if d.isEmpty {
                    handle.readabilityHandler = nil
                } else {
                    outQueue.sync { outBuf.append(d) }
                }
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let d = handle.availableData
                if d.isEmpty {
                    handle.readabilityHandler = nil
                } else {
                    errQueue.sync { errBuf.append(d) }
                }
            }

            process.terminationHandler = { proc in
                let remainOut = (try? outPipe.fileHandleForReading.readToEnd()) ?? nil
                let remainErr = (try? errPipe.fileHandleForReading.readToEnd()) ?? nil
                if let remainOut { outQueue.sync { outBuf.append(remainOut) } }
                if let remainErr { errQueue.sync { errBuf.append(remainErr) } }
                let out = outQueue.sync { String(data: outBuf, encoding: .utf8) ?? "" }
                let err = errQueue.sync { String(data: errBuf, encoding: .utf8) ?? "" }
                continuation.resume(returning: (out, err, proc.terminationStatus))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning { process.terminate() }
            }
        }
    }
}
