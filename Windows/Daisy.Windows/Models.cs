using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace Daisy.Windows;

public enum ServiceId
{
    CopilotApi,
    LiteLlmProxy
}

public static class ServiceIdExtensions
{
    public static string DisplayName(this ServiceId id) => id switch
    {
        ServiceId.CopilotApi => "copilot-api",
        ServiceId.LiteLlmProxy => "LiteLLM Proxy",
        _ => id.ToString()
    };

    public static string Endpoint(this ServiceId id) => id switch
    {
        ServiceId.CopilotApi => "http://localhost:4141",
        ServiceId.LiteLlmProxy => "http://localhost:4000",
        _ => string.Empty
    };

    public static int Port(this ServiceId id) => id switch
    {
        ServiceId.CopilotApi => 4141,
        ServiceId.LiteLlmProxy => 4000,
        _ => 0
    };
}

public sealed class ManagedServiceState : INotifyPropertyChanged
{
    private bool _isRunning;
    private string _statusText = "Stopped";
    private string? _lastError;

    public ManagedServiceState(ServiceId id)
    {
        Id = id;
    }

    public ServiceId Id { get; }
    public string DisplayName => Id.DisplayName();
    public string Endpoint => Id.Endpoint();

    public bool IsRunning
    {
        get => _isRunning;
        set => SetField(ref _isRunning, value);
    }

    public string StatusText
    {
        get => _statusText;
        set => SetField(ref _statusText, value);
    }

    public string? LastError
    {
        get => _lastError;
        set => SetField(ref _lastError, value);
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    private void SetField<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
        {
            return;
        }

        field = value;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}

public sealed class ModelListItem
{
    public required string Id { get; init; }
    public bool IsConfigured { get; init; }
    public string StatusText => IsConfigured ? "Configured" : "Available";
    public string ActionText => IsConfigured ? "Remove" : "Add to LiteLLM";
}
