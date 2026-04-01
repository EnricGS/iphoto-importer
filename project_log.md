# iPhotoManager — Project Log

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
