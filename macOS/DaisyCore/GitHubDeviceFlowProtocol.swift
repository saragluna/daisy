import Foundation

public struct DeviceFlowSession: Equatable {
    public let userCode: String
    public let deviceCode: String
    public let verificationURL: URL
    public let pollIntervalSeconds: Int

    public init(userCode: String, deviceCode: String, verificationURL: URL, pollIntervalSeconds: Int) {
        self.userCode = userCode
        self.deviceCode = deviceCode
        self.verificationURL = verificationURL
        self.pollIntervalSeconds = pollIntervalSeconds
    }
}

public enum DeviceFlowPollResult: Equatable {
    case token(String)
    case pending
    case slowDown
    case failure(String)
}

public enum GitHubDeviceFlowProtocol {
    public static let clientID = "Iv1.b507a08c87ecfe98"
    public static let scope = "read:user"
    public static let grantType = "urn:ietf:params:oauth:grant-type:device_code"
    public static let minimumIntervalSeconds = 5
    public static let slowDownIncrementSeconds = 5
    public static let deviceCodeURL = URL(string: "https://github.com/login/device/code")!
    public static let accessTokenURL = URL(string: "https://github.com/login/oauth/access_token")!

    public static var beginRequestPayload: [String: String] {
        ["client_id": clientID, "scope": scope]
    }

    public static func pollRequestPayload(deviceCode: String) -> [String: String] {
        ["client_id": clientID, "device_code": deviceCode, "grant_type": grantType]
    }

    public static func session(from responseData: Data) throws -> DeviceFlowSession {
        guard let root = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let userCode = root["user_code"] as? String,
              let deviceCode = root["device_code"] as? String,
              let verificationURI = root["verification_uri"] as? String,
              let verificationURL = URL(string: verificationURI),
              let interval = root["interval"] as? Int else {
            throw DaisyCoreError.invalidDeviceFlowResponse
        }
        return DeviceFlowSession(
            userCode: userCode,
            deviceCode: deviceCode,
            verificationURL: verificationURL,
            pollIntervalSeconds: max(interval, minimumIntervalSeconds)
        )
    }

    public static func pollResult(from responseData: Data) throws -> DeviceFlowPollResult {
        guard let root = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw DaisyCoreError.invalidDeviceFlowResponse
        }
        if let token = root["access_token"] as? String, !token.isEmpty {
            return .token(token)
        }
        let error = root["error"] as? String
        switch error {
        case "authorization_pending":
            return .pending
        case "slow_down":
            return .slowDown
        default:
            let description = root["error_description"] as? String
            return .failure(description ?? error ?? "GitHub device flow failed.")
        }
    }
}
