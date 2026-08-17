import Foundation
import AVFoundation
import CryptoKit
import os

private let remuxLog = Logger(subsystem: "com.iphotomanager.app", category: "dv-remux")

/// Fa reproduïbles els AVI amb vídeo DV re-encapsulant-los a `.mov` **sense
/// recodificar**: els frames DV i les mostres PCM es copien tal qual a un
/// contenidor que AVFoundation sí que sap demuxar.
///
/// El problema és només el demuxer d'AVI: `AVPlayer` accepta aquests fitxers
/// (el temps avança) però no entrega cap frame de vídeo. Amb el mateix stream
/// dins d'un `.mov` es reprodueix bé, sense pèrdua de qualitat i a velocitat de
/// còpia de disc.
///
/// El resultat es guarda a la cache de l'app, així que només es paga el primer cop.
actor DVAVIRemuxService {

    // MARK: - Estat

    private let cacheFolder: URL
    /// Remuxos en curs, per no fer el mateix fitxer dues vegades si l'usuari
    /// va endavant i enrere pel visor.
    private var inFlight: [String: Task<URL, Error>] = [:]

    /// Límit de la cache de vídeos re-encapsulats.
    private let cacheLimitBytes: Int64 = 20 * 1024 * 1024 * 1024

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheFolder = caches.appendingPathComponent("com.iphotomanager.remux", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)
    }

    // MARK: - API

    enum RemuxError: LocalizedError {
        case notDVAVI
        case writerFailed(String)

        var errorDescription: String? {
            switch self {
            case .notDVAVI: return "El fitxer no és un AVI amb vídeo DV."
            case .writerFailed(let reason): return reason
            }
        }
    }

    /// Diu si un fitxer necessita re-encapsulat: AVI amb pista de vídeo DV.
    /// Només llegeix capçaleres, no recorre les dades.
    nonisolated static func requiresRemux(path: String) -> Bool {
        guard URL(fileURLWithPath: path).pathExtension.lowercased() == "avi" else { return false }
        guard let file = try? AVIParser.parse(path: path, scan: .none),
              let video = file.videoStream else { return false }
        return DVVideoFormat.isDV(codec: video.codec)
    }

    /// URL reproduïble per un AVI DV: el `.mov` de la cache, generant-lo si cal.
    /// `progress` rep la fracció completada (0…1) durant la generació.
    func playableURL(for path: String, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let destination = cacheURL(for: path)

        if let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path),
           (attributes[.size] as? Int64 ?? 0) > 0 {
            return destination
        }

        if let existing = inFlight[destination.path] {
            return try await existing.value
        }

        let task = Task<URL, Error> {
            try await Self.remux(source: path, destination: destination, progress: progress)
        }
        inFlight[destination.path] = task

        defer { inFlight[destination.path] = nil }
        let url = try await task.value
        pruneCache()
        return url
    }

    // MARK: - Cache

    /// Clau per path + mida + data de modificació: si el fitxer canvia, es regenera.
    private func cacheURL(for path: String) -> URL {
        var raw = "v1|\(path)"
        if let attributes = try? FileManager.default.attributesOfItem(atPath: path) {
            let size = attributes[.size] as? Int64 ?? 0
            let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            raw = "v1|\(path)|\(size)|\(modified)"
        }
        let digest = SHA256.hash(data: Data(raw.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
        return cacheFolder.appendingPathComponent("\(digest).mov")
    }

    /// Esborra els `.mov` menys usats quan la cache passa del límit.
    private func pruneCache() {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentAccessDateKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: cacheFolder, includingPropertiesForKeys: keys
        ) else { return }

        let sized = entries.compactMap { url -> (url: URL, size: Int64, accessed: Date)? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return (url, Int64(values.fileSize ?? 0), values.contentAccessDate ?? .distantPast)
        }

        var total = sized.reduce(Int64(0)) { $0 + $1.size }
        guard total > cacheLimitBytes else { return }

        for entry in sized.sorted(by: { $0.accessed < $1.accessed }) {
            guard total > cacheLimitBytes else { break }
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
            remuxLog.info("Cache de remux: esborrat \(entry.url.lastPathComponent, privacy: .public)")
        }
    }

    // MARK: - Escriptura

    private nonisolated static func remux(
        source: String,
        destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let file = try AVIParser.parse(path: source, scan: .all)
        guard let videoStream = file.videoStream, DVVideoFormat.isDV(codec: videoStream.codec),
              let video = VideoFeeder(file: file, stream: videoStream, source: source, progress: progress)
        else { throw RemuxError.notDVAVI }

        let audio = AudioFeeder(file: file, source: source, dvFormat: video.format, firstFrame: video.firstFrame)
        let feeders: [TrackFeeder] = [video] + (audio.map { [$0] } ?? [])
        defer { feeders.forEach { $0.close() } }

        // Escrivim a un temporal i el movem en acabar: si es cancel·la o petem,
        // no queda un .mov mig escrit a la cache que després es donaria per bo.
        let partial = destination.appendingPathExtension("partial")
        try? FileManager.default.removeItem(at: partial)
        try? FileManager.default.removeItem(at: destination)

        let writer = try AVAssetWriter(outputURL: partial, fileType: .mov)
        for feeder in feeders {
            guard writer.canAdd(feeder.input) else {
                throw RemuxError.writerFailed("L'escriptor no accepta la pista \(feeder.input.mediaType.rawValue).")
            }
            writer.add(feeder.input)
        }

        guard writer.startWriting() else {
            throw RemuxError.writerFailed(writer.error?.localizedDescription ?? "No s'ha pogut començar a escriure.")
        }
        writer.startSession(atSourceTime: .zero)

        do {
            try await feed(feeders: feeders, writer: writer)
        } catch {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: partial)
            throw error
        }

        await writer.finishWriting()
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: partial)
            throw RemuxError.writerFailed(writer.error?.localizedDescription ?? "L'escriptura ha fallat.")
        }

        try FileManager.default.moveItem(at: partial, to: destination)
        remuxLog.info("Remuxat \((source as NSString).lastPathComponent, privacy: .public): \(video.frameCount) frames, àudio=\(audio != nil)")
        return destination
    }

    /// Alimenta les pistes alternant-les: sempre la que va més endarrerida en
    /// temps **d'entre les que accepten dades**. Escollir per temps sol i esperar
    /// una pista concreta encalla l'escriptor, que espera l'altra pista per poder
    /// entrellaçar. Cada pista es marca com a acabada tan bon punt s'esgota,
    /// perquè l'escriptor no es quedi esperant dades que ja no arribaran.
    private nonisolated static func feed(feeders: [TrackFeeder], writer: AVAssetWriter) async throws {
        var finished = Set<ObjectIdentifier>()

        func markExhausted() {
            for feeder in feeders where !feeder.hasMore && !finished.contains(ObjectIdentifier(feeder)) {
                feeder.input.markAsFinished()
                finished.insert(ObjectIdentifier(feeder))
            }
        }

        while feeders.contains(where: \.hasMore) {
            try Task.checkCancellation()
            guard writer.status == .writing else {
                throw RemuxError.writerFailed(writer.error?.localizedDescription ?? "L'escriptura s'ha aturat.")
            }

            let pending = feeders.filter(\.hasMore).sorted { $0.nextPresentationTime < $1.nextPresentationTime }
            if let next = pending.first(where: { $0.input.isReadyForMoreMediaData }) {
                try next.appendNext()
            } else {
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            markExhausted()
        }

        markExhausted()
    }
}

// MARK: - Pistes

/// Una pista que es va copiant al `.mov` de sortida.
private protocol TrackFeeder: AnyObject {
    var input: AVAssetWriterInput { get }
    var hasMore: Bool { get }
    /// Instant de la pròxima mostra pendent — serveix per entrellaçar pistes.
    var nextPresentationTime: CMTime { get }
    func appendNext() throws
    func close()
}

/// Vídeo DV: cada chunk `##db`/`##dc` de l'AVI és un frame sencer i intra,
/// així que es copia tal qual amb el PTS calculat pel número de frame.
private final class VideoFeeder: TrackFeeder {

    let input: AVAssetWriterInput
    let format: DVVideoFormat
    let firstFrame: Data
    var frameCount: Int { chunks.count }

    private let chunks: [AVIParser.Chunk]
    private let handle: FileHandle
    private let description: CMVideoFormatDescription
    private let progress: @Sendable (Double) -> Void
    private var index = 0
    private var reportedPercent = -1

    init?(
        file: AVIParser.File,
        stream: AVIParser.Stream,
        source: String,
        progress: @escaping @Sendable (Double) -> Void
    ) {
        let chunks = file.chunks(ofStream: stream.index)
        guard let handle = FileHandle(forReadingAtPath: source),
              let first = chunks.first,
              let frame = AVIParser.read(first, from: handle),
              let format = DVVideoFormat(frameSize: frame.count),
              let description = format.formatDescription(is16by9: DVVideoFormat.isWidescreen(frame: frame))
        else { return nil }

        self.chunks = chunks
        self.handle = handle
        self.firstFrame = frame
        self.format = format
        self.description = description
        self.progress = progress
        self.input = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: description)
        self.input.expectsMediaDataInRealTime = false
    }

    var hasMore: Bool { index < chunks.count }

    var nextPresentationTime: CMTime {
        CMTimeMultiply(format.frameDuration, multiplier: Int32(index))
    }

    func appendNext() throws {
        guard hasMore else { return }
        let time = nextPresentationTime
        let chunk = chunks[index]
        index += 1

        guard let data = AVIParser.read(chunk, from: handle),
              let sample = CMSampleBufferFactory.video(
                data: data, format: description,
                presentationTime: time, duration: format.frameDuration
              ) else {
            throw DVAVIRemuxService.RemuxError.writerFailed("Frame de vídeo il·legible (frame \(index)).")
        }
        guard input.append(sample) else {
            throw DVAVIRemuxService.RemuxError.writerFailed("Frame de vídeo rebutjat per l'escriptor.")
        }

        let percent = Int(Double(index) / Double(chunks.count) * 100)
        if percent != reportedPercent {
            reportedPercent = percent
            progress(Double(index) / Double(chunks.count))
        }
    }

    func close() {
        try? handle.close()
    }
}

/// Àudio d'un AVI DV, que pot venir de dos llocs:
/// - **tipus 2**: stream PCM propi de l'AVI (chunks `##wb`) → es copia tal qual.
/// - **tipus 1**: dins dels propis frames DV → cal desxifrar-lo (`DVAudioExtractor`).
private final class AudioFeeder: TrackFeeder {

    private enum Source {
        case pcmStream([AVIParser.Chunk])
        case embeddedInDV([AVIParser.Chunk])

        var chunks: [AVIParser.Chunk] {
            switch self {
            case .pcmStream(let chunks), .embeddedInDV(let chunks): return chunks
            }
        }
    }

    let input: AVAssetWriterInput

    private let source: Source
    private let description: CMAudioFormatDescription
    private let sampleRate: Int
    private let bytesPerFrame: Int
    private let handle: FileHandle
    private let isPAL: Bool
    private var index = 0
    private var samplesWritten: Int64 = 0

    init?(file: AVIParser.File, source path: String, dvFormat: DVVideoFormat, firstFrame: Data) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }

        // Stream PCM propi (el cas de les captures amb Premiere / la majoria d'eines)
        if let stream = file.audioStream, stream.sampleRate > 0, stream.bitsPerSample == 16,
           case let chunks = file.chunks(ofStream: stream.index), !chunks.isEmpty,
           let description = Self.formatDescription(
            sampleRate: stream.sampleRate, channels: max(1, stream.channels)
           ) {
            self.source = .pcmStream(chunks)
            self.description = description
            self.sampleRate = stream.sampleRate
            self.bytesPerFrame = max(1, stream.blockAlign)
        } else if let embedded = DVAudioExtractor.extract(from: firstFrame, isPAL: dvFormat.isPAL),
                  let description = Self.formatDescription(
                    sampleRate: embedded.format.sampleRate, channels: 2
                  ),
                  let videoStream = file.videoStream {
            // Àudio dins dels frames DV
            self.source = .embeddedInDV(file.chunks(ofStream: videoStream.index))
            self.description = description
            self.sampleRate = embedded.format.sampleRate
            self.bytesPerFrame = 4
        } else {
            remuxLog.info("AVI DV sense àudio llegible: es remuxa només el vídeo")
            try? handle.close()
            return nil
        }

        self.handle = handle
        self.isPAL = dvFormat.isPAL
        self.input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: description)
        self.input.expectsMediaDataInRealTime = false
    }

    var hasMore: Bool { index < source.chunks.count }

    var nextPresentationTime: CMTime {
        CMTime(value: samplesWritten, timescale: CMTimeScale(sampleRate))
    }

    func appendNext() throws {
        guard hasMore else { return }
        let time = nextPresentationTime
        let chunk = source.chunks[index]
        index += 1

        guard let pcm = pcmData(for: chunk), pcm.count >= bytesPerFrame,
              let sample = CMSampleBufferFactory.audio(
                data: pcm, format: description,
                presentationTime: time, sampleRate: sampleRate, bytesPerFrame: bytesPerFrame
              ) else { return }

        guard input.append(sample) else {
            throw DVAVIRemuxService.RemuxError.writerFailed("Bloc d'àudio rebutjat per l'escriptor.")
        }
        samplesWritten += Int64(pcm.count / bytesPerFrame)
    }

    func close() {
        try? handle.close()
    }

    private func pcmData(for chunk: AVIParser.Chunk) -> Data? {
        guard let raw = AVIParser.read(chunk, from: handle) else { return nil }
        switch source {
        case .pcmStream:
            return raw
        case .embeddedInDV:
            return DVAudioExtractor.extract(from: raw, isPAL: isPAL)?.pcm
        }
    }

    private static func formatDescription(sampleRate: Int, channels: Int) -> CMAudioFormatDescription? {
        let bytesPerFrame = UInt32(channels * 2)
        var asbd = AudioStreamBasicDescription(
            mSampleRate: Float64(sampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: bytesPerFrame,
            mFramesPerPacket: 1,
            mBytesPerFrame: bytesPerFrame,
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 16,
            mReserved: 0
        )

        var description: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &description
        ) == noErr else { return nil }
        return description
    }
}
