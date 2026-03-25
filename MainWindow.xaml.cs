using System.Windows;
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

    public MainWindow()
    {
        InitializeComponent();
        _viewModel = new MainViewModel();
        DataContext = _viewModel;
    }

    /// <summary>
    /// Gestiona les tecles de drecera globals.
    /// </summary>
    private void Window_KeyDown(object sender, KeyEventArgs e)
    {
        // Visor obert: dreceres de navegació
        if (_viewModel.IsViewerOpen)
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
            }
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
        if (!_viewModel.IsViewerOpen) return;

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
        if (!_viewModel.IsViewerOpen) return;

        // Doble clic per tancar el visor
        if (e.ClickCount == 2)
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
}
