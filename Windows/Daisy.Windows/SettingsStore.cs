using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.Json;
using Daisy.Core;
using Microsoft.Win32;

namespace Daisy.Windows;

public sealed class SettingsStore
{
    public const string DefaultLiteLlmVersion = "1.101.0";
    private const string StartupRegistryPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string StartupValueName = "Daisy";
    private static readonly UTF8Encoding Utf8NoBom = new(encoderShouldEmitUTF8Identifier: false);

    public SettingsStore()
    {
        Directory.CreateDirectory(AppDataDirectory);
        Directory.CreateDirectory(Path.GetDirectoryName(ClaudeSettingsPath)!);
    }

    public static string AppDataDirectory { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Daisy");

    public static string EnvironmentPath => Path.Combine(AppDataDirectory, "copilot-api.env");
    public static string LiteLlmConfigPath => Path.Combine(AppDataDirectory, "litellm-config.yaml");
    public static string LiteLlmVersionPath => Path.Combine(AppDataDirectory, "litellm-version.txt");
    public static string LiteLlmVenvPath => Path.Combine(AppDataDirectory, "litellm-venv");
    public static string CopilotRuntimePath => Path.Combine(AppDataDirectory, "copilot-runtime");
    public static string ModelsCachePath => Path.Combine(AppDataDirectory, "models-cache.json");
    public static string ClaudeSettingsPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
        ".claude",
        "settings.json");

    public string Token { get; private set; } = string.Empty;
    public string LiteLlmConfig { get; private set; } = string.Empty;
    public string LiteLlmVersion { get; private set; } = DefaultLiteLlmVersion;
    public string ClaudeSettings { get; private set; } = "{}";

    public void Load()
    {
        Token = ReadToken();
        LiteLlmConfig = ReadFileOrDefault(LiteLlmConfigPath, string.Empty);
        var configuredVersion = ReadFileOrDefault(LiteLlmVersionPath, string.Empty).Trim();
        LiteLlmVersion = configuredVersion.Length == 0
                         || configuredVersion.Equals("latest", StringComparison.OrdinalIgnoreCase)
            ? DefaultLiteLlmVersion
            : configuredVersion;
        ClaudeSettings = FormatJson(ReadFileOrDefault(ClaudeSettingsPath, "{}")) ?? "{}";
    }

    public void SaveToken(string token)
    {
        var normalized = ConfigurationRules.NormalizeToken(token);
        WindowsCredentialStore.Write(normalized);
        TryDelete(EnvironmentPath);
        Token = normalized;
    }

    public void SaveLiteLlmConfig(string config)
    {
        File.WriteAllText(LiteLlmConfigPath, config, Utf8NoBom);
        LiteLlmConfig = config;
    }

    public void SaveLiteLlmVersion(string version)
    {
        var normalized = version.Trim();
        var error = ValidateLiteLlmVersion(normalized);
        if (error is not null)
        {
            throw new InvalidOperationException(error);
        }

        File.WriteAllText(LiteLlmVersionPath, normalized, Utf8NoBom);
        LiteLlmVersion = normalized;
    }

    public void SaveClaudeSettings(string json)
    {
        var validationError = ValidateJson(json);
        if (validationError is not null)
        {
            throw new InvalidOperationException(validationError);
        }

        var formatted = FormatJson(json)!;
        File.WriteAllText(ClaudeSettingsPath, formatted, Utf8NoBom);
        ClaudeSettings = formatted;
    }

    public static string? ValidateLiteLlmVersion(string version) =>
        ConfigurationRules.ValidateLiteLlmVersion(version);

    public static string? ValidateJson(string text) => ConfigurationRules.ValidateJsonObject(text);

    public static string? FormatJson(string text)
    {
        try
        {
            return ConfigurationRules.CanonicalJsonObject(text);
        }
        catch (InvalidOperationException)
        {
            return null;
        }
    }

    public bool IsModelConfigured(string modelId) => LiteLlmConfigEditor.ContainsModel(modelId, LiteLlmConfig);

    public void AddModel(string modelId, string modelName)
    {
        var result = LiteLlmConfigEditor.AddModel(modelId, modelName, LiteLlmConfig);
        if (!string.Equals(result, LiteLlmConfig, StringComparison.Ordinal))
        {
            SaveLiteLlmConfig(result);
        }
    }

    public void RemoveModel(string modelId)
    {
        var result = LiteLlmConfigEditor.RemoveModel(modelId, LiteLlmConfig);
        if (!string.Equals(result, LiteLlmConfig, StringComparison.Ordinal))
        {
            SaveLiteLlmConfig(result);
        }
    }

    public bool IsOpenAtLoginEnabled()
    {
        using var key = Registry.CurrentUser.OpenSubKey(StartupRegistryPath, writable: false);
        return key?.GetValue(StartupValueName) is string;
    }

    public void SetOpenAtLogin(bool enabled)
    {
        using var key = Registry.CurrentUser.CreateSubKey(StartupRegistryPath, writable: true);
        if (!enabled)
        {
            key.DeleteValue(StartupValueName, throwOnMissingValue: false);
            return;
        }

        var executablePath = Environment.ProcessPath
            ?? throw new InvalidOperationException("Daisy could not determine its executable path.");
        key.SetValue(StartupValueName, $"\"{executablePath}\" --minimized");
    }

    public async Task<string?> GetInstalledLiteLlmVersionAsync(CancellationToken cancellationToken = default)
    {
        var python = Path.Combine(LiteLlmVenvPath, "Scripts", "python.exe");
        if (!File.Exists(python))
        {
            return null;
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = python,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };
        startInfo.ArgumentList.Add("-c");
        startInfo.ArgumentList.Add("import importlib.metadata; print(importlib.metadata.version('litellm'))");

        using var process = Process.Start(startInfo);
        if (process is null)
        {
            return null;
        }

        var output = await process.StandardOutput.ReadToEndAsync(cancellationToken);
        await process.WaitForExitAsync(cancellationToken);
        return process.ExitCode == 0 ? output.Trim() : null;
    }

    public IReadOnlyList<string> LoadCachedModels()
    {
        try
        {
            return JsonSerializer.Deserialize<List<string>>(File.ReadAllText(ModelsCachePath)) ?? [];
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or JsonException)
        {
            return [];
        }
    }

    public void SaveCachedModels(IEnumerable<string> models)
    {
        File.WriteAllText(
            ModelsCachePath,
            JsonSerializer.Serialize(models, new JsonSerializerOptions { WriteIndented = true }),
            Utf8NoBom);
    }

    private static string ReadFileOrDefault(string path, string fallback)
    {
        try
        {
            return File.Exists(path) ? File.ReadAllText(path, Utf8NoBom) : fallback;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            return fallback;
        }
    }

    private static string ReadToken()
    {
        var stored = WindowsCredentialStore.Read();
        if (!string.IsNullOrEmpty(stored))
        {
            TryDelete(EnvironmentPath);
            return stored;
        }

        var legacyToken = ConfigurationRules.TokenFromEnvironment(
            ReadFileOrDefault(EnvironmentPath, string.Empty));
        if (legacyToken.Length > 0)
        {
            WindowsCredentialStore.Write(legacyToken);
            TryDelete(EnvironmentPath);
        }
        return legacyToken;
    }

    private static void TryDelete(string path)
    {
        try
        {
            File.Delete(path);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            // The credential is already stored securely; a stale migration file
            // can be removed manually if another process currently owns it.
        }
    }
}
