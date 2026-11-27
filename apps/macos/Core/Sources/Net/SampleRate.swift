// fMP4 init segment 采样率解析（Swift 版，对应 packages/core/src/sources/http.ts 的 parseSampleRate）。
//
// B 站 `playurl` 不回报采样率，唯一诚实的取法是读文件头：fMP4 的 `ftyp + moov` 在最前面，
// 采样率在 `moov/…/stbl/stsd` 首个 AudioSampleEntry（ISO 14496-12：box 头 8 字节 + SampleEntry
// 8 字节 + 保留 8 字节后，第 24 字节偏移处的 16.16 定点采样率）。纯函数，导出供单测。
import Foundation

/// 采样率探测单次读取的字节数（init segment 实测 < 4KB，32KB 裕量充足）。
public let PROBE_BYTES = 32 * 1024

private let MP4_CONTAINERS: Set<String> = ["moov", "trak", "mdia", "minf", "stbl"]
/// AudioSampleEntry 标准布局的音频格式（采样率字段偏移一致）；FLAC 轨走扩展布局，不在此路径。
private let MP4_AUDIO_FORMATS: Set<String> = ["mp4a", "ac-3", "ec-3"]

/// 从 fMP4 init segment 解析音频采样率（Hz）；解析不出返回 nil。
public func parseSampleRate(_ bytes: [UInt8]) -> Int? {
    let end0 = bytes.count
    func be32(_ p: Int) -> Int {
        Int(bytes[p]) << 24 | Int(bytes[p + 1]) << 16 | Int(bytes[p + 2]) << 8 | Int(bytes[p + 3])
    }
    func typeAt(_ p: Int) -> String {
        String(decoding: bytes[p..<(p + 4)], as: UTF8.self)
    }
    func find(_ start: Int, _ end: Int) -> Int? {
        var pos = start
        while pos + 8 <= end {
            let size = be32(pos)
            let type = typeAt(pos + 4)
            let boxEnd = size == 0 ? end : pos + size  // size=0：box 延伸到缓冲区末尾
            if boxEnd > end || boxEnd < pos + 8 { return nil }  // 脏数据：整段放弃
            if type == "stsd" {
                // 头 8 + version/flags 4 + entry_count 4 → 首个 sample entry
                let entry = pos + 16
                if entry + 36 > boxEnd { return nil }
                if !MP4_AUDIO_FORMATS.contains(typeAt(entry + 4)) { return nil }
                let sr = be32(entry + 8 + 24) >> 16
                return sr > 0 ? sr : nil
            }
            if MP4_CONTAINERS.contains(type), let hit = find(pos + 8, boxEnd) { return hit }
            pos = boxEnd
        }
        return nil
    }
    return find(0, end0)
}
