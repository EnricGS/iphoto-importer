using System.Windows;
using iPhotoImporter.ViewModels;

namespace iPhotoImporter;

/// <summary>
/// Code-behind de la finestra principal.
/// </summary>
public partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        DataContext = new MainViewModel();
    }
}
