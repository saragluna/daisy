using System.Text.Json;

namespace Daisy.Core;

public sealed record DeviceFlowSession(
    string UserCode,
    string DeviceCode,
    Uri VerificationUri,
    int PollIntervalSeconds);

public enum DeviceFlowPollStatus
{
    Token,
    Pending,
    SlowDown,
    Failure
}

public sealed record DeviceFlowPollResult(DeviceFlowPollStatus Status, string? Value = null);

public static class GitHubDeviceFlowProtocol
{
    public const string ClientId = "Iv1.b507a08c87ecfe98";
    public const string Scope = "read:user";
    public const string GrantType = "urn:ietf:params:oauth:grant-type:device_code";
    public const int MinimumIntervalSeconds = 5;
    public const int SlowDownIncrementSeconds = 5;
    public static Uri DeviceCodeUri { get; } = new("https://github.com/login/device/code");
    public static Uri AccessTokenUri { get; } = new("https://github.com/login/oauth/access_token");

    public static IReadOnlyDictionary<string, string> BeginRequestPayload() => new Dictionary<string, string>
    {
        ["client_id"] = ClientId,
        ["scope"] = Scope
    };

    public static IReadOnlyDictionary<string, string> PollRequestPayload(string deviceCode) => new Dictionary<string, string>
    {
        ["client_id"] = ClientId,
        ["device_code"] = deviceCode,
        ["grant_type"] = GrantType
    };

    public static DeviceFlowSession SessionFromResponse(string response)
    {
        try
        {
            using var document = JsonDocument.Parse(response);
            var root = document.RootElement;
            var userCode = RequiredString(root, "user_code");
            var deviceCode = RequiredString(root, "device_code");
            var verificationUri = new Uri(RequiredString(root, "verification_uri"));
            if (!root.TryGetProperty("interval", out var intervalElement)
                || !intervalElement.TryGetInt32(out var interval))
            {
                throw new InvalidOperationException("GitHub returned an invalid device-flow response.");
            }
            return new DeviceFlowSession(
                userCode,
                deviceCode,
                verificationUri,
                Math.Max(interval, MinimumIntervalSeconds));
        }
        catch (Exception exception) when (exception is JsonException or UriFormatException or KeyNotFoundException)
        {
            throw new InvalidOperationException("GitHub returned an invalid device-flow response.");
        }
    }

    public static DeviceFlowPollResult PollResultFromResponse(string response)
    {
        try
        {
            using var document = JsonDocument.Parse(response);
            var root = document.RootElement;
            if (root.TryGetProperty("access_token", out var tokenElement)
                && tokenElement.GetString() is { Length: > 0 } token)
            {
                return new DeviceFlowPollResult(DeviceFlowPollStatus.Token, token);
            }

            var error = root.TryGetProperty("error", out var errorElement) ? errorElement.GetString() : null;
            if (error == "authorization_pending")
            {
                return new DeviceFlowPollResult(DeviceFlowPollStatus.Pending);
            }
            if (error == "slow_down")
            {
                return new DeviceFlowPollResult(DeviceFlowPollStatus.SlowDown);
            }
            var description = root.TryGetProperty("error_description", out var descriptionElement)
                ? descriptionElement.GetString()
                : null;
            return new DeviceFlowPollResult(
                DeviceFlowPollStatus.Failure,
                description ?? error ?? "GitHub device flow failed.");
        }
        catch (JsonException)
        {
            throw new InvalidOperationException("GitHub returned an invalid device-flow response.");
        }
    }

    private static string RequiredString(JsonElement root, string name)
    {
        if (!root.TryGetProperty(name, out var element) || element.GetString() is not { Length: > 0 } value)
        {
            throw new KeyNotFoundException(name);
        }
        return value;
    }
}
