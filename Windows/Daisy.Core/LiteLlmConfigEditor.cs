using System.Text;
using System.Text.RegularExpressions;

namespace Daisy.Core;

public enum LiteLlmModelMode
{
    Chat,
    Embedding,
    Responses
}

public static class LiteLlmConfigEditor
{
    public static bool ContainsModel(string modelId, string config)
    {
        var fullModel = $"github_copilot/{modelId}";
        return NormalizedLines(config).Any(line => YamlModelValue(line) == fullModel);
    }

    public static LiteLlmModelMode ModeFor(string modelId)
    {
        var lowered = modelId.ToLowerInvariant();
        if (lowered.Contains("embedding", StringComparison.Ordinal))
        {
            return LiteLlmModelMode.Embedding;
        }
        return new[] { "codex", "o1", "o3", "o4" }.Any(value => lowered.Contains(value, StringComparison.Ordinal))
            ? LiteLlmModelMode.Responses
            : LiteLlmModelMode.Chat;
    }

    public static string AddModel(string modelId, string modelName, string originalConfig)
    {
        var normalizedId = modelId.Trim();
        if (normalizedId.Length == 0)
        {
            throw new InvalidOperationException("Model ID cannot be empty.");
        }
        if (ContainsModel(normalizedId, originalConfig))
        {
            return originalConfig;
        }

        var normalizedName = modelName.Trim();
        if (normalizedName.Length == 0)
        {
            throw new InvalidOperationException("Model name cannot be empty.");
        }

        var config = NormalizeNewlines(originalConfig);
        if (string.IsNullOrWhiteSpace(config))
        {
            config = "model_list:\n";
        }
        else
        {
            config = Regex.Replace(config, @"(?m)^(\s*)model_list:\s*\[\s*\]\s*$", "$1model_list:");
            if (!config.EndsWith('\n'))
            {
                config += '\n';
            }
        }

        var entry = new StringBuilder()
            .Append("  - model_name: ").Append(YamlQuotedScalar(normalizedName)).Append('\n');
        switch (ModeFor(normalizedId))
        {
            case LiteLlmModelMode.Embedding:
                entry.Append("    model_info:\n      mode: embedding\n");
                break;
            case LiteLlmModelMode.Responses:
                entry.Append("    model_info:\n      mode: responses\n");
                break;
        }
        entry.Append("    litellm_params:\n      model: ")
            .Append(YamlQuotedScalar($"github_copilot/{normalizedId}"))
            .Append('\n');
        return config + entry;
    }

    public static string RemoveModel(string modelId, string originalConfig)
    {
        var targetModel = $"github_copilot/{modelId.Trim()}";
        var lines = NormalizedLines(originalConfig);
        var removed = false;

        while (lines.FindIndex(line => YamlModelValue(line) == targetModel) is var modelIndex && modelIndex >= 0)
        {
            var entryStart = -1;
            for (var index = modelIndex; index >= 0; index--)
            {
                if (lines[index].TrimStart().StartsWith("- model_name:", StringComparison.Ordinal))
                {
                    entryStart = index;
                    break;
                }
            }
            if (entryStart < 0)
            {
                throw new InvalidOperationException("Could not find the LiteLLM model entry to remove.");
            }

            var entryIndent = LeadingWhitespaceCount(lines[entryStart]);
            var entryEnd = entryStart + 1;
            while (entryEnd < lines.Count)
            {
                var line = lines[entryEnd];
                var trimmed = line.Trim();
                if (trimmed.Length > 0)
                {
                    var indent = LeadingWhitespaceCount(line);
                    if (indent < entryIndent || (indent == entryIndent && trimmed.StartsWith("- model_name:", StringComparison.Ordinal)))
                    {
                        break;
                    }
                }
                entryEnd++;
            }
            lines.RemoveRange(entryStart, entryEnd - entryStart);
            removed = true;
        }

        if (!removed)
        {
            return originalConfig;
        }
        if (!lines.Any(line => line.TrimStart().StartsWith("- model_name:", StringComparison.Ordinal)))
        {
            var modelListIndex = lines.FindIndex(line => line.Trim() is "model_list:" or "model_list: []");
            if (modelListIndex >= 0)
            {
                var indentation = new string(lines[modelListIndex].TakeWhile(character => character is ' ' or '\t').ToArray());
                lines[modelListIndex] = $"{indentation}model_list: []";
            }
        }
        return string.Join('\n', lines);
    }

    private static string NormalizeNewlines(string value) => value
        .Replace("\r\n", "\n", StringComparison.Ordinal)
        .Replace('\r', '\n');

    private static List<string> NormalizedLines(string value) => NormalizeNewlines(value).Split('\n').ToList();

    private static string? YamlModelValue(string line)
    {
        var trimmed = line.Trim();
        if (!trimmed.StartsWith("model:", StringComparison.Ordinal))
        {
            return null;
        }
        var value = trimmed["model:".Length..].Trim();
        if (value.Length >= 2 && ((value[0] == '"' && value[^1] == '"') || (value[0] == '\'' && value[^1] == '\'')))
        {
            value = value[1..^1];
        }
        return value;
    }

    private static int LeadingWhitespaceCount(string line) => line.TakeWhile(character => character is ' ' or '\t').Count();

    private static string YamlQuotedScalar(string value) => '"' + value
        .Replace("\\", "\\\\", StringComparison.Ordinal)
        .Replace("\"", "\\\"", StringComparison.Ordinal)
        .Replace("\n", "\\n", StringComparison.Ordinal)
        .Replace("\r", "\\r", StringComparison.Ordinal)
        .Replace("\t", "\\t", StringComparison.Ordinal) + '"';
}
