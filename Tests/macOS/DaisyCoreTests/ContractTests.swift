import Foundation
import XCTest
@testable import DaisyCore

final class ContractTests: XCTestCase {
    private static let suite: ContractSuite = {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../../Shared/Contracts/Fixtures/conformance.json")
            .standardizedFileURL
        let data = try! Data(contentsOf: fixtureURL)
        return try! JSONDecoder().decode(ContractSuite.self, from: data)
    }()

    func testProtocolAndModelResponseContract() throws {
        XCTAssertEqual(ModelCatalog.modelsURL.absoluteString, Self.suite.modelsEndpoint)

        for testCase in Self.suite.modelResponses {
            let data = Data(testCase.input.utf8)
            if testCase.valid {
                XCTAssertEqual(try ModelCatalog.models(from: data), testCase.expected!, testCase.name)
            } else {
                XCTAssertThrowsError(try ModelCatalog.models(from: data), testCase.name)
            }
        }
    }

    func testGitHubDeviceFlowContract() throws {
        let fixture = Self.suite.deviceFlow
        XCTAssertEqual(GitHubDeviceFlowProtocol.clientID, fixture.clientId)
        XCTAssertEqual(GitHubDeviceFlowProtocol.scope, fixture.scope)
        XCTAssertEqual(GitHubDeviceFlowProtocol.grantType, fixture.grantType)
        XCTAssertEqual(GitHubDeviceFlowProtocol.deviceCodeURL.absoluteString, fixture.beginEndpoint)
        XCTAssertEqual(GitHubDeviceFlowProtocol.accessTokenURL.absoluteString, fixture.tokenEndpoint)
        XCTAssertEqual(GitHubDeviceFlowProtocol.minimumIntervalSeconds, fixture.minimumIntervalSeconds)
        XCTAssertEqual(GitHubDeviceFlowProtocol.slowDownIncrementSeconds, fixture.slowDownIncrementSeconds)

        let session = try GitHubDeviceFlowProtocol.session(from: Data(fixture.beginResponse.utf8))
        XCTAssertEqual(session.userCode, fixture.expectedUserCode)
        XCTAssertEqual(session.deviceCode, fixture.expectedDeviceCode)
        XCTAssertEqual(session.verificationURL.absoluteString, fixture.expectedVerificationUri)
        XCTAssertEqual(session.pollIntervalSeconds, fixture.expectedIntervalSeconds)
        XCTAssertEqual(GitHubDeviceFlowProtocol.beginRequestPayload["client_id"], fixture.clientId)
        XCTAssertEqual(
            GitHubDeviceFlowProtocol.pollRequestPayload(deviceCode: session.deviceCode)["grant_type"],
            fixture.grantType
        )

        for testCase in fixture.pollResponses {
            let result = try GitHubDeviceFlowProtocol.pollResult(from: Data(testCase.input.utf8))
            switch result {
            case let .token(value):
                XCTAssertEqual(testCase.status, "token")
                XCTAssertEqual(value, testCase.value)
            case .pending:
                XCTAssertEqual(testCase.status, "pending")
            case .slowDown:
                XCTAssertEqual(testCase.status, "slowDown")
            case let .failure(value):
                XCTAssertEqual(testCase.status, "failure")
                XCTAssertEqual(value, testCase.value)
            }
        }
    }

    func testConfigurationContract() throws {
        for testCase in Self.suite.tokens {
            let token = ConfigurationRules.token(fromEnvironment: testCase.environment)
            XCTAssertEqual(token, testCase.expected, testCase.name)
            XCTAssertEqual(try ConfigurationRules.tokenEnvironment(token), testCase.rendered, testCase.name)
        }

        for testCase in Self.suite.liteLlmVersions {
            XCTAssertEqual(
                ConfigurationRules.validateLiteLLMVersion(testCase.input) == nil,
                testCase.valid,
                testCase.name
            )
        }

        for testCase in Self.suite.jsonObjects {
            XCTAssertEqual(
                ConfigurationRules.validateJSONObject(testCase.input) == nil,
                testCase.valid,
                testCase.name
            )
            if let expected = testCase.expected {
                XCTAssertEqual(try ConfigurationRules.canonicalJSONObject(testCase.input), expected, testCase.name)
            }
        }

        XCTAssertThrowsError(try ConfigurationRules.normalizeToken("part-one\npart-two"))
    }

    func testLiteLLMAndModelRulesContract() throws {
        for testCase in Self.suite.modelModes {
            XCTAssertEqual(LiteLLMConfigEditor.mode(for: testCase.modelId).rawValue, testCase.expected, testCase.modelId)
        }

        for testCase in Self.suite.configuredModels {
            XCTAssertEqual(
                LiteLLMConfigEditor.containsModel(testCase.modelId, in: testCase.config),
                testCase.expected,
                testCase.name
            )
        }

        for testCase in Self.suite.liteLlmMutations {
            let actual: String
            switch testCase.operation {
            case "add":
                actual = try LiteLLMConfigEditor.addingModel(
                    testCase.modelId,
                    named: testCase.modelName!,
                    to: testCase.input
                )
            case "remove":
                actual = try LiteLLMConfigEditor.removingModel(testCase.modelId, from: testCase.input)
            default:
                XCTFail("Unknown operation \(testCase.operation)")
                continue
            }
            XCTAssertEqual(actual, testCase.expected, testCase.name)
        }
    }
}

private struct ContractSuite: Decodable {
    let schemaVersion: Int
    let modelsEndpoint: String
    let deviceFlow: DeviceFlowCase
    let tokens: [TokenCase]
    let liteLlmVersions: [ValidationCase]
    let jsonObjects: [JSONCase]
    let modelResponses: [ModelResponseCase]
    let modelModes: [ModelModeCase]
    let configuredModels: [ConfiguredModelCase]
    let liteLlmMutations: [MutationCase]
}

private struct DeviceFlowCase: Decodable {
    let clientId: String
    let scope: String
    let grantType: String
    let beginEndpoint: String
    let tokenEndpoint: String
    let minimumIntervalSeconds: Int
    let slowDownIncrementSeconds: Int
    let beginResponse: String
    let expectedUserCode: String
    let expectedDeviceCode: String
    let expectedVerificationUri: String
    let expectedIntervalSeconds: Int
    let pollResponses: [PollResponseCase]
}

private struct PollResponseCase: Decodable {
    let input: String
    let status: String
    let value: String?
}

private struct TokenCase: Decodable {
    let name: String
    let environment: String
    let expected: String
    let rendered: String
}

private struct ValidationCase: Decodable {
    let name: String
    let input: String
    let valid: Bool
}

private struct JSONCase: Decodable {
    let name: String
    let input: String
    let valid: Bool
    let expected: String?
}

private struct ModelResponseCase: Decodable {
    let name: String
    let input: String
    let valid: Bool
    let expected: [String]?
}

private struct ModelModeCase: Decodable {
    let modelId: String
    let expected: String
}

private struct ConfiguredModelCase: Decodable {
    let name: String
    let config: String
    let modelId: String
    let expected: Bool
}

private struct MutationCase: Decodable {
    let name: String
    let operation: String
    let input: String
    let modelId: String
    let modelName: String?
    let expected: String
}
