# iPhotoManager — Project Log

## 2026-07-14 — Release pública v1.0.0 (Mac notaritzat) + descàrrega des de Mirat

**Build macOS notaritzat** (`MacOS/notarize.sh`): `swift build -c release` → codesign *Developer ID Application: MassiuSoft SL* (hardened runtime) → `notarytool submit --wait` → **Accepted** → `stapler staple`. Reempaquetat com a **`Photo Manager.app`** (el bundle es renombra DESPRÉS de notaritzar/estapar; el segell no depèn del nom de carpeta → `spctl` segueix «accepted, source=Notarized Developer ID») i comprimit a `PhotoManager-1.0.0-mac.zip` (~3,6 MB, arm64 natiu). Commit del `.app` re-signat/notaritzat: `ee3adca`.

**GitHub Release `v1.0.0`** (repo públic `EnricGS/iphoto-importer`) amb els dos binaris descarregables:
- `PhotoManager_Setup_1.0.0.exe` — Windows x64 (~75 MB, self-contained + Inno Setup; build fet a màquina Windows, vegeu l'entrada següent)
- `PhotoManager-1.0.0-mac.zip` — macOS arm64 notaritzat (~3,6 MB)

**Descàrrega des de Mirat**: la web `/baixar` (miratfotos.com) enllaça aquests assets via `/api/desktop/download?platform=win|mac`, que fa **302 a l'asset de la GitHub Release** (repo públic → CDN de GitHub, res a MinIO). Detalls al `project_log.md` de **mirat**. ⚠️ El Windows encara **no està signat** (SmartScreen mostra l'avís el primer cop) — pendent Azure Trusted Signing amb MassiuSoft SL.

## 2026-07-14 — Build Windows de distribució + investigació signatura de codi

### Build fet (màquina Windows)

Compilat l'instal·lador descarregable per a usuaris finals, amb la icona nova i el nom «Photo Manager»:

1. `dotnet publish -c Release -o publish` → `publish\iPhotoImporter.exe` (~80 MB, single-file + self-contained win-x64; porta el runtime .NET 8 a dins, l'usuari final no ha d'instal·lar res).
2. Inno Setup 6 (`ISCC.exe installer.iss`) → `installer_output\PhotoManager_Setup_1.0.0.exe` (~75 MB, compressió LZMA2/ultra64).

Verificat: `ProductName=Photo Manager`, `Version=1.0.0`, icona nova (`app.ico` 364 KB) aplicada tant a l'exe com al `Setup.exe`. Idiomes de l'instal·lador: català, castellà, anglès. Eliminat l'instal·lador antic `iPhotoImporter_Setup_1.0.0.exe` (nom/icona vells).

Nota: l'exe de `publish\` **funciona directament** (doble clic, sense instal·lar .NET); el setup només afegeix comoditat (dreceres menú Inici/escriptori, còpia a Program Files, desinstal·lador). `publish/` i `installer_output/` estan a `.gitignore`.

### Signatura de codi (Windows) — investigació i decisió

Cap dels binaris (ni l'exe sol ni el setup) està signat → SmartScreen mostra «Windows ha protegit el teu PC» el primer cop. Per treure-ho cal un **certificat de code-signing** d'una CA reconeguda per Windows. Aclariment important: **ni el compte de Google (Play Console, només Android) ni el d'Apple Developer (macOS) serveixen per signar `.exe` de Windows** — són ecosistemes separats.

Opcions:
- **Azure Trusted Signing (Microsoft)** — ~10 $/mes, al núvol (sense token USB físic), s'integra amb `signtool.exe`. Requereix entitat legal verificable → **MassiuSoft SL hi qualifica**. **Opció triada** (millor cost/benefici; es comporta com un EV per a SmartScreen).
- **Certificat EV** (Sectigo/DigiCert/GlobalSign) — ~300–600 $/any, token hardware obligatori, treu l'avís SmartScreen des del dia 1.
- **Certificat OV** — ~200–400 $/any, token hardware, la reputació SmartScreen s'acumula amb les descàrregues.

**Pendent:** donar d'alta Azure Trusted Signing amb MassiuSoft SL i afegir el pas `signtool sign /fd sha256 /tr <timestamp-url> ...` al final del build (signar `iPhotoImporter.exe` i `Setup.exe`). De moment es distribueix **sense signar**.

## 2026-07-13 — Icona nova + rename públic a «Photo Manager»

### Icona
Redissenyada la icona de l'app (abans «graella + visor», poc reconeixible com a gestor de fotos) via **Claude Design**. Triada una **pila de fotos oberta**: ventall de fotos crema amb un paisatge (muntanya + sol) a la de davant, sobre fons fosc càlid amb accent ambre/terracota. Font vectorial a **`brand/icon.svg`**; script **`brand/make-icons.sh`** (rsvg-convert + ImageMagick + iconutil) regenera i col·loca:
- `app.ico` (Windows, 16→256)
- `AppIcon.icns` + `iPhotoManager.icns` (macOS, 16→1024) a totes les ubicacions del bundle `.app`.

`AppIcon` i `iPhotoManager` ara són la mateixa icona (la pila). Per regenerar després d'editar el SVG: `./brand/make-icons.sh`.

### Rename → «Photo Manager»
Canviat el nom **visible** de l'app a **Photo Manager** (abans «iPhoto Manager»/«iPhoto Importer»; «iPhoto» és marca d'Apple). Tocades només les cadenes de cara a l'usuari; els identificadors interns es mantenen per no trencar builds ni orfenar caches:
- **Windows**: `installer.iss` (`MyAppName`, `OutputBaseFilename=PhotoManager_Setup_*`), `iPhotoImporter.csproj` (`Product`/`AssemblyTitle`/`Version=1.0.0`), títol + capçalera de `MainWindow.xaml`, textos Connect/Settings. Es manté `AssemblyName=iPhotoImporter` → l'exe segueix sent `iPhotoImporter.exe` i els paths `%LocalAppData%\iPhotoImporter\`.
- **macOS**: `Info.plist` (`CFBundleName`/`CFBundleDisplayName`), `WindowGroup`, vistes About/Toolbar/Connect/Settings. Es manté el bundle `iPhotoManager.app`, `CFBundleExecutable`, `CFBundleIdentifier com.iphotomanager.app`.

### Pendent (descàrrega des de Mirat)
Windows: compilar exe/instal·lador en una màquina Windows (Inno Setup) — per això es fa commit+push. macOS: `cd MacOS && ./notarize.sh` (idealment empaquetant com a `Photo Manager.app`). Menor: el badge del header WPF encara és un glif Segoe, no la pila.

## 2026-07-02 — Notarització Apple del build macOS (distribució fora App Store)

### Objectiu

Poder compartir `iPhotoManager.app` a **qualsevol Mac** sense que Gatekeeper el bloquegi ni calgui treure la quarantena manualment (`xattr`). Fins ara `build.sh` firmava amb un certificat *Apple Development* → només corria localment.

### Muntatge (fet un sol cop, ja no cal repetir)

1. **Xcode → Settings → Accounts**: iniciat sessió amb l'Apple ID de MassiuSoft (`enric@massiusoft.com`, team `YQYXYXUDWA`).
2. **Manage Certificates → + → Developer ID Application**: creat i instal·lat a la keychain el certificat `Developer ID Application: MassiuSoft SL (YQYXYXUDWA)` (SHA1 `E48F1489FCFB608F180DC17B321D6F28D248736E`).
3. **App-specific password** generada a appleid.apple.com (nom `notarize-iphoto`).
4. Credencials guardades a la keychain amb `xcrun notarytool store-credentials "massiusoft" --apple-id enric@massiusoft.com --team-id YQYXYXUDWA` → perfil **`massiusoft`** (validat OK).

### Nou script `MacOS/notarize.sh`

Fa tot el flux de distribució en una comanda: build release → `codesign` amb Developer ID + `--options runtime` (hardened) + `--timestamp` → `ditto` zip → `xcrun notarytool submit --keychain-profile massiusoft --wait` → `xcrun stapler staple` → re-empaqueta a `~/Desktop/iPhotoManager-mac.zip`.

**Per a futures versions n'hi ha prou amb:**
```bash
cd ~/Projectes/iphoto-importer/MacOS && ./notarize.sh
```

### Notes

- El build és **arm64** (Apple Silicon). Per a Macs Intel caldria fer-lo universal.
- `build.sh` (debug, firma Apple Development) segueix servint per a iteració local ràpida; `notarize.sh` és per a distribució.
- La cua de notarització d'Apple pot trigar de 2 a 20 min; el `--wait` bloqueja fins que acaba.

---

## 2026-05-02 — Fix penjada en desconnectar iPhone + selector destí Mirat visible

### Problema 1: app es penja en desenxufar l'iPhone durant browse

Quan l'usuari tenia l'iPhone seleccionat com a font (mode `isDeviceBrowseMode`) i el desconnectava, la UI quedava bloquejada fins a 30s o indefinidament:

- `DeviceImportService.didRemove` netejava la llista de dispositius però **no resolia** les continuations en curs (`thumbnailContinuations`, `tempDownloadContinuations`, `metadataContinuations`, `downloadContinuation`, `deleteContinuation`).
- `sessionContinuation` i `catalogContinuation` no tenien cap timeout — podien quedar penjades per sempre.
- `closeSession()` cridava `requestCloseSession()` sobre un `ICCameraDevice` ja desaparegut.

### Fix (`Services/DeviceImportService.swift`)

- Nou helper `cancelAllPendingContinuations()` que resol totes les continuations actives (sessió, catàleg, downloads, thumbnails, metadata, delete) amb valors per defecte (`nil`/`false`/`()`).
- `didRemove`: quan el dispositiu eliminat és el seleccionat, drena pendents abans de tocar l'estat, neteja `selectedDevice`, posa `isImporting=false`/`isBrowsing=false`, i només llavors notifica `onDeviceDisconnected`.
- `closeSession`: drena pendents primer, i només envia `requestCloseSession` si el dispositiu encara és present a `browser?.devices`.
- Afegits timeouts a `sessionContinuation` (30s en import, 15s per intent en browse) per impedir bloquejos infinits si el callback `device(_:didOpenSessionWithError:)` no torna mai.

### Problema 2: selector de destí Mirat invisible

`MiratDestinationPicker` al toolbar només mostrava un `chevron.down` de mida 8pt sense text. Els usuaris no s'adonaven que era un botó per triar el destí.

### Fix (`Views/ToolbarView.swift`)

- Picker amb etiqueta de text llegible: "Triar destí Mirat" quan no hi ha actiu, o el nom del destí actual amb fons accent quan n'hi ha un seleccionat.
- Substituït el chip duplicat (nom + X) per un sol botó `xmark.circle.fill` per desactivar — evita mostrar el nom dues vegades.

### Build

`./build.sh` OK (warning preexistent de `enumerator.makeIterator` no relacionat).

---

## 2026-04-18 — Paritat macOS: integració Mirat replicada

### Context

Replica a la versió macOS (SwiftUI, `iPhotoManager.app`) la integració Mirat afegida ahir a Windows (WPF). Mateix flux: usuari configura destins Mirat (URL + API Key + grup + àlbum opcional), selecciona un com a actiu, i les accions Copiar/Moure pugen a Mirat en lloc de la carpeta local.

### Canvis a iPhoto Manager (macOS)

**Nous fitxers:**

- `MacOS/iPhotoManager/Models/MiratDestination.swift` — `struct Codable, Identifiable, Hashable` amb els mateixos camps que la versió Windows (`id, nom, baseUrl, apiKey, grupId, grupNom, albumId?, albumNom?, pujatPer?`) i `displayLabel` computada.
- `MacOS/iPhotoManager/Services/MiratDestinationStore.swift` — persistència JSON a `~/Library/Application Support/iPhotoManager/mirat-destinations.json` via `JSONEncoder`/`Decoder`. Load/Save atòmic.
- `MacOS/iPhotoManager/Services/MiratService.swift` — client `URLSession`:
  - `listGroups()`, `listAlbums(grupId:)` — GET amb `X-API-Key`
  - `uploadPhoto(_:)` — multipart construït manualment (boundary sense cometes, evita el bug .NET que va calcar undici al client Windows). SHA-256 via `CryptoKit` streaming (chunks 64KB). Thumbnail 200px q70 i preview 2048px q80 via `ImageIO` (`CGImageSourceCreateThumbnailAtIndex` + `kCGImageSourceCreateThumbnailWithTransform` per respectar EXIF orientation, `CGImageDestination` JPEG amb `kCGImageDestinationLossyCompressionQuality`). Filename ASCII-safe. Taula MIME idèntica a Windows.
  - Retorna `MiratUploadResult { success, fotoId, duplicat, errorMessage }`
- `MacOS/iPhotoManager/Views/MiratSettingsView.swift` — `sheet` de configuració: llista destins amb Editar/Eliminar, formulari URL → API Key → Provar connexió → Picker Grup → Picker Àlbum (opcional) → Nom descriptiu → Desar. Preompleix el nom amb el slug del grup quan n'hi ha.

**Fitxers modificats:**

- `MacOS/iPhotoManager/ViewModels/MainViewModel.swift`:
  - Nova propietat `miratStore = MiratDestinationStore()`
  - Estat: `miratDestinations: [MiratDestination]`, `activeMiratDestination: MiratDestination?`, `isUploadingToMirat`, `miratUploadProgress`. Computed `hasActiveMiratDestination`, `activeMiratLabel`.
  - `loadPersistedSettings()` carrega la llista de disc.
  - `addOrUpdateMiratDestination(_:)`, `removeMiratDestination(_:)`, `selectMiratDestination(_:)` — amb persistència automàtica.
  - `uploadPhotosToMirat(_:destination:)` — `withTaskGroup` amb concurrència limitada a 3 simultanis. Actualitza `statusMessage` i `miratUploadProgress` a cada resultat. Format consistent amb Windows: `"Pujant a Mirat (Nom): done/total · N noves · N duplicades · N errors"`.
  - `copySelected()`, `copyCurrentPhoto()`: si hi ha `activeMiratDestination`, ruteja a upload Mirat en lloc de copiar a carpeta local.
  - `moveSelected()`: si hi ha destí Mirat actiu, puja primer i, sense errors, elimina els originals via paperera (reversible amb Cmd+Z).

- `MacOS/iPhotoManager/Views/ToolbarView.swift`:
  - Nova icona núvol (`icloud.and.arrow.up`) que obre el sheet `MiratSettingsView`. Pinta en Accent quan hi ha destí actiu.
  - Nou `MiratDestinationPicker` (`Menu` de SwiftUI) per triar el destí actiu, visible quan hi ha almenys un destí configurat.
  - Chip del destí actiu amb fons `accentSubtle` i botó X per desactivar-lo i tornar a usar la carpeta local.

### Decisions de disseny macOS-específiques

- **HTTP amb `URLSession`**: en lloc de `HttpClient` (Windows). `URLSessionConfiguration` amb timeouts de 300s/600s igual al client Windows. Multipart construït amb `Data` i escapament manual — la Fundació no té equivalent a `MultipartFormDataContent` amb el seu bug del boundary entre cometes, així que evitem d'arrel el problema que Windows va tenir amb undici/Next.js.
- **Thumbnail/preview amb `ImageIO`**: sense dependències externes (Magick.NET a Windows). `CGImageSourceCreateThumbnailAtIndex` és ja el mètode usat per a miniatures de la graella, sabem que funciona amb RAW, HEIC, etc. El flag `kCGImageSourceCreateThumbnailWithTransform: true` aplica la rotació EXIF; no tornem a escriure propietats originals, que equival al `Strip()` de Magick.
- **SHA-256 via `CryptoKit`**: streaming amb `FileHandle.read(upToCount:)` + `SHA256.update(data:)` per no carregar el fitxer sencer a memòria.
- **Concurrència**: `withTaskGroup` amb límit manual a 3 tasques in-flight. Equivalent a `SemaphoreSlim(3)` de Windows, més idiomàtic en Swift.
- **Persistència**: `~/Library/Application Support/iPhotoManager/` seguint les convencions Apple. Separat del `UserDefaults.destinationFolder` perquè la llista de destins pot créixer.

### Build

`swift build` net. `./build.sh` actualitza `iPhotoManager.app` amb firma Developer ID. Avisos preexistents de `makeIterator` a `FileService.swift` i `MainViewModel.swift` no es toquen.

### Pendent

- Barra de progrés visual mentre `isUploadingToMirat` (ara només es veu al `statusMessage`).
- Cancel·lació d'upload en curs.
- Testar amb un destí Mirat real: cal verificar que el servidor accepta el multipart de Swift igual que el de C#.

---

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

## 2026-04-21 — Device-code flow: vinculació amb Mirat sense claus API

### Context

Mirat ha introduït un device-code flow (tipus GitHub CLI / Apple TV / Spotify
Connect) que permet vincular clients desktop amb el compte de l'usuari sense
demanar claus API manuals. Com que Mirat és un family album, els usuaris
típics no poden gestionar `MIRAT_API_KEY` manualment: aquesta Fase 3 completa
el cicle implementant el client del flux a les dues plataformes.

### Versions i compatibilitat

- **Cap trencament**: configuracions existents amb `ApiKey` segueixen funcionant.
  El servidor de Mirat accepta tant `Authorization: Bearer mkd_...` com
  `X-API-Key`, i els clients prioritzen el token si n'hi ha.
- Els usuaris nous veuran el botó "Vincular amb Mirat (recomanat)" destacat.
  L'opció manual queda com a "Afegir manualment (avançat)" per power users i
  self-hosted sense compte Mirat.

### Implementació .NET (iPhotoImporter Windows/WPF)

**Nou fitxer `Services/MiratDeviceCodeClient.cs`**:
- Client `HttpClient` independent de `MiratService` (no necessita grup_id).
- `RequestDeviceCodeAsync(deviceName, ct)` → `DeviceCodeResponse` (device_code,
  user_code, verification_url, interval, expires_in).
- `PollForTokenAsync(deviceCode, interval, expiresAt, onProgress, ct)` →
  retorna un `AuthorizationResult` terminal (Authorized / Expired / Revoked /
  Cancelled). Gestió d'estats HTTP: 200 → decode TokenResponse, 202/429 →
  continuar, 410 → diferencia revoked vs expired pel camp `status` del body,
  404 → expired, altres → retry amb interval.
- Gestió robusta: errors de xarxa transitoris fan retry en lloc d'avortar;
  `OperationCanceledException` propaga correctament.
- DTOs: `DeviceCodeResponse`, `TokenResponse`, `TokenUser`, `TokenGrup`,
  `ErrorResponse`, enum `PollStatus`, `AuthorizationResult` amb factory methods.

**Modificat `Models/MiratDestination.cs`**:
- Afegits camps opcionals `AccessToken`, `UserId`, `UserName` al costat de
  `ApiKey` (que es marca legacy al comentari). Cap canvi trencador al JSON
  existent — els camps nous són `string?`.

**Modificat `Services/MiratService.cs`**:
- Constructor prioritza `dest.AccessToken` (envia `Authorization: Bearer`) per
  sobre de `dest.ApiKey` (envia `X-API-Key`). Un dels dos ha d'estar present.

### Implementació Swift (iPhotoManager macOS)

**Nou fitxer `MacOS/iPhotoManager/Services/MiratDeviceCodeClient.swift`**:
- Mateixa API que la versió .NET, adaptada a Swift 6 strict concurrency
  (`Sendable` a tots els DTOs, `final class ... : Sendable`).
- `requestDeviceCode(deviceName:)` i `pollForToken(deviceCode:intervalSeconds:
  expiresAt:onProgress:)` amb `Task.sleep` respectant `Task.isCancelled`.
- Polling loop funciona via `pollOnce()` que retorna `AuthorizationResult?` on
  `nil` significa "continuar".

**Modificat `MacOS/iPhotoManager/Models/MiratDestination.swift`**:
- Camps nous `accessToken: String?`, `userId: String?`, `userName: String?`.

**Modificat `MacOS/iPhotoManager/Services/MiratService.swift`**:
- Nou helper privat `applyAuth(to: inout URLRequest)` que afegeix Bearer si hi
  ha token, X-API-Key si n'hi ha apiKey. Cridat tant a GET `listGroups`/
  `listAlbums` com al POST `uploadPhoto`.

**Nou fitxer `MacOS/iPhotoManager/Views/ConnectMiratSheet.swift`**:
- Sheet SwiftUI autocontinguda amb 4 estats: input, waiting, success, error.
- **Input**: TextField pre-plenat amb `https://www.miratfotos.com`, botó
  "Començar".
- **Waiting**: mostra el `user_code` en gran (font `design: .monospaced`, 36pt)
  i obre automàticament el navegador a `verificationUrlComplete` amb
  `NSWorkspace.shared.open(url)`. Link clicable com a fallback. `ProgressView`
  amb text "Esperant autorització...".
- **Success**: checkmark, nom d'usuari, nom del grup, missatge per tornar a
  iPhoto. El `MiratDestination` ja està desat al `viewModel` abans d'arribar
  aquí.
- **Error**: missatge + botó "Tornar a provar".
- `onDisappear` cancel·la el `Task` de polling.
- Nom del dispositiu: `Host.current().localizedName` (p.ex. "MacBook Pro d'Enric").

**Modificat `MacOS/iPhotoManager/Views/MiratSettingsView.swift`**:
- Botó primari "Vincular amb Mirat (recomanat)" al començament de la sheet que
  obre el `ConnectMiratSheet`. El formulari manual (URL/ApiKey/Grup/Àlbum)
  queda sota el títol "Afegir manualment (avançat)" per casos power-user.
- Frame ampliat de 640 → 700 alt per encabir el botó nou sense quedar atapeït.

### Validació

- **Swift**: `swift build` ha completat sense errors. Només un warning
  pre-existent a `MainViewModel.swift:224` no tocat per aquesta sessió.
- **.NET**: sense toolchain local al Mac per validar; el codi es compilarà al
  build Windows següent. Valido estàticament les signatures.

### Seguretat i notes

- **Persistència del token**: ara el `access_token` es guarda en clar al JSON
  de `MiratDestinationStore` (ambdues plataformes). Per versions futures
  hauria de passar a Keychain (macOS) / DPAPI (Windows). No és crític avui
  perquè el JSON viu a `~/Library/Application Support` (macOS) o
  `%LocalAppData%` (Windows) — no és accessible per altres usuaris del mateix
  sistema sense privilegis.
- **Revocació**: si el token queda invalidat (l'usuari el revoca des del
  dashboard web de Mirat), el pròxim upload rebrà 401. Caldrà afegir un
  handler que detecti el 401 i re-obri el `ConnectMiratSheet` automàticament.
  Pendent per a una versió posterior.
- **Self-hosted**: el flow funciona contra qualsevol instància de Mirat perquè
  tots els endpoints `/api/desktop/*` són relatius al `baseUrl` del client.

### Pendent

- .NET: afegir botó "Vincular amb Mirat" a `MiratSettingsWindow.xaml` amb la
  mateixa UX que `ConnectMiratSheet` de Swift. Actualment el client .NET té
  les peces (model + client + servei) però no té la UI per iniciar el flux
  — es pot fer manualment amb codi si cal.
- Detecció automàtica de 401 → auto-reconnect sense que l'usuari hagi de
  tornar a Ajustos.
- Migrar token a Keychain/DPAPI.

### Fitxers canviats

**.NET**:
- `Services/MiratDeviceCodeClient.cs` (NOU)
- `Models/MiratDestination.cs` — afegits AccessToken/UserId/UserName
- `Services/MiratService.cs` — prioritza Bearer sobre X-API-Key

**Swift (macOS)**:
- `MacOS/iPhotoManager/Services/MiratDeviceCodeClient.swift` (NOU)
- `MacOS/iPhotoManager/Views/ConnectMiratSheet.swift` (NOU)
- `MacOS/iPhotoManager/Models/MiratDestination.swift` — afegits accessToken/userId/userName
- `MacOS/iPhotoManager/Services/MiratService.swift` — helper applyAuth
- `MacOS/iPhotoManager/Views/MiratSettingsView.swift` — botó "Vincular amb Mirat"

## 2026-04-21 — Sessió d'integració end-to-end device-code flow (macOS)

### Context

Primera vinculació funcional contra `www.miratfotos.com` en producció. Iteració
de diverses correccions sobre el flow inicial per arribar a una UX neta.

### Resultat final

L'usuari obre iPhoto Manager, clica **"Vincular amb Mirat"**, autoritza al
navegador i ja pot pujar fotos al seu compte. Sense claus API, sense URLs,
sense camps tècnics visibles. Token guardat local (JSON). Funcionalitat
confirmada amb pantalla d'èxit mostrant "MacBook Pro de Enric · Família".

### Iteracions i correccions d'aquesta sessió

**1. `ConnectMiratSheet` auto-start (commit `15b259c`)**

L'usuari va reportar "no cal que demani el host, només hi ha host public". Es
va eliminar el stage `input` del sheet: el flow comença automàticament via
`.task` quan s'obre la sheet. Ara hi ha 3 estats (waiting/success/error) en
comptes de 4. `miratBaseUrl` hardcoded a `https://www.miratfotos.com`.

**2. MiratSettingsView netejat (commit `395651e`)**

L'usuari va voler eliminar tota la UI manual. Pantalla Destins Mirat ara només
té: capçalera + botó "Vincular amb Mirat" + llista de destins vinculats amb
Eliminar. El form manual sencer (URL, API Key, Provar connexió, Grup, Àlbum,
Nom descriptiu, Desar) s'ha eliminat. També el botó Editar dels destins
(sense form no serveix — elimina i torna a vincular). Frame 700 → 440 alt.

Configs legacy creades amb API Key abans del flow es llegeixen igual i apareixen
a la llista. Com que `MiratService` prioritza Bearer sobre X-API-Key, les noves
sempre usaran token; les antigues continuen funcionant amb X-API-Key.

### Debugging realitzat

Mentre es provava, van sortir un seguit de problemes al costat servidor (Mirat)
que ens van obligar a iterar allà (veure mirat/project_log.md). Especialment
crític: el flux OTP de Mirat perdia el `?next=/vincular?code=X` i l'usuari
acabava al dashboard sense veure la pantalla de vinculació. Un cop arreglat
també el flow per usuaris que entren via slug (form A de /registre), tot ha
quedat connectat.

### Versió Windows (.NET) pendent d'actualització

La versió Windows té les peces del device-code (model amb AccessToken,
`MiratDeviceCodeClient.cs`, `MiratService.cs` amb Bearer), però **la UI encara
no té botó "Vincular amb Mirat"**. Cal afegir-hi l'equivalent de
`ConnectMiratSheet` per WPF:

- Nou diàleg `ConnectMiratWindow.xaml` amb 3 estats (waiting/success/error)
- Obrir navegador via `Process.Start(new ProcessStartInfo { FileName = url, UseShellExecute = true })`
- Polling via `Task.Run` + `CancellationToken` aplicat a `MiratDeviceCodeClient.PollForTokenAsync`
- A `MiratSettingsWindow.xaml`: botó primari "Vincular amb Mirat (recomanat)"
  al començament, i netejar també el form manual (mateix criteri que la versió
  macOS)
- Al rebre el token, crear `MiratDestination` amb `AccessToken` (no `ApiKey`),
  `GrupId`, `GrupNom`, `UserId`, `UserName`, desar-lo via `MiratDestinationStore`
- Mantenir compatibilitat amb les configs legacy existents (igual que macOS)

Mentre no es faci, la versió Windows funciona amb claus API manuals com
abans — però cap usuari familiar no l'hauria d'usar fins que la UI nova estigui
desplegada.

### Commits d'aquesta sessió

- `15b259c` — `ConnectMiratSheet` auto-start sense input URL
- `395651e` — `MiratSettingsView` simplificat (sense form manual, sense Editar)

---

## 2026-04-21 — Windows: paritat UI device-code flow

### Context

Replicat a WPF el que macOS ja tenia: UI de vinculació via device-code i
simplificació de la pantalla de destins Mirat. Les peces del servidor i el
client HTTP ja eren presents al pull (`MiratDeviceCodeClient.cs`,
`MiratService.cs` amb Bearer, `MiratDestination.cs` amb `AccessToken`), però
no hi havia manera d'engegar el flux des de la UI — el formulari manual d'API
Key era l'única opció.

### Fitxers nous

- `ConnectMiratWindow.xaml` + `.xaml.cs` — diàleg de vinculació amb 3 estats
  (waiting / success / error). Auto-arrenca al `Loaded`: demana device-code a
  `MiratBaseUrl = https://www.miratfotos.com`, pinta el `user_code` en
  `Consolas 36pt`, obre el navegador amb
  `Process.Start(new ProcessStartInfo { FileName = url, UseShellExecute = true })`
  i fa polling via `MiratDeviceCodeClient.PollForTokenAsync`. El
  `CancellationTokenSource` es cancel·la a `Window_Closed` per aturar el polling
  si l'usuari tanca el diàleg. `Environment.MachineName` com a `device_name`.
  Icones via `Segoe MDL2 Assets` (`&#xE73E;` checkmark, `&#xEB90;` error). Enllaç
  clicable com a fallback si `Process.Start` falla.

### Fitxers modificats

- `MiratSettingsWindow.xaml` — eliminat tot el formulari manual (URL base,
  API Key, "Provar connexió", ComboBox grup/àlbum, nom descriptiu, "Desar
  destí"). Pantalla ara només té: capçalera + botó primari "Vincular amb Mirat"
  + llista de destins vinculats amb botó "Eliminar" a cada fila + botó "Tancar"
  al peu. Frame 560x620 → 500x460, `ResizeMode=NoResize`. Placeholder "Cap destí
  configurat" quan la llista és buida.
- `MiratSettingsWindow.xaml.cs` — reduït del flux complet de creació/edició
  manual a només: obrir `ConnectMiratWindow`, mostrar la llista, eliminar. Es
  suscriu a `MiratDestinations.CollectionChanged` per togglar el placeholder vs
  la llista. Netejada la dependència de `MiratService`/`MiratGrup`/`MiratAlbum`
  que ara no cal aquí.

### Compatibilitat

- Destins legacy creats amb API Key abans del device-code flow segueixen
  apareixent a la llista i es poden eliminar igual. `MiratService` ja prioritza
  `Bearer` sobre `X-API-Key`, així que tot funciona automàticament.
- `MainViewModel` intacte: `AddOrUpdateMiratDestination`, `ActiveMiratDestination`,
  `RemoveMiratDestinationCommand`, `MiratDestinations` ja existien des de
  l'integració inicial.

### Validació

- **`dotnet build` correcte**: 0 errors, 54 avisos — tots `NU1901`/`NU1902`/
  `NU1903` preexistents de `Magick.NET-Q8-AnyCPU` 14.11.1, no introduïts per
  aquesta sessió. (SDK invocat des de `C:\Users\enricg\.dotnet\dotnet.exe` —
  no és al PATH.)
- **Sense prova real** contra `www.miratfotos.com` des de Windows — caldrà
  fer-la abans de considerar-ho "desplegat".

### Pendent

- Detecció automàtica de 401 a `MiratService` → re-obrir `ConnectMiratWindow`
  sense que l'usuari hagi de tornar a Ajustos (paritat amb macOS, també
  pendent allà).
- Migrar `AccessToken` de JSON en clar a DPAPI (Windows Data Protection API).
- Eliminar el `MiratSettingsWindow.ShowOnTopCorner` o variants si apareixen
  — la pantalla ara cap al frame 500x460.

## 2026-05-16 — Suport thumbnails de vídeos a l'upload Mirat

### Problema

Els uploads de vídeos a Mirat fallaven amb 400 "Falta thumbnail":

- **macOS**: `generateThumbAndPreview` usa `CGImageSourceCreateWithURL`, que només llegeix imatges. Per a vídeos retorna `(Data(), Data(), 0, 0)` i el codi multipart feia `if !thumbBytes.isEmpty { appendFile("thumbnail"...) }`, de manera que el camp no s'enviava → servidor refusava.
- **Windows**: `GenerateThumbAndPreview` usa Magick.NET, que tampoc obre vídeos. L'excepció es capturava i retornava bytes buits, però al multipart **sempre** s'afegia el `thumbnail` encara que estigués buit — el servidor rebia un fitxer de 0 bytes (pitjor: l'acceptava i guardava un blob inservible).

### Fix macOS (`MacOS/iPhotoManager/Services/MiratService.swift`)

Importat `AVFoundation`. Nova `generateFromVideo(url:)` que:

1. Crea `AVURLAsset` i `AVAssetImageGenerator` amb `appliesPreferredTrackTransform = true` (respecta rotació).
2. Extreu un frame a t=1s (o la meitat de la durada si el vídeo és més curt).
3. L'escala via `CGContext` i el codifica a JPEG amb `CGImageDestination`. Genera thumb 200px @ q70 i preview 2048px @ q80.

`generateThumbAndPreview` ara prova primer ImageIO; si retorna nil, cau a AVFoundation. Funciona per a MP4, MOV, M4V, AVI, MKV (els formats que macOS reconeix natives via AVFoundation).

Compilat amb `./build.sh` i instal·lat — el Dock apunta directament al bundle del repo.

### Fix Windows (`Services/MiratService.cs`)

Per ara, només condicionar `thumbnail` a `thumbBytes.Length > 0` per evitar enviar un fitxer buit. Magick.NET segueix sense generar thumbnails per a vídeos, així que el servidor rebrà l'upload sense `thumbnail`. El nou fix server-side a Mirat (commit `acd46d6` allà) l'accepta sense problema.

**Fase 2 pendent al Windows**: generar thumbnail real des d'un frame del vídeo. Opcions:

1. `IShellItemImageFactory` (Windows Shell, nadiu, sense dependències extra): l'Explorer ja sap mostrar miniatures de vídeos, podem invocar la mateixa API via P/Invoke o un paquet wrapper.
2. FFMpegCore + ffmpeg al PATH: més potent però afegeix dependència externa.

Opció 1 recomanada quan toqui.

### Servidor Mirat — fix paral·lel

Per defensa robusta, `/api/external/upload` ara accepta MIME `video/*` sense thumbnail (commit `acd46d6` al repo mirat). `thumbnailPath` queda `null` a la DB i el frontend mostra fallback (icona de play sobre fons fosc).

### Commits

- macOS: `7cc2630` — `fix(macos): generar thumbnail per videos amb AVFoundation`.
- Windows: pendent (en aquest mateix commit, després d'aquesta entrada).

## 2026-05-16 — TODO al Windows: generar thumbnails reals de vídeos

Quan obris aquest repo al Windows, vegeu aquesta entrada per implementar la **fase 2** del fix de vídeos.

### Estat actual

- El client Windows (`Services/MiratService.cs`) **no genera thumbnail** per a vídeos perquè `GenerateThumbAndPreview` usa Magick.NET, que només llegeix imatges. L'excepció es captura silenciosament i retorna `(Array.Empty<byte>(), Array.Empty<byte>(), 0, 0)`.
- **Fase 1 (ja feta, commit `d4da8a2`)**: condicionar `form.Add(thumbContent, "thumbnail", ...)` a `thumbBytes.Length > 0`. Així no s'envia un fitxer buit. El servidor Mirat (commit `acd46d6` al repo `mirat`) ja accepta uploads de `video/*` sense thumbnail.
- **Conseqüència actual**: els vídeos pugen correctament des de Windows, però apareixen al dashboard amb una cel·la fosca amb icona de play (fallback genèric). Sense miniatura específica del vídeo.

### Què volem (fase 2)

Generar un thumbnail real des d'un frame del vídeo, com fa el client macOS amb AVFoundation. Així el dashboard mostra una miniatura representativa.

### Proposta: `IShellItemImageFactory` (recomanat)

Windows Shell ja sap mostrar thumbnails de vídeos a l'Explorer. Podem invocar la mateixa API des de C# sense afegir cap dependència externa (Magick.NET, FFmpeg…).

L'API és [`IShellItemImageFactory::GetImage`](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-ishellitemimagefactory-getimage). Retorna un `HBITMAP` amb la miniatura, escalada a la mida demanada.

Esquema d'implementació (`Services/MiratService.cs`, dins `GenerateThumbAndPreview`):

```csharp
private static (byte[] thumb, byte[] preview, int width, int height) GenerateThumbAndPreview(string path)
{
    // Primer prova com a imatge (Magick.NET com fins ara)
    try
    {
        using var image = new MagickImage(path);
        // ...lògica existent...
        return (thumbBytes, previewBytes, width, height);
    }
    catch
    {
        // No és imatge — prova com a vídeo via Shell
        return GenerateFromVideoShell(path);
    }
}

private static (byte[], byte[], int, int) GenerateFromVideoShell(string path)
{
    try
    {
        // Obté thumbnail 2048px del Shell (és el màxim útil per a previews)
        using var hbitmap = ShellThumbnail.GetImage(path, new Size(2048, 2048));
        if (hbitmap == null) return (Array.Empty<byte>(), Array.Empty<byte>(), 0, 0);

        // Converteix HBITMAP a Bitmap → byte[] JPEG via System.Drawing o ImageSharp
        using var bmp = Image.FromHbitmap(hbitmap.DangerousGetHandle());
        var width = bmp.Width;
        var height = bmp.Height;

        var preview = EncodeJpeg(bmp, 2048, 80);
        var thumb = EncodeJpeg(bmp, 200, 70);
        return (thumb, preview, width, height);
    }
    catch { return (Array.Empty<byte>(), Array.Empty<byte>(), 0, 0); }
}
```

### Helper `ShellThumbnail.GetImage`

Cal una classe wrapper que faça P/Invoke a `SHCreateItemFromParsingName` + `IShellItemImageFactory`. Codi de referència ([microsoft/WindowsAPICodePack](https://github.com/aybe/Windows-API-Code-Pack-1.1) ho té però és vell). Versió compacta:

```csharp
using System;
using System.Runtime.InteropServices;

public static class ShellThumbnail
{
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern int SHCreateItemFromParsingName(
        [MarshalAs(UnmanagedType.LPWStr)] string path,
        IntPtr pbc,
        [MarshalAs(UnmanagedType.LPStruct)] Guid riid,
        out IShellItemImageFactory ppv);

    [ComImport, Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellItemImageFactory
    {
        [PreserveSig]
        int GetImage(SIZE size, SIIGBF flags, out IntPtr phbm);
    }

    [StructLayout(LayoutKind.Sequential)] private struct SIZE { public int cx, cy; }
    [Flags] private enum SIIGBF
    {
        ResizeToFit = 0x00,
        BiggerSizeOk = 0x01,
        MemoryOnly = 0x02,
        IconOnly = 0x04,
        ThumbnailOnly = 0x08,
        InCacheOnly = 0x10,
    }

    public static IntPtr GetImage(string path, System.Drawing.Size desired)
    {
        var iid = typeof(IShellItemImageFactory).GUID;
        int hr = SHCreateItemFromParsingName(path, IntPtr.Zero, iid, out var factory);
        if (hr != 0 || factory == null) return IntPtr.Zero;
        try
        {
            var sz = new SIZE { cx = desired.Width, cy = desired.Height };
            hr = factory.GetImage(sz, SIIGBF.ResizeToFit | SIIGBF.BiggerSizeOk, out var hbm);
            return hr == 0 ? hbm : IntPtr.Zero;
        }
        finally { Marshal.ReleaseComObject(factory); }
    }
}
```

### Cosa important

`IShellItemImageFactory` requereix que **algú estigui registrat al Shell per generar thumbnails d'aquell format**. Per als formats estàndard (MP4, MOV, AVI, MKV, WebM) això funciona out-of-the-box si Windows té els codecs corresponents instal·lats (normalment sí). Per a formats exòtics pot retornar `E_FAIL` — en aquest cas la lògica cau de tornada a "sense thumbnail" i el servidor el gestiona (fallback al dashboard).

### Alternativa secundària

Si `IShellItemImageFactory` resulta inestable o vol més control (frame en moment concret, no el que decideixi el Shell): paquet `FFMpegCore` + `ffmpeg.exe` al PATH o `\Resources`. Aporta:

- Control precís del segon del frame.
- Suport a formats que el Shell no reconeix.
- Mida del binari: ffmpeg pesa ~80MB; cal decidir si val la pena distribuir-lo.

### Test mínim

Triar un MP4 a iPhotoManager al Windows, pujar-lo a Mirat. Verificar:

1. La pujada no falla.
2. Al dashboard apareix una miniatura **del vídeo** (un frame), no la cel·la fosca generic.
3. El visor reprodueix el vídeo amb `<video>`.

### Documentació afí

- Bug original i fix macOS: aquest mateix `project_log.md`, entrada 2026-05-16.
- Servidor Mirat (accepta vídeos sense thumbnail): `mirat/project_log.md` entrada 2026-05-16, commit `acd46d6`.

## 2026-05-16 — Fix vídeos macOS (continuació): detectar per extensió, reusar FileService

Després del primer fix amb AVFoundation + CGContext, els uploads de vídeos seguien arribant sense miniatura. Dos bugs encadenats:

### Bug A: detecció ingènua "imatge o vídeo"

`generateThumbAndPreview` decidia si el fitxer era imatge o vídeo fent `CGImageSourceCreateWithURL(url)` i caient a vídeo si retornava nil. Però els `.MOV` de l'iPhone tenen un **poster JPEG embedded** (Live-Photos-like) i ImageIO els obre sense problemes — el codi entrava a la branca d'imatge i extreia el poster (que no és el frame del vídeo).

**Fix**: discriminar per extensió, fent servir `PhotoItem.videoExtensions` que ja existia al projecte. Si l'extensió és `mp4`, `mov`, `m4v`, `avi`, `mkv`, `webm` → sempre va a `generateFromVideo`.

### Bug B: CGContext + DeviceRGB fràgil per a frames de vídeo

La meva primera implementació de `generateFromVideo` cridava `AVAssetImageGenerator.copyCGImage` i després passava el CGImage per un `CGContext` per escalar i codificar a JPEG. Els frames d'AVFoundation venen en color spaces de vídeo (YCbCr / BT.709), que `CGContext(..., space: cgImage.colorSpace)` no acceptava correctament amb `noneSkipLast`. Encara forçant `DeviceRGB`, el draw fallava silenciosament en alguns formats.

**Fix**: reescrita `generateFromVideo` per reutilitzar `FileService.generateVideoThumbnail(for:maxSize:)`, que és exactament el camí que ja s'usa a la graella d'iPhoto Manager i sabem que funciona. Converteix l'NSImage resultant a JPEG via `NSBitmapImageRep` (mateixa via que `ThumbnailCacheService.saveToDisk`).

### Diagnòstic

L'ús de `Logger(subsystem: "com.iphotomanager.app", category: "video-thumbs")` amb nivell `.notice` (els `.info` són memory-only i no apareixen a `log show`) va permetre veure el flux real:

```
generateThumbAndPreview start: IMG_0739.MOV
→ tractant com a imatge (ImageIO obre el fitxer)   ← BUG! Cap a la branca incorrecta
```

Després del fix per extensió:
```
generateThumbAndPreview start: IMG_0739.MOV
→ tractant com a vídeo (extensió mov)
```
I la miniatura va aparèixer al dashboard de Mirat. ✅

### Notes per al futur

- `Logger.info()` no persisteix per defecte; per a debug post-mortem cal `.notice` o superior, o configurar el subsystem amb `log config --subsystem com.iphotomanager.app --mode "level:debug,persist:debug"`.
- Per a detectar "imatge vs vídeo" no fer servir "qui pot obrir el fitxer" — usar sempre extensió o UTType. ImageIO obre molts containers de vídeo perquè hi llegeix posters/covers.
- `FileService.generateVideoThumbnail` ja era la solució correcta — no calia reimplementar-la. Lliçó: abans d'escriure codi de tractament d'imatge/vídeo en aquest repo, mirar si `FileService` ja en té una versió.

### Commits a aquesta sessió

- `7cc2630` — `fix(macos): generar thumbnail per videos amb AVFoundation` (primera versió, fràgil).
- `d4da8a2` — `fix(windows): no enviar thumbnail buit per videos + doc al log`.
- `7d6fad8` — `docs(log): TODO Windows fase 2 — thumbnails de videos amb Shell`.
- (pendent en aquest commit) — `fix(macos): detectar per extensio + reusar FileService`.

## 2026-05-16 — Fix vídeos Windows (fase 2): reaprofitar `ThumbnailCacheService`

Implementada la fase 2 Windows pendent (TODO de l'entrada anterior). Descartada la proposta original (P/Invoke directe a `IShellItemImageFactory` des de `MiratService`) i aplicat el mateix patró que el fix Mac final `3f98e3d`: **reutilitzar la lògica que ja funciona a la UI**.

### Idea

`ThumbnailCacheService` ja genera miniatures de vídeos per la galeria (via `FileService.GenerateVideoThumbnail`, que internament usa el Windows Shell amb COM interop en thread STA — exactament l'API que recomanava el TODO). Les desa com a JPEG q85 ~1024px a `%LocalAppData%\iPhotoImporter\ThumbnailCache\<sha256>.jpg`.

En comptes de duplicar aquesta lògica a `MiratService`, llegim el JPEG del cache directament i l'enviem (reescalat a 200px) com a camp `thumbnail` del multipart. Cache hit típic (vídeo ja vist a la galeria) → upload pràcticament instantani sense regenerar res.

### Canvis

- **`Services/ThumbnailCacheService.cs`** — nou mètode públic `GetThumbnailBytesAsync(filePath, ct) → byte[]?`:
  1. Si el `.jpg` del cache existeix → `File.ReadAllBytesAsync`.
  2. Si no → crida `GetThumbnailAsync` perquè el generi (popula el cache a disc i el memory cache) i després llegeix els bytes.
  3. Retorna `null` si la generació falla (format no suportat pel Shell).

- **`Services/MiratService.cs`**:
  - Constructor accepta `ThumbnailCacheService? thumbCache = null` (opcional per no trencar usos existents).
  - `UploadPhotoAsync`: detecta `mime.StartsWith("video/")` i bifurca:
    - **Vídeo**: nou helper `GetVideoThumbnailFromCacheAsync` → bytes del cache, reescalats a 200px JPEG q70 amb Magick.NET. **No s'envia `preview`** ni `amplada`/`alcada` per a vídeos. El servidor (`acd46d6` al repo `mirat`) accepta uploads de `video/*` sense aquests camps.
    - **Imatge**: lògica anterior (`GenerateThumbAndPreview` via Magick.NET) sense canvis.

- **`ViewModels/MainViewModel.cs`** — línia 371: `new MiratService(dest, _thumbnailCache)`.

### Per què aquest enfocament és millor que la proposta original

- **Zero P/Invoke nou** a `MiratService` (la proposta del TODO incloïa una classe `ShellThumbnail` amb declaracions COM).
- **Reutilitza codi provat**: `FileService.GenerateVideoThumbnail` ja s'executa cada vegada que es navega per una carpeta amb vídeos.
- **Cache hit instantani** per a vídeos ja visualitzats a la UI (cas comú quan l'usuari decideix pujar-los).
- **Fallback nadiu**: si el Shell no genera miniatura per a un format exòtic, `GetThumbnailBytesAsync` retorna `null` → s'envia sense thumbnail (= comportament de la fase 1).

### Paral·lel amb la lliçó del fix Mac (`3f98e3d`)

Mateixa lliçó documentada a l'entrada anterior: **"abans d'escriure codi de tractament d'imatge/vídeo en aquest repo, mirar si `FileService` ja en té una versió"**. La proposta original ignorava que `ThumbnailCacheService`/`FileService` ja resolien el problema.

### Tradeoffs acceptats

- **Sense `preview` 2048px per a vídeos**: el cache només té 1024px. Es podria enviar el 1024px com a preview, però el visor de Mirat reprodueix el vídeo amb `<video>`, així que el JPEG només és el cartell inicial — el thumbnail 200px ja serveix per al dashboard.
- **Sense `amplada`/`alcada`**: el cache no les guarda. Per a `video/*` el servidor les pot calcular més tard o quedar com a `null`.

### Test

1. Obrir `iPhotoManager.exe` (desktop, build del 2026-05-16).
2. Navegar a carpeta amb vídeos → la galeria genera/llegeix les miniatures (populant el cache).
3. Pujar un vídeo a Mirat.
4. Al dashboard de Mirat → miniatura del frame, no la cel·la fosca generica.

### Fitxers tocats

- `Services/ThumbnailCacheService.cs` — `GetThumbnailBytesAsync`.
- `Services/MiratService.cs` — constructor + bifurcació video/imatge + helper.
- `ViewModels/MainViewModel.cs` — instanciació de `MiratService` amb cache.

---

## 2026-06-23 — iPhone: thumbnails ràpids + "Enviar a Mirat" directe (macOS)

Dues millores al mode browse del dispositiu (iPhone via ImageCaptureCore), **només a macOS** → **cal portar-les a la versió Windows** (WPF/MediaDevices), vegeu sota.

### 1. Thumbnails del dispositiu ràpids (commit `7317076`)
Amb 35k fotos els thumbnails sortien lentíssims: es carregaven **en SÈRIE** (un `requestThumbnail` rere l'altre per USB). A més, un **bug latent**: la continuation s'indexava per `file.name`, i l'iPhone té noms repetits (IMG_0001.jpg en àlbums diferents) → xocaven en paral·lel.
- **Clau única** `ObjectIdentifier(file)` per la continuation (`DeviceImportService`) — requisit per paral·lelitzar.
- **Càrrega concurrent** (6 alhora) + **mandrosa per cel·la** (`.task` a `ThumbnailGridView`): només es carrega el que es dibuixa → respecta els anys colapsats del timeline.
- **Escaneig de duplicats SOTA DEMANDA** (en activar el filtre de duplicats), no automàtic en obrir → ja no carrega 35k miniatures només navegant. **Resol el "spinner infinit dedup iPhone 34K".**
- Validat per l'usuari amb el seu iPhone.

### 2. "Enviar a Mirat" des del dispositiu (aquesta entrada)
Abans, per pujar fotos de l'iPhone a Mirat calia **importar-les abans al disc**. Ara, en mode browse, hi ha un botó **"Enviar a Mirat"** (si hi ha un destí Mirat vinculat) que les envia **directament**:
1. Baixa les seleccionades a una carpeta **temporal** (reusa `importSelectedFiles`, en sèrie i provat).
2. Les puja amb el flux Mirat existent (`uploadPhotosToMirat` → SHA, thumbnail, preview, GPS de l'EXIF, dedup, reintents), **concurrent (3)**.
3. Esborra la temporal + desmarca la selecció. **Sense còpia permanent al disc.**
- `MainViewModel.uploadSelectedDeviceToMirat()` + botó a `ActionBarView` (mode dispositiu, gated per `hasActiveMiratDestination`).
- **Limitació v1**: baixada en sèrie (camí provat); pujada concurrent. Noms repetits (rar) → només baixa un del parell (`overwrite:false`). Per a baixada concurrent + noms únics caldria arreglar `downloadTempFile`/`importSelectedFiles` (com el fix de thumbnails).

### ⚠️ A FER A LA VERSIÓ WINDOWS (WPF/.NET, MediaDevices)
Portar les dues coses: (a) càrrega de thumbnails ràpida/mandrosa + dedup sota demanda si pateix la mateixa lentitud amb 34K; (b) **"Enviar a Mirat" directe** des del dispositiu (baixar a temp → `MiratService.UploadPhotoAsync` → esborrar). El `MiratService` de Windows ja existeix (s'usa per a fotos locals).

## 2026-06-23 — Windows: port de thumbnails mandrosos + "Enviar a Mirat" des del dispositiu

Portades a la versió Windows (WPF/.NET 8, MediaDevices) les dues millores que macOS va rebre avui (entrada anterior). Build `dotnet build` correcte: 0 errors, 54 avisos (tots NU190x preexistents de `Magick.NET-Q8-AnyCPU` 14.11.1, cap de nou).

### 1. Thumbnails del dispositiu mandrosos (lazy per cel·la)

**Problema a Windows**: `LoadDeviceThumbnailsAsync` recorria **totes** les fotos del dispositiu (`foreach item in Photos`) baixant cada miniatura per MTP. Amb 34K fotos, i com que el `DeviceService` serialitza tota operació WPD en un **únic thread STA**, això era una cua de 34K baixades → app penjada amb "spinner infinit", igual que macOS.

**Diferència amb macOS**: el bug de continuations indexades per `file.name` (noms repetits a l'iPhone) **no aplica** a Windows — `GetThumbnailAsync(device, fullPath)` ja s'indexa pel `FullPath` (únic) i la cua STA garanteix exclusió. Tampoc té sentit la "càrrega concurrent (6)": el canal MTP de Windows és single-threaded STA per construcció. El que sí que aplica —i és el guany real— és **carregar només el que es dibuixa**.

**Solució (paritat amb el `.task` per cel·la de SwiftUI)**:
- Nou `MainViewModel.RequestDeviceThumbnail(PhotoItem)`: baixa la miniatura d'**una** foto sota demanda, amb dedup via `HashSet<string> _deviceThumbRequested` (un sol intent per `FullPath`; s'allibera si falla, per permetre reintent). Surt d'immediat si no estem en mode dispositiu (les fotos locals segueixen amb `LoadThumbnailsAsync`).
- Wiring a la graella: `DataContextChanged` del `ThumbBorder` (a `MainWindow.xaml` → handler `Thumbnail_DataContextChanged` al code-behind). Amb `VirtualizationMode="Recycling"`, `DataContextChanged` és el hook correcte: es dispara tant en la realització inicial com quan un contenidor es recicla cap a una foto nova en fer scroll (`Loaded` **no** es torna a disparar en reciclar).
- Eliminades les crides eager `_ = LoadDeviceThumbnailsAsync()` de `BrowseDeviceAsync` i `LoadMoreFromDeviceAsync`. El `_deviceThumbRequested` i el `_deviceThumbnailCts` es reinicien en entrar a browse i es netegen a `ExitDeviceBrowseMode`.

Resultat: en obrir l'iPhone, només es baixen les ~30-50 miniatures visibles; la resta es baixen a mesura que l'usuari fa scroll. **Resol l'"spinner infinit dedup iPhone 34K" a Windows.**

**Dedup sota demanda**: a Windows el browse del dispositiu **ja no** disparava cap escaneig de duplicats automàtic (`ScanForDuplicatesAsync` és només per a carpetes locals; els toggles de filtre de duplicats criden `LoadThumbnailsAsync`, que filtra per `p.IsLocal`). Per tant aquesta part del fix macOS ja estava satisfeta — no calia canvi.

### 2. "Enviar a Mirat" des del dispositiu (sense importar al disc)

Nou `MainViewModel.UploadSelectedDeviceToMiratAsync` (`[RelayCommand]`), paritat amb el botó macOS:
1. Baixa les seleccionades a la carpeta temporal (`DeviceService.DownloadTempFileAsync`, en sèrie — el canal MTP ho és igualment), creant `PhotoItem` temporals que apunten al fitxer local.
2. Reusa **tal qual** `UploadPhotosToMiratAsync` (concurrència 3, SHA-256, thumbnail/preview Magick.NET, dedup per hash, reintents) — el mateix flux que les fotos locals.
3. Esborra els temporals + desmarca la selecció. Sense còpia permanent al disc.

UI: nou botó **"Enviar a Mirat"** (icona núvol `&#xE753;`) a la barra d'accions del mode dispositiu de `MainWindow.xaml`, gated per `HasActiveMiratDestination` (només visible si hi ha un destí Mirat vinculat). Conviu amb el botó "Importar" existent.

**Limitació v1** (igual que macOS): baixada en sèrie; pujada concurrent. Noms repetits a l'iPhone (rar, àlbums diferents) → el segon sobreescriu el temporal del primer (`DownloadTempFileAsync` usa el `FileName` com a nom temporal); la dedup per hash del servidor ho absorbeix.

### Fitxers tocats (Windows)

- `ViewModels/MainViewModel.cs` — `RequestDeviceThumbnail`/`LoadOneDeviceThumbnailAsync` (substitueixen `LoadDeviceThumbnailsAsync`), `_deviceThumbRequested`, reinici/neteja a browse/exit, nou `UploadSelectedDeviceToMiratAsync`.
- `MainWindow.xaml` — `DataContextChanged` al `ThumbBorder`; botó "Enviar a Mirat" a la barra d'accions del mode dispositiu.
- `MainWindow.xaml.cs` — handler `Thumbnail_DataContextChanged`.

### Pendent

- **Provar amb un iPhone real** a Windows (el fix macOS es va validar amb el dispositiu de l'usuari; aquí només validat per compilació). Verificar: (a) en obrir l'iPhone les miniatures apareixen progressivament en fer scroll sense penjar-se; (b) seleccionar i "Enviar a Mirat" puja directament i deixa el disc net.
- Si en proves la baixada en sèrie per a "Enviar a Mirat" amb moltes fotos és lenta, considerar baixada a una subcarpeta temp dedicada + noms únics (mateix camí que caldria per a la baixada concurrent a macOS).

## 2026-06-23 — macOS: fix regressió — els thumbnails del dispositiu no carregaven

El mateix dia, el canvi de thumbnails ràpids (`7317076`) va introduir una regressió: en mode browse de l'iPhone **cap miniatura carregava** (placeholders pertot, fins i tot a les cel·les visibles). Validat per l'usuari amb captura.

**Causa**: la continuation del thumbnail s'havia passat a clau `ObjectIdentifier(file)`. Però l'`ICCameraItem` que ImageCaptureCore torna al delegate `didReceiveThumbnail(_:for:)` **no és la mateixa instància** que el `file` sobre el qual es crida `requestThumbnail()` → la clau no casava mai → la continuation no es resolia → timeout de 10s → `nil` → placeholder permanent. Per nom (codi anterior) sí casava, perquè el nom és idèntic entre petició i resposta.

**Fix**: clau per **nom** (`file.name`/`item.name`), però amb una **cua FIFO de continuations per clau** — això resol de debò el motiu pel qual s'havia provat `ObjectIdentifier` (noms repetits de l'iPhone demanats en paral·lel ja no es trepitgen; cada petició ocupa el seu lloc a la cua i el delegate en resol la més antiga). El timeout treu també la més antiga pendent de la clau. Net de continuations a la desconnexió adaptat a la cua.

**Lliçó**: amb ImageCaptureCore no es pot assumir identitat d'objecte (`ObjectIdentifier`) entre el `file` enumerat i l'`item` del delegate; cal casar per una propietat estable (nom) i gestionar les col·lisions amb una cua, no canviant la clau a identitat.

- `Services/DeviceImportService.swift` — `thumbnailContinuations` passa a `[String: [Continuation]]`; `requestThumbnail`, delegate i neteja adaptats; log diagnòstic al delegate.

## 2026-06-23 — macOS: fix — la paperera del visor esborrava la selecció

La paperera del visor (i la tecla Del amb el visor obert) eliminava **totes les fotos seleccionades** en comptes de només la foto que s'estava veient. El botó feia `toggleSelection(viewerCurrentItem)` + `deleteSelected()` → afegia la foto del visor a la selecció i esborrava tot el conjunt. Validat per l'usuari.

**Comportament correcte** (demanat per l'usuari): la paperera del visor només ha d'eliminar la foto del visor; les fotos seleccionades es mantenen seleccionades. Per eliminar la selecció s'usa la paperera de la galeria.

**Fix**:
- Noves `deleteCurrentViewerPhoto()` (local) i `deleteCurrentViewerFromDevice()` (dispositiu): eliminen NOMÉS `viewerCurrentItem`, avancen el visor a la següent foto (o el tanquen si era l'última), treuen de la selecció només la foto eliminada i deixen la resta intacta. La versió local manté l'undo (⌘Z).
- Botons paperera del visor (`ViewerOverlayView`, `ViewerPanelView`) recablejats a les noves funcions (fora el `toggleSelection` previ).
- Tecla **Del** (`ContentView`) i drecera `.delete` de l'`ActionBar` fetes viewer-aware: amb el visor obert eliminen la foto del visor; tancat, la selecció. (L'`ActionBar` queda sota l'overlay del visor amb la drecera activa, per això també s'hi blinda.)

### ⚠️ A FER A LA VERSIÓ WINDOWS

Mateix bug. Els dos botons paperera del visor (`MainWindow.xaml` ~1128 i ~1273) i la drecera Del criden `DeleteSelectedCommand` → esborren la selecció. Cal una comanda `DeleteCurrentViewer` (+ versió device) que elimini només `ViewerCurrentItem` sense tocar la selecció, recablejar els dos botons, i fer que la drecera Del esborri la foto del visor quan el visor és obert.

### Fitxers tocats (macOS)

- `ViewModels/MainViewModel.swift` — `deleteCurrentViewerPhoto`, `deleteCurrentViewerFromDevice`.
- `Views/ViewerOverlayView.swift`, `Views/ViewerPanelView.swift` — botons paperera del visor.
- `Views/ContentView.swift` — tecla Del viewer-aware.
- `Views/ActionBarView.swift` — drecera `.delete` viewer-aware.

## 2026-06-23 — Windows: port del fix de la paperera del visor

Portat a WPF el fix de l'entrada anterior (el seu "⚠️ A FER A LA VERSIÓ WINDOWS"). Build `dotnet build` net: 0 errors, 54 avisos NU190x preexistents.

**Fix**:
- Refactoritzat `DeleteSelectedAsync`: el nucli d'eliminació passa a un helper privat `DeleteLocalFilesAsync(List<PhotoItem>)` (paperera de reciclatge + treure de `_allPhotos`/`Photos`/selecció + avanç del visor + undo 1 nivell). `DeleteSelectedAsync` només construeix la llista (selecció, o la foto del visor si no hi ha selecció) i el crida. Comportament extern idèntic — el flux "Moure a Mirat" que també crida `DeleteSelectedAsync` no canvia.
- Nova comanda `DeleteCurrentViewerAsync` (`[RelayCommand]`): elimina **només** `ViewerCurrentItem` via el helper, així que la resta de la selecció de la graella es manté intacta. En mode dispositiu fa no-op amb avís ("No es poden eliminar fotos de l'iPhone des de Windows") perquè el delete via MTP no és possible a Windows (constraint preexistent; aquí NO hi ha `deleteCurrentViewerFromDevice` real com a macOS).
- Recablejats els dos botons de paperera del visor (`MainWindow.xaml`: overlay i panell split) de `DeleteSelectedCommand` → `DeleteCurrentViewerCommand`; tooltip actualitzat a "Eliminar aquesta foto (Del)".
- `Window_PreviewKeyDown` (tecla Del) fet viewer-aware: visor obert mostrant una foto (`ViewerCurrentItem != null`) → `DeleteCurrentViewerCommand`; visor tancat → `DeleteSelectedCommand` sobre la selecció.

La paperera de la barra d'accions de la graella (mode local) segueix amb `DeleteSelectedCommand` — és la via per eliminar la selecció.

### Diferència amb macOS

macOS té `deleteCurrentViewerFromDevice` que esborra del propi iPhone. A Windows el delete via MTP es congela (limitació documentada des de 2026-04-06), així que la versió device de `DeleteCurrentViewer` és un no-op informatiu en lloc d'esborrar del dispositiu.

### Fitxers tocats (Windows)

- `ViewModels/MainViewModel.cs` — `DeleteCurrentViewerAsync` nou + helper `DeleteLocalFilesAsync` (refactor de `DeleteSelectedAsync`).
- `MainWindow.xaml` — dos botons de paperera del visor recablejats.
- `MainWindow.xaml.cs` — `Window_PreviewKeyDown` viewer-aware.

### Pendent

- Provar a Windows: (a) amb fotos seleccionades a la graella i el visor obert, la paperera del visor / Del eliminen **només** la foto vista i mantenen la selecció; (b) l'avanç del visor a la següent foto funciona; (c) Ctrl+Z restaura; (d) la paperera de la barra d'accions segueix eliminant la selecció.

## 2026-06-23 — macOS: fix — els vídeos del dispositiu no es reproduïen al visor

En mode browse de l'iPhone, obrir un vídeo al visor només mostrava la miniatura: no es reproduïa. Validat per l'usuari.

**Causa**: a `loadViewerImage`, els ítems del dispositiu (`!isLocal`) sortien tots per la mateixa branca, que baixava el fitxer a temp i l'intentava obrir com a **imatge** (`fileService.loadFullImage`) — que torna nil per un vídeo — i feia `return` abans d'arribar mai al codi de vídeo (`if item.isVideo`). Resultat: `isViewingVideo` quedava `false` i el reproductor no apareixia.

**Fix**: la branca de dispositiu ara bifurca imatge vs vídeo:
- **Vídeo**: `isViewingVideo = true`, baixa el fitxer a temp (`downloadTempFile`) i posa `viewerVideoURL` → s'activa l'`AVPlayer`. Mentre es baixa es veu la miniatura (la vista cau a `viewerImage` perquè `viewerVideoURL` encara és nil) + status "Baixant vídeo del dispositiu…"; en acabar restaura el peu (`updateStatusMessage`) i llegeix la rotació del fitxer baixat.
- **Imatge**: igual que abans.

`VideoPlayerView`/`AVPlayerNSView` ja reconfiguren el player quan canvia la URL i mostren error si no es pot reproduir, així que navegar entre vídeos del telèfon també funciona.

**Limitació v1**: la baixada del vídeo no mostra progrés concret (`downloadTempFile` no l'exposa) — només miniatura + missatge; navegar a un altre ítem cancel·la la baixada (`viewerDownloadTask`).

### ⚠️ A FER A LA VERSIÓ WINDOWS

Comprovar si el visor de la versió WPF reprodueix vídeos del dispositiu; molt probablement té el mateix problema (cal baixar a temp i reproduir, no llegir del `FullPath` del dispositiu).

- `ViewModels/MainViewModel.swift` — `loadViewerImage`: bifurcació imatge/vídeo per ítems de dispositiu.

## 2026-06-23 — Windows: port — reproduir vídeos del dispositiu al visor

Confirmat el mateix bug a WPF i portat el fix. Build `dotnet build` net: 0 errors, 54 avisos NU190x preexistents.

**Causa a Windows**: a `LoadViewerImage`, el branch de vídeo feia `ViewerVideoPath = item.IsLocal ? item.FullPath : null` → per a un vídeo del dispositiu quedava **null** (el path MTP no es pot passar al `MediaElement`), i `LoadDeviceFullImageAsync` salta els vídeos. Resultat: `IsViewingVideo=true` però sense font → només es veia la miniatura.

**Fix** (encaixa amb el code-behind existent — `LoadVideoInActivePlayer` ja reacciona a **qualsevol** canvi de `ViewerVideoPath`):
- Branch de vídeo de `LoadViewerImage` bifurcat **local vs dispositiu**:
  - Local: com abans (`ViewerVideoPath = FullPath`, rotació coneguda o llegida en background).
  - Dispositiu: `ViewerVideoPath = null` (es veu la miniatura) + `_ = LoadDeviceVideoAsync(item)`.
- Nou `LoadDeviceVideoAsync(item)`: baixa el vídeo a temp (`DeviceService.DownloadTempFileAsync`), llegeix la rotació del fitxer baixat (en `Task.Run`, abans de fixar el path perquè el handler l'apliqui), i fixa `ViewerVideoPath` al temporal → el code-behind reprodueix des del fitxer local. Mentre baixa, status "Baixant vídeo del dispositiu…"; en acabar `UpdateStatusMessage()`. Guard `ViewerCurrentItem != item` per si l'usuari navega.
- Comentari del code-behind actualitzat: `ViewerVideoPath` ara sempre és un fitxer local (temporal per al dispositiu).

Navegar entre vídeos del telèfon funciona: en obrir el següent, `ViewerVideoPath=null` atura el reproductor (el handler fa Stop+Source=null) i s'inicia una nova baixada.

**Limitació v1** (com macOS): la baixada del vídeo no mostra progrés concret (`DownloadTempFileAsync` no l'exposa) — només miniatura + missatge. La baixada no es cancel·la en navegar (el guard descarta el resultat); per a vídeos grans es podria afegir cancel·lació via CTS més endavant.

### Fitxers tocats (Windows)

- `ViewModels/MainViewModel.cs` — `LoadDeviceVideoAsync` nou + bifurcació local/dispositiu al branch de vídeo de `LoadViewerImage`.
- `MainWindow.xaml.cs` — comentari aclarit a `LoadVideoInActivePlayer` (cap canvi de lògica; ja servia per a qualsevol path local).

### Pendent

- Provar a Windows amb l'iPhone: obrir un vídeo del telèfon al visor → es baixa i es reprodueix; navegar entre vídeos; verificar rotació.

## 2026-07-02 — Windows: port — pujada MULTIPART presignada de vídeos (fix 502/503) + MIME + serialització

Portat a la versió WPF el bloc de fixos de pujada a Mirat que ja eren a macOS (commits `4e4b42b` multipart, `77b8031` MIME, `313a0fa` serialitzar+retry). Build `dotnet build` net: 0 errors, 54 avisos NU190x preexistents. Guia: `PORT-WINDOWS.md`.

**Problema**: a Windows TOTS els fitxers (també vídeos) pujaven per `api/external/upload`, bufferitzat pel pod → amb vídeos grans donava **502** (requestTimeout de Node) i **503** (SlowDown del MinIO de disc únic del NAS).

**Fixos portats**:
1. **Pujada MULTIPART presignada de vídeos** (`Services/MiratService.cs`): nou `UploadVideoPresignedAsync` que fa `upload-init-multipart` → PUT de cada part de 16 MiB **seqüencial** directament a MinIO capturant l'ETag → PUT de thumb/preview → `upload-complete-multipart`. Les fotos segueixen pel multipart-form de sempre. La decisió "és vídeo" es fa per la **llista autoritativa d'extensions** (`PhotoItem.VideoExtensions`), no pel MIME, perquè cap vídeo s'escapi al camí vell.
2. **Retry amb backoff al PUT presignat**: `PutWithRetryAsync` (5 intents, backoff exponencial 1→8s + jitter; reintenta en 5xx/429/xarxa, falla immediat en 4xx). Excepció interna `MiratHttpException` per distingir un 4xx llançat expressament d'un error de xarxa (que a .NET també és `HttpRequestException`). Client HTTP a part `_presignedHttp` **sense auth ni BaseAddress** (timeout 30 min) per no enviar els nostres headers a MinIO.
3. **MIME de vídeo** (`Services/MiratService.cs`, `Models/PhotoItem.cs`): afegit `.ts` a `VideoExtensions` i mapejat `.3gp → video/3gpp`, `.mts/.m2ts/.ts → video/mp2t` (abans queien a `application/octet-stream` i tornaven al multipart → 502).
4. **Serialitzar vídeos** (`ViewModels/MainViewModel.cs`): `UploadPhotosToMiratAsync` ara puja en dues tandes — **fotos amb concurrència 3**, **vídeos d'un en un** (concurrència 1) — per no saturar el disc únic del NAS (503).

**Verificat com a NO aplicable a Windows** (les altres dues notes del `PORT-WINDOWS.md`):
- *Id únic de fotos de dispositiu* (nota #5): `device.EnumerateFiles` ja retorna el path MTP complet (`\DCIM\100APPLE\IMG_2390.JPG`), únic per fitxer → sense el bug de noms repetits.
- *Dedup de dispositiu per mida+hash* (nota #6): el dedup de Windows usa comptador `md5-{n++}` (no `md5-size<mida>`) i no té camí de dedup específic de dispositiu → no fusiona clústers de la mateixa mida.

### Fitxers tocats (Windows)

- `Services/MiratService.cs` — `UploadVideoPresignedAsync`, `PostJsonAsync`, `PutWithRetryAsync`, `PutPresignedAsync`, `_presignedHttp`, excepció `MiratHttpException`, MIME de vídeo, decisió vídeo per extensió.
- `Models/PhotoItem.cs` — `.ts` afegit a `VideoExtensions`.
- `ViewModels/MainViewModel.cs` — `UploadPhotosToMiratAsync` amb tandes fotos(3)/vídeos(1).

### Pendent

- Provar a Windows amb l'iPhone / vídeos grans reals: que un vídeo pugi per multipart (init → parts → complete) sense 502/503, i que les extensions `.mts/.m2ts/.ts/.3gp` agafin el camí presignat.
