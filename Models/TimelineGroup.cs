using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace iPhotoImporter.Models;

/// <summary>
/// Agrupació temporal per a la vista timeline.
/// </summary>
public enum TimelineGrouping
{
    Day,
    Month,
    Year
}

/// <summary>
/// Un grup de fotos agrupades per data (dia, mes o any).
/// </summary>
public class TimelineGroup : INotifyPropertyChanged
{
    private bool _isCollapsed;

    /// <summary>Clau del grup (ex: "Gener 2026", "15/03/2026", "2026")</summary>
    public string Key { get; init; } = "";

    /// <summary>Fotos dins el grup</summary>
    public ObservableCollection<PhotoItem> Photos { get; init; } = [];

    /// <summary>Nombre de fotos al grup</summary>
    public int Count => Photos.Count;

    /// <summary>Indica si el grup està col·lapsat</summary>
    public bool IsCollapsed
    {
        get => _isCollapsed;
        set
        {
            if (_isCollapsed == value) return;
            _isCollapsed = value;
            OnPropertyChanged();
        }
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
