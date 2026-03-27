using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using iPhotoImporter.Models;
using iPhotoImporter.ViewModels;

namespace iPhotoImporter;

/// <summary>
/// Code-behind de la finestra principal.
/// Gestiona events de teclat i ratolí que requereixen accés directe a la UI.
/// </summary>
public partial class MainWindow : Window
{
    private readonly MainViewModel _viewModel;
    private bool _isDragging;
    private Point _dragStart;
    private double _dragStartOffsetX;
    private double _dragStartOffsetY;
    private double _savedScrollOffset;

    public MainWindow()
    {
        InitializeComponent();
        _viewModel = new MainViewModel();
        DataContext = _viewModel;

        // Subscriure's als canvis de mode per actualitzar les columnes del layout
        _viewModel.PropertyChanged += OnViewModelPropertyChanged;

        // Subscriure's a l'event de scroll automàtic cap a la miniatura activa
        _viewModel.ScrollToThumbnailRequested += OnScrollToThumbnailRequested;
    }

    /// <summary>
    /// Actualitza les columnes del Grid quan canvia el mode split/toggle.
    /// </summary>
    private void OnViewModelPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(MainViewModel.IsSplitViewerVisible))
        {
            UpdateSplitLayout();
        }
        else if (e.PropertyName == nameof(MainViewModel.ViewerVideoPath))
        {
            LoadVideoInActivePlayer();
        }
        // Guardar posició del scroll quan s'obre l'overlay, restaurar al tancar
        else if (e.PropertyName == nameof(MainViewModel.IsOverlayViewerVisible))
        {
            if (_viewModel.IsOverlayViewerVisible)
            {
                _savedScrollOffset = ThumbnailScrollViewer.VerticalOffset;
            }
            else
            {
                // Restaurar scroll al tancar l'overlay
                Dispatcher.BeginInvoke(new Action(() =>
                {
                    ThumbnailScrollViewer.ScrollToVerticalOffset(_savedScrollOffset);
                }), System.Windows.Threading.DispatcherPriority.Loaded);
            }
        }
    }

    /// <summary>
    /// Ajusta les amplades de les columnes segons si el visor split és visible.
    /// </summary>
    private void UpdateSplitLayout()
    {
        if (_viewModel.IsSplitViewerVisible)
        {
            // Mode split amb visor visible: graella ~40%, separador, visor ~60%
            GridColumn.Width = new GridLength(2, GridUnitType.Star);
            SplitterColumn.Width = new GridLength(4);
            ViewerColumn.Width = new GridLength(3, GridUnitType.Star);
        }
        else
        {
            // Mode toggle o split sense visor: graella ocupa tot
            GridColumn.Width = new GridLength(1, GridUnitType.Star);
            SplitterColumn.Width = new GridLength(0);
            ViewerColumn.Width = new GridLength(0);
        }
    }

    /// <summary>
    /// Fa scroll a la miniatura indicada per índex dins del ScrollViewer.
    /// </summary>
    private void OnScrollToThumbnailRequested(int index)
    {
        if (index < 0 || index >= _viewModel.Photos.Count) return;

        // Buscar l'element visual corresponent al ItemsControl
        Dispatcher.BeginInvoke(new Action(() =>
        {
            var container = PhotoGrid.ItemContainerGenerator.ContainerFromIndex(index) as FrameworkElement;
            container?.BringIntoView();
        }), System.Windows.Threading.DispatcherPriority.Loaded);
    }

    /// <summary>
    /// Gestiona les tecles de drecera globals.
    /// </summary>
    private void Window_KeyDown(object sender, KeyEventArgs e)
    {
        // Tab i F5: canviar mode split/toggle (sempre disponible)
        if (e.Key == Key.Tab && Keyboard.Modifiers == ModifierKeys.None)
        {
            _viewModel.ToggleViewModeCommand.Execute(null);
            e.Handled = true;
            return;
        }

        if (e.Key == Key.F5)
        {
            _viewModel.ToggleViewModeCommand.Execute(null);
            e.Handled = true;
            return;
        }

        // Visor obert (overlay o split): dreceres de navegació
        var viewerActive = _viewModel.IsViewerOpen || _viewModel.IsSplitViewerVisible;
        if (viewerActive)
        {
            switch (e.Key)
            {
                case Key.Escape:
                    _viewModel.CloseViewerCommand.Execute(null);
                    e.Handled = true;
                    break;
                case Key.Left:
                    _viewModel.ViewerPreviousCommand.Execute(null);
                    e.Handled = true;
                    break;
                case Key.Right:
                    _viewModel.ViewerNextCommand.Execute(null);
                    e.Handled = true;
                    break;
                case Key.Add:
                case Key.OemPlus:
                    _viewModel.ViewerZoomInCommand.Execute(null);
                    e.Handled = true;
                    break;
                case Key.Subtract:
                case Key.OemMinus:
                    _viewModel.ViewerZoomOutCommand.Execute(null);
                    e.Handled = true;
                    break;
                case Key.D0:
                case Key.NumPad0:
                    _viewModel.ViewerZoomResetCommand.Execute(null);
                    e.Handled = true;
                    break;
                case Key.F:
                    _viewModel.ViewerFitToScreenCommand.Execute(null);
                    e.Handled = true;
                    break;
                case Key.C when Keyboard.Modifiers == ModifierKeys.None:
                    _viewModel.CopyCurrentPhotoCommand.Execute(null);
                    e.Handled = true;
                    break;
                case Key.Space:
                    VideoPlay_Click(this, e);
                    e.Handled = true;
                    break;
            }

            // En mode split, no bloquejar les dreceres de graella (Ctrl+A, etc.)
            if (_viewModel.IsOverlayViewerVisible)
                return;
        }

        // Graella: dreceres generals
        switch (e.Key)
        {
            case Key.O when Keyboard.Modifiers == ModifierKeys.Control:
                _viewModel.OpenFolderCommand.Execute(null);
                e.Handled = true;
                break;
            case Key.A when Keyboard.Modifiers == ModifierKeys.Control:
                _viewModel.SelectAllCommand.Execute(null);
                e.Handled = true;
                break;
            case Key.D when Keyboard.Modifiers == ModifierKeys.Control:
                _viewModel.DeselectAllCommand.Execute(null);
                e.Handled = true;
                break;
            case Key.Delete:
                if (_viewModel.SelectedPhotosCount > 0)
                    _viewModel.DeleteSelectedCommand.Execute(null);
                e.Handled = true;
                break;
        }
    }

    /// <summary>
    /// Gestiona el clic a una miniatura de la graella.
    /// Suporta Ctrl+clic i Shift+clic per selecció múltiple.
    /// </summary>
    private void Thumbnail_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (sender is FrameworkElement element && element.DataContext is PhotoItem item)
        {
            var isCtrl = Keyboard.Modifiers.HasFlag(ModifierKeys.Control);
            var isShift = Keyboard.Modifiers.HasFlag(ModifierKeys.Shift);

            _viewModel.HandleGridClick(item, isCtrl, isShift);
            e.Handled = true;
        }
    }

    /// <summary>
    /// Zoom amb la roda del ratolí al visor.
    /// </summary>
    private void Viewer_MouseWheel(object sender, MouseWheelEventArgs e)
    {
        // Funciona tant en overlay com en split
        var viewerActive = _viewModel.IsViewerOpen || _viewModel.IsSplitViewerVisible;
        if (!viewerActive) return;

        if (e.Delta > 0)
            _viewModel.ViewerZoomInCommand.Execute(null);
        else
            _viewModel.ViewerZoomOutCommand.Execute(null);

        e.Handled = true;
    }

    /// <summary>
    /// Inici del pan (arrossegar) al visor.
    /// </summary>
    private void Viewer_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        var viewerActive = _viewModel.IsViewerOpen || _viewModel.IsSplitViewerVisible;
        if (!viewerActive) return;

        // Doble clic per tancar el visor (només en mode overlay)
        if (e.ClickCount == 2 && _viewModel.IsOverlayViewerVisible)
        {
            _viewModel.CloseViewerCommand.Execute(null);
            e.Handled = true;
            return;
        }

        // Iniciar pan si hi ha zoom
        if (_viewModel.ViewerZoom > 1.0)
        {
            _isDragging = true;
            _dragStart = e.GetPosition(this);
            _dragStartOffsetX = _viewModel.ViewerOffsetX;
            _dragStartOffsetY = _viewModel.ViewerOffsetY;
            ((UIElement)sender).CaptureMouse();
            e.Handled = true;
        }
    }

    /// <summary>
    /// Fi del pan al visor.
    /// </summary>
    private void Viewer_MouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        if (_isDragging)
        {
            _isDragging = false;
            ((UIElement)sender).ReleaseMouseCapture();
            e.Handled = true;
        }
    }

    /// <summary>
    /// Moviment del ratolí durant el pan al visor.
    /// </summary>
    private void Viewer_MouseMove(object sender, MouseEventArgs e)
    {
        if (!_isDragging) return;

        var pos = e.GetPosition(this);
        _viewModel.ViewerOffsetX = _dragStartOffsetX + (pos.X - _dragStart.X);
        _viewModel.ViewerOffsetY = _dragStartOffsetY + (pos.Y - _dragStart.Y);
    }

    // === Control de vídeo ===

    private bool _isVideoPlaying;

    /// <summary>Retorna el MediaElement actiu (split o overlay).</summary>
    private MediaElement? GetActiveVideoPlayer()
    {
        if (_viewModel.IsSplitMode)
            return SplitVideoPlayer;
        return OverlayVideoPlayer;
    }

    private void LoadVideoInActivePlayer()
    {
        // Aturar qualsevol vídeo anterior i netejar rotació
        SplitVideoPlayer.Stop();
        SplitVideoPlayer.Source = null;
        SplitVideoPlayer.LayoutTransform = null;
        OverlayVideoPlayer.Stop();
        OverlayVideoPlayer.Source = null;
        OverlayVideoPlayer.LayoutTransform = null;
        _isVideoPlaying = false;

        var path = _viewModel.ViewerVideoPath;
        if (string.IsNullOrEmpty(path)) return;

        var player = GetActiveVideoPlayer();
        if (player == null) return;

        // Aplicar rotació del vídeo si cal
        var rotation = _viewModel.ViewerVideoRotation;
        if (rotation != 0)
        {
            player.LayoutTransform = new System.Windows.Media.RotateTransform(rotation);
        }

        player.Source = new Uri(path, UriKind.Absolute);
        player.Play();
        _isVideoPlaying = true;
    }

    private void VideoPlay_Click(object sender, RoutedEventArgs e)
    {
        var player = GetActiveVideoPlayer();
        if (player?.Source == null) return;

        if (_isVideoPlaying)
        {
            player.Pause();
            _isVideoPlaying = false;
        }
        else
        {
            player.Play();
            _isVideoPlaying = true;
        }
    }

    private void VideoStop_Click(object sender, RoutedEventArgs e)
    {
        var player = GetActiveVideoPlayer();
        if (player?.Source == null) return;

        player.Stop();
        _isVideoPlaying = false;
    }

    private void VideoPlayer_MediaEnded(object sender, RoutedEventArgs e)
    {
        _isVideoPlaying = false;
    }

    // === Filtre per tipus ===

    private void FilterAll_Checked(object sender, RoutedEventArgs e) { if (_viewModel != null) _viewModel.FilterType = 0; }
    private void FilterPhotos_Checked(object sender, RoutedEventArgs e) { if (_viewModel != null) _viewModel.FilterType = 1; }
    private void FilterVideos_Checked(object sender, RoutedEventArgs e) { if (_viewModel != null) _viewModel.FilterType = 2; }
}
