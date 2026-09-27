using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Net.Http;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using Daisy.Core;
using Forms = System.Windows.Forms;

namespace Daisy.Windows;

public partial class MainWindow : Window
{
    private readonly SettingsStore _settings = new();
    private readonly LoggingService _logs = new();
    private readonly GitHubDeviceFlowService _deviceFlow = new();
    private readonly HttpClient _httpClient = new();
    private readonly ServiceManager _serviceManager;
    private readonly List<string> _allModels = [];
    private readonly Forms.NotifyIcon _trayIcon;
    private readonly Forms.ToolStripMenuItem _copilotTrayItem;
    private readonly Forms.ToolStripMenuItem _liteLlmTrayItem;
    private CancellationTokenSource? _deviceFlowCancellation;
    private bool _isInitializing = true;
    private bool _isExiting;
    private bool _shutdownPerformed;
    private bool _syncingTokenFields;

    public MainWindow()
    {
        _settings.Load();
        _serviceManager = new ServiceManager(_settings, _logs);

        InitializeComponent();
        DataContext = this;

        _logs.LogsChanged += (_, _) => RefreshLogs();
        _serviceManager.StateChanged += (_, _) => RefreshServiceSummary();

        var trayMenu = new Forms.ContextMenuStrip();
        trayMenu.Items.Add("Open Daisy", null, (_, _) => Dispatcher.Invoke(ShowMainWindow));
        trayMenu.Items.Add(new Forms.ToolStripSeparator());
        _copilotTrayItem = new Forms.ToolStripMenuItem("Start copilot-api", null, async (_, _) =>
        {
            await ToggleServiceAsync(ServiceId.CopilotApi);
        });
        _liteLlmTrayItem = new Forms.ToolStripMenuItem("Start LiteLLM Proxy", null, async (_, _) =>
        {
            await ToggleServiceAsync(ServiceId.LiteLlmProxy);
        });
        trayMenu.Items.Add(_copilotTrayItem);
        trayMenu.Items.Add(_liteLlmTrayItem);
        trayMenu.Items.Add(new Forms.ToolStripSeparator());
        trayMenu.Items.Add("Exit", null, (_, _) => Dispatcher.Invoke(ExitApplication));

        _trayIcon = new Forms.NotifyIcon
        {
            Icon = System.Drawing.SystemIcons.Application,
            Text = "Daisy — services stopped",
            Visible = true,
            ContextMenuStrip = trayMenu
        };
        _trayIcon.DoubleClick += (_, _) => Dispatcher.Invoke(ShowMainWindow);
    }

    public ObservableCollection<ManagedServiceState> Services => _serviceManager.Services;
    public ObservableCollection<ModelListItem> VisibleModels { get; } = new();

    public void StopServicesForExit()
    {
        if (_shutdownPerformed)
        {
            return;
        }

        _shutdownPerformed = true;
        _deviceFlowCancellation?.Cancel();
        _serviceManager.StopAllForExit();
        _trayIcon.Visible = false;
    }

    private async void Window_Loaded(object sender, RoutedEventArgs e)
    {
        TokenPasswordBox.Password = _settings.Token;
        TokenTextBox.Text = _settings.Token;
        LiteLlmConfigBox.Text = _settings.LiteLlmConfig;
        LiteLlmVersionBox.Text = _settings.LiteLlmVersion;
        ClaudeSettingsBox.Text = _settings.ClaudeSettings;
        OpenAtLoginCheckBox.IsChecked = _settings.IsOpenAtLoginEnabled();

        _allModels.AddRange(_settings.LoadCachedModels());
        RebuildVisibleModels();
        await RefreshInstalledVersionAsync();

        _isInitializing = false;
        RefreshServiceSummary();
        if (Environment.GetCommandLineArgs().Any(argument =>
                argument.Equals("--minimized", StringComparison.OrdinalIgnoreCase)))
        {
            Hide();
        }

        await _serviceManager.StartAllAsync();
    }

    private void Window_Closing(object? sender, CancelEventArgs e)
    {
        if (_isExiting)
        {
            return;
        }

        e.Cancel = true;
        Hide();
        _trayIcon.ShowBalloonTip(
            1_500,
            "Daisy is still running",
            "Use the tray icon to reopen Daisy or stop its services.",
            Forms.ToolTipIcon.Info);
    }

    private async void ServiceStart_Click(object sender, RoutedEventArgs e)
    {
        if (GetServiceId(sender) is { } service)
        {
            await _serviceManager.StartAsync(service);
        }
    }

    private async void ServiceStop_Click(object sender, RoutedEventArgs e)
    {
        if (GetServiceId(sender) is { } service)
        {
            await _serviceManager.StopAsync(service);
        }
    }

    private async void ServiceRestart_Click(object sender, RoutedEventArgs e)
    {
        if (GetServiceId(sender) is { } service)
        {
            await _serviceManager.RestartAsync(service);
        }
    }

    private static ServiceId? GetServiceId(object sender) => (sender as FrameworkElement)?.Tag switch
    {
        ServiceId id => id,
        string text when Enum.TryParse<ServiceId>(text, out var id) => id,
        _ => null
    };

    private async Task ToggleServiceAsync(ServiceId service)
    {
        if (_serviceManager.StateFor(service).IsRunning)
        {
            await _serviceManager.StopAsync(service);
        }
        else
        {
            await _serviceManager.StartAsync(service);
        }
    }

    private void RefreshServiceSummary()
    {
        if (!Dispatcher.CheckAccess())
        {
            Dispatcher.BeginInvoke(RefreshServiceSummary);
            return;
        }

        var runningCount = Services.Count(service => service.IsRunning);
        RunningSummaryText.Text = $"{runningCount}/{Services.Count} running";
        SummaryDot.Fill = new SolidColorBrush((System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString(
            runningCount == Services.Count ? "#22C55E" : "#F59E0B"));
        _trayIcon.Text = runningCount == Services.Count
            ? "Daisy — all services running"
            : $"Daisy — {runningCount}/{Services.Count} services running";
        _copilotTrayItem.Text = Services.Single(state => state.Id == ServiceId.CopilotApi).IsRunning
            ? "Stop copilot-api"
            : "Start copilot-api";
        _liteLlmTrayItem.Text = Services.Single(state => state.Id == ServiceId.LiteLlmProxy).IsRunning
            ? "Stop LiteLLM Proxy"
            : "Start LiteLLM Proxy";
    }

    private async void RefreshModels_Click(object sender, RoutedEventArgs e)
    {
        RefreshModelsButton.IsEnabled = false;
        ModelsStatusText.Text = "Refreshing models…";
        try
        {
            using var response = await _httpClient.GetAsync(ModelCatalog.ModelsUri);
            response.EnsureSuccessStatusCode();
            var models = ModelCatalog.ModelsFromResponse(await response.Content.ReadAsStringAsync());

            _allModels.Clear();
            _allModels.AddRange(models);
            _settings.SaveCachedModels(models);
            RebuildVisibleModels();
            ModelsStatusText.Text = $"{models.Count} models available";
        }
        catch (Exception exception)
        {
            ModelsStatusText.Text = $"Refresh failed: {exception.Message}";
        }
        finally
        {
            RefreshModelsButton.IsEnabled = true;
        }
    }

    private void ModelSearchBox_TextChanged(object sender, TextChangedEventArgs e) => RebuildVisibleModels();

    private void RebuildVisibleModels()
    {
        if (ModelsList is null)
        {
            return;
        }

        var filtered = ModelCatalog.Filtered(_allModels, ModelSearchBox.Text);
        VisibleModels.Clear();
        foreach (var model in filtered)
        {
            VisibleModels.Add(new ModelListItem
            {
                Id = model,
                IsConfigured = _settings.IsModelConfigured(model)
            });
        }

        ModelsStatusText.Text = _allModels.Count == 0
            ? "No models cached. Start copilot-api, then refresh."
            : $"{VisibleModels.Count} of {_allModels.Count} models shown";
    }

    private void ModelAction_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is not ModelListItem item)
        {
            return;
        }

        try
        {
            if (item.IsConfigured)
            {
                var result = System.Windows.MessageBox.Show(
                    this,
                    $"Remove {item.Id} from the LiteLLM configuration?",
                    "Remove model",
                    MessageBoxButton.YesNo,
                    MessageBoxImage.Question);
                if (result != MessageBoxResult.Yes)
                {
                    return;
                }

                _settings.RemoveModel(item.Id);
                ConfigMessageText.Text = $"Removed {item.Id}. Restart LiteLLM Proxy to apply.";
            }
            else
            {
                var modelName = PromptForModelName(item.Id);
                if (modelName is null)
                {
                    return;
                }

                _settings.AddModel(item.Id, modelName);
                ConfigMessageText.Text = $"Added {item.Id} as {modelName}. Restart LiteLLM Proxy to apply.";
            }

            LiteLlmConfigBox.Text = _settings.LiteLlmConfig;
            RebuildVisibleModels();
        }
        catch (Exception exception)
        {
            System.Windows.MessageBox.Show(this, exception.Message, "Daisy", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private string? PromptForModelName(string modelId)
    {
        var input = new System.Windows.Controls.TextBox { Text = modelId, MinWidth = 360 };
        var dialog = new Window
        {
            Title = "Add to LiteLLM",
            Owner = this,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            SizeToContent = SizeToContent.WidthAndHeight,
            ResizeMode = ResizeMode.NoResize,
            Content = new StackPanel
            {
                Margin = new Thickness(18),
                Children =
                {
                    new TextBlock
                    {
                        Text = $"Choose the name clients will use for {modelId}.",
                        Margin = new Thickness(0, 0, 0, 10)
                    },
                    input
                }
            }
        };

        var buttons = new StackPanel
        {
            Orientation = System.Windows.Controls.Orientation.Horizontal,
            HorizontalAlignment = System.Windows.HorizontalAlignment.Right,
            Margin = new Thickness(0, 14, 0, 0)
        };
        var cancel = new System.Windows.Controls.Button { Content = "Cancel", IsCancel = true };
        var add = new System.Windows.Controls.Button { Content = "Add", IsDefault = true };
        add.Click += (_, _) =>
        {
            if (!string.IsNullOrWhiteSpace(input.Text))
            {
                dialog.DialogResult = true;
            }
        };
        buttons.Children.Add(cancel);
        buttons.Children.Add(add);
        ((StackPanel)dialog.Content).Children.Add(buttons);
        input.SelectAll();
        input.Focus();

        return dialog.ShowDialog() == true ? input.Text.Trim() : null;
    }

    private void TokenPasswordBox_PasswordChanged(object sender, RoutedEventArgs e)
    {
        if (_syncingTokenFields)
        {
            return;
        }

        _syncingTokenFields = true;
        TokenTextBox.Text = TokenPasswordBox.Password;
        _syncingTokenFields = false;
    }

    private void TokenTextBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (_syncingTokenFields)
        {
            return;
        }

        _syncingTokenFields = true;
        TokenPasswordBox.Password = TokenTextBox.Text;
        _syncingTokenFields = false;
    }

    private void ShowToken_Changed(object sender, RoutedEventArgs e)
    {
        if (ShowTokenCheckBox.IsChecked == true)
        {
            TokenTextBox.Text = TokenPasswordBox.Password;
            TokenTextBox.Visibility = Visibility.Visible;
            TokenPasswordBox.Visibility = Visibility.Collapsed;
        }
        else
        {
            TokenPasswordBox.Password = TokenTextBox.Text;
            TokenTextBox.Visibility = Visibility.Collapsed;
            TokenPasswordBox.Visibility = Visibility.Visible;
        }
    }

    private void SaveToken_Click(object sender, RoutedEventArgs e)
    {
        RunConfigAction(() =>
        {
            _settings.SaveToken(CurrentToken());
            ConfigMessageText.Text = "Token saved. Restart copilot-api to apply it.";
        });
    }

    private async void GetToken_Click(object sender, RoutedEventArgs e)
    {
        _deviceFlowCancellation?.Cancel();
        _deviceFlowCancellation = new CancellationTokenSource();
        var cancellationToken = _deviceFlowCancellation.Token;
        GetTokenButton.IsEnabled = false;
        ConfigMessageText.Text = "Starting GitHub device flow…";

        try
        {
            var session = await _deviceFlow.BeginAsync(cancellationToken);
            DeviceCodeText.Text = session.UserCode;
            DeviceFlowPanel.Visibility = Visibility.Visible;
            ConfigMessageText.Text = "Complete authorization in your browser.";

            var token = await _deviceFlow.PollForTokenAsync(session, cancellationToken);
            _settings.SaveToken(token);
            TokenPasswordBox.Password = token;
            TokenTextBox.Text = token;
            DeviceFlowPanel.Visibility = Visibility.Collapsed;
            ConfigMessageText.Text = "Copilot token saved.";
        }
        catch (OperationCanceledException)
        {
            ConfigMessageText.Text = "Device flow cancelled.";
        }
        catch (Exception exception)
        {
            ConfigMessageText.Text = exception.Message;
        }
        finally
        {
            DeviceFlowPanel.Visibility = Visibility.Collapsed;
            GetTokenButton.IsEnabled = true;
        }
    }

    private string CurrentToken() => ShowTokenCheckBox.IsChecked == true
        ? TokenTextBox.Text
        : TokenPasswordBox.Password;

    private void CopyDeviceCode_Click(object sender, RoutedEventArgs e)
    {
        if (DeviceCodeText.Text.Length > 0)
        {
            System.Windows.Clipboard.SetText(DeviceCodeText.Text);
        }
    }

    private void CancelDeviceFlow_Click(object sender, RoutedEventArgs e) => _deviceFlowCancellation?.Cancel();

    private void SaveLiteLlmVersion_Click(object sender, RoutedEventArgs e)
    {
        RunConfigAction(() =>
        {
            _settings.SaveLiteLlmVersion(LiteLlmVersionBox.Text);
            LiteLlmVersionBox.Text = _settings.LiteLlmVersion;
            ConfigMessageText.Text = "LiteLLM version saved. Restart the proxy to apply it.";
        });
    }

    private void SaveLiteLlmConfig_Click(object sender, RoutedEventArgs e)
    {
        RunConfigAction(() =>
        {
            _settings.SaveLiteLlmConfig(LiteLlmConfigBox.Text);
            ConfigMessageText.Text = "LiteLLM config saved. Restart the proxy to apply it.";
            RebuildVisibleModels();
        });
    }

    private async void RefreshInstalledVersion_Click(object sender, RoutedEventArgs e) => await RefreshInstalledVersionAsync();

    private async Task RefreshInstalledVersionAsync()
    {
        try
        {
            var version = await _settings.GetInstalledLiteLlmVersionAsync();
            InstalledVersionText.Text = $"Installed: {version ?? "Not installed"}";
        }
        catch (Exception exception)
        {
            InstalledVersionText.Text = $"Installed: unknown ({exception.Message})";
        }
    }

    private void FormatClaudeSettings_Click(object sender, RoutedEventArgs e)
    {
        var formatted = SettingsStore.FormatJson(ClaudeSettingsBox.Text);
        if (formatted is null)
        {
            ConfigMessageText.Text = SettingsStore.ValidateJson(ClaudeSettingsBox.Text);
            return;
        }

        ClaudeSettingsBox.Text = formatted;
        ConfigMessageText.Text = "JSON formatted.";
    }

    private void SaveClaudeSettings_Click(object sender, RoutedEventArgs e)
    {
        RunConfigAction(() =>
        {
            _settings.SaveClaudeSettings(ClaudeSettingsBox.Text);
            ClaudeSettingsBox.Text = _settings.ClaudeSettings;
            ConfigMessageText.Text = "Claude Code settings saved.";
        });
    }

    private void OpenAtLogin_Changed(object sender, RoutedEventArgs e)
    {
        if (_isInitializing)
        {
            return;
        }

        RunConfigAction(() =>
        {
            _settings.SetOpenAtLogin(OpenAtLoginCheckBox.IsChecked == true);
            ConfigMessageText.Text = OpenAtLoginCheckBox.IsChecked == true
                ? "Daisy will open when you sign in."
                : "Daisy was removed from startup.";
        });
    }

    private async void RestartCopilot_Click(object sender, RoutedEventArgs e) =>
        await _serviceManager.RestartAsync(ServiceId.CopilotApi);

    private async void RestartLiteLlm_Click(object sender, RoutedEventArgs e)
    {
        await _serviceManager.RestartAsync(ServiceId.LiteLlmProxy);
        await RefreshInstalledVersionAsync();
    }

    private void RunConfigAction(Action action)
    {
        try
        {
            action();
        }
        catch (Exception exception)
        {
            ConfigMessageText.Text = exception.Message;
        }
    }

    private void LogFilter_Changed(object sender, EventArgs e) => RefreshLogs();

    private void RefreshLogs()
    {
        if (!Dispatcher.CheckAccess())
        {
            Dispatcher.BeginInvoke(RefreshLogs);
            return;
        }

        if (LogsTextBox is null || LogServiceFilter is null || LogSearchBox is null)
        {
            return;
        }

        ServiceId? service = null;
        if (LogServiceFilter.SelectedItem is ComboBoxItem { Tag: string tag }
            && Enum.TryParse<ServiceId>(tag, out var parsed))
        {
            service = parsed;
        }

        var search = LogSearchBox.Text.Trim();
        var lines = _logs.LinesFor(service);
        if (search.Length > 0)
        {
            lines = lines.Where(line => line.Contains(search, StringComparison.OrdinalIgnoreCase)).ToList();
        }

        LogsTextBox.Text = string.Join(Environment.NewLine, lines);
        LogLineCountText.Text = $"{lines.Count} lines";
        if (AutoScrollCheckBox.IsChecked == true)
        {
            LogsTextBox.ScrollToEnd();
        }
    }

    private void ClearLogs_Click(object sender, RoutedEventArgs e) => _logs.Clear();

    private void ShowMainWindow()
    {
        Show();
        WindowState = WindowState.Normal;
        Activate();
        Topmost = true;
        Topmost = false;
        Focus();
    }

    private void ExitApplication()
    {
        if (_isExiting)
        {
            return;
        }

        _isExiting = true;
        StopServicesForExit();
        _trayIcon.Dispose();
        _httpClient.Dispose();
        _serviceManager.Dispose();
        System.Windows.Application.Current.Shutdown();
    }
}
