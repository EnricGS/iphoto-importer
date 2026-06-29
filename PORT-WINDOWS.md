# Posar al dia la versió Windows (WPF) — pendent de portar des de macOS

**Data:** 2026-06-29

Aquesta sessió s'han arreglat al client **macOS** (`MacOS/iPhotoManager`) diversos bugs de
**pujada a Mirat** i del **visor**. L'app **Windows** (WPF .NET 8, a l'arrel del repo)
comparteix les mateixes funcions i necessita els mateixos canvis. Patró habitual del
repo: cada fix es fa a mac i a windows (commits `fix(mac)` / `fix(windows)`).

## Commits de referència (macOS, branca `main`)
- `617f240` — pujada presignada de vídeos (init → PUT directe a MinIO → complete)
- `77b8031` — MIME de vídeo per a `.mts/.m2ts/.ts/.3gp`
- `313a0fa` — serialitzar vídeos (concurrència 1) + retry amb backoff al PUT
- `f61d047` — id únic de fotos de dispositiu + dedup per mida+hash

---

## Què cal portar a Windows

### 1. Pujada presignada de vídeos  ⚠️ CRÍTIC (el 502 / 503)
**Problema:** `Services/MiratService.cs` puja TOT per `api/external/upload` (multipart
bufferitzat pel pod) — línia ~211. Amb vídeos grans → **502** (requestTimeout de Node) i,
un cop esquivat, **503** (SlowDown del MinIO).
**Fix** (per a vídeos; `isVideo` ja es detecta a la línia 107) — replicar
`MiratService.swift › uploadVideoPresigned`:
1. `POST api/external/upload-init` (JSON `{ mime_type, hash_fitxer?, has_thumbnail, has_preview, grup_id }`)
   → rep `{ fotoId, foto_url, thumb_url?, preview_url? }` o `{ id, duplicat:true }`.
2. `PUT` del vídeo (+ thumb + preview) **directament** a aquestes URLs presignades
   (només capçalera `Content-Type`, **sense** la nostra auth).
3. `POST api/external/upload-complete` (JSON `{ fotoId, mime_type, mida, metadades,
   has_thumbnail, has_preview, grup_id, album_id }`).
   Les **FOTOS** segueixen pel multipart de sempre.
Els dos endpoints ja són **vius a producció** (repo mirat).

### 2. MIME de vídeo per a totes les extensions
- `Models/PhotoItem.cs › VideoExtensions` (línia ~41): té `.3gp/.mts/.m2ts` però **falta `.ts`** → afegir-lo.
- `Services/MiratService.cs` (mapa MIME ~359): assegurar `.mts/.m2ts/.ts → video/mp2t` i
  `.3gp → video/3gpp`. Si queden `application/octet-stream`, NO agafen el camí presignat
  i tornen al multipart → 502 (va ser exactament el bug a macOS).

### 3. Serialitzar vídeos a la pujada (evita el 503 SlowDown del NAS)
`ViewModels/MainViewModel.cs` línia ~377: `new SemaphoreSlim(3)` puja 3 alhora. El MinIO
del NAS (**disc únic**) no aguanta diverses escriptures grans concurrents → 503. Cal pujar
les **FOTOS amb concurrència 3** i els **VÍDEOS d'un en un** (concurrència 1). A macOS:
`MainViewModel.swift › processarTanda` (dues tandes: imatges conc.3, vídeos conc.1).

### 4. Retry amb backoff al PUT presignat
Al `PUT` directe a MinIO: reintentar (5 intents, backoff exponencial 1→8s + jitter) en
**5xx/429/error de xarxa**; fallar immediat en **4xx**. A macOS: `MiratService.swift › putToPresigned`.

### 5. Id únic de fotos de dispositiu (bug del visor amb noms repetits)
`Services/DeviceService.cs` ~389: `FullPath = filePath`. **VERIFICAR primer:** si `filePath`
és el path MTP **complet** (p.ex. `\DCIM\100APPLE\IMG_2390.JPG`) ja és únic i **NO** té el
bug. Però si poden existir dos fitxers DIFERENTS amb el mateix `FullPath` (mateix nom i
carpeta), cal afegir **mida + data** a la identitat (com macOS `PhotoItem(cameraFile:)` →
`...#<size>-<ts>`). Motiu: `PhotoItem` compara per `FullPath`/Id; amb id repetit,
`firstIndex/Equals` retornen l'altra foto i el visor/graella les barregen.

### 6. Dedup de dispositiu: groupId únic per mida+hash
`ViewModels/MainViewModel.cs` (dedup ~1155): si el groupId de "duplicats exactes" del
**dispositiu** es basa NOMÉS en la mida (com el `md5-size<mida>` que tenia macOS), dos
clústers diferents amb la mateixa mida es fusionen i la propagació de miniatures clava la
imatge errònia. Cal incloure-hi el **hash perceptual** al groupId. A macOS:
`groupId = "md5-<size>-<phash>"`. (Windows sembla usar md5 real per a locals — comprovar
específicament el camí de **dispositiu**.)

---

## Servidor — JA FET (aplica a TOTS els clients, també iOS/Android/Windows)
- Endpoints `api/external/upload-init` + `upload-complete` + `extensioDesDeMime`
  (`video/3gpp`→3gp, `video/mp2t`→ts) desplegats a prod.
- **Traefik `readTimeout` 60s → 1800s** (HelmChartConfig a k3s `kube-system`). Sense això,
  QUALSEVOL pujada >60s a `storage.arxivat.com` donava 502 (Traefik v3 talla la lectura del
  cos als 60s per defecte). Detall i runbook: memòria `infra-traefik-readtimeout`.
