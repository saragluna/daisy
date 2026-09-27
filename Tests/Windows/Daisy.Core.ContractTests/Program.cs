using System.Text.Json;
using Daisy.Core;

var fixturePath = Path.Combine(AppContext.BaseDirectory, "Fixtures", "conformance.json");
var suite = JsonSerializer.Deserialize<ContractSuite>(
    File.ReadAllText(fixturePath),
    new JsonSerializerOptions { PropertyNameCaseInsensitive = true })
    ?? throw new InvalidOperationException("Could not read the conformance fixture.");
var failures = new List<string>();

Check(ModelCatalog.ModelsUri.AbsoluteUri == suite.ModelsEndpoint, "models endpoint");

var deviceFlow = suite.DeviceFlow;
Check(GitHubDeviceFlowProtocol.ClientId == deviceFlow.ClientId, "device-flow client ID");
Check(GitHubDeviceFlowProtocol.Scope == deviceFlow.Scope, "device-flow scope");
Check(GitHubDeviceFlowProtocol.GrantType == deviceFlow.GrantType, "device-flow grant type");
Check(GitHubDeviceFlowProtocol.DeviceCodeUri.AbsoluteUri == deviceFlow.BeginEndpoint, "device-flow begin endpoint");
Check(GitHubDeviceFlowProtocol.AccessTokenUri.AbsoluteUri == deviceFlow.TokenEndpoint, "device-flow token endpoint");
Check(GitHubDeviceFlowProtocol.MinimumIntervalSeconds == deviceFlow.MinimumIntervalSeconds, "device-flow minimum interval");
Check(GitHubDeviceFlowProtocol.SlowDownIncrementSeconds == deviceFlow.SlowDownIncrementSeconds, "device-flow slow-down increment");
var session = GitHubDeviceFlowProtocol.SessionFromResponse(deviceFlow.BeginResponse);
Check(session.UserCode == deviceFlow.ExpectedUserCode, "device-flow user code");
Check(session.DeviceCode == deviceFlow.ExpectedDeviceCode, "device-flow device code");
Check(session.VerificationUri.AbsoluteUri == deviceFlow.ExpectedVerificationUri, "device-flow verification URI");
Check(session.PollIntervalSeconds == deviceFlow.ExpectedIntervalSeconds, "device-flow normalized interval");
Check(GitHubDeviceFlowProtocol.BeginRequestPayload()["client_id"] == deviceFlow.ClientId, "device-flow begin payload");
Check(GitHubDeviceFlowProtocol.PollRequestPayload(session.DeviceCode)["grant_type"] == deviceFlow.GrantType, "device-flow poll payload");
foreach (var testCase in deviceFlow.PollResponses)
{
    var result = GitHubDeviceFlowProtocol.PollResultFromResponse(testCase.Input);
    var status = result.Status switch
    {
        DeviceFlowPollStatus.Token => "token",
        DeviceFlowPollStatus.Pending => "pending",
        DeviceFlowPollStatus.SlowDown => "slowDown",
        _ => "failure"
    };
    Check(status == testCase.Status, "device-flow poll status " + testCase.Status);
    Check(result.Value == testCase.Value, "device-flow poll value " + testCase.Status);
}

foreach (var testCase in suite.Tokens)
{
    var token = ConfigurationRules.TokenFromEnvironment(testCase.Environment);
    Check(token == testCase.Expected, testCase.Name + " parse");
    Check(ConfigurationRules.TokenEnvironment(token) == testCase.Rendered, testCase.Name + " render");
}

foreach (var testCase in suite.LiteLlmVersions)
{
    Check((ConfigurationRules.ValidateLiteLlmVersion(testCase.Input) is null) == testCase.Valid, testCase.Name);
}

foreach (var testCase in suite.JsonObjects)
{
    Check((ConfigurationRules.ValidateJsonObject(testCase.Input) is null) == testCase.Valid, testCase.Name);
    if (testCase.Expected is not null)
    {
        Check(ConfigurationRules.CanonicalJsonObject(testCase.Input) == testCase.Expected, testCase.Name + " canonical form");
    }
}

foreach (var testCase in suite.ModelResponses)
{
    try
    {
        var models = ModelCatalog.ModelsFromResponse(testCase.Input);
        Check(testCase.Valid, testCase.Name + " should be rejected");
        Check(models.SequenceEqual(testCase.Expected ?? []), testCase.Name + " model list");
    }
    catch (InvalidOperationException)
    {
        Check(!testCase.Valid, testCase.Name + " should be accepted");
    }
}

foreach (var testCase in suite.ModelModes)
{
    Check(LiteLlmConfigEditor.ModeFor(testCase.ModelId).ToString().ToLowerInvariant() == testCase.Expected, testCase.ModelId);
}

foreach (var testCase in suite.ConfiguredModels)
{
    Check(LiteLlmConfigEditor.ContainsModel(testCase.ModelId, testCase.Config) == testCase.Expected, testCase.Name);
}

foreach (var testCase in suite.LiteLlmMutations)
{
    var actual = testCase.Operation switch
    {
        "add" => LiteLlmConfigEditor.AddModel(testCase.ModelId, testCase.ModelName!, testCase.Input),
        "remove" => LiteLlmConfigEditor.RemoveModel(testCase.ModelId, testCase.Input),
        _ => throw new InvalidOperationException($"Unknown operation {testCase.Operation}")
    };
    Check(actual == testCase.Expected, testCase.Name);
}

try
{
    ConfigurationRules.NormalizeToken("part-one\npart-two");
    Check(false, "embedded token newline");
}
catch (InvalidOperationException)
{
    // Expected.
}

if (failures.Count > 0)
{
    Console.Error.WriteLine("Daisy contract conformance failed:");
    foreach (var failure in failures)
    {
        Console.Error.WriteLine($"- {failure}");
    }
    return 1;
}

Console.WriteLine($"Daisy contract v{suite.SchemaVersion} conformance passed.");
return 0;

void Check(bool condition, string name)
{
    if (!condition)
    {
        failures.Add(name);
    }
}

internal sealed class ContractSuite
{
    public int SchemaVersion { get; init; }
    public string ModelsEndpoint { get; init; } = "";
    public DeviceFlowCase DeviceFlow { get; init; } = new();
    public List<TokenCase> Tokens { get; init; } = [];
    public List<ValidationCase> LiteLlmVersions { get; init; } = [];
    public List<JsonCase> JsonObjects { get; init; } = [];
    public List<ModelResponseCase> ModelResponses { get; init; } = [];
    public List<ModelModeCase> ModelModes { get; init; } = [];
    public List<ConfiguredModelCase> ConfiguredModels { get; init; } = [];
    public List<MutationCase> LiteLlmMutations { get; init; } = [];
}

internal sealed class DeviceFlowCase
{
    public string ClientId { get; init; } = "";
    public string Scope { get; init; } = "";
    public string GrantType { get; init; } = "";
    public string BeginEndpoint { get; init; } = "";
    public string TokenEndpoint { get; init; } = "";
    public int MinimumIntervalSeconds { get; init; }
    public int SlowDownIncrementSeconds { get; init; }
    public string BeginResponse { get; init; } = "";
    public string ExpectedUserCode { get; init; } = "";
    public string ExpectedDeviceCode { get; init; } = "";
    public string ExpectedVerificationUri { get; init; } = "";
    public int ExpectedIntervalSeconds { get; init; }
    public List<PollResponseCase> PollResponses { get; init; } = [];
}

internal sealed class PollResponseCase
{
    public string Input { get; init; } = "";
    public string Status { get; init; } = "";
    public string? Value { get; init; }
}

internal sealed class TokenCase
{
    public string Name { get; init; } = "";
    public string Environment { get; init; } = "";
    public string Expected { get; init; } = "";
    public string Rendered { get; init; } = "";
}

internal class ValidationCase
{
    public string Name { get; init; } = "";
    public string Input { get; init; } = "";
    public bool Valid { get; init; }
}

internal sealed class JsonCase : ValidationCase
{
    public string? Expected { get; init; }
}

internal sealed class ModelResponseCase : ValidationCase
{
    public List<string>? Expected { get; init; }
}

internal sealed class ModelModeCase
{
    public string ModelId { get; init; } = "";
    public string Expected { get; init; } = "";
}

internal sealed class ConfiguredModelCase
{
    public string Name { get; init; } = "";
    public string Config { get; init; } = "";
    public string ModelId { get; init; } = "";
    public bool Expected { get; init; }
}

internal sealed class MutationCase
{
    public string Name { get; init; } = "";
    public string Operation { get; init; } = "";
    public string Input { get; init; } = "";
    public string ModelId { get; init; } = "";
    public string? ModelName { get; init; }
    public string Expected { get; init; } = "";
}
