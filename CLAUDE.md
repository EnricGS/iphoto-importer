# iPhotoImporter

Aplicació WPF (.NET 8) per visualitzar, gestionar i importar fotos i vídeos.

## Convencions del projecte

- **Idioma del codi**: Noms de classes, mètodes i variables en anglès. Comentaris i documentació en català.
- **Arquitectura**: MVVM (Model-View-ViewModel) sense framework extern (excepte CommunityToolkit.Mvvm).
- **Namespace arrel**: `iPhotoImporter`
- **Target**: `net8.0-windows` (WPF)

## Estructura

```
iPhotoImporter.csproj
App.xaml / App.xaml.cs              → Punt d'entrada
MainWindow.xaml / .xaml.cs          → Finestra principal (vista)
ViewModels/MainViewModel.cs         → ViewModel principal
Models/PhotoItem.cs                 → Model de dades per foto/vídeo
Services/DeviceService.cs           → Accés a dispositius MTP via MediaDevices
Services/FileService.cs             → Operacions amb fitxers locals (escanejar, copiar, moure, eliminar)
Services/ThumbnailCacheService.cs   → Cache de miniatures persistent a disc (JPEG 85%, 512px)
Services/ImageCacheService.cs       → Cache LRU en RAM per imatges a resolució completa (~20 imatges)
Converters/Converters.cs            → Converters de WPF (Bool, Visibility, FileSizem, etc.)
```

## Dependències

- **MediaDevices** (NuGet): Accés a dispositius MTP sense COM interop directe.
- **CommunityToolkit.Mvvm** (NuGet): Patró MVVM (ObservableObject, RelayCommand).

## Compilació

```bash
dotnet build
```

## Normes

- No afegir paquets NuGet sense justificació.
- Mantenir el code-behind mínim; la lògica va al ViewModel o als Services.
- Fer servir `INotifyPropertyChanged` per al binding, sense frameworks MVVM externs per ara.
- El code-behind de MainWindow només gestiona events de teclat/ratolí que requereixen accés directe a la UI.
