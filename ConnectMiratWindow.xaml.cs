using System.Diagnostics;
using System.Windows;
using System.Windows.Input;
using iPhotoImporter.Models;
using iPhotoImporter.Services;
using iPhotoImporter.ViewModels;

namespace iPhotoImporter;

/// <summary>
/// Diàleg de vinculació amb Mirat via device-code flow.
///
/// Flux:
///   1. En obrir-se, demana un device_code al servidor (<c>/api/desktop/device-code</c>).
///   2. Mostra el <c>user_code</c> i obre el navegador a <c>verification_url_complete</c>.
///   3. Fa polling a <c>/api/desktop/token</c> fins rebre un access_token, caducar o cancel·lar.
///   4. Si s'autoritza, crea un <see cref="MiratDestination"/> amb <c>AccessToken</c> i
///      el desa al <see cref="MainViewModel"/>. L'usuari no veu ni enganxa cap clau API.
///
/// Basat en la versió Swift <c>ConnectMiratSheet</c>.
/// </summary>
public partial class ConnectMiratWindow : Window
{
    /// <summary>Host públic de Mirat. Hardcoded: els usuaris mai toquen URLs.</summary>
    private const string MiratBaseUrl = "https://www.miratfotos.com";

    private readonly MainViewModel _vm;
    private CancellationTokenSource? _cts;

    public ConnectMiratWindow(MainViewModel vm)
    {
        InitializeComponent();
        _vm = vm;
    }

    private async void Window_Loaded(object sender, RoutedEventArgs e)
    {
        await BeginFlowAsync();
    }

    private void Window_Closed(object? sender, EventArgs e)
    {
        _cts?.Cancel();
    }

    private async void Retry_Click(object sender, RoutedEventArgs e)
    {
        await BeginFlowAsync();
    }

    private void Close_Click(object sender, RoutedEventArgs e)
    {
        Close();
    }

    private void VerificationUrl_Click(object sender, MouseButtonEventArgs e)
    {
        var url = VerificationUrlText.Tag as string;
        if (!string.IsNullOrEmpty(url)) OpenBrowser(url);
    }

    private async Task BeginFlowAsync()
    {
        _cts?.Cancel();
        _cts = new CancellationTokenSource();
        var ct = _cts.Token;

        ShowWaiting(initialHint: "Demanant codi al servidor...");

        var deviceName = Environment.MachineName;
        using var client = new MiratDeviceCodeClient(MiratBaseUrl);

        DeviceCodeResponse dc;
        try
        {
            dc = await client.RequestDeviceCodeAsync(deviceName, ct);
        }
        catch (OperationCanceledException)
        {
            return;
        }
        catch (Exception ex)
        {
            ShowError(ex.Message);
            return;
        }

        // Pinta el codi i obre navegador
        UserCodeText.Text = dc.UserCode;
        UserCodeBox.Visibility = Visibility.Visible;
        WaitingHint.Text = "Entra aquest codi al navegador";
        BrowserHint.Visibility = Visibility.Visible;
        VerificationUrlText.Text = dc.VerificationUrl;
        VerificationUrlText.Tag = dc.VerificationUrlComplete;
        VerificationUrlText.Visibility = Visibility.Visible;
        PollingIndicator.Visibility = Visibility.Visible;

        OpenBrowser(dc.VerificationUrlComplete);

        AuthorizationResult result;
        try
        {
            result = await client.PollForTokenAsync(
                dc.DeviceCode,
                dc.Interval,
                dc.ExpiresAt,
                onProgress: null,
                ct: ct);
        }
        catch (OperationCanceledException)
        {
            return;
        }
        catch (Exception ex)
        {
            ShowError(ex.Message);
            return;
        }

        HandleResult(result, deviceName);
    }

    private void HandleResult(AuthorizationResult result, string deviceName)
    {
        switch (result.Kind)
        {
            case AuthorizationResult.Outcome.Authorized:
                var token = result.Token;
                if (token is null || string.IsNullOrEmpty(token.AccessToken) || token.Grup is null)
                {
                    ShowError("Resposta incompleta del servidor.");
                    return;
                }
                var grup = token.Grup;
                var user = token.User;
                var dest = new MiratDestination
                {
                    BaseUrl = MiratBaseUrl,
                    AccessToken = token.AccessToken,
                    ApiKey = "",
                    GrupId = grup.Id,
                    GrupNom = grup.Nom ?? "",
                    UserId = user?.Id,
                    UserName = user?.Name,
                    Nom = !string.IsNullOrEmpty(user?.Name)
                        ? $"{user!.Name} · {grup.Nom ?? ""}"
                        : (grup.Nom ?? deviceName),
                };
                _vm.AddOrUpdateMiratDestination(dest);
                if (_vm.ActiveMiratDestination == null)
                    _vm.ActiveMiratDestination = dest;

                ShowSuccess(user, grup);
                break;

            case AuthorizationResult.Outcome.Expired:
                ShowError("El codi ha caducat. Torna a provar.");
                break;
            case AuthorizationResult.Outcome.Revoked:
                ShowError("La sessió s'ha revocat abans d'utilitzar-la.");
                break;
            case AuthorizationResult.Outcome.Cancelled:
                // L'usuari ha tancat el diàleg — cap canvi d'estat.
                break;
        }
    }

    private void ShowWaiting(string initialHint)
    {
        WaitingPanel.Visibility = Visibility.Visible;
        SuccessPanel.Visibility = Visibility.Collapsed;
        ErrorPanel.Visibility = Visibility.Collapsed;

        WaitingHint.Text = initialHint;
        UserCodeBox.Visibility = Visibility.Collapsed;
        BrowserHint.Visibility = Visibility.Collapsed;
        VerificationUrlText.Visibility = Visibility.Collapsed;
        PollingIndicator.Visibility = Visibility.Collapsed;
        UserCodeText.Text = "";

        CloseButton.Content = "Cancel·lar";
    }

    private void ShowSuccess(TokenUser? user, TokenGrup grup)
    {
        WaitingPanel.Visibility = Visibility.Collapsed;
        SuccessPanel.Visibility = Visibility.Visible;
        ErrorPanel.Visibility = Visibility.Collapsed;

        SuccessUserText.Text = user?.Name ?? user?.Email ?? "";
        SuccessGrupText.Text = !string.IsNullOrEmpty(grup.Nom)
            ? $"Fotos pujades a: {grup.Nom}"
            : "";
        CloseButton.Content = "Tancar";
    }

    private void ShowError(string message)
    {
        WaitingPanel.Visibility = Visibility.Collapsed;
        SuccessPanel.Visibility = Visibility.Collapsed;
        ErrorPanel.Visibility = Visibility.Visible;

        ErrorMessageText.Text = message;
        CloseButton.Content = "Tancar";
    }

    private static void OpenBrowser(string url)
    {
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = url,
                UseShellExecute = true,
            });
        }
        catch
        {
            // Si falla, el link clicable a la UI serveix de fallback.
        }
    }
}
