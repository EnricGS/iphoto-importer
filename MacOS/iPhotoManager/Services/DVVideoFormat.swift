import Foundation
import CoreMedia

/// Paràmetres del vídeo DV25 deduïts del propi frame.
///
/// La mida d'un frame DV és fixa per norma (IEC 61834 / SMPTE 314M), així que
/// identifica el sistema sense llegir capçaleres. La relació d'aspecte va dins
/// del frame, al pack VAUX «source control».
struct DVVideoFormat {

    enum System {
        case pal   // 625/50 — 720×576 a 25 fps
        case ntsc  // 525/60 — 720×480 a 29,97 fps
    }

    let system: System
    let frameSize: Int
    let codec: CMVideoCodecType
    let width: Int
    let height: Int
    /// Durada d'un frame com a (valor, timescale).
    let frameDuration: CMTime

    var isPAL: Bool { system == .pal }

    // MARK: - Detecció

    static let palFrameSize = 144_000
    static let ntscFrameSize = 120_000

    /// Fourccs de DV25 que es troben en contenidors AVI i MOV.
    private static let dvCodecs: Set<String> = [
        "dvsd", "DVSD", "dvc ", "dvcp", "dv25", "DV25", "CDVC", "dvsl", "dvhd",
    ]

    static func isDV(codec fourCC: String) -> Bool {
        dvCodecs.contains(fourCC.trimmingCharacters(in: CharacterSet(charactersIn: "\0")))
            || dvCodecs.contains(fourCC)
    }

    init?(frameSize: Int) {
        switch frameSize {
        case Self.palFrameSize:
            system = .pal
            codec = Self.fourCC("dvcp")
            width = 720
            height = 576
            frameDuration = CMTime(value: 1, timescale: 25)
        case Self.ntscFrameSize:
            system = .ntsc
            codec = Self.fourCC("dvc ")
            width = 720
            height = 480
            frameDuration = CMTime(value: 1001, timescale: 30_000)
        default:
            return nil
        }
        self.frameSize = frameSize
    }

    // MARK: - Aspecte

    /// Offset del pack VAUX «source control» (0x61) dins del frame DV.
    private static let vauxSourceControlOffset = 80 * 5 + 48 + 5
    private static let vauxSourceControlID: UInt8 = 0x61

    /// El DV té píxel no quadrat: 720×576 es mostra com 4:3 (768×576) o 16:9
    /// (1024×576). El flag viu al pack VAUX del frame.
    static func isWidescreen(frame: Data) -> Bool {
        let start = frame.startIndex
        guard frame.count > vauxSourceControlOffset + 2,
              frame[start + vauxSourceControlOffset] == vauxSourceControlID else { return false }
        return frame[start + vauxSourceControlOffset + 2] & 0x07 == 0x02
    }

    /// Relació de píxel (horizontal:vertical) per obtenir la imatge quadrada final.
    func pixelAspectRatio(is16by9: Bool) -> (horizontal: Int, vertical: Int) {
        switch (system, is16by9) {
        case (.pal, false): return (16, 15)    // 720 → 768
        case (.pal, true): return (64, 45)     // 720 → 1024
        case (.ntsc, false): return (8, 9)     // 720 → 640
        case (.ntsc, true): return (32, 27)    // 720 → 854
        }
    }

    func displaySize(is16by9: Bool) -> CGSize {
        let par = pixelAspectRatio(is16by9: is16by9)
        let ratio = CGFloat(par.horizontal) / CGFloat(par.vertical)
        return CGSize(width: (CGFloat(width) * ratio).rounded(), height: CGFloat(height))
    }

    // MARK: - Descripció de format

    /// Descripció de format per a VideoToolbox i per a l'AVAssetWriter, amb la
    /// relació de píxel inclosa perquè el reproductor no mostri la imatge estirada.
    func formatDescription(is16by9: Bool) -> CMVideoFormatDescription? {
        let par = pixelAspectRatio(is16by9: is16by9)
        let extensions: [CFString: Any] = [
            kCMFormatDescriptionExtension_PixelAspectRatio: [
                kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing: par.horizontal,
                kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing: par.vertical,
            ] as CFDictionary,
        ]

        var description: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: codec,
            width: Int32(width),
            height: Int32(height),
            extensions: extensions as CFDictionary,
            formatDescriptionOut: &description
        ) == noErr else { return nil }
        return description
    }

    private static func fourCC(_ code: String) -> CMVideoCodecType {
        code.utf8.reduce(0) { ($0 << 8) | CMVideoCodecType($1) }
    }
}
