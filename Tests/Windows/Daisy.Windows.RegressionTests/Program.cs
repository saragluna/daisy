using System.Diagnostics;
using Daisy.Windows;

var failures = new List<string>();
var temporaryDirectory = Path.Combine(Path.GetTempPath(), $"daisy-regression-{Guid.NewGuid():N}");

try
{
    Directory.CreateDirectory(temporaryDirectory);
    var configPath = Path.Combine(temporaryDirectory, "litellm-config.yaml");

    var initialConfig = SettingsStore.LoadOrCreateLiteLlmConfig(configPath);
    Check(initialConfig == SettingsStore.DefaultLiteLlmConfig, "missing LiteLLM config returns the default");
    Check(File.ReadAllText(configPath) == SettingsStore.DefaultLiteLlmConfig, "missing LiteLLM config is created");

    const string customConfig = "model_list:\n  - model_name: custom\n";
    File.WriteAllText(configPath, customConfig);
    Check(SettingsStore.LoadOrCreateLiteLlmConfig(configPath) == customConfig, "existing LiteLLM config is preserved");

    var startInfo = new ProcessStartInfo();
    ServiceManager.ConfigureLiteLlmEnvironment(startInfo);
    Check(startInfo.Environment["PYTHONUTF8"] == "1", "LiteLLM enables Python UTF-8 mode");
    Check(startInfo.Environment["PYTHONIOENCODING"] == "utf-8", "LiteLLM uses UTF-8 standard streams");

    var runtimePatchPath = Path.Combine(AppContext.BaseDirectory, "patch-litellm-runtime.py");
    Check(File.Exists(runtimePatchPath), "published Windows app includes the LiteLLM runtime patch");
    if (File.Exists(runtimePatchPath))
    {
        var runtimePatch = File.ReadAllText(runtimePatchPath);
        Check(runtimePatch.Contains("if not result.choices:", StringComparison.Ordinal),
            "LiteLLM runtime patch guards empty choices");
    }
}
finally
{
    Directory.Delete(temporaryDirectory, recursive: true);
}

if (failures.Count > 0)
{
    Console.Error.WriteLine("Daisy Windows regression tests failed:");
    foreach (var failure in failures)
    {
        Console.Error.WriteLine($"- {failure}");
    }
    return 1;
}

Console.WriteLine("Daisy Windows regression tests passed.");
return 0;

void Check(bool condition, string name)
{
    if (!condition)
    {
        failures.Add(name);
    }
}
