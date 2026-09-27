using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Daisy.Core;

public static partial class ConfigurationRules
{
    public const string InvalidJsonMessage = "Text must be valid JSON.";
    public const string JsonRootMessage = "Root must be a JSON object ({}), not an array.";
    public const string InvalidLiteLlmVersionMessage = "Enter an exact LiteLLM version, such as 1.101.0.";
    public const string TokenNewlineMessage = "The GitHub token cannot contain a newline.";

    public static string NormalizeToken(string token)
    {
        var normalized = token.Trim();
        if (normalized.Contains('\r') || normalized.Contains('\n'))
        {
            throw new InvalidOperationException(TokenNewlineMessage);
        }
        return normalized;
    }

    public static string TokenFromEnvironment(string content)
    {
        content = content.TrimStart('\uFEFF');
        return content.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries)
            .FirstOrDefault(line => line.StartsWith("GITHUB_TOKEN=", StringComparison.Ordinal))?
            ["GITHUB_TOKEN=".Length..]
            .Trim() ?? string.Empty;
    }

    public static string TokenEnvironment(string token) => $"GITHUB_TOKEN={NormalizeToken(token)}\n";

    public static string? ValidateLiteLlmVersion(string version)
    {
        return LiteLlmVersionRegex().IsMatch(version) ? null : InvalidLiteLlmVersionMessage;
    }

    public static string? ValidateJsonObject(string text)
    {
        try
        {
            _ = CanonicalJsonObject(text);
            return null;
        }
        catch (InvalidOperationException exception)
        {
            return exception.Message;
        }
    }

    public static string CanonicalJsonObject(string text)
    {
        JsonDocument document;
        try
        {
            document = JsonDocument.Parse(text);
        }
        catch (JsonException)
        {
            throw new InvalidOperationException(InvalidJsonMessage);
        }

        using (document)
        {
            if (document.RootElement.ValueKind != JsonValueKind.Object)
            {
                throw new InvalidOperationException(JsonRootMessage);
            }

            using var stream = new MemoryStream();
            using (var writer = new Utf8JsonWriter(stream, new JsonWriterOptions
            {
                Indented = true,
                Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping
            }))
            {
                WriteCanonical(document.RootElement, writer);
            }
            return Encoding.UTF8.GetString(stream.ToArray()).Replace("\r\n", "\n", StringComparison.Ordinal);
        }
    }

    private static void WriteCanonical(JsonElement element, Utf8JsonWriter writer)
    {
        switch (element.ValueKind)
        {
            case JsonValueKind.Object:
                writer.WriteStartObject();
                foreach (var property in element.EnumerateObject().OrderBy(property => property.Name, StringComparer.Ordinal))
                {
                    writer.WritePropertyName(property.Name);
                    WriteCanonical(property.Value, writer);
                }
                writer.WriteEndObject();
                break;
            case JsonValueKind.Array:
                writer.WriteStartArray();
                foreach (var value in element.EnumerateArray())
                {
                    WriteCanonical(value, writer);
                }
                writer.WriteEndArray();
                break;
            default:
                element.WriteTo(writer);
                break;
        }
    }

    [GeneratedRegex(@"^[0-9]+(?:\.[0-9]+)*(?:(?:a|b|rc)[0-9]+)?(?:\.post[0-9]+)?(?:\.dev[0-9]+)?(?:\+[A-Za-z0-9]+(?:[._-][A-Za-z0-9]+)*)?$")]
    private static partial Regex LiteLlmVersionRegex();
}
