using System.Diagnostics;
using Daisy.Windows;

if (args is ["--version"])
{
    Console.WriteLine(Environment.GetEnvironmentVariable("DAISY_TEST_PYTHON_VERSION") ?? "not Python");
    return 0;
}

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

    Check(ServiceManager.IsSupportedPythonVersionOutput("Python 3.10.0"), "Python 3.10 is supported");
    Check(ServiceManager.IsSupportedPythonVersionOutput("Python 3.14.1\r\n"), "Python 3.14 is supported");
    Check(!ServiceManager.IsSupportedPythonVersionOutput("Python 3.9.18"), "Python 3.9 is rejected");
    Check(!ServiceManager.IsSupportedPythonVersionOutput("Python 3.15.0"), "Python 3.15 is rejected");
    Check(
        !ServiceManager.IsSupportedPythonVersionOutput(
            "Python was not found; run without arguments to install from the Microsoft Store"),
        "the Microsoft Store app execution alias is rejected");

    var processPath = Environment.ProcessPath;
    Check(processPath is not null, "the regression test process path is available");
    if (processPath is not null)
    {
        var previousFakeVersion = Environment.GetEnvironmentVariable("DAISY_TEST_PYTHON_VERSION");
        try
        {
            Environment.SetEnvironmentVariable("DAISY_TEST_PYTHON_VERSION", "Python 3.12.7");
            Check(
                await ServiceManager.IsSupportedPythonLauncherAsync(processPath),
                "a launcher reporting a supported Python version is accepted");

            Environment.SetEnvironmentVariable(
                "DAISY_TEST_PYTHON_VERSION",
                "Python was not found; run without arguments to install from the Microsoft Store");
            Check(
                !await ServiceManager.IsSupportedPythonLauncherAsync(processPath),
                "a launcher reporting the Microsoft Store placeholder is rejected");
        }
        finally
        {
            Environment.SetEnvironmentVariable("DAISY_TEST_PYTHON_VERSION", previousFakeVersion);
        }
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
