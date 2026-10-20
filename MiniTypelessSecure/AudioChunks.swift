import Foundation

/// Lossless PCM WAV splitting. Chunks contain every sample exactly once and remain
/// below the ASR five-minute limit. RIFF metadata/padding is parsed, not assumed.
struct AudioChunk {
    let wav: Data
    let duration: TimeInterval
}

enum AudioChunks {
    static let secondsPerChunk = 240
    static func split(_ wav: Data) throws -> [AudioChunk] {
        func invalid() -> CocoaError { CocoaError(.fileReadCorruptFile) }
        func string(_ offset: Int) -> String { String(decoding: wav[offset..<offset + 4], as: UTF8.self) }
        func number(_ offset: Int, _ bytes: Int) -> Int {
            (0..<bytes).reduce(0) { $0 | (Int(wav[offset + $1]) << (8 * $1)) }
        }
        guard wav.count >= 44, wav.count <= 20_000_000,
              string(0) == "RIFF", string(8) == "WAVE" else { throw invalid() }
        var format: Data?
        var samples: Data?
        var cursor = 12
        while cursor + 8 <= wav.count {
            let length = number(cursor + 4, 4)
            let start = cursor + 8
            guard length <= wav.count - start else { throw invalid() }
            switch string(cursor) {
            case "fmt ": format = wav.subdata(in: start..<start + length)
            case "data":
                guard samples == nil else { throw invalid() }
                samples = wav.subdata(in: start..<start + length)
            default: break
            }
            cursor = start + length + length % 2
        }
        guard let format, format.count >= 16, let samples, !samples.isEmpty else { throw invalid() }
        func fmt(_ offset: Int, _ bytes: Int) -> Int {
            (0..<bytes).reduce(0) { $0 | (Int(format[offset + $1]) << (8 * $1)) }
        }
        guard fmt(0, 2) == 1, fmt(2, 2) == 1, fmt(4, 4) == 16000,
              fmt(8, 4) == 32000, fmt(12, 2) == 2, fmt(14, 2) == 16,
              samples.count % 2 == 0, samples.count <= 600 * 32000 else { throw invalid() }
        let chunkBytes = secondsPerChunk * 32000
        return stride(from: 0, to: samples.count, by: chunkBytes).map { start in
            let end = min(start + chunkBytes, samples.count)
            let pcm = samples.subdata(in: start..<end)
            return AudioChunk(wav: encodePCM(pcm), duration: Double(pcm.count) / 32000)
        }
    }

    static func encodePCM(_ pcm: Data) -> Data {
        var data = Data("RIFF".utf8)
        func append(_ value: UInt32, bytes: Int) {
            for index in 0..<bytes { data.append(UInt8(truncatingIfNeeded: value >> (8 * index))) }
        }
        append(UInt32(36 + pcm.count), bytes: 4)
        data.append(Data("WAVEfmt ".utf8))
        append(16, bytes: 4); append(1, bytes: 2); append(1, bytes: 2)
        append(16000, bytes: 4); append(32000, bytes: 4); append(2, bytes: 2); append(16, bytes: 2)
        data.append(Data("data".utf8)); append(UInt32(pcm.count), bytes: 4)
        data.append(pcm)
        return data
    }
}
