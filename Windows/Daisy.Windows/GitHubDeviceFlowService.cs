using System.Diagnostics;
using System.Net.Http;
using System.Net.Http.Json;
using Daisy.Core;

namespace Daisy.Windows;

public sealed class GitHubDeviceFlowService
{
    private readonly HttpClient _httpClient = new();

    public async Task<DeviceFlowSession> BeginAsync(CancellationToken cancellationToken)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, GitHubDeviceFlowProtocol.DeviceCodeUri)
        {
            Content = JsonContent.Create(GitHubDeviceFlowProtocol.BeginRequestPayload())
        };
        request.Headers.Accept.ParseAdd("application/json");

        using var response = await _httpClient.SendAsync(request, cancellationToken);
        response.EnsureSuccessStatusCode();
        var session = GitHubDeviceFlowProtocol.SessionFromResponse(
            await response.Content.ReadAsStringAsync(cancellationToken));

        Process.Start(new ProcessStartInfo(session.VerificationUri.ToString()) { UseShellExecute = true });

        return session;
    }

    public async Task<string> PollForTokenAsync(DeviceFlowSession session, CancellationToken cancellationToken)
    {
        var interval = session.PollIntervalSeconds;
        while (true)
        {
            await Task.Delay(TimeSpan.FromSeconds(interval), cancellationToken);
            using var request = new HttpRequestMessage(HttpMethod.Post, GitHubDeviceFlowProtocol.AccessTokenUri)
            {
                Content = JsonContent.Create(GitHubDeviceFlowProtocol.PollRequestPayload(session.DeviceCode))
            };
            request.Headers.Accept.ParseAdd("application/json");

            using var response = await _httpClient.SendAsync(request, cancellationToken);
            response.EnsureSuccessStatusCode();
            var result = GitHubDeviceFlowProtocol.PollResultFromResponse(
                await response.Content.ReadAsStringAsync(cancellationToken));
            switch (result.Status)
            {
                case DeviceFlowPollStatus.Token:
                    return result.Value!;
                case DeviceFlowPollStatus.Pending:
                    continue;
                case DeviceFlowPollStatus.SlowDown:
                    interval += GitHubDeviceFlowProtocol.SlowDownIncrementSeconds;
                    continue;
                default:
                    throw new InvalidOperationException(result.Value ?? "GitHub device flow failed.");
            }
        }
    }
}
