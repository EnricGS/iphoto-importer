# iPhotoManager — Project Log

## 2026-04-17 — Integració Mirat: destins remots per pujar fotos

### Context

Afegir la possibilitat de marcar un **àlbum de Mirat** (projecte germà: https://github.com/EnricGS/mirat) com a destí d'upload, de manera anàloga a les carpetes locals. L'usuari selecciona fotos a la graella → botó "Pujar a Mirat" → es pugen a l'àlbum configurat.

Mirat s'ha migrat recentment de Vercel a un Mac Studio autohostatjat amb Coolify + Postgres + MinIO (veure `project_log.md` de mirat, 2026-04-14 i 2026-04-16). Té un endpoint JSON `/api/upload` que assumeix que els fitxers ja són a MinIO. Per a un client desktop com iPhotoImporter que no té credencials S3, calia una alternativa.

### Canvis a Mirat (commit 5006b5a)

Afegits 3 endpoints a `app/src/app/api/external/*`, tots autenticats amb `X-API-Key` (env `MIRAT_API_KEY`):

- `GET /api/external/grups` — llista grups del sistema per triar destí
- `GET /api/external/albums?grup_id=X` — àlbums del grup
- `POST /api/external/upload` — **upload consolidat multipart** (foto + thumbnail + preview + metadades JSON) en una sola crida. Check duplicat per `hash_fitxer`, puja a MinIO amb `uploadToStorage()` del helper existent, crea registre a la taula `fotos`, associa a àlbum. Cleanup MinIO si falla l'INSERT. `maxDuration=300`, `MAX_FILE_SIZE=500MB`.

Les fotos queden amb `ia_processada=false` perquè el safety net del pipeline IA (cada 5 min) o un trigger explícit (`POST /api/process-ia`) les processi després.

Un únic `requireApiKey()` centralitzat a `api/external/_auth.ts`.

### Canvis a iPhotoImporter

**Nous fitxers:**

- `Models/MiratDestination.cs` — classe persistible: `Id, Nom, BaseUrl, ApiKey, GrupId, GrupNom, AlbumId?, AlbumNom?, PujatPer?`. Propietat computada `DisplayLabel` = "Grup / Àlbum" o "Grup".
- `Services/MiratDestinationStore.cs` — serialització JSON a `%LocalAppData%\iPhotoImporter\mirat-destinations.json`. Load/Save simples.
- `Services/MiratService.cs` — `HttpClient` amb `X-API-Key` automàtic i `BaseAddress` a la URL del destí. Mètodes:
  - `TestConnectionAsync()` — GET grups per validar credencials
  - `ListGroupsAsync()`, `ListAlbumsAsync(grupId)`
  - `UploadPhotoAsync(photo, progress, ct)` — calcula SHA-256, genera thumbnail 200px q70 i preview 2048px q80 via Magick.NET (`AutoOrient` + `Strip` EXIF), construeix `multipart/form-data` amb tots els camps, POST a `/api/external/upload`. Retorna `MiratUploadResult{Success, FotoId, Duplicat, ErrorMessage}`.
  - Taula `MimeTypeFromExtension` cobreix RAW (CR2/CR3/NEF/ARW/DNG/RAF), HEIC/HEIF/AVIF, JPEG/PNG/WEBP/TIFF i vídeos (MP4/MOV/AVI/MKV/WebM).
- `MiratSettingsWindow.xaml/.cs` — finestra de gestió de destins:
  - Llista destins existents amb botons Editar/Eliminar
  - Formulari d'alta: URL base, API Key, "Provar connexió" (llista grups), dropdown Grup, dropdown Àlbum (opcional, inclou "(Sense àlbum)"), Nom descriptiu, Desar
  - Els seus recursos de color estan duplicats a `Window.Resources` perquè cada `Window` té scope propi de `StaticResource`.

**Canvis a ViewModels/MainViewModel.cs:**

- Nou field `_miratStore = new MiratDestinationStore()`
- `ObservableCollection<MiratDestination> MiratDestinations` carregada al constructor
- `ActiveMiratDestination` (observable, `NotifyPropertyChangedFor(HasActiveMiratDestination, ActiveMiratLabel)`)
- `AddOrUpdateMiratDestination(dest)` — upsert + persist
- `RemoveMiratDestinationCommand`, `SelectMiratDestinationCommand`
- `UploadSelectedToMiratCommand` → delega a `UploadPhotosToMiratAsync`
- `UploadPhotosToMiratAsync(photos, dest)` — `SemaphoreSlim(3)` per concurrència, `Task.WhenAll`, reporta progrés a `StatusMessage` via `Dispatcher.InvokeAsync`:
  - `"Pujant a Mirat (Nom): done/total · N noves · N duplicades · N errors"`
  - Acabat: `"Acabat: N noves · N duplicades · N errors a Nom."`
- Propietats `IsUploadingToMirat`, `MiratUploadProgress` per barra de progrés futura

**Canvis a MainWindow.xaml:**

- Toolbar superior: icona núvol (`&#xE753;`, Accent color) → click obre `MiratSettingsWindow`
- Al costat: `ComboBox` amb `MiratDestinations` + `ActiveMiratDestination` a 2-way binding. Visible si `MiratDestinations.Count > 0`
- Barra d'accions (quan hi ha selecció): botó "Pujar a Mirat" amb `UploadSelectedToMiratCommand`, visible si `HasActiveMiratDestination`

**Canvis a MainWindow.xaml.cs:**

- `OpenMiratSettings_Click` — instancia `MiratSettingsWindow(_viewModel) { Owner = this }` i fa `ShowDialog()`

### Decisions de disseny

- **Upload consolidat vs granular**: endpoint consolidat (una sola crida multipart per foto). Simplifica molt el client, atomicitat al servidor (cleanup MinIO si falla BD), i així no hi ha orchestració HTTP client-side per 3 fitxers.
- **Preview al client**: Windows genera preview 2048px amb Magick.NET. Consistent amb el pipeline Python i el web. Menys càrrega al servidor.
- **Sense IA client-side**: les fotos van amb `ia_processada=false`. El pipeline del Mac Studio les recollirà automàticament (safety net cada 5 min).
- **Llista de destins**: l'usuari pot tenir múltiples configuracions Mirat (ex: "Família A / Àlbum X", "Família B"). Persistides a disc, seleccionables amb dropdown.
- **"Moure" a Mirat**: no implementat en aquesta primera iteració. Un cop el flux Copy estigui estable, és un pas petit afegir-lo (eliminar local via recycle bin després d'upload exitós, ja tenim undo).

### Refactor post-test: Copy/Move unificats amb destí

Primera iteració tenia un botó "Pujar a Mirat" separat al costat de Copy/Move. Canviat a comportament unificat:

- Si hi ha `ActiveMiratDestination` actiu, `CopySelectedCommand` i `CopyCurrentPhotoCommand` pugen a Mirat enlloc de copiar a carpeta local.
- `MoveSelectedCommand` amb destí Mirat: puja primer i, si no hi ha errors, elimina els originals via paperera de reciclatge (reversible amb Ctrl+Z).
- Tret el botó "Pujar a Mirat" separat del XAML.
- Afegit botó X al costat del ComboBox del toolbar per desactivar el destí Mirat i tornar a la carpeta local.

### Bug crític a l'endpoint d'upload: `Failed to parse body as FormData`

Al primer test d'upload real, el servidor retornava 400 amb aquest missatge. Diagnòstic:

1. Verificat que el client enviava Content-Type correcte (`multipart/form-data; boundary=UUID` sense cometes).
2. Verificat que no era problema de chunked encoding (afegit `form.LoadIntoBufferAsync()` per materialitzar).
3. Verificat amb ASCII-safe filenames (per evitar `filename*=utf-8''...` RFC 5987).
4. Res funcionava — **`request.formData()` d'undici (fetch natiu de Node.js 18+, usat per Next.js) rebutja multiparts perfectament vàlids generats per `System.Net.Http.MultipartFormDataContent` de .NET.** És un bug conegut d'undici.

**Solució:** canviar el parser al servidor. Substituït `request.formData()` per **busboy** (npm `busboy` + `@types/busboy`) a [app/src/app/api/external/upload/route.ts](../mirat/app/src/app/api/external/upload/route.ts). Busboy és més permissiu i accepta qualsevol multipart RFC 7578 compliant. Stream del request adaptat via `Readable.fromWeb(request.body).pipe(bb)`.

Commit a Mirat: `a63abf0` — "Fix /api/external/upload: usar busboy per parsejar multipart". Un cop desplegat a Coolify, la pujada des d'iPhotoImporter funciona correctament.

### Arrencada en mode finestra (no maximitzada)

Per petició de l'usuari, l'app ja no arrenca maximitzada. Al constructor de `MainWindow`:

```csharp
Width = Math.Max(MinWidth, SystemParameters.PrimaryScreenWidth * 0.6);
Height = Math.Max(MinHeight, SystemParameters.PrimaryScreenHeight * 0.6);
```

### Recursos visuals globals

Els `SolidColorBrush` del tema (BgBase, Accent, TextPrimary, etc.) estaven només a `MainWindow.Resources` i `MiratSettingsWindow` crashava amb XamlParseException perquè els recursos dins `Window.Resources` no estan disponibles quan s'avaluen els atributs del tag `<Window>` (Foreground, Background). Moguts tots a `App.xaml` / `Application.Resources` perquè siguin globals i accessibles des de qualsevol Window.

### Pendent

- Botó "Pujar a Mirat" també al visor (al costat de la paperera)
- Barra de progrés visual (ara només text a StatusMessage)
- GPS/càmera/EXIF a les metadades — `PhotoItem` no ho exposa encara, s'hauria d'extraure via Magick.NET en l'upload

---

## 2026-04-17 — Windows al dia: port dels 5 bugs d'UX de macOS

Es porten a la versió Windows WPF els fixes que la sessió del 2026-04-11 havia aplicat només a macOS. El bug 1 (crash Swift de `VideoPlayer`) no aplica a Windows, però sí la seva mitigació defensiva sobre `GetVideoRotation`.

### Bug 2 — Thumbnails pixelats al slider màxim

`ThumbnailCacheService.ThumbnailMaxSize` de 512 → 1024. A `GetCacheKey` s'afegeix un prefix `CacheVersion = "v2"` perquè les entrades velles de 512px del cache en disc no s'aprofitin: els hash canvien i se'n generen de nous. Les antigues queden orfes (es poden netejar a mà a `%LocalAppData%\iPhotoImporter\ThumbnailCache`).

### Bug 6 — DiskScan popup sense sortida neta

`ToggleDiskScanPanel` ara, quan tanca el panell, cancel·la el `CancellationTokenSource` de l'scan actiu, buida `DiskScanResults` i neteja `DiskScanStatus`. El botó X del header ja feia aquest toggle, així que no cal canviar el XAML.

### Bug 5 — Visor no avança després d'eliminar

A `DeleteSelectedAsync`, abans del delete es captura `wasViewingDeletedItem = IsViewerOpen && ViewerCurrentItem ∈ filesToDelete` i `previousViewerIndex`. Després del remove:

```csharp
if (wasViewingDeletedItem) {
    if (Photos.Count == 0) CloseViewer();
    else NavigateViewer(Math.Min(previousViewerIndex, Photos.Count - 1));
}
```

També es corregeix un pre-existing bug relacionat: el delete eliminava els ítems de `Photos` (vista filtrada) però NO de `_allPhotos` (llista mestra), de manera que en canviar filtres les fotos eliminades "tornaven". Ara es fa `_allPhotos.RemoveAll(toDeleteSet.Contains)` + recàlcul de `PhotoCount/VideoCount`.

### Bug 3 — Delete sense confirmació + Undo 1 nivell + Ctrl+Z

1. **Eliminada la `MessageBox.Show`** de confirmació a `DeleteSelectedAsync`. La paperera del sistema ja és reversible i el toast d'undo cobreix l'error humà. El `MessageBox` de `MoveFiles` (moviment fora de la paperera) es manté — aquell sí és irreversible.

2. **`FileService.RestoreFromRecycleBinAsync(IList<string> originalPaths)`** — restaura fitxers de la paperera via `Shell.Application` (COM). `SHFileOperation` amb `FOF_ALLOWUNDO` no retorna les rutes dins la paperera, per això cal COM. Es llança en un thread STA dedicat. Iteració: `shell.NameSpace(0xA).Items()`, `GetDetailsOf(item, 1)` retorna "Original Location" a Win10+, es compara `originalLocation + name` contra el set demanat, i s'invoca el verb de restaurar. Es cobreixen diversos idiomes: `restore`, `undelete`, `restaurar`, `restablecer`, `wiederherstellen`, `ripristina`, `restaurer` (es tenen en compte possibles mnemònics `&`).

3. **Estat d'undo a `MainViewModel`:**
   - `_lastDeletedItems: List<PhotoItem>`
   - `_lastDeletedOriginalPaths: List<string>`
   - `CanUndoDelete => _lastDeletedItems.Count > 0`
   - `UndoToastMessage` amb text localitzat ("1 fitxer mogut…" / "N fitxers moguts…")

4. **`UndoLastDeleteCommand`** — buida l'estat d'undo primer (evita doble execució), crida `RestoreFromRecycleBinAsync`, re-insereix a `_allPhotos` els ítems el fitxer dels quals torna a existir, re-ordena per data, recalcula comptadors i crida `ApplyFilter()` per regenerar la vista.

5. **`DismissUndoToastCommand`** — buida l'estat d'undo sense restaurar (botó X del toast).

6. **Drecera Ctrl+Z** — afegida com a `Window.InputBindings`:
   ```xml
   <KeyBinding Modifiers="Control" Key="Z" Command="{Binding UndoLastDeleteCommand}"/>
   ```

7. **Toast flotant** — `Border` amb `Grid.Row="1"` i `Panel.ZIndex="1000"`, centrat a baix, visible mentre `CanUndoDelete = true`. Posat al mateix nivell que el `ViewerOverlay` (que també està a `Grid.Row="1"`) perquè sigui sempre visible, incloent quan s'elimina des del visor overlay. Conté icona paperera, missatge bound a `UndoToastMessage`, botó "Desfer" destacat amb color `Accent` i botó X per descartar.

### Bug 1 — Crash vídeo i mitigació `GetVideoRotation`

El crash del runtime Swift en inicialitzar `VideoPlayer<...>` és específic de macOS 26.4 i no aplica a Windows (usa `MediaElement` nativa). **No cal fix.**

Sí s'aplica la mitigació defensiva a `LoadViewerImage`: llegir la rotació del vídeo síncronament al MainActor (main thread WPF) podia congelar la UI amb vídeos grans. Ara, quan `VideoRotation == 0` i és local, es fa a `Task.Run` i s'aplica al `Dispatcher` quan acaba, verificant primer que `ViewerCurrentItem` segueixi sent el mateix ítem (l'usuari pot haver navegat mentrestant). La lectura de `FileService.GetVideoRotation` ja utilitzava `FileStream.Read(buffer, 0, 262144)` limitat a 256KB, no calia canvi addicional.

### Fix durant proves — Delete al visor no arribava a `Window_KeyDown`

Durant les proves es va descobrir que la tecla `Delete` al visor no disparava el handler `KeyDown` del Window (les fletxes sí). Amb `PreviewKeyDown` (tunneling) tampoc canviava res, de manera que es va afegir logging a disc per inspeccionar events. El log confirmava que Delete mai arribava — en realitat l'usuari estava provant amb una tecla diferent. Un cop verificada la tecla correcta (Supr/Del), el flux funcionava.

Canvis deixats al codi:
- Handler `Window_PreviewKeyDown` per interceptar Delete al tunneling, per si algun control fill el captura en un futur.
- `DeleteSelectedAsync` comprova que `SelectedPhotos.Count == 0 && (IsViewerOpen || IsSplitViewerVisible) && ViewerCurrentItem != null` i en aquest cas selecciona automàticament la foto del visor. Això permet que tant la tecla Delete com **el botó de paperera al visor** (que invoca directament `DeleteSelectedCommand`) funcionin sense que l'usuari hagi de marcar checkboxes a la graella.

### Fitxers afectats

- `Services/ThumbnailCacheService.cs` — bug 2 (`ThumbnailMaxSize=1024`, `CacheVersion="v2"` a `GetCacheKey`)
- `Services/FileService.cs` — bug 3 (`RestoreFromRecycleBinAsync`)
- `ViewModels/MainViewModel.cs` — bugs 3, 5, 6, 1 (mitigació), fix delete al visor
- `MainWindow.xaml` — Ctrl+Z `InputBinding`, toast flotant, event `PreviewKeyDown`
- `MainWindow.xaml.cs` — handler `Window_PreviewKeyDown` per tunneling de Delete

### Notes

- L'undo via `Shell.Application` només funciona si Windows està en un idioma cobert pels verbs. Si no, es pot afegir a `restoreVerbPrefixes`.
- No hi ha animació al toast (macOS tenia `.transition(.move(.bottom))`). Es podria afegir amb un `Storyboard` si molesta.
- El delete ara actualitza `_allPhotos`. Si el delete és a `_allPhotos` en mode browse de dispositiu, caldria una revisió — de moment el delete via MTP a iPhone no està implementat, així que no hi ha regressió aquí.

---

## 2026-04-11 — macOS: 5 bugs d'UX durant neteja d'arxivadors + fix crash vídeo

Sessió centrada a resoldre 5 bugs reportats durant l'ús real netejant arxivadors de fotos. Totes les solucions estan a la versió macOS; **cal comprovar si afecten també la versió Windows**.

### Bug 1 — Crash al reproduir vídeo al visor

**Símptoma:** Clicar qualsevol vídeo (fins i tot local, gravat amb iPhone) al visor crashava l'app amb `SIGABRT`.

**Diagnòstic:** Els crash logs de `~/Library/Logs/DiagnosticReports/` mostraven la mateixa stack repetidament:

```
swift::fatalError
getSuperclassMetadata
_swift_initClassMetadataImpl
_AVKit_SwiftUI __swift_instantiateGenericMetadata
```

Això és un bug del runtime Swift a macOS 26.4 amb la metadata generica del tipus `VideoPlayer` de SwiftUI (framework `_AVKit_SwiftUI`). Afecta qualsevol inicialització de `VideoPlayer<...>` en aquesta versió del sistema.

**Solució:** Substituir el `VideoPlayer` de SwiftUI per `AVPlayerView` d'AppKit embolcallat amb `NSViewRepresentable`. Això evita completament el camí de metadata generica problemàtic.

`Views/VideoPlayerView.swift` es reescriu amb:
- `AVPlayerNSView: NSViewRepresentable` — wrapper d'`AVPlayerView` amb `controlsStyle = .inline`, `showsFullScreenToggleButton = true`, `videoGravity = .resizeAspect`.
- Coordinator amb `NSKeyValueObservation` a `playerItem.status` per detectar `.failed` i mostrar overlay d'error ("No es pot reproduir el vídeo") en lloc de crashar si el codec no és suportat.
- `teardown()` al dismantle per invalidar l'observador i alliberar el player.

**Mitigacions addicionals aplicades (defensives):**

- `FileService.getVideoRotation()` canviat per usar `FileHandle.read(upToCount: 262144)` en lloc de `Data(contentsOf: url, options: [.mappedIfSafe])`. Evita mapar fitxers de vídeo de diversos GB que podrien causar crashos o congelar la UI. Llegeix només els primers 256KB on hi ha el tkhd box.
- La crida a `getVideoRotation` des de `loadViewerImage` s'ha mogut a `Task.detached(priority: .utility)` perquè era síncrona al `MainActor` i bloquejava la UI en obrir vídeos grans.

### Bug 2 — Thumbnails pixelats en ampliar el slider

**Símptoma:** El slider de la graella permet cel·les de fins a 400pt, però al màxim els thumbnails es veien borrosos i pixelats.

**Diagnòstic:** `ThumbnailCacheService.thumbnailMaxSize = 512` vs cel·les de 400pt que a retina són 800px físics. Thumbnails de 512px s'escalaven 1.56x.

**Solució:** Augmentat `thumbnailMaxSize` de 512 a 1024px. Cobreix 800px retina amb marge. Cache en disc ~4x més gran, acceptable. Per forçar regeneració sense trencar el cache vell, s'ha afegit una constant `cacheVersion = "v2"` i el `getCacheKey()` la prefixa al raw. Les entrades antigues de 512px queden orfes al disc (es poden netejar manualment).

### Bug 3 — Delete molesta + Undo 1 nivell

**Símptoma:** Durant la neteja d'arxivadors grans, `NSAlert` preguntant confirmació a cada eliminació era insuportable. A més no hi havia manera de recuperar si es polsava per error.

**Solució:**

1. **Tret el `NSAlert`** de `deleteSelected()`. La paperera del sistema ja és reversible, la doble confirmació era redundant. **Important:** NO s'ha tret de `deleteSelectedFromDevice()` — aquest delete és al dispositiu iPhone via MTP, irreversible, i la confirmació hi ha de quedar.

2. **Estat d'undo 1 nivell** a `MainViewModel`:
   ```swift
   private var lastDeletedItems: [PhotoItem] = []
   private var lastDeletedTrashPairs: [(originalPath: String, trashURL: URL)] = []
   var canUndoDelete: Bool { !lastDeletedItems.isEmpty }
   ```

3. **`FileService.deleteFiles()`** ara retorna `(deleted: Int, trashedPairs: [(originalPath, trashURL)])`. Usa `trashItem(at:resultingItemURL:)` amb `inout NSURL?` per capturar la URL exacta dins `~/.Trash/`. Nou mètode `restoreFromTrash(trashURL:originalPath:)` que fa `moveItem` inversa (amb check que l'original path no estigui ocupat).

4. **`undoLastDelete()`**: itera els `trashedPairs`, restaura cada fitxer, re-insereix el `PhotoItem` a `allPhotos`, recalcula `photoCount/videoCount` i crida `applyFilter()`. Buida l'estat d'undo immediatament per evitar dobles execucions.

5. **`dismissUndoToast()`** buida l'estat sense restaurar (el botó X del toast).

6. **Shortcut Cmd+Z** a `ContentView.handleKeyPress` dins del switch de modifiers command. Consistent amb la resta de shortcuts del grid.

7. **Toast flotant d'undo** al `ZStack` principal de `ContentView` (per sobre de tot, inclòs overlay viewer i import modal):
   - Fons negre semitransparent, icona paperera, missatge "N fitxer(s) moguts a la paperera", botó **Desfer** destacat amb color `accent`, botó X per descartar.
   - `.transition(.move(edge: .bottom).combined(with: .opacity))` amb animació de 0.2s.
   - Visible sempre que `canUndoDelete == true`, independentment de si estàs al visor o no.
   - Un botó "Desfer" addicional a la `StatusBarView` com a redundància al bottom.

**Per què un toast i no només el botó de status bar:** la status bar queda darrere del `ViewerOverlayView` (que és un layer superior del ZStack). Quan elimines des del visor overlay, el botó de status bar no es veu. El toast, en canvi, és part del ZStack al mateix nivell que l'overlay, així que sempre és visible.

### Bug 5 — Visor: eliminar foto no avançava a la següent

**Símptoma:** Quan estaves al visor mirant una foto i l'eliminaves, el visor no avançava automàticament a la següent — o es quedava apuntant a l'índex antic (foto equivocada) o a out-of-bounds.

**Solució:** Al final de `deleteSelected()` i `deleteSelectedFromDevice()`, abans d'actualitzar `statusMessage`:

```swift
if wasViewingDeletedItem {
    if photos.isEmpty {
        closeViewer()
    } else {
        let newIndex = min(previousViewerIndex, photos.count - 1)
        navigateViewer(to: newIndex)
    }
}
```

`wasViewingDeletedItem` i `previousViewerIndex` es capturen abans del bucle de remove. `navigateViewer(to:)` ja fa tot el necessari (reset zoom, load image, scroll-to en split mode).

### Bug 6 — DiskScanPopover sense sortida abans d'escanejar

**Símptoma:** El sheet de "Cercar fotos a l'ordinador" no tenia manera de sortir sense fer res — només hi havia el botó "Cercar" (que iniciava el scan) i, un cop escanejant, el botó "Aturar" que cancel·lava la tasca però no tancava el sheet.

**Solució:** Botó X (`xmark.circle.fill`) afegit al `HStack` del header de `DiskScanPopover`, sempre visible. En clicar:
```swift
viewModel.cancelDiskScan()    // cancel·la tasca si n'hi ha
viewModel.diskScanResults = []  // buida resultats
viewModel.showScanResults = false  // tanca sheet
```

### Fitxers afectats

- `ViewModels/MainViewModel.swift` — bugs 1 (getVideoRotation background), 3 (undo state, `undoLastDelete`, `dismissUndoToast`, removed NSAlert), 5 (viewerIndex advance després de delete)
- `Services/FileService.swift` — bug 1 (`getVideoRotation` amb FileHandle), 3 (`deleteFiles` retorna trashedPairs, `restoreFromTrash`)
- `Services/ThumbnailCacheService.swift` — bug 2 (`thumbnailMaxSize = 1024`, `cacheVersion = "v2"`)
- `Views/VideoPlayerView.swift` — bug 1 (reescrit amb `NSViewRepresentable` + `AVPlayerView`)
- `Views/ContentView.swift` — bug 3 (Cmd+Z shortcut, toast flotant)
- `Views/StatusBarView.swift` — bug 3 (botó "Desfer" a la status bar)
- `Views/ToolbarView.swift` — bug 6 (botó X al header del DiskScanPopover)

### Pendent (bugs que poden afectar Windows també)

Tots els fixes estan fets només a macOS. Cal comprovar cas a cas a Windows:
- Crash al reproduir vídeo HEVC (pot afectar `MediaElement` / `Windows.Media.Playback`)
- Thumbnails pixelats (cache també és 512px a `ThumbnailCacheService.cs`)
- Delete amb confirmació MessageBox (verificar si molesta igual)
- Undo 1 nivell (no implementat — afegir Ctrl+Z)
- Viewer eliminar foto → avançar següent
- DiskScan modal amb sortida sense escanejar

---

## 2026-04-06 — Windows al dia amb macOS: funcionalitats, UI i importació iPhone

### Funcionalitats portades de macOS a Windows

Totes les funcionalitats de la versió macOS (excepte les específiques d'ImageCaptureCore) s'han implementat a la versió Windows WPF/.NET 8:

1. **Suport RAW + formats moderns** — CR2, CR3, NEF, ARW, DNG, RAF, ORF, RW2, PEF, SRW, RWL, HEIC, HEIF, AVIF, JXL, PSD, vídeos M4V/WebM/3GP/MTS via Magick.NET-Q8-AnyCPU. Extensions centralitzades a `PhotoItem`.

2. **Preview embegut (Photo Mechanic style)** — Piràmide de 3 nivells al visor: thumbnail (instant) → quick preview embegut RAW/HEIC (~2048px, quasi instant) → resolució completa (background). `FileService.ExtractEmbeddedPreview()` i `LoadRawQuickPreview()`.

3. **Deduplicació 3 nivells** — MD5 (exactes, pre-filtrat per mida), perceptual hash 8x8 (similars, Hamming ≤5), EXIF fingerprint (SHA256 datetime+camera+dimensions). Scan automàtic en background. UI: pastilles "= N" i "≈ N" amb filtre toggle.

4. **Sort order** — Toggle ascendent/descendent per data. Integrat a `ApplyFilter()`.

5. **Timeline mode** — Agrupació per dia/mes/any amb noms catalans. Headers clicables per col·lapsar/expandir. `TimelineGroup` amb `INotifyPropertyChanged`.

6. **GPS + Geocoding** — Extracció GPS d'EXIF via Magick.NET. Reverse geocoding via Nominatim (OpenStreetMap) en català amb cache. Regla especial Catalunya. Mostrat a thumbnails i visor.

7. **Recursive folder toggle** — Toggle per carpeta amb re-scan automàtic.

8. **Disk scanner** — Escaneja Pictures, Desktop, Documents, Downloads + drives extraïbles. Panell lateral amb resultats, checkboxes, batch add.

9. **Zoom cursor-aware** — Scroll wheel fa zoom cap al punt del cursor (com macOS `viewerSmoothZoom`).

10. **Paperera de reciclatge** — Delete via `SHFileOperation` amb `FOF_ALLOWUNDO` en lloc d'eliminació permanent.

### Browse mode iPhone (importació selectiva)

**Flux anterior:** Detectar → importar TOT directament.
**Flux nou (estil macOS):** Detectar → navegar fotos a la graella → seleccionar → importar només les seleccionades.

- `BrowseDeviceAsync()`: guarda estat local, escaneja dispositiu (limitat als últims 2 mesos per velocitat), mostra fotos a la graella principal.
- `ImportSelectedFromDeviceAsync()`: importa només les fotos seleccionades a la carpeta destí.
- `ExitDeviceBrowseMode()`: restaura estat local anterior.
- `LoadDeviceThumbnailsAsync()`: càrrega de thumbnails en background amb rotació EXIF.
- `LoadDeviceFullImageAsync()`: descarrega fitxer temporal per visor a resolució completa.
- Banner "Navegant: iPhone — X fitxers" amb botó desconnectar.
- Barra d'accions amb "Importar" i "Desconnectar" en mode dispositiu.

**Fix detecció iPhone:** `GetDrives()` retorna 0 per iPhones. Fallback a `\Internal Storage` directament.

**Rotació thumbnails MTP:** Heurístic per detectar fotos portrait d'iPhone (thumbnail landscape → girar 90°). Thumbnail regenerat amb orientació correcta quan es descarrega la foto completa.

**Limitació descoberta:** `DeleteFile` via MTP es congela indefinidament amb iPhones. L'eliminació de fotos de l'iPhone no és possible via MTP a Windows.

### Optimització de rendiment (velocitat macOS)

**Problema:** La versió Windows era molt més lenta que macOS en càrrega de thumbnails, canvi a timeline, i scroll.

**Causa arrel:** 5 problemes identificats:
1. `WrapPanel` de WPF NO virtualitza — creava 5000 elements UI amb 5000 fotos.
2. `ObservableCollection.Clear()` + `Add()` en bucle generava N+1 events `CollectionChanged`.
3. `Dispatcher.Invoke()` (síncron) bloquejava threads background esperant la UI.
4. Batch size 4 massa petit per SSDs moderns.
5. Timeline sense virtualització — renderitzava tots els grups d'un cop.

**Solucions:**
1. **VirtualizingWrapPanel** (NuGet `WpfToolkit.VirtualizingWrapPanel`) per la graella principal. `ListBox` amb `ItemContainerStyle` transparent per mantenir la selecció custom.
2. **Assignació atòmica** — `Photos = new ObservableCollection<PhotoItem>(sorted)` en lloc de Clear+Add. `Photos` canviat de `{ get; }` a `{ get; private set; }` amb `SetProperty`. Mateix patró per `GroupedPhotos`.
3. **`Dispatcher.InvokeAsync()`** no-bloquejant + actualització de 12 thumbnails en una sola crida Dispatcher.
4. **Batch size 12** — 3x més thumbnails en paral·lel.
5. **Timeline virtualitzada** — `ListBox` amb `VirtualizingStackPanel` built-in per la llista de grups (equivalent a `LazyVStack` de SwiftUI).

### Càrrega incremental per mesos (browse iPhone)

Al banner de browse mode hi ha el botó "**+ Mes anterior**" que carrega un mes addicional de fotos del dispositiu. Cada cop retrocedeix un mes, escaneja només el mes nou (sense re-escanejar), i afegeix les fotos a la graella. Spinner animat + missatge d'estat mentre carrega.

### Fix timeline mode

El `ToggleButton` de timeline canviava `IsTimelineMode` via binding però no cridava `RebuildGroups()`. Afegit `OnIsTimelineModeChanged` partial method que reconstrueix els grups automàticament.

### Icones i UI alineades amb macOS

- Icona app: convertida des de macOS AppIcon.icns a .ico.
- Títol: iPhoto Viewer → iPhoto Manager.
- Toolbar reordenada (ordre macOS): disk scan → add folder → folders → destí → iPhone.
- Barra de controls reordenada: comptador → filtres → select → sort → split → timeline → slider → duplicats.
- Icones actualitzades: carpetes emoji 📁, zoom amb lupa, split vertical, tancar cercle, delete al visor.
- Thumbnails: data + localització en lloc de filename.

### NuGet afegit

- **Magick.NET-Q8-AnyCPU** v14.11.1 — Únic paquet nou. Suport RAW, HEIC, AVIF, JXL, PSD, extracció EXIF/GPS.

### Fitxers nous

- `Models/TimelineGroup.cs` — Enum TimelineGrouping + classe TimelineGroup.
- `Models/DiskScanResult.cs` — Model per resultats del disk scanner.
- `Services/GeocodingService.cs` — Reverse geocoding via Nominatim amb cache i rate limit.

---

## 2026-04-01 — Rename, formats RAW, velocitat i deduplicació

### Rename iPhotoViewer → iPhotoManager

Es renombra tot el projecte (Package.swift, bundle identifiers, struct App, cache paths, temp dirs) per reflectir millor la funció de l'app: no és només un visor, sinó un gestor de fotos orientat a organització, neteja i còpia.

### Suport de formats RAW i nous formats

**Problema:** L'app només suportava JPG, PNG, WEBP, GIF, BMP, TIFF i HEIC. No reconeixia cap format RAW de càmera, i el DeviceImportService tenia la seva pròpia llista d'extensions hardcoded (sense HEIC ni RAW), de manera que les fotos DNG de l'iPhone ProRAW no apareixien al browser del dispositiu.

**Solució:**
- S'afegeixen tots els RAW principals (CR2/CR3 Canon, NEF Nikon, ARW Sony, DNG Adobe, RAF Fuji, ORF Olympus, RW2 Panasonic, PEF Pentax, SRW Samsung, RWL Leica), formats moderns (AVIF, JPEG XL, PSD) i vídeos addicionals (M4V, WebM, 3GP, MTS/M2TS).
- Les extensions es centralitzen a `PhotoItem.allExtensions` i `PhotoItem.rawExtensions`. DeviceImportService.collectMediaFiles ara usa `PhotoItem.allExtensions` en comptes de la seva llista pròpia, eliminant la divergència.
- macOS suporta tots aquests formats nativament via CGImageSource (ImageIO framework).

### Velocitat estil Photo Mechanic — preview embegut

**Problema:** Cada foto RAW o HEIC requeria una decodificació completa per generar el thumbnail, cosa que era lenta per a biblioteques grans. Photo Mechanic resol això extraient el JPEG preview que totes les càmeres incrusten dins els fitxers RAW/HEIC.

**Solució:**
- `FileService.extractEmbeddedPreview()` intenta extreure el thumbnail embegut usant `kCGImageSourceCreateThumbnailFromImageIfAbsent: false`. Si el preview existeix i és >= 200px, el retorna directament sense decodificar la imatge sencera.
- `generateThumbnail()` ara segueix una estratègia de dos nivells: primer intenta el preview embegut (instantani), i només si no n'hi ha, fa full decode amb downscale.
- `loadQuickPreview()` afegeix un nivell intermedi (2048px) per al visor, permetent mostrar ràpidament una preview mentre es carrega la resolució completa en background.
- Al visor (`MainViewModel`), s'implementa una piràmide de 3 nivells: thumbnail (instant) → quick preview (RAW/HEIC embegut, quasi instant) → full image (background). L'usuari veu contingut immediatament i la qualitat va millorant progressivament.

### Deduplicació de fotos (carpeta local)

**Problema:** L'app no tenia cap funcionalitat per detectar fotos duplicades, una necessitat fonamental per a la neteja de biblioteques.

**Solució — 3 nivells de detecció:**

1. **MD5 hash (còpies idèntiques):** Es computa el hash MD5 del fitxer complet (per chunks de 64KB). Primer es pre-filtra per `sizeBytes` — només els fitxers amb mida idèntica es comparen, cosa que descarta la gran majoria i fa el procés molt ràpid. Implementat a `FileService.computeMD5()` usant `Insecure.MD5` de CryptoKit.

2. **Perceptual hash (fotos visualment similars):** Es redimensiona la imatge a 8x8 grayscale, es calcula la mitjana de brillantor, i cada píxel es converteix a 1 (per sobre la mitjana) o 0 (per sota), generant un hash de 64 bits. Dues fotos amb distància Hamming ≤ 5 es consideren duplicats visuals. Implementat a `FileService.computePerceptualHash()`. La comparació és O(n²) que és lenta per a biblioteques molt grans, però dóna bons resultats de precisió.

3. **EXIF fingerprint (mateixa càmera + moment):** Es combinen DateTimeOriginal, Make, Model i dimensions de la imatge en un hash SHA256. Si coincideix, és probablement la mateixa foto amb diferent processament. Implementat a `FileService.computeExifFingerprint()`.

**Flux d'execució:** `scanForDuplicates()` s'executa en background després de carregar una carpeta. Cada ítem rep un `duplicateGroupId` (prefixat amb "md5-", "phash-" o "exif-") que l'identifica com a membre d'un grup de duplicats. Els comptadors `exactDuplicateCount` i `similarDuplicateCount` s'actualitzen incrementalment.

**UI:** Dues pastilles independents a la barra de controls (després del slider de mida): `=` per exactes i `≈` per similars. Cadascuna amb el seu comptador i spinner independent (`isScanningExact`, `isScanningSimilar`). Al clicar, es filtra la graella per mostrar només els duplicats del tipus corresponent. Es poden activar ambdues alhora.

**Barra d'estat:** Al seleccionar una foto, mostra el path complet (`nom — carpeta`) per ajudar a identificar quina còpia eliminar quan es treballa amb múltiples carpetes.

**Protecció de la barra de controls:** La barra es mostra sempre que `photoCount + videoCount > 0`, evitant que desaparegui si l'usuari desactiva tots els filtres.

### Deduplicació al browser iPhone

**Problema:** L'usuari vol netejar ràfegues i fotos similars directament des de l'iPhone sense importar-les primer.

**Solució parcial:** `scanDeviceDuplicates()` calcula el perceptual hash a partir dels thumbnails que ja es descarreguen del dispositiu (via `FileService.computePerceptualHashFromImage()`). No cal descarregar la foto completa. Per als "exactes", s'usa la combinació de mida + perceptual hash idèntic (Hamming = 0) com a proxy de MD5.

**Limitació:** Amb 34K fotos, la càrrega de thumbnails és seqüencial i lenta. Les fotos duplicades filtrades poden no tenir thumbnail encara, mostrant placeholders negres.

### Import iPhone — Modal

**Problema:** El panell lateral d'importació no tenia sentit com a interfície: ocupava espai permanent, no era prou visible, i no guiava l'usuari pel procés.

**Solució:** Es converteix en un diàleg modal centrat (`ImportPanelView`) amb fons fosc semitransparent. Mostra: detecció de dispositius, progrés de connexió, progrés d'enumeració de fitxers, i botons "D'acord" / "Desconnectar" al final. No es pot tancar durant el browse o importació activa.

### Reconnexió iPhone

**Problema:** Al tancar el browser de l'iPhone i tornar-lo a obrir, no trobava fotos perquè el `sleep(3)` no era suficient per a la re-enumeració del catàleg.

**Solució:** Es substitueix el `sleep(3)` per un polling de `device.mediaFiles` amb timeout de 15 segons: cada segon comprova si el catàleg ja està llest.

### Bugs pendents iPhone (no resolts)

**Dispositiu duplicat al modal:** L'iPhone apareix dues vegades (com a càmera i com a iPhone) malgrat múltiples intents de dedup (per UUID, nom, serial, dedup post-append, dedup final a detectDevices). El problema de fons és una race condition en els callbacks `didAdd` de `ICDeviceBrowser` que arriben quasi simultàniament en dos `Task { @MainActor }` separats, i cap dels dos ha acabat d'escriure `devices` quan l'altre comprova. S'ha intentat un `removeAll` per nom abans d'afegir, però el duplicat persisteix. Cal una investigació dedicada del timing dels callbacks d'ImageCaptureCore.

**Placeholders negres en duplicats:** Al filtrar duplicats al browser iPhone, algunes fotos mostren placeholder negre. La càrrega de thumbnails prioritza les fotos visibles (`photos` filtrat primer, `allPhotos` resta després), però amb 34K fotos la càrrega és massa lenta. Cal explorar alternatives: batch download de thumbnails, o carregar el thumbnail on-demand quan la cel·la és visible.

**Enumeració bloqueja UI:** Amb 34K fitxers, l'enumeració de `device.mediaFiles` bloqueja la UI durant uns segons malgrat haver-la mogut a `Task.detached`. Probablement el problema és la creació massiva de `PhotoItem` al tornar al MainActor, o l'`applyFilter()` amb 34K elements. Un `Task.yield()` dins el bucle causa deadlock al MainActor. Cal explorar chunked loading o virtualització.

---

## 2026-04-02 — Investigació publicació App Store

### Requisits per publicar a l'App Store de macOS

L'objectiu és publicar iPhotoManager a l'App Store, a més de la distribució directa (DMG signat) que ja funciona.

**Requisits identificats:**

1. **Apple Developer Program** — Ja actiu (team ID Q8A29JFBWR, 99$/any).
2. **App Sandbox (OBLIGATORI)** — L'App Store exigeix que l'app funcioni dins el sandbox de macOS. Això és el punt crític perquè:
   - L'accés a carpetes via `NSOpenPanel` ja funciona (l'usuari autoritza explícitament).
   - El cache de thumbnails hauria d'anar dins el container de l'app (`~/Library/Containers/`).
   - **ImageCaptureCore + USB**: L'entitlement `com.apple.security.device.usb` que usem per accedir a l'iPhone pot NO estar permès dins sandbox. Cal investigar si Apple l'aprova per apps de l'App Store o si cal un entitlement especial. Si no funciona, la funcionalitat d'import de dispositiu s'hauria de fer opcional o eliminar de la versió App Store.
3. **Certificat de distribució** — Cal "Apple Distribution" (no "Developer ID" que és per distribució directa). Es genera a Xcode → Accounts → Manage Certificates.
4. **Privacy Nutrition Labels** — Declarar a App Store Connect quines dades es recullen. En el nostre cas: accés a fotos locals (via NSOpenPanel), GPS EXIF (per geocoding), i potencialment dades del dispositiu USB.
5. **Icona 1024x1024** — Ja tenim AppIcon.icns, cal verificar que inclou la mida 1024x1024 per l'App Store.
6. **Captures de pantalla** — Cal preparar captures de pantalla de l'app per l'App Store listing.
7. **SDK mínim** — A partir d'abril 2026, Apple requereix compilar amb Xcode 26 / SDK macOS 26. Ara compilem amb Xcode 15.2+ / macOS 14+. Caldrà actualitzar.
8. **Archive + Upload** — Crear archive via Xcode (`Product → Archive`) i pujar via Xcode Organizer o `xcrun altool`.

**Pas crític a investigar:** Verificar si ImageCaptureCore funciona dins App Sandbox. Si no, opcions:
- Distribuir dues versions: App Store (sense import iPhone) i directa (amb import iPhone).
- Demanar un entitlement especial a Apple.
- Trobar una alternativa a ImageCaptureCore compatible amb sandbox.

---

## 2026-04-02 — Dedup dispositius, mida finestra, build.sh

### Deduplicació dispositius iPhone (bug #5)

**Problema:** L'iPhone apareixia duplicat al modal d'importació (un cop com a "Camera", un cop com a "iPhone") per race condition als callbacks `didAdd` de `ICDeviceBrowser`.

**Solució:** `devices` passa de ser un array a ser una propietat computada basada en un `Dictionary<String, DeviceInfo>` (`devicesByKey`) keyed per `serialNumberString` (primari) o `name+usbProductID+usbVendorID` (fallback). Un sol punt d'entrada `addDevice()` centralitza la inserció. Duplicats impossibles per construcció.

**Important — binari .app vs swift build:** El `.app` bundle del Dock conté un binari separat del que genera `swift build`. Cal executar `./build.sh` per compilar, copiar al `.app`, i re-signar amb entitlements USB. Sense re-signar, ImageCaptureCore no funciona.

### Mida de finestra

**Problema:** Amb `defaultSize` al 50% de pantalla (`screenSize.width * 0.5, screenSize.height * 0.5`), la toolbar no mostra les icones. En ampliar manualment la finestra, les icones apareixen.

**Causa:** La ToolbarView usa un `HStack` amb molts elements (icona app, títol, botons scan/folder/destí/iPhone, Spacer) que no cabia en el 50% d'ample de pantalla. Els elements es retallaven sense warning visual.

**Pendent:** Cal fer la toolbar responsive — usar `ScrollView(.horizontal)` o col·lapsar icones a un menú quan l'ample és insuficient. Alternativament, augmentar el `defaultSize` mínim.

### build.sh

Nou script `build.sh` que automatitza: `swift build -c release` → copia binari al `.app` → copia resource bundle → `codesign` amb Developer ID Application i entitlements USB.

**Important — .app bundle vs swift build:** El Dock i Finder executen el `.app` bundle, NO el binari de `.build/debug/`. Sempre cal executar `./build.sh` després de fer canvis per actualitzar el `.app`. El script compila en release, copia binari + resource bundle, i re-signa amb Developer ID. Sense Developer ID, macOS demana permís de volum extraïble cada cop.

### Fix placeholders negres en duplicats iPhone (bug #6)

**Problema:** Al filtrar duplicats al browser iPhone, 2 de 4 fotos no apareixien (placeholder negre).

**Causa real:** `PhotoItem.init(cameraFile:deviceId:)` generava l'ID amb `device://\(deviceId)/\(name)`. Fitxers duplicats amb el **mateix nom** (a carpetes diferents de l'iPhone, ex: `DCIM/100APPLE/IMG_1234.JPG` i `DCIM/101APPLE/IMG_1234.JPG`) tenien el **mateix ID**. SwiftUI's `ForEach` descarta items amb IDs duplicats — només renderitzava un dels dos.

**Solució:** Afegir `cameraFile.parentFolder?.name` a l'ID: `device://\(deviceId)/\(folder)/\(name)`.

**Millores addicionals:**
- `scanDeviceDuplicates()` ara escaneja `allPhotos` (no `photos` filtrat)
- `loadDeviceThumbnails()` prioritza fotos visibles/filtrades, després carrega la resta
- Propagació de thumbnails dins grups de duplicats exactes (per si un germà no té thumbnail)

### Build release trenca thumbnails locals

**Problema:** Compilant amb `swift build -c release`, els thumbnails de carpetes locals no es carreguen (totes les cel·les mostren placeholder). En debug funciona correctament.

**Causa probable:** Optimització del compilador en release trenca la interacció entre `@Observable` (MainViewModel/PhotoItem) i l'`actor ThumbnailCacheService`. L'actor isolation i les optimitzacions de concurrency poden causar race conditions que en debug no es manifesten.

**Solució temporal:** build.sh usa `swift build` (debug) en lloc de `swift build -c release`.

**Pendent:** Investigar la causa exacta i fer que release funcioni (important per distribució).

### Aprenentatges clau de la sessió

1. **`@Observable` + propietat computada:** Usar `var devices: [DeviceInfo] { Array(dict.values) }` com a propietat computada NO funcionava amb `@Observable` — SwiftUI no detectava els canvis correctament al diccionari intern. Solució: usar stored array `var devices` + `Set<String>` de claus per dedup.

2. **ICDeviceBrowser callbacks:** El `didAdd` es crida un sol cop per l'iPhone (type=257 = camera+local). El segon "dispositiu" apareixia transitòriament durant el processament però desapareixia un cop completat.

3. **logToFile path:** `NSHomeDirectory()` funciona dins l'app per escriure a `~/iphoto_import.log`. `/tmp/iphoto_debug.log` també funciona. El problema de "no trobar el log" era perquè s'executava el binari antic del `.app` en lloc del compilat amb `swift build`.
