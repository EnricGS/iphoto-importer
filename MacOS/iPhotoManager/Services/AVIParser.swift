import Foundation

/// Lector de l'estructura RIFF d'un fitxer AVI: capçaleres de stream i índex de
/// chunks de dades. Serveix per accedir a vídeos que AVFoundation no sap demuxar
/// (DV dins d'AVI) sense carregar el fitxer a memòria: només es llegeixen
/// capçaleres de 8 bytes i les dades es llegeixen després per offset.
///
/// Cobreix el que es troba en captures de MiniDV reals: AVI 1.0, OpenDML/AVI 2.0
/// (segments `RIFF/AVIX` addicionals per passar d'1 GB) i grups `LIST rec `.
enum AVIParser {

    // MARK: - Model

    struct Stream {
        enum Kind { case video, audio }

        let index: Int
        let kind: Kind
        /// `fccHandler` de l'`strh` o `biCompression` de l'`strf` (p. ex. `dvsd`).
        let codec: String
        /// Durada d'un frame de vídeo = `scale / rate`.
        let scale: Int
        let rate: Int
        // Només àudio (WAVEFORMATEX)
        let sampleRate: Int
        let channels: Int
        let bitsPerSample: Int
        let blockAlign: Int
    }

    /// Referència a un chunk de dades del LIST `movi`, sense llegir-ne el contingut.
    struct Chunk {
        let stream: Int
        let offset: UInt64
        let size: Int
    }

    struct File {
        let streams: [Stream]
        let chunks: [Chunk]

        var videoStream: Stream? { streams.first { $0.kind == .video } }
        var audioStream: Stream? { streams.first { $0.kind == .audio } }

        func chunks(ofStream index: Int) -> [Chunk] {
            chunks.filter { $0.stream == index }
        }
    }

    /// Quants chunks de dades cal indexar. Per a un thumbnail només fa falta el primer.
    enum ChunkScan {
        case none
        case firstVideo
        case all
    }

    enum ParseError: Error {
        case notAnAVI
        case unreadable
    }

    // MARK: - API

    static func parse(path: String, scan: ChunkScan) throws -> File {
        guard let handle = FileHandle(forReadingAtPath: path) else { throw ParseError.unreadable }
        defer { try? handle.close() }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        guard fileSize > 12 else { throw ParseError.notAnAVI }
        handle.seek(toFileOffset: 0)
        guard let header = try? handle.read(upToCount: 12), header.count == 12,
              header.prefix(4).elementsEqual("RIFF".utf8),
              header.dropFirst(8).elementsEqual("AVI ".utf8) else { throw ParseError.notAnAVI }

        var streams: [Stream] = []
        var chunks: [Chunk] = []
        var segmentStart: UInt64 = 0

        // AVI 2.0: el fitxer pot tenir diversos segments RIFF (`AVI ` + `AVIX`)
        while segmentStart + 12 <= fileSize {
            handle.seek(toFileOffset: segmentStart)
            guard let riff = try? handle.read(upToCount: 12), riff.count == 12,
                  riff.prefix(4).elementsEqual("RIFF".utf8) else { break }
            let segmentSize = UInt64(littleEndian32(riff.dropFirst(4)))
            let segmentEnd = min(segmentStart + 8 + segmentSize, fileSize)

            readSegment(
                handle: handle,
                from: segmentStart + 12,
                to: segmentEnd,
                scan: scan,
                streams: &streams,
                chunks: &chunks
            )

            if scan == .firstVideo, !chunks.isEmpty { break }
            segmentStart = segmentEnd + (segmentSize % 2)
        }

        return File(streams: streams, chunks: chunks)
    }

    /// Llegeix les dades d'un chunk. El handle s'obre a part per poder-lo reusar
    /// durant tot un remux sense reobrir el fitxer a cada frame.
    static func read(_ chunk: Chunk, from handle: FileHandle) -> Data? {
        handle.seek(toFileOffset: chunk.offset)
        guard let data = try? handle.read(upToCount: chunk.size), data.count == chunk.size else { return nil }
        return data
    }

    // MARK: - Recorregut de chunks

    private static func readSegment(
        handle: FileHandle,
        from start: UInt64,
        to end: UInt64,
        scan: ChunkScan,
        streams: inout [Stream],
        chunks: inout [Chunk]
    ) {
        var offset = start
        while offset + 8 <= end {
            handle.seek(toFileOffset: offset)
            guard let header = try? handle.read(upToCount: 8), header.count == 8 else { return }
            let id = fourCC(header.prefix(4))
            let size = UInt64(littleEndian32(header.dropFirst(4)))

            if id == "LIST" {
                guard let type = try? handle.read(upToCount: 4), type.count == 4 else { return }
                let listType = fourCC(type)
                let contentEnd = min(offset + 8 + size, end)

                switch listType {
                case "hdrl", "strl":
                    readSegment(handle: handle, from: offset + 12, to: contentEnd,
                                scan: scan, streams: &streams, chunks: &chunks)
                case "movi", "rec ":
                    if scan != .none {
                        readData(handle: handle, from: offset + 12, to: contentEnd,
                                 scan: scan, chunks: &chunks)
                    }
                default:
                    break
                }
                offset = contentEnd + (size % 2)
                continue
            }

            if id == "strh" || id == "strf",
               let payload = try? handle.read(upToCount: Int(min(size, 128))) {
                apply(chunkID: id, payload: payload, to: &streams)
            }

            offset += 8 + size + (size % 2)
        }
    }

    /// Indexa els chunks de dades (`##dc`, `##db`, `##wb`) d'un LIST `movi`/`rec `.
    private static func readData(
        handle: FileHandle,
        from start: UInt64,
        to end: UInt64,
        scan: ChunkScan,
        chunks: inout [Chunk]
    ) {
        var offset = start
        while offset + 8 <= end {
            handle.seek(toFileOffset: offset)
            guard let header = try? handle.read(upToCount: 8), header.count == 8 else { return }
            let id = fourCC(header.prefix(4))
            let size = UInt64(littleEndian32(header.dropFirst(4)))

            if id == "LIST" {
                guard let type = try? handle.read(upToCount: 4), type.count == 4 else { return }
                let contentEnd = min(offset + 8 + size, end)
                if fourCC(type) == "rec " {
                    readData(handle: handle, from: offset + 12, to: contentEnd, scan: scan, chunks: &chunks)
                    if scan == .firstVideo, !chunks.isEmpty { return }
                }
                offset = contentEnd + (size % 2)
                continue
            }

            if let stream = streamIndex(ofDataChunk: id), size > 0 {
                let isVideo = id.hasSuffix("dc") || id.hasSuffix("db")
                if scan == .all || (scan == .firstVideo && isVideo) {
                    chunks.append(Chunk(stream: stream, offset: offset + 8, size: Int(size)))
                    if scan == .firstVideo { return }
                }
            }

            offset += 8 + size + (size % 2)
        }
    }

    // MARK: - Capçaleres de stream

    /// `strh` obre un stream nou; l'`strf` que ve després el completa.
    private static func apply(chunkID: String, payload: Data, to streams: inout [Stream]) {
        if chunkID == "strh" {
            guard payload.count >= 28 else { return }
            let type = fourCC(payload.prefix(4))
            let kind: Stream.Kind
            switch type {
            case "vids": kind = .video
            case "auds": kind = .audio
            default: return
            }
            streams.append(Stream(
                index: streams.count,
                kind: kind,
                codec: fourCC(payload.dropFirst(4).prefix(4)),
                scale: Int(littleEndian32(payload.dropFirst(20).prefix(4))),
                rate: Int(littleEndian32(payload.dropFirst(24).prefix(4))),
                sampleRate: 0, channels: 0, bitsPerSample: 0, blockAlign: 0
            ))
            return
        }

        guard let last = streams.last else { return }
        switch last.kind {
        case .video:
            // BITMAPINFOHEADER: biCompression a l'offset 16
            guard payload.count >= 20 else { return }
            let compression = fourCC(payload.dropFirst(16).prefix(4))
            guard !compression.isEmpty, compression != "\0\0\0\0" else { return }
            streams[streams.count - 1] = Stream(
                index: last.index, kind: .video,
                codec: last.codec.isEmpty ? compression : last.codec,
                scale: last.scale, rate: last.rate,
                sampleRate: 0, channels: 0, bitsPerSample: 0, blockAlign: 0
            )
        case .audio:
            // WAVEFORMATEX: nChannels(2) nSamplesPerSec(4) nAvgBytesPerSec(4) nBlockAlign(2) wBitsPerSample(2)
            guard payload.count >= 16 else { return }
            let channels = Int(littleEndian16(payload.dropFirst(2).prefix(2)))
            let sampleRate = Int(littleEndian32(payload.dropFirst(4).prefix(4)))
            let blockAlign = Int(littleEndian16(payload.dropFirst(12).prefix(2)))
            let bits = Int(littleEndian16(payload.dropFirst(14).prefix(2)))
            streams[streams.count - 1] = Stream(
                index: last.index, kind: .audio, codec: last.codec,
                scale: last.scale, rate: last.rate,
                sampleRate: sampleRate, channels: channels,
                bitsPerSample: bits,
                blockAlign: blockAlign > 0 ? blockAlign : max(1, channels * bits / 8)
            )
        }
    }

    // MARK: - Utilitats

    /// Els chunks de dades es diuen `<núm. de stream><tipus>`, p. ex. `00db`, `01wb`.
    private static func streamIndex(ofDataChunk id: String) -> Int? {
        guard id.count == 4 else { return nil }
        let suffix = String(id.suffix(2))
        guard ["dc", "db", "wb"].contains(suffix) else { return nil }
        return Int(id.prefix(2))
    }

    private static func fourCC(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    private static func littleEndian32(_ data: Data) -> UInt32 {
        data.prefix(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
    }

    private static func littleEndian16(_ data: Data) -> UInt16 {
        data.prefix(2).withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) }
    }
}
