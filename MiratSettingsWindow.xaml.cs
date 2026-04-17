using System.Windows;
using System.Windows.Controls;
using iPhotoImporter.Models;
using iPhotoImporter.Services;
using iPhotoImporter.ViewModels;

namespace iPhotoImporter;

/// <summary>
/// Finestra de configuració de destins Mirat. Permet llistar els existents,
/// afegir-ne de nous i editar/eliminar els actuals.
///
/// Flux afegir destí:
///   1. URL base + API Key
///   2. "Provar connexió" → llista grups
///   3. Seleccionar grup → llista àlbums
///   4. (opcional) Seleccionar àlbum
///   5. Nom descriptiu → "Desar"
/// </summary>
public partial class MiratSettingsWindow : Window
{
    private readonly MainViewModel _vm;
    private MiratDestination _editing = new();
    private List<MiratGrup> _grups = [];
    private List<MiratAlbum> _albums = [];

    public MiratSettingsWindow(MainViewModel vm)
    {
        InitializeComponent();
        _vm = vm;
        DestinationsList.ItemsSource = vm.MiratDestinations;
        ResetForm();
    }

    private void ResetForm()
    {
        _editing = new MiratDestination();
        BaseUrlInput.Text = "https://www.miratfotos.com";
        ApiKeyInput.Password = "";
        NomInput.Text = "";
        GrupCombo.ItemsSource = null;
        GrupCombo.IsEnabled = false;
        AlbumCombo.ItemsSource = null;
        AlbumCombo.IsEnabled = false;
        SaveButton.IsEnabled = false;
        StatusText.Text = "";
    }

    private async void Connect_Click(object sender, RoutedEventArgs e)
    {
        var url = BaseUrlInput.Text.Trim();
        var key = ApiKeyInput.Password;
        if (string.IsNullOrWhiteSpace(url) || string.IsNullOrWhiteSpace(key))
        {
            StatusText.Text = "Cal URL i API Key.";
            StatusText.Foreground = FindResource("DangerColor") as System.Windows.Media.Brush;
            return;
        }

        StatusText.Text = "Connectant...";
        StatusText.Foreground = FindResource("TextSecondary") as System.Windows.Media.Brush;
        ConnectButton.IsEnabled = false;

        _editing.BaseUrl = url;
        _editing.ApiKey = key;

        try
        {
            using var svc = new MiratService(_editing);
            _grups = await svc.ListGroupsAsync();
            GrupCombo.ItemsSource = _grups;
            GrupCombo.IsEnabled = _grups.Count > 0;
            StatusText.Text = $"{_grups.Count} grup(s) trobat(s). Selecciona'n un.";
            StatusText.Foreground = FindResource("SuccessColor") as System.Windows.Media.Brush;
        }
        catch (Exception ex)
        {
            StatusText.Text = $"Error: {ex.Message}";
            StatusText.Foreground = FindResource("DangerColor") as System.Windows.Media.Brush;
        }
        finally
        {
            ConnectButton.IsEnabled = true;
        }
    }

    private async void Grup_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (GrupCombo.SelectedItem is not MiratGrup g)
        {
            SaveButton.IsEnabled = false;
            return;
        }
        _editing.GrupId = g.Id;
        // Guardem l'etiqueta combinada (nom BD + slug si n'hi ha) per al DisplayLabel
        // del destí — el camp `nom` a la BD sol ser "Família" per default, el slug
        // és l'identificador real visible a la URL.
        _editing.GrupNom = !string.IsNullOrEmpty(g.Slug) ? $"{g.Nom} ({g.Slug})" : g.Nom;

        // Pre-omplir nom descriptiu amb el slug (més descriptiu que "Família")
        if (string.IsNullOrWhiteSpace(NomInput.Text))
            NomInput.Text = !string.IsNullOrEmpty(g.Slug) ? g.Slug : g.Nom;

        // Carregar àlbums del grup
        AlbumCombo.ItemsSource = null;
        AlbumCombo.IsEnabled = false;
        try
        {
            using var svc = new MiratService(_editing);
            _albums = await svc.ListAlbumsAsync(g.Id);
            var withNone = new List<MiratAlbum> { new("", "(Sense àlbum)", null, false) };
            withNone.AddRange(_albums);
            AlbumCombo.ItemsSource = withNone;
            AlbumCombo.SelectedIndex = 0;
            AlbumCombo.IsEnabled = withNone.Count > 1;
            SaveButton.IsEnabled = true;
        }
        catch (Exception ex)
        {
            StatusText.Text = $"Error carregant àlbums: {ex.Message}";
            StatusText.Foreground = FindResource("DangerColor") as System.Windows.Media.Brush;
            SaveButton.IsEnabled = true; // tot i sense àlbums, pot desar-se
        }
    }

    private void Save_Click(object sender, RoutedEventArgs e)
    {
        if (AlbumCombo.SelectedItem is MiratAlbum a && !string.IsNullOrEmpty(a.Id))
        {
            _editing.AlbumId = a.Id;
            _editing.AlbumNom = a.Nom;
        }
        else
        {
            _editing.AlbumId = null;
            _editing.AlbumNom = null;
        }
        _editing.Nom = string.IsNullOrWhiteSpace(NomInput.Text)
            ? _editing.DisplayLabel
            : NomInput.Text.Trim();

        _vm.AddOrUpdateMiratDestination(_editing);

        // Si és el primer, activar-lo automàticament
        if (_vm.ActiveMiratDestination == null)
            _vm.ActiveMiratDestination = _editing;

        StatusText.Text = $"Desat: {_editing.DisplayLabel}";
        StatusText.Foreground = FindResource("SuccessColor") as System.Windows.Media.Brush;
        ResetForm();
    }

    private void Cancel_Click(object sender, RoutedEventArgs e)
    {
        Close();
    }

    private void RemoveDestination_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button b && b.DataContext is MiratDestination d)
            _vm.RemoveMiratDestinationCommand.Execute(d);
    }

    private void EditDestination_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button b || b.DataContext is not MiratDestination d) return;
        _editing = new MiratDestination
        {
            Id = d.Id,
            Nom = d.Nom,
            BaseUrl = d.BaseUrl,
            ApiKey = d.ApiKey,
            GrupId = d.GrupId,
            GrupNom = d.GrupNom,
            AlbumId = d.AlbumId,
            AlbumNom = d.AlbumNom,
            PujatPer = d.PujatPer,
        };
        BaseUrlInput.Text = d.BaseUrl;
        ApiKeyInput.Password = d.ApiKey;
        NomInput.Text = d.Nom;
        StatusText.Text = $"Editant {d.DisplayLabel}. Torna a provar connexió per actualitzar grups/àlbums.";
        StatusText.Foreground = FindResource("TextSecondary") as System.Windows.Media.Brush;
    }
}
