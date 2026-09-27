using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Net.NetworkInformation;
using System.Text;
using System.Windows;

namespace Daisy.Windows;

public sealed class ServiceManager : IDisposable
{
    private readonly SettingsStore _settings;
    private readonly LoggingService _logs;
    private readonly Dictionary<ServiceId, Process> _processes = new();
    private readonly HashSet<Process> _setupProcesses = [];
    private readonly object _processSync = new();
    private readonly Dictionary<ServiceId, SemaphoreSlim> _serviceLocks = new()
    {
        [ServiceId.CopilotApi] = new SemaphoreSlim(1, 1),
        [ServiceId.LiteLlmProxy] = new SemaphoreSlim(1, 1)
    };
    private volatile bool _isDisposing;

    public ServiceManager(SettingsStore settings, LoggingService logs)
    {
        _settings = settings;
        _logs = logs;
        Services = new ObservableCollection<ManagedServiceState>(
            Enum.GetValues<ServiceId>().Select(id => new ManagedServiceState(id)));
    }

    public ObservableCollection<ManagedServiceState> Services { get; }

    public event EventHandler? StateChanged;

    public ManagedServiceState StateFor(ServiceId id) => Services.Single(service => service.Id == id);

    public async Task StartAsync(ServiceId id)
    {
        if (_isDisposing)
        {
            return;
        }

        var serviceLock = _serviceLocks[id];
        await serviceLock.WaitAsync();
        try
        {
            Process? existing;
            var existingIsRunning = false;
            lock (_processSync)
            {
                _processes.TryGetValue(id, out existing);
                if (existing is not null)
                {
                    try
                    {
                        existingIsRunning = !existing.HasExited;
                    }
                    catch (InvalidOperationException)
                    {
                        existingIsRunning = false;
                    }

                    if (!existingIsRunning)
                    {
                        _processes.Remove(id);
                    }
                }
            }

            if (existingIsRunning)
            {
                return;
            }
            existing?.Dispose();

            await UpdateStateAsync(id, false, "Starting", null);
            EnsurePortIsAvailable(id);

            ProcessStartInfo startInfo;
            if (id == ServiceId.CopilotApi)
            {
                await EnsureCopilotRuntimeInstalledAsync();
                startInfo = CreateCopilotStartInfo();
            }
            else
            {
                await EnsureLiteLlmInstalledAsync();
                startInfo = CreateLiteLlmStartInfo();
            }

            if (_isDisposing)
            {
                return;
            }

            var process = new Process
            {
                StartInfo = startInfo,
                EnableRaisingEvents = true
            };
            process.OutputDataReceived += (_, args) => AppendOutput(id, "out", args.Data);
            process.ErrorDataReceived += (_, args) => AppendOutput(id, "err", args.Data);
            process.Exited += (_, _) => OnProcessExited(id, process);

            lock (_processSync)
            {
                if (_isDisposing)
                {
                    process.Dispose();
                    return;
                }

                _processes[id] = process;
                if (!process.Start())
                {
                    _processes.Remove(id);
                    throw new InvalidOperationException($"Windows could not start {id.DisplayName()}.");
                }
            }

            process.BeginOutputReadLine();
            process.BeginErrorReadLine();
            if (process.HasExited)
            {
                return;
            }
            await UpdateStateAsync(id, true, "Running", null);
        }
        catch (Exception exception)
        {
            Process? failedProcess;
            lock (_processSync)
            {
                _processes.Remove(id, out failedProcess);
            }
            failedProcess?.Dispose();
            AppendOutput(id, "error", exception.Message);
            await UpdateStateAsync(id, false, "Failed", exception.Message);
        }
        finally
        {
            serviceLock.Release();
        }
    }

    public async Task StopAsync(ServiceId id)
    {
        var serviceLock = _serviceLocks[id];
        await serviceLock.WaitAsync();
        try
        {
            await StopWithoutLockAsync(id);
        }
        finally
        {
            serviceLock.Release();
        }
    }

    public async Task RestartAsync(ServiceId id)
    {
        if (_isDisposing)
        {
            return;
        }

        var serviceLock = _serviceLocks[id];
        await serviceLock.WaitAsync();
        try
        {
            await StopWithoutLockAsync(id);
            await UpdateStateAsync(id, false, "Starting", null);
            EnsurePortIsAvailable(id);

            ProcessStartInfo startInfo;
            if (id == ServiceId.CopilotApi)
            {
                await EnsureCopilotRuntimeInstalledAsync();
                startInfo = CreateCopilotStartInfo();
            }
            else
            {
                await EnsureLiteLlmInstalledAsync();
                startInfo = CreateLiteLlmStartInfo();
            }

            if (_isDisposing)
            {
                return;
            }

            var process = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
            process.OutputDataReceived += (_, args) => AppendOutput(id, "out", args.Data);
            process.ErrorDataReceived += (_, args) => AppendOutput(id, "err", args.Data);
            process.Exited += (_, _) => OnProcessExited(id, process);
            lock (_processSync)
            {
                if (_isDisposing)
                {
                    process.Dispose();
                    return;
                }

                _processes[id] = process;
                if (!process.Start())
                {
                    _processes.Remove(id);
                    throw new InvalidOperationException($"Windows could not start {id.DisplayName()}.");
                }
            }

            process.BeginOutputReadLine();
            process.BeginErrorReadLine();
            if (process.HasExited)
            {
                return;
            }
            await UpdateStateAsync(id, true, "Running", null);
        }
        catch (Exception exception)
        {
            Process? failedProcess;
            lock (_processSync)
            {
                _processes.Remove(id, out failedProcess);
            }
            failedProcess?.Dispose();
            AppendOutput(id, "error", exception.Message);
            await UpdateStateAsync(id, false, "Failed", exception.Message);
        }
        finally
        {
            serviceLock.Release();
        }
    }

    public Task StartAllAsync() => Task.WhenAll(Enum.GetValues<ServiceId>().Select(StartAsync));

    public async Task StopAllAsync()
    {
        await Task.WhenAll(Enum.GetValues<ServiceId>().Select(StopAsync));
    }

    public void StopAllForExit()
    {
        List<Process> processes;
        lock (_processSync)
        {
            if (_isDisposing)
            {
                return;
            }

            _isDisposing = true;
            processes = _processes.Values.Concat(_setupProcesses).Distinct().ToList();
            _processes.Clear();
            _setupProcesses.Clear();
        }

        foreach (var process in processes)
        {
            TryKillProcessTree(process);
        }
    }

    public void Dispose()
    {
        StopAllForExit();
    }

    private async Task StopWithoutLockAsync(ServiceId id)
    {
        Process? process;
        lock (_processSync)
        {
            _processes.Remove(id, out process);
        }

        if (process is null)
        {
            await UpdateStateAsync(id, false, "Stopped", null);
            return;
        }

        await UpdateStateAsync(id, false, "Stopping", null);
        TryKillProcessTree(process);
        try
        {
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
            await process.WaitForExitAsync(timeout.Token);
        }
        catch (OperationCanceledException)
        {
            // Kill(entireProcessTree: true) has already been requested.
        }
        finally
        {
            process.Dispose();
        }

        await UpdateStateAsync(id, false, "Stopped", null);
    }

    private ProcessStartInfo CreateCopilotStartInfo()
    {
        if (string.IsNullOrWhiteSpace(_settings.Token))
        {
            throw new InvalidOperationException("Missing GitHub token in Windows Credential Manager.");
        }

        var node = FindExecutable("node.exe")
            ?? throw new InvalidOperationException("Node.js was not found. Install Node.js 20.16 or newer.");
        var runtimeMain = Path.Combine(
            SettingsStore.CopilotRuntimePath,
            "node_modules", "copilot-api", "dist", "main.js");
        if (!File.Exists(runtimeMain))
        {
            throw new InvalidOperationException("The managed copilot-api runtime is missing.");
        }

        var startInfo = CreateRedirectedStartInfo(node);
        startInfo.ArgumentList.Add(runtimeMain);
        startInfo.ArgumentList.Add("start");
        startInfo.Environment["DAISY_GITHUB_TOKEN"] = _settings.Token;
        startInfo.Environment["HOST"] = "127.0.0.1";
        return startInfo;
    }

    private ProcessStartInfo CreateLiteLlmStartInfo()
    {
        var executable = Path.Combine(SettingsStore.LiteLlmVenvPath, "Scripts", "litellm.exe");
        if (!File.Exists(executable))
        {
            throw new InvalidOperationException("LiteLLM was not installed successfully.");
        }

        var startInfo = CreateRedirectedStartInfo(executable);
        startInfo.ArgumentList.Add("--config");
        startInfo.ArgumentList.Add(SettingsStore.LiteLlmConfigPath);
        startInfo.ArgumentList.Add("--host");
        startInfo.ArgumentList.Add("127.0.0.1");
        startInfo.ArgumentList.Add("--port");
        startInfo.ArgumentList.Add(ServiceId.LiteLlmProxy.Port().ToString());
        return startInfo;
    }

    private async Task EnsureLiteLlmInstalledAsync()
    {
        var requirementsPath = Path.Combine(AppContext.BaseDirectory, "litellm-requirements.txt");
        var runtimeVersionPath = Path.Combine(AppContext.BaseDirectory, "litellm-runtime-version.txt");
        if (!File.Exists(requirementsPath) || !File.Exists(runtimeVersionPath))
        {
            throw new InvalidOperationException("The bundled LiteLLM runtime manifest is missing. Reinstall Daisy.");
        }

        var venvPython = Path.Combine(SettingsStore.LiteLlmVenvPath, "Scripts", "python.exe");
        var executable = Path.Combine(SettingsStore.LiteLlmVenvPath, "Scripts", "litellm.exe");
        var markerPath = Path.Combine(SettingsStore.LiteLlmVenvPath, ".daisy-managed-runtime");
        var desiredVersion = _settings.LiteLlmVersion.Trim();
        if (desiredVersion.Length == 0)
        {
            desiredVersion = SettingsStore.DefaultLiteLlmVersion;
        }

        var runtimeVersion = File.ReadAllText(runtimeVersionPath).Trim();
        if (runtimeVersion.Length == 0)
        {
            throw new InvalidOperationException("The bundled LiteLLM runtime manifest is invalid. Reinstall Daisy.");
        }
        var desiredMarker = $"{desiredVersion}\n{runtimeVersion}";
        var installedMarker = File.Exists(markerPath) ? File.ReadAllText(markerPath).Trim() : string.Empty;
        if (installedMarker == desiredMarker && File.Exists(executable))
        {
            return;
        }

        if (!File.Exists(venvPython))
        {
            var python = FindPythonLauncher()
                ?? throw new InvalidOperationException("Python 3.10 through 3.14 was not found. Install Python and enable its PATH option.");
            var arguments = new List<string>();
            if (Path.GetFileName(python).Equals("py.exe", StringComparison.OrdinalIgnoreCase))
            {
                arguments.Add("-3");
            }

            arguments.AddRange(["-m", "venv", SettingsStore.LiteLlmVenvPath]);
            await RunSetupProcessAsync(ServiceId.LiteLlmProxy, python, arguments);
        }

        var installArguments = new List<string>
        {
            "-m", "pip", "install", "--disable-pip-version-check", "--upgrade",
            $"litellm=={desiredVersion}", "-r", requirementsPath
        };
        await RunSetupProcessAsync(ServiceId.LiteLlmProxy, venvPython, installArguments);
        await RunSetupProcessAsync(
            ServiceId.LiteLlmProxy,
            venvPython,
            new[] { "-m", "pip", "uninstall", "--yes", "litellm-enterprise" });
        File.WriteAllText(markerPath, desiredMarker, Encoding.UTF8);
    }

    private async Task EnsureCopilotRuntimeInstalledAsync()
    {
        var bundledRuntime = Path.Combine(AppContext.BaseDirectory, "copilot-runtime");
        var bundledVersionPath = Path.Combine(bundledRuntime, "runtime-version.txt");
        if (!File.Exists(bundledVersionPath))
        {
            throw new InvalidOperationException("The bundled copilot-api runtime is missing. Reinstall Daisy.");
        }

        var desiredVersion = File.ReadAllText(bundledVersionPath).Trim();
        var markerPath = Path.Combine(SettingsStore.CopilotRuntimePath, ".installed-version");
        var runtimeMain = Path.Combine(
            SettingsStore.CopilotRuntimePath,
            "node_modules", "copilot-api", "dist", "main.js");
        var installedVersion = File.Exists(markerPath) ? File.ReadAllText(markerPath).Trim() : string.Empty;
        if (installedVersion == desiredVersion && File.Exists(runtimeMain))
        {
            return;
        }

        var node = FindExecutable("node.exe")
            ?? throw new InvalidOperationException("Node.js was not found. Install Node.js 20.16 or newer.");
        var npmCli = Path.Combine(
            Path.GetDirectoryName(node)!,
            "node_modules", "npm", "bin", "npm-cli.js");
        if (!File.Exists(npmCli))
        {
            throw new InvalidOperationException("npm was not found. Reinstall Node.js 20.16 or newer.");
        }

        Directory.CreateDirectory(SettingsStore.CopilotRuntimePath);
        foreach (var fileName in new[]
                 {
                     "package.json", "package-lock.json", "patch-copilot-api.mjs", "runtime-version.txt"
                 })
        {
            var source = Path.Combine(bundledRuntime, fileName);
            if (!File.Exists(source))
            {
                throw new InvalidOperationException($"The bundled copilot-api runtime is missing {fileName}.");
            }
            File.Copy(source, Path.Combine(SettingsStore.CopilotRuntimePath, fileName), overwrite: true);
        }

        await RunSetupProcessAsync(
            ServiceId.CopilotApi,
            node,
            new[] { npmCli, "ci", "--omit=dev", "--ignore-scripts", "--no-audit", "--no-fund" },
            SettingsStore.CopilotRuntimePath);
        await RunSetupProcessAsync(
            ServiceId.CopilotApi,
            node,
            new[] { Path.Combine(SettingsStore.CopilotRuntimePath, "patch-copilot-api.mjs") },
            SettingsStore.CopilotRuntimePath);
        File.WriteAllText(markerPath, desiredVersion, Encoding.UTF8);
    }

    private async Task RunSetupProcessAsync(
        ServiceId service,
        string executable,
        IEnumerable<string> arguments,
        string? workingDirectory = null)
    {
        var startInfo = CreateRedirectedStartInfo(executable, workingDirectory);
        foreach (var argument in arguments)
        {
            startInfo.ArgumentList.Add(argument);
        }

        using var process = new Process { StartInfo = startInfo };
        process.OutputDataReceived += (_, args) => AppendOutput(service, "setup", args.Data);
        process.ErrorDataReceived += (_, args) => AppendOutput(service, "setup", args.Data);
        try
        {
            lock (_processSync)
            {
                if (_isDisposing)
                {
                    return;
                }

                if (!process.Start())
                {
                    throw new InvalidOperationException($"Could not start {Path.GetFileName(executable)}.");
                }
                _setupProcesses.Add(process);
            }

            process.BeginOutputReadLine();
            process.BeginErrorReadLine();
            await process.WaitForExitAsync();
            if (process.ExitCode != 0)
            {
                throw new InvalidOperationException($"{Path.GetFileName(executable)} exited with code {process.ExitCode}.");
            }
        }
        finally
        {
            lock (_processSync)
            {
                _setupProcesses.Remove(process);
            }
        }
    }

    private static ProcessStartInfo CreateRedirectedStartInfo(
        string executable,
        string? workingDirectory = null) => new()
    {
        FileName = executable,
        WorkingDirectory = workingDirectory ?? Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
        UseShellExecute = false,
        RedirectStandardOutput = true,
        RedirectStandardError = true,
        CreateNoWindow = true,
        StandardOutputEncoding = Encoding.UTF8,
        StandardErrorEncoding = Encoding.UTF8
    };

    private static string? FindPythonLauncher() => FindExecutable("py.exe", "python.exe", "python3.exe");

    private static string? FindExecutable(params string[] names)
    {
        var pathEntries = (Environment.GetEnvironmentVariable("PATH") ?? string.Empty)
            .Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        foreach (var name in names)
        {
            if (Path.IsPathRooted(name) && File.Exists(name))
            {
                return name;
            }

            foreach (var directory in pathEntries)
            {
                var candidate = Path.Combine(directory.Trim('"'), name);
                if (File.Exists(candidate))
                {
                    return candidate;
                }
            }
        }

        return null;
    }

    private static void EnsurePortIsAvailable(ServiceId id)
    {
        var occupied = IPGlobalProperties.GetIPGlobalProperties()
            .GetActiveTcpListeners()
            .Any(endpoint => endpoint.Port == id.Port());
        if (occupied)
        {
            throw new InvalidOperationException(
                $"Port {id.Port()} is already in use. Stop the process using it, then start {id.DisplayName()} again.");
        }
    }

    private void OnProcessExited(ServiceId id, Process process)
    {
        if (_isDisposing)
        {
            return;
        }

        var exitCode = 0;
        try
        {
            exitCode = process.ExitCode;
        }
        catch (InvalidOperationException)
        {
            // The process may be racing with shutdown.
        }

        var wasCurrent = false;
        lock (_processSync)
        {
            if (_processes.TryGetValue(id, out var current) && ReferenceEquals(current, process))
            {
                _processes.Remove(id);
                wasCurrent = true;
            }
        }

        if (wasCurrent)
        {
            process.WaitForExit();
            _ = UpdateStateAsync(
                id,
                false,
                "Stopped",
                exitCode == 0 ? null : $"Exited with code {exitCode}");
            _ = Task.Run(async () =>
            {
                await Task.Delay(1_000);
                process.Dispose();
            });
        }
    }

    private void AppendOutput(ServiceId service, string stream, string? content)
    {
        if (_isDisposing || content is null)
        {
            return;
        }

        var dispatcher = System.Windows.Application.Current?.Dispatcher;
        if (dispatcher is null || dispatcher.CheckAccess())
        {
            _logs.Append(service, stream, content);
        }
        else
        {
            dispatcher.BeginInvoke(() => _logs.Append(service, stream, content));
        }
    }

    private async Task UpdateStateAsync(ServiceId id, bool isRunning, string status, string? error)
    {
        if (_isDisposing)
        {
            return;
        }

        var dispatcher = System.Windows.Application.Current?.Dispatcher;
        if (dispatcher is null || dispatcher.CheckAccess())
        {
            Update();
            return;
        }

        await dispatcher.InvokeAsync(Update);
        return;

        void Update()
        {
            var state = StateFor(id);
            state.IsRunning = isRunning;
            state.StatusText = status;
            state.LastError = error;
            StateChanged?.Invoke(this, EventArgs.Empty);
        }
    }

    private static void TryKillProcessTree(Process process)
    {
        try
        {
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
            }
        }
        catch (ObjectDisposedException)
        {
            // Already cleaned up.
        }
        catch (InvalidOperationException)
        {
            // Already exited.
        }
        catch (System.ComponentModel.Win32Exception)
        {
            // The OS may already be tearing down the process tree.
        }
    }
}
