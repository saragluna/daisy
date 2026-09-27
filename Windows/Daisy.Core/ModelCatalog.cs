using System.Text.Json;

namespace Daisy.Core;

public static class ModelCatalog
{
    public static Uri ModelsUri { get; } = new("http://127.0.0.1:4141/v1/models?limit=1000");

    public static IReadOnlyList<string> ModelsFromResponse(string response)
    {
        try
        {
            using var document = JsonDocument.Parse(response);
            if (document.RootElement.ValueKind != JsonValueKind.Object
                || !document.RootElement.TryGetProperty("data", out var data)
                || data.ValueKind != JsonValueKind.Array)
            {
                throw new InvalidOperationException("The models response must contain a data array.");
            }

            return Sorted(data.EnumerateArray()
                .Where(item => item.ValueKind == JsonValueKind.Object)
                .Select(item => item.TryGetProperty("id", out var id) && id.ValueKind == JsonValueKind.String
                    ? id.GetString()?.Trim()
                    : null)
                .Where(id => !string.IsNullOrEmpty(id))
                .Cast<string>());
        }
        catch (JsonException)
        {
            throw new InvalidOperationException("The models response must contain a data array.");
        }
    }

    public static IReadOnlyList<string> Sorted(IEnumerable<string> models) => models
        .Where(model => model.Length > 0)
        .Distinct(StringComparer.Ordinal)
        .OrderBy(Rank)
        .ThenBy(model => model, StringComparer.OrdinalIgnoreCase)
        .ThenBy(model => model, StringComparer.Ordinal)
        .ToList();

    public static IReadOnlyList<string> Filtered(IEnumerable<string> models, string query)
    {
        var normalizedQuery = query.Trim();
        return normalizedQuery.Length == 0
            ? models.ToList()
            : models.Where(model => model.Contains(normalizedQuery, StringComparison.OrdinalIgnoreCase)).ToList();
    }

    private static int Rank(string model)
    {
        if (model.StartsWith("gpt", StringComparison.OrdinalIgnoreCase))
        {
            return 0;
        }
        return model.StartsWith("claude", StringComparison.OrdinalIgnoreCase) ? 1 : 2;
    }
}
