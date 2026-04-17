using System.ComponentModel;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
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

    // Rubber band selection
    private bool _isRubberBandActive;
    private Point _rubberBandOrigin;
    private bool _rubberBandCtrlHeld;

    // Drag-and-drop de miniatures cap a aplicacions externes
    private bool _thumbDragPending;
    private Point _thumbDragStartPos;
    private PhotoItem? _thumbDragItem;
    private FrameworkElement? _thumbDragElement;

    private ScrollViewer? GetGridScrollViewer()
    {
        if (VisualTreeHelper.GetChildrenCount(PhotoGrid) > 0)
        {
            var border = VisualTreeHelper.GetChild(PhotoGrid, 0);
            if (border is Decorator decorator && decorator.Child is ScrollViewer sv)
                return sv;
        }
        return null;
    }

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
        if (e.PropertyName == nameof(MainViewModel.ViewerZoom))
        {
            // Sync _targetZoom when zoom changes from ViewModel (buttons, reset)
            _targetZoom = _viewModel.ViewerZoom;
        }
        else if (e.PropertyName == nameof(MainViewModel.IsSplitViewerVisible))
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
                _savedScrollOffset = GetGridScrollViewer()?.VerticalOffset ?? 0;
            }
            else
            {
                // Restaurar scroll al tancar l'overlay
                Dispatcher.BeginInvoke(new Action(() =>
                {
                    GetGridScrollViewer()?.ScrollToVerticalOffset(_savedScrollOffset);
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
    /// <summary>
    /// PreviewKeyDown (tunneling) per Delete: alguns controls del visor (ex. video player)
    /// capten la tecla Delete abans que bombolli fins a Window_KeyDown. Amb PreviewKeyDown
    /// l'interceptem al nivell del Window abans que cap fill la pugui absorbir.
    /// </summary>
    private void Window_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Delete) return;

        // El command ja gestiona el cas "visor sense selecció" internament.
        var viewerActive = _viewModel.IsViewerOpen || _viewModel.IsSplitViewerVisible;
        if (viewerActive || _viewModel.SelectedPhotosCount > 0)
        {
            _viewModel.DeleteSelectedCommand.Execute(null);
            e.Handled = true;
        }
    }

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
                // Key.Delete es gestiona a Window_PreviewKeyDown perquè alguns controls
                // del visor absorbeixen la tecla abans que arribi aquí.
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
            // Key.Delete: veure Window_PreviewKeyDown
        }
    }

    /// <summary>
    /// Gestiona el clic a una miniatura de la graella.
    /// Suporta Ctrl+clic, Shift+clic per selecció múltiple,
    /// i drag-and-drop cap a aplicacions externes.
    /// </summary>
    /// <summary>
    /// Clic a un element de la llista de dispositius per seleccionar-lo.
    /// </summary>
    private void DeviceItem_Click(object sender, MouseButtonEventArgs e)
    {
        if (sender is FrameworkElement element && element.DataContext is MediaDevices.MediaDevice device)
        {
            _viewModel.SelectedDevice = device;
        }
    }

    /// <summary>
    /// Clic al header d'un grup del timeline per col·lapsar/expandir.
    /// </summary>
    private void TimelineHeader_Click(object sender, MouseButtonEventArgs e)
    {
        if (sender is FrameworkElement element && element.DataContext is Models.TimelineGroup group)
        {
            _viewModel.ToggleGroupCollapseCommand.Execute(group.Key);
        }
    }

    private void Thumbnail_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (sender is FrameworkElement element && element.DataContext is PhotoItem item)
        {
            // Registrar posició inicial per detectar arrossegament cap a fora
            _thumbDragPending = true;
            _thumbDragStartPos = e.GetPosition(this);
            _thumbDragItem = item;
            _thumbDragElement = element;

            // Si l'element ja està seleccionat, no processar el clic encara
            // (es farà al MouseUp si no hi ha drag)
            if (item.IsSelected)
            {
                e.Handled = true;
                return;
            }

            // Per elements no seleccionats, processar el clic immediatament
            // (Ctrl/Shift selecció o obrir visor)
            var isCtrl = Keyboard.Modifiers.HasFlag(ModifierKeys.Control);
            var isShift = Keyboard.Modifiers.HasFlag(ModifierKeys.Shift);
            _viewModel.HandleGridClick(item, isCtrl, isShift);
            e.Handled = true;
        }
    }

    /// <summary>
    /// Detecta si l'usuari arrossega una miniatura més enllà del llindar mínim
    /// i inicia un drag-and-drop amb els fitxers seleccionats.
    /// </summary>
    private void Thumbnail_MouseMove(object sender, MouseEventArgs e)
    {
        if (!_thumbDragPending || _thumbDragItem == null) return;
        if (e.LeftButton != MouseButtonState.Pressed)
        {
            _thumbDragPending = false;
            return;
        }

        var currentPos = e.GetPosition(this);
        var dx = Math.Abs(currentPos.X - _thumbDragStartPos.X);
        var dy = Math.Abs(currentPos.Y - _thumbDragStartPos.Y);

        if (dx < SystemParameters.MinimumHorizontalDragDistance &&
            dy < SystemParameters.MinimumVerticalDragDistance)
            return;

        // Llindar superat: iniciar drag-and-drop
        _thumbDragPending = false;

        // Si l'element arrossegat no està seleccionat, seleccionar-lo sol
        if (!_thumbDragItem.IsSelected)
        {
            foreach (var p in _viewModel.Photos)
                p.IsSelected = false;
            _thumbDragItem.IsSelected = true;
        }

        // Recollir les rutes de tots els elements seleccionats
        var selectedPaths = _viewModel.Photos
            .Where(p => p.IsSelected && !string.IsNullOrEmpty(p.FullPath))
            .Select(p => p.FullPath)
            .ToArray();

        if (selectedPaths.Length == 0) return;

        var dataObject = new DataObject(DataFormats.FileDrop, selectedPaths);
        DragDrop.DoDragDrop(_thumbDragElement!, dataObject, DragDropEffects.Copy);
    }

    /// <summary>
    /// Quan es deixa anar el botó sense haver arrossegat, processar el clic normal.
    /// </summary>
    private void Thumbnail_MouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        if (!_thumbDragPending || _thumbDragItem == null)
        {
            _thumbDragPending = false;
            return;
        }

        _thumbDragPending = false;

        // El clic va ser sobre un element seleccionat sense arrossegar:
        // processar com a clic normal (obrir visor o gestionar Ctrl/Shift)
        var isCtrl = Keyboard.Modifiers.HasFlag(ModifierKeys.Control);
        var isShift = Keyboard.Modifiers.HasFlag(ModifierKeys.Shift);
        _viewModel.HandleGridClick(_thumbDragItem, isCtrl, isShift);
        e.Handled = true;
    }

    /// <summary>
    /// Zoom amb la roda del ratolí al visor (smooth).
    /// </summary>
    private double _targetZoom = 1.0;
    private void Viewer_MouseWheel(object sender, MouseWheelEventArgs e)
    {
        var viewerActive = _viewModel.IsViewerOpen || _viewModel.IsSplitViewerVisible;
        if (!viewerActive) return;

        var oldZoom = _targetZoom;
        if (e.Delta > 0)
            _targetZoom = Math.Min(_targetZoom * 1.15, 10.0);
        else
            _targetZoom = Math.Max(_targetZoom / 1.15, 0.1);

        // Zoom cursor-aware: ajustar offsets perquè el punt sota el cursor es mantingui fix
        if (sender is FrameworkElement container)
        {
            var cursorPos = e.GetPosition(container);
            var centerX = container.ActualWidth / 2.0;
            var centerY = container.ActualHeight / 2.0;
            var relX = cursorPos.X - centerX;
            var relY = cursorPos.Y - centerY;

            var factor = _targetZoom / oldZoom;
            _viewModel.ViewerOffsetX = _viewModel.ViewerOffsetX * factor + relX * (1 - factor);
            _viewModel.ViewerOffsetY = _viewModel.ViewerOffsetY * factor + relY * (1 - factor);
        }

        AnimateZoomTo(_targetZoom);
        e.Handled = true;
    }

    private void AnimateZoomTo(double target)
    {
        var duration = new Duration(TimeSpan.FromMilliseconds(150));
        var ease = new System.Windows.Media.Animation.CubicEase { EasingMode = System.Windows.Media.Animation.EasingMode.EaseOut };
        var anim = new System.Windows.Media.Animation.DoubleAnimation(target, duration) { EasingFunction = ease };

        anim.Completed += (s, e) =>
        {
            _viewModel.ViewerZoom = target;
        };

        // Animate both overlay and split ScaleTransforms
        var overlayScale = FindScaleTransform("ViewerImageControl");
        var splitScale = FindScaleTransform("SplitViewerImageControl");

        if (overlayScale != null)
        {
            overlayScale.BeginAnimation(ScaleTransform.ScaleXProperty, anim);
            overlayScale.BeginAnimation(ScaleTransform.ScaleYProperty, anim);
        }
        if (splitScale != null)
        {
            splitScale.BeginAnimation(ScaleTransform.ScaleXProperty, anim);
            splitScale.BeginAnimation(ScaleTransform.ScaleYProperty, anim);
        }

        // Update display text
        _viewModel.ViewerZoom = target;
    }

    private ScaleTransform? FindScaleTransform(string imageName)
    {
        var img = FindName(imageName) as FrameworkElement;
        if (img?.RenderTransform is TransformGroup tg)
        {
            foreach (var t in tg.Children)
            {
                if (t is ScaleTransform st) return st;
            }
        }
        return null;
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

        // Només carregar vídeos locals (paths MTP del dispositiu no es poden reproduir)
        if (Uri.TryCreate(path, UriKind.Absolute, out var uri))
        {
            player.Source = uri;
            player.Play();
            _isVideoPlaying = true;
        }
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

    // === Selecció amb arrossegament (rubber band) ===

    /// <summary>
    /// Determina si el clic ha impactat sobre una miniatura (thumbnail border).
    /// </summary>
    private bool IsClickOnThumbnail(MouseButtonEventArgs e)
    {
        var hit = e.OriginalSource as DependencyObject;
        while (hit != null)
        {
            if (hit is FrameworkElement fe && fe.DataContext is PhotoItem)
            {
                // Hem trobat un element dins d'una miniatura
                if (hit is Border || hit is Image || hit is CheckBox || hit is TextBlock)
                    return true;
            }
            if (hit == PhotoGrid) break;
            hit = VisualTreeHelper.GetParent(hit);
        }
        return false;
    }

    /// <summary>
    /// Inicia la selecció amb arrossegament si el clic és sobre espai buit de la graella.
    /// </summary>
    private bool IsClickOnScrollBar(MouseButtonEventArgs e)
    {
        var hit = e.OriginalSource as DependencyObject;
        while (hit != null)
        {
            if (hit is System.Windows.Controls.Primitives.ScrollBar) return true;
            hit = VisualTreeHelper.GetParent(hit);
        }
        return false;
    }

    private void ThumbnailArea_PreviewMouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        // No interceptar clics sobre el scrollbar
        if (IsClickOnScrollBar(e)) return;

        // No iniciar rubber band si el clic és sobre una miniatura
        if (IsClickOnThumbnail(e)) return;

        // No iniciar si el visor overlay està obert
        if (_viewModel.IsOverlayViewerVisible) return;

        _rubberBandOrigin = e.GetPosition(SelectionCanvas);
        _rubberBandCtrlHeld = Keyboard.Modifiers.HasFlag(ModifierKeys.Control);
        _isRubberBandActive = true;

        // Configurar el rectangle de selecció
        Canvas.SetLeft(SelectionRectangle, _rubberBandOrigin.X);
        Canvas.SetTop(SelectionRectangle, _rubberBandOrigin.Y);
        SelectionRectangle.Width = 0;
        SelectionRectangle.Height = 0;
        SelectionRectangle.Visibility = Visibility.Visible;

        // Capturar el ratolí al ScrollViewer
        PhotoGrid.CaptureMouse();
        e.Handled = true;
    }

    /// <summary>
    /// Actualitza el rectangle de selecció durant l'arrossegament.
    /// </summary>
    private void ThumbnailArea_PreviewMouseMove(object sender, MouseEventArgs e)
    {
        if (!_isRubberBandActive) return;

        var currentPos = e.GetPosition(SelectionCanvas);

        var x = Math.Min(_rubberBandOrigin.X, currentPos.X);
        var y = Math.Min(_rubberBandOrigin.Y, currentPos.Y);
        var w = Math.Abs(currentPos.X - _rubberBandOrigin.X);
        var h = Math.Abs(currentPos.Y - _rubberBandOrigin.Y);

        Canvas.SetLeft(SelectionRectangle, x);
        Canvas.SetTop(SelectionRectangle, y);
        SelectionRectangle.Width = w;
        SelectionRectangle.Height = h;
    }

    /// <summary>
    /// Finalitza la selecció amb arrossegament i selecciona les miniatures dins del rectangle.
    /// </summary>
    private void ThumbnailArea_PreviewMouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        if (!_isRubberBandActive) return;

        _isRubberBandActive = false;
        PhotoGrid.ReleaseMouseCapture();
        SelectionRectangle.Visibility = Visibility.Collapsed;

        // Calcular el rectangle de selecció en coordenades del canvas
        var selRect = new Rect(
            Canvas.GetLeft(SelectionRectangle),
            Canvas.GetTop(SelectionRectangle),
            SelectionRectangle.Width,
            SelectionRectangle.Height);

        // Si el rectangle és massa petit, tractar com un clic simple (deseleccionar tot)
        if (selRect.Width < 5 && selRect.Height < 5)
        {
            if (!_rubberBandCtrlHeld)
                _viewModel.DeselectAllCommand.Execute(null);
            return;
        }

        // Si no es manté Ctrl, deseleccionar tot primer
        if (!_rubberBandCtrlHeld)
            _viewModel.DeselectAllCommand.Execute(null);

        // Trobar quines miniatures intersecten amb el rectangle de selecció
        for (var i = 0; i < _viewModel.Photos.Count; i++)
        {
            var container = PhotoGrid.ItemContainerGenerator.ContainerFromIndex(i) as FrameworkElement;
            if (container == null) continue;

            // Obtenir la posició de la miniatura relativa al canvas overlay
            try
            {
                var topLeft = container.TranslatePoint(new Point(0, 0), SelectionCanvas);
                var itemRect = new Rect(topLeft, new Size(container.ActualWidth, container.ActualHeight));

                if (selRect.IntersectsWith(itemRect))
                {
                    _viewModel.Photos[i].IsSelected = true;
                }
            }
            catch
            {
                // L'element pot no ser visible (fora del viewport virtualitzat)
            }
        }

        e.Handled = true;
    }

    // === Clic dret per deseleccionar ===

    /// <summary>
    /// Clic dret a la graella: deseleccionar tots els elements.
    /// </summary>
    private void ThumbnailArea_MouseRightButtonDown(object sender, MouseButtonEventArgs e)
    {
        _viewModel.DeselectAllCommand.Execute(null);
        e.Handled = true;
    }

    /// <summary>
    /// Obre la finestra de gestió de destins Mirat. Un cop tancada, si no hi
    /// havia destí actiu i s'ha afegit algun destí, el primer es tria automàticament.
    /// </summary>
    private void OpenMiratSettings_Click(object sender, RoutedEventArgs e)
    {
        var win = new MiratSettingsWindow(_viewModel) { Owner = this };
        win.ShowDialog();
    }
}
