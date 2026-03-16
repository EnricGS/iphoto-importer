# iPhoto Importer

Aplicació d'escriptori per importar fotos i vídeos des d'un iPhone o dispositiu MTP al PC amb Windows.

## Requisits

- **Windows 10 o 11** (x64)
- **.NET 8 Runtime** — [Descarregar](https://dotnet.microsoft.com/download/dotnet/8.0)
- **iTunes** o **drivers Apple Mobile Device USB** instal·lats (necessari perquè Windows reconegui l'iPhone via MTP)

## Ús

1. Connecta l'iPhone al PC amb un cable USB.
2. Desbloqueja l'iPhone i prem **"Confiar"** quan aparegui el missatge a la pantalla.
3. Obre **iPhotoImporter.exe**.
4. Prem **"Actualitzar"** per detectar el dispositiu.
5. Prem **"Carregar fotos"** per escanejar les fotos del dispositiu.
6. Selecciona o desselecciona les fotos que vulguis copiar.
7. Prem **"Copiar seleccionades"** i tria la carpeta de destí.

## Compilar el projecte

```bash
dotnet build
```

## Publicar (executable únic)

```bash
dotnet publish -c Release
```

L'executable es genera a `bin/Release/net8.0-windows/win-x64/publish/iPhotoImporter.exe`.

## Estructura del projecte

```
iPhotoImporter.csproj           → Configuració del projecte .NET 8 WPF
App.xaml / App.xaml.cs           → Punt d'entrada de l'aplicació
MainWindow.xaml / .xaml.cs       → Finestra principal (vista)
ViewModels/MainViewModel.cs      → ViewModel principal (MVVM)
Models/PhotoItem.cs              → Model de dades per foto/vídeo
Services/DeviceService.cs        → Accés a dispositius MTP via MediaDevices
app.ico                          → Icona de l'aplicació
```

## Dependències

| Paquet | Versió | Ús |
|--------|--------|----|
| [MediaDevices](https://www.nuget.org/packages/MediaDevices) | 1.10.2 | Accés a dispositius MTP |
| [CommunityToolkit.Mvvm](https://www.nuget.org/packages/CommunityToolkit.Mvvm) | 8.4.0 | Patró MVVM |
