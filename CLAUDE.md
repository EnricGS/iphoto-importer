# iPhotoImporter

Aplicació WPF (.NET 8) per importar fotos i vídeos des de dispositius mòbils connectats per MTP.

## Convencions del projecte

- **Idioma del codi**: Noms de classes, mètodes i variables en anglès. Comentaris i documentació en català.
- **Arquitectura**: MVVM (Model-View-ViewModel) sense framework extern.
- **Namespace arrel**: `iPhotoImporter`
- **Target**: `net8.0-windows` (WPF)

## Estructura

```
iPhotoImporter.csproj
App.xaml / App.xaml.cs          → Punt d'entrada
MainWindow.xaml / .xaml.cs      → Finestra principal (vista)
ViewModels/MainViewModel.cs     → ViewModel principal
Models/PhotoItem.cs             → Model de dades per foto/vídeo
Services/DeviceService.cs       → Accés a dispositius MTP via MediaDevices
```

## Dependències

- **MediaDevices** (NuGet): Accés a dispositius MTP sense COM interop directe.

## Compilació

```bash
dotnet build
```

## Normes

- No afegir paquets NuGet sense justificació.
- Mantenir el code-behind mínim; la lògica va al ViewModel o als Services.
- Fer servir `INotifyPropertyChanged` per al binding, sense frameworks MVVM externs per ara.
