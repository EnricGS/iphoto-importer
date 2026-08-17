import Foundation
import CoreMedia

/// Construcció de `CMSampleBuffer` a partir de bytes crus llegits d'un contenidor,
/// per passar-los a VideoToolbox o a un `AVAssetWriter` sense recodificar.
enum CMSampleBufferFactory {

    /// Un frame de vídeo comprimit (una mostra).
    static func video(
        data: Data,
        format: CMVideoFormatDescription,
        presentationTime: CMTime,
        duration: CMTime
    ) -> CMSampleBuffer? {
        make(
            data: data,
            format: format,
            presentationTime: presentationTime,
            sampleDuration: duration,
            sampleCount: 1,
            sampleSize: data.count
        )
    }

    /// Un bloc de mostres PCM. `bytesPerFrame` és la mida d'una mostra de tots
    /// els canals, i la durada individual és 1/sampleRate.
    static func audio(
        data: Data,
        format: CMAudioFormatDescription,
        presentationTime: CMTime,
        sampleRate: Int,
        bytesPerFrame: Int
    ) -> CMSampleBuffer? {
        guard bytesPerFrame > 0, data.count >= bytesPerFrame else { return nil }
        return make(
            data: data,
            format: format,
            presentationTime: presentationTime,
            sampleDuration: CMTime(value: 1, timescale: CMTimeScale(sampleRate)),
            sampleCount: data.count / bytesPerFrame,
            sampleSize: bytesPerFrame
        )
    }

    // MARK: - Privat

    private static func make(
        data: Data,
        format: CMFormatDescription,
        presentationTime: CMTime,
        sampleDuration: CMTime,
        sampleCount: Int,
        sampleSize: Int
    ) -> CMSampleBuffer? {
        guard let blockBuffer = blockBuffer(from: data) else { return nil }

        var timing = CMSampleTimingInfo(
            duration: sampleDuration,
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var sizes = [sampleSize]
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: format,
            sampleCount: sampleCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sizes,
            sampleBufferOut: &sample
        ) == noErr else { return nil }

        return sample
    }

    /// Còpia dels bytes a un `CMBlockBuffer` propietat de CoreMedia, per no
    /// dependre de la vida del `Data` original.
    private static func blockBuffer(from data: Data) -> CMBlockBuffer? {
        var buffer: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: data.count,
            blockAllocator: nil,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: data.count,
            flags: 0,
            blockBufferOut: &buffer
        ) == noErr, let buffer,
              CMBlockBufferAssureBlockMemory(buffer) == noErr else { return nil }

        let copied: OSStatus = data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return kCMBlockBufferBadPointerParameterErr }
            return CMBlockBufferReplaceDataBytes(
                with: base,
                blockBuffer: buffer,
                offsetIntoDestination: 0,
                dataLength: data.count
            )
        }
        guard copied == noErr else { return nil }

        return buffer
    }
}
