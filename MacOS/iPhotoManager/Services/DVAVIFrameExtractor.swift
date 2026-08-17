import Foundation
import AppKit
import CoreMedia
import VideoToolbox
import os

private let dvLog = Logger(subsystem: "com.iphotomanager.app", category: "dv-avi")

/// Extreu un frame de vídeos DV (DV25, fourcc `dvsd`) dins d'un contenidor AVI —
/// el format típic de les captures de càmeres MiniDV/Digital8 dels anys 90 i 2000.
///
/// AVFoundation obre el contenidor i veu la pista de vídeo, però falla al
/// descodificar amb `-11869 "Cannot Open"` (OSStatus -12430): macOS SÍ que porta
/// descodificador DV, però només l'aplica quan el DV ve dins d'un `.mov`. Aquí
/// saltem el demuxer d'AVFoundation: llegim el primer frame directament del RIFF
/// i el passem a VideoToolbox, que el descodifica sense problemes.
enum DVAVIFrameExtractor {

    /// Genera un thumbnail del primer frame d'un AVI amb vídeo DV.
    /// Retorna `nil` si el fitxer no és un AVI DV o si la descodificació falla:
    /// el cridador ha de tractar-ho com «no hi ha thumbnail», igual que abans.
    static func thumbnail(for path: String, maxSize: Int) -> NSImage? {
        guard let frame = firstFrame(at: path), let format = DVVideoFormat(frameSize: frame.count) else {
            return nil
        }
        guard let decoded = decode(frame: frame, format: format) else { return nil }

        let display = format.displaySize(is16by9: DVVideoFormat.isWidescreen(frame: frame))
        guard let scaled = resize(decoded, to: fit(display, within: maxSize)) else { return nil }

        return NSImage(cgImage: scaled, size: NSSize(width: scaled.width, height: scaled.height))
    }

    /// Llegeix el primer chunk de vídeo del LIST `movi`.
    private static func firstFrame(at path: String) -> Data? {
        guard let file = try? AVIParser.parse(path: path, scan: .firstVideo),
              let chunk = file.chunks.first,
              let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        return AVIParser.read(chunk, from: handle)
    }

    // MARK: - Descodificació amb VideoToolbox

    /// Descodifica un únic frame DV. Crea i destrueix la sessió a cada crida:
    /// els frames DV són tots intra, no hi ha estat a mantenir entre frames.
    static func decode(frame: Data, format: DVVideoFormat) -> CGImage? {
        guard let description = format.formatDescription(is16by9: DVVideoFormat.isWidescreen(frame: frame)) else {
            return nil
        }

        var session: VTDecompressionSession?
        let attributes: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA]
        guard VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: description,
            decoderSpecification: nil,
            imageBufferAttributes: attributes as CFDictionary,
            outputCallback: nil,
            decompressionSessionOut: &session
        ) == noErr, let session else {
            dvLog.error("No s'ha pogut crear la sessió VideoToolbox per a DV")
            return nil
        }
        defer { VTDecompressionSessionInvalidate(session) }

        guard let sample = CMSampleBufferFactory.video(
            data: frame,
            format: description,
            presentationTime: .zero,
            duration: format.frameDuration
        ) else { return nil }

        var pixelBuffer: CVImageBuffer?
        let status = VTDecompressionSessionDecodeFrame(
            session, sampleBuffer: sample, flags: [], infoFlagsOut: nil
        ) { status, _, image, _, _ in
            guard status == noErr else { return }
            pixelBuffer = image
        }
        VTDecompressionSessionWaitForAsynchronousFrames(session)

        guard status == noErr, let pixelBuffer else {
            dvLog.error("Descodificació DV fallida (status \(status))")
            return nil
        }

        var image: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &image)
        return image
    }

    // MARK: - Escalat

    private static func fit(_ size: CGSize, within maxSize: Int) -> CGSize {
        let scale = min(1, CGFloat(maxSize) / max(size.width, size.height))
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    private static func resize(_ image: CGImage, to size: CGSize) -> CGImage? {
        guard size.width >= 1, size.height >= 1,
              let context = CGContext(
                data: nil,
                width: Int(size.width),
                height: Int(size.height),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else { return nil }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return context.makeImage()
    }
}
