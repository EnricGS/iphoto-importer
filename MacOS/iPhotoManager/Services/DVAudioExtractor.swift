import Foundation
import os

private let dvAudioLog = Logger(subsystem: "com.iphotomanager.app", category: "dv-audio")

/// Extreu l'àudio PCM d'un frame DV.
///
/// En DV l'àudio no va en un stream a part: viu dins del mateix frame, repartit
/// entre els blocs DIF d'àudio i **desordenat** segons la taula de shuffle que
/// defineixen IEC 61834 / SMPTE 314M (l'entrellaçat protegeix contra ràfegues
/// d'errors de cinta). Per reproduir-lo cal desfer aquest ordre.
///
/// Suporta el mode normal de les càmeres MiniDV/Digital8: 2 canals, 16 bits
/// lineals. El mode de 12 bits no lineals (4 canals) no es descodifica.
enum DVAudioExtractor {

    // MARK: - Format d'àudio del frame

    struct Format: Equatable {
        let sampleRate: Int
        let channels: Int = 2
        let bitsPerSample: Int = 16
    }

    /// Àudio d'un frame: bytes PCM entrellaçats (L,R little-endian) i format.
    struct Frame {
        let pcm: Data
        let format: Format
        var sampleCount: Int { pcm.count / 4 }
    }

    // MARK: - Constants del format DV

    /// Offset del pack AAUX «audio source» (0x50) dins del frame. Mateix càlcul que ffmpeg.
    private static let audioSourceOffset = 80 * 6 + 80 * 16 * 3 + 3
    private static let audioSourceID: UInt8 = 0x50

    private static let sampleRates = [48_000, 44_100, 32_000]
    /// Mostres mínimes per frame segons freqüència; el pack AAUX porta el sobrant.
    private static let minSamples525 = [1580, 1452, 1053]
    private static let minSamples625 = [1896, 1742, 1264]

    /// Distància entre mostres consecutives del mateix bloc DIF.
    private static let stride525 = 90
    private static let stride625 = 108

    // MARK: - API

    /// Desxifra l'àudio d'un frame DV. Retorna `nil` si el frame no porta àudio
    /// llegible (pack AAUX absent o mode de 12 bits).
    static func extract(from frame: Data, isPAL: Bool) -> Frame? {
        guard frame.count > audioSourceOffset + 4,
              frame[frame.startIndex + audioSourceOffset] == audioSourceID else { return nil }

        let pack = Array(frame[(frame.startIndex + audioSourceOffset)...].prefix(5))
        let frequencyIndex = Int((pack[4] >> 3) & 0x07)
        let quantization = pack[4] & 0x07

        guard quantization == 0 else {
            dvAudioLog.debug("Àudio DV de 12 bits no suportat (quant=\(quantization))")
            return nil
        }
        guard frequencyIndex < sampleRates.count else { return nil }

        let minimum = isPAL ? minSamples625[frequencyIndex] : minSamples525[frequencyIndex]
        let sampleCount = minimum + Int(pack[1] & 0x3f)
        let byteCount = sampleCount * 4 // 2 canals × 16 bits

        let pcm = deshuffle(frame: frame, byteCount: byteCount, isPAL: isPAL)
        return Frame(pcm: pcm, format: Format(sampleRate: sampleRates[frequencyIndex]))
    }

    // MARK: - Deshuffle

    /// Recorre els blocs DIF d'àudio i reordena les mostres a la seva posició real.
    /// Cada seqüència DIF són 150 blocs de 80 bytes: 6 de capçalera/subcode/VAUX i
    /// després 9 grups d'1 bloc d'àudio + 15 de vídeo.
    private static func deshuffle(frame: Data, byteCount: Int, isPAL: Bool) -> Data {
        let shuffle = isPAL ? shuffle625 : shuffle525
        let stride = isPAL ? stride625 : stride525
        let sequences = isPAL ? 12 : 10

        var pcm = [UInt8](repeating: 0, count: byteCount)

        frame.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            for sequence in 0..<sequences {
                // Salta capçalera (1), subcode (2) i VAUX (3) de la seqüència
                var block = sequence * 150 * 80 + 6 * 80
                for group in 0..<9 {
                    let base = shuffle[sequence][group]
                    for byte in Swift.stride(from: 8, to: 80, by: 2) {
                        let offset = base + (byte - 8) / 2 * stride
                        let target = offset * 2
                        guard target + 1 < byteCount else { continue }
                        let high = bytes[block + byte]
                        let low = bytes[block + byte + 1]
                        // 0x8000 marca mostra inexistent; el buffer ja és zero.
                        guard !(high == 0x80 && low == 0x00) else { continue }
                        // El DV desa les mostres en big-endian; les girem a little-endian.
                        pcm[target] = low
                        pcm[target + 1] = high
                    }
                    block += 16 * 80 // 1 bloc d'àudio + 15 de vídeo
                }
            }
        }

        return Data(pcm)
    }

    // MARK: - Taules de shuffle (IEC 61834 / SMPTE 314M)

    /// 525/60 (NTSC): 10 seqüències DIF × 9 blocs d'àudio.
    /// Files 0-4 = canal 1, files 5-9 = canal 2 (índexs parells/senars → estèreo entrellaçat).
    private static let shuffle525: [[Int]] = [
        [0, 30, 60, 20, 50, 80, 10, 40, 70],
        [6, 36, 66, 26, 56, 86, 16, 46, 76],
        [12, 42, 72, 2, 32, 62, 22, 52, 82],
        [18, 48, 78, 8, 38, 68, 28, 58, 88],
        [24, 54, 84, 14, 44, 74, 4, 34, 64],
        [1, 31, 61, 21, 51, 81, 11, 41, 71],
        [7, 37, 67, 27, 57, 87, 17, 47, 77],
        [13, 43, 73, 3, 33, 63, 23, 53, 83],
        [19, 49, 79, 9, 39, 69, 29, 59, 89],
        [25, 55, 85, 15, 45, 75, 5, 35, 65],
    ]

    /// 625/50 (PAL): 12 seqüències DIF × 9 blocs d'àudio.
    private static let shuffle625: [[Int]] = [
        [0, 36, 72, 26, 62, 98, 16, 52, 88],
        [6, 42, 78, 32, 68, 104, 22, 58, 94],
        [12, 48, 84, 2, 38, 74, 28, 64, 100],
        [18, 54, 90, 8, 44, 80, 34, 70, 106],
        [24, 60, 96, 14, 50, 86, 4, 40, 76],
        [30, 66, 102, 20, 56, 92, 10, 46, 82],
        [1, 37, 73, 27, 63, 99, 17, 53, 89],
        [7, 43, 79, 33, 69, 105, 23, 59, 95],
        [13, 49, 85, 3, 39, 75, 29, 65, 101],
        [19, 55, 91, 9, 45, 81, 35, 71, 107],
        [25, 61, 97, 15, 51, 87, 5, 41, 77],
        [31, 67, 103, 21, 57, 93, 11, 47, 83],
    ]
}
