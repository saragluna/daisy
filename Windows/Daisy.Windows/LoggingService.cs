using System.Collections.ObjectModel;

namespace Daisy.Windows;

public sealed class LoggingService
{
    private const int MaxLogLines = 5_000;
    private readonly Dictionary<ServiceId, List<string>> _serviceLines = new();

    public ObservableCollection<string> CombinedLines { get; } = new();

    public event EventHandler? LogsChanged;

    public void Append(ServiceId service, string stream, string content)
    {
        var rawLines = content.Replace("\r\n", "\n").Split('\n');
        var serviceLines = _serviceLines.GetValueOrDefault(service) ?? new List<string>();
        _serviceLines[service] = serviceLines;

        foreach (var rawLine in rawLines)
        {
            serviceLines.Add($"[{stream}] {rawLine}");
            CombinedLines.Add($"[{service.DisplayName()}][{stream}] {rawLine}");
        }

        Trim(serviceLines);
        while (CombinedLines.Count > MaxLogLines)
        {
            CombinedLines.RemoveAt(0);
        }

        LogsChanged?.Invoke(this, EventArgs.Empty);
    }

    public IReadOnlyList<string> LinesFor(ServiceId? service) => service is null
        ? CombinedLines.ToList()
        : _serviceLines.GetValueOrDefault(service.Value)?.ToList() ?? [];

    public void Clear()
    {
        _serviceLines.Clear();
        CombinedLines.Clear();
        LogsChanged?.Invoke(this, EventArgs.Empty);
    }

    private static void Trim(List<string> lines)
    {
        if (lines.Count > MaxLogLines)
        {
            lines.RemoveRange(0, lines.Count - MaxLogLines);
        }
    }
}
