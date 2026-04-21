using System.Collections.Specialized;
using System.Windows;
using System.Windows.Controls;
using iPhotoImporter.Models;
using iPhotoImporter.ViewModels;

namespace iPhotoImporter;

/// <summary>
/// Finestra de gestió de destins Mirat.
///
/// UX simplificada (paritat amb macOS): l'única via per crear un destí és el device-code
/// flow a través de <see cref="ConnectMiratWindow"/>. Des d'aquí l'usuari pot veure els
/// destins vinculats i eliminar-los — res més. Les configuracions legacy creades amb
/// API Key abans del device-code flow segueixen apareixent i es poden eliminar igual.
/// </summary>
public partial class MiratSettingsWindow : Window
{
    private readonly MainViewModel _vm;

    public MiratSettingsWindow(MainViewModel vm)
    {
        InitializeComponent();
        _vm = vm;
        DestinationsList.ItemsSource = vm.MiratDestinations;
        vm.MiratDestinations.CollectionChanged += Destinations_CollectionChanged;
        UpdateEmptyState();
    }

    private void Destinations_CollectionChanged(object? sender, NotifyCollectionChangedEventArgs e)
    {
        UpdateEmptyState();
    }

    private void UpdateEmptyState()
    {
        var empty = _vm.MiratDestinations.Count == 0;
        EmptyState.Visibility = empty ? Visibility.Visible : Visibility.Collapsed;
        DestinationsScroll.Visibility = empty ? Visibility.Collapsed : Visibility.Visible;
    }

    private void ConnectMirat_Click(object sender, RoutedEventArgs e)
    {
        var win = new ConnectMiratWindow(_vm) { Owner = this };
        win.ShowDialog();
    }

    private void RemoveDestination_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button b && b.DataContext is MiratDestination d)
            _vm.RemoveMiratDestinationCommand.Execute(d);
    }

    private void Close_Click(object sender, RoutedEventArgs e)
    {
        Close();
    }

    protected override void OnClosed(EventArgs e)
    {
        _vm.MiratDestinations.CollectionChanged -= Destinations_CollectionChanged;
        base.OnClosed(e);
    }
}
