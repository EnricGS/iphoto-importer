# Photo Manager

Aplicació d'escriptori per visualitzar, gestionar i importar fotos i vídeos. Inclou visor d'imatges complet amb suport per carpetes locals i importació des de dispositius MTP (iPhone).

## Registre de progrés

- 2026-03-25 - inici
- 2026-03-25 - Phase 1 completada: arquitectura base del visor (panells dividits, model central, obrir carpeta)
- 2026-03-25 - Phase 2 completada: graella virtual amb miniatures (virtualització, slider mida, selecció múltiple, cache disc)
- 2026-03-25 - Phase 3 completada: visor i pipeline de fons (render progressiu, prefetch N±2, cache LRU RAM, zoom/pan, navegació)
- 2026-03-25 - Phase 4 completada: accions de gestió (copiar, moure, eliminar amb confirmació, barra d'accions)
- 2026-03-25 - Phase 5 completada: integració d'importació (MTP com a mòdul/panell lateral, flux importar→revisar→organitzar)
- 2026-03-25 - Phase 6 completada: poliment (EXIF bàsic via BitmapDecoder, installer actualitzat)
- 2026-03-25 - en produccio
- 2026-03-26 - Mode split/toggle: visor lateral simultani (estil Lightroom) amb Tab/F5 per canviar de mode, sincronització graella↔visor, GridSplitter redimensionable
- 2026-03-26 - Rotació de vídeos: lectura de metadades de rotació (tkhd matrix) de fitxers MP4/MOV i aplicació de RotateTransform al MediaElement
- 2026-03-26 - Filtre per tipus: selector de radio buttons (Tot/Fotos/Vídeos) amb comptadors a la barra de controls de la graella
- 2026-03-26 - Miniatures de vídeo: generació via Windows Shell IShellItemImageFactory (COM interop), sense dependències externes
- 2026-03-26 - Redisseny visual complet: tema fosc càlid amb accent ambre/terracota, cantonades arrodonides, icones Segoe Fluent, gradient overlays, tipografia moderna

## Requisits

- **Windows 10 o 11** (x64)
- **.NET 8 Runtime** — [Descarregar](https://dotnet.microsoft.com/download/dotnet/8.0)
- **iTunes** o **drivers Apple Mobile Device USB** (només si vols importar des d'iPhone via MTP)

## Ús

### Visor d'imatges
1. Obre l'aplicació **iPhotoImporter.exe**.
2. Prem **"Obrir carpeta"** o `Ctrl+O` per seleccionar una carpeta d'imatges.
3. Navega per la graella de miniatures. Usa l'slider per canviar la mida (S→XL).
4. Fes clic a una miniatura per obrir-la al visor a pantalla completa.
5. Utilitza `←` `→` per navegar, `+`/`-` per zoom, `Esc` per tancar.

### Selecció i gestió
- **Ctrl+clic**: selecció individual
- **Shift+clic**: selecció per rang
- **Ctrl+A**: seleccionar tot
- Amb elements seleccionats apareix la barra d'accions: Copiar, Moure, Eliminar.

### Importació MTP
1. Connecta l'iPhone via USB i prem "Confiar".
2. Prem el botó **"Importar"** a la barra superior.
3. Al panell lateral, prem **"Detectar dispositius"**.
4. Prem **"Importar fotos"** i selecciona la carpeta de destí.
5. Després d'importar, l'app ofereix obrir la carpeta al visor.

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
iPhotoImporter.csproj                → Configuració del projecte .NET 8 WPF
App.xaml / App.xaml.cs               → Punt d'entrada de l'aplicació
MainWindow.xaml / .xaml.cs           → Finestra principal (vista + events UI)
ViewModels/MainViewModel.cs          → ViewModel principal (MVVM)
Models/PhotoItem.cs                  → Model de dades per foto/vídeo
Services/DeviceService.cs            → Accés a dispositius MTP via MediaDevices
Services/FileService.cs              → Operacions amb fitxers locals
Services/ThumbnailCacheService.cs    → Cache de miniatures persistent a disc
Services/ImageCacheService.cs        → Cache LRU en RAM (~20 imatges)
Converters/Converters.cs             → Converters WPF (Visibility, FileSize, etc.)
app.ico                              → Icona de l'aplicació
```

## Dreceres de teclat

| Drecera | Acció |
|---------|-------|
| `Ctrl+O` | Obrir carpeta |
| `Ctrl+A` | Seleccionar tot |
| `Ctrl+D` | Desseleccionar tot |
| `Delete` | Eliminar seleccionats |
| `←` `→` | Navegar al visor |
| `+` `-` | Zoom al visor |
| `0` | Reset zoom |
| `F` | Ajustar a pantalla |
| `Tab` / `F5` | Canviar mode split/toggle |
| `Esc` | Tancar visor |

## Dependències

| Paquet | Versió | Ús |
|--------|--------|----|
| [MediaDevices](https://www.nuget.org/packages/MediaDevices) | 1.10.2 | Accés a dispositius MTP |
| [CommunityToolkit.Mvvm](https://www.nuget.org/packages/CommunityToolkit.Mvvm) | 8.4.0 | Patró MVVM |
