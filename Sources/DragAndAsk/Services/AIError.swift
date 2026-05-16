import Foundation

enum AIError: LocalizedError {
    case cliNotFound(AIProvider)
    case cliFailed(AIProvider, Int32, String)
    case empty(AIProvider)
    case timeout(AIProvider)

    var errorDescription: String? {
        switch self {
        case .cliNotFound(let p):
            return "\(p.displayName)을 찾을 수 없습니다. 설치 후 \(p.authHint)으로 인증하세요."
        case .cliFailed(let p, let code, let stderr):
            return "\(p.displayName) 오류 (\(code)): \(stderr.prefix(300))"
        case .empty(let p):
            return "\(p.displayName)에서 빈 응답을 받았습니다."
        case .timeout(let p):
            return "\(p.displayName) 호출이 시간 안에 끝나지 않았습니다."
        }
    }
}
