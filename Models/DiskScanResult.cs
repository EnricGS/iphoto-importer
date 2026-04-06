using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace iPhotoImporter.Models;

/// <summary>
/// Resultat d'una carpeta trobada durant l'escaneig de disc.
/// </summary>
public class DiskScanResult : INotifyPropertyChanged
{
    private bool _isSelected;

    /// <summary>Ruta de la carpeta</summary>
    public required string FolderPath { get; init; }

    /// <summary>Nombre de fitxers de foto/vídeo trobats</summary>
    public int FileCount { get; init; }

    /// <summary>Seleccionat per l'usuari</summary>
    public bool IsSelected
    {
        get => _isSelected;
        set { _isSelected = value; OnPropertyChanged(); }
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
