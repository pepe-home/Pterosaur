// 播放地址与歌词的解析（Swift 版，对应 packages/core/src/sources/netease.ts 的
// songUrl / audioQuality / getLyric，以及 sources/http.ts 的 codecName / makeQuality / toHttps）。
import Foundation

/// 统一抽象音质档（与 shared/types.ts 的 `AUDIO_LEVELS` 一致）。
public enum AudioLevel: String, CaseIterable, Sendable {
    case standard, higher, exhigh, lossless, hires

    public static let defaultLevel: AudioLevel = .exhigh
    public static func parse(_ v: String?) -> AudioLevel {
        v.flatMap(AudioLevel.init(rawValue:)) ?? .defaultLevel
    }
}

/// 上游如实回报的流参数（供沉浸页音质 chip）。
public struct AudioQuality: Equatable, Sendable {
    public let codec: String?
    public let br: Int?
    public let sr: Int?
    public init(codec: String? = nil, br: Int? = nil, sr: Int? = nil) {
        self.codec = codec
        self.br = br
        self.sr = sr
    }
}

/// 把地址统一改写为 https（上游常回 `http://`）。
public func toHttps(_ url: String) -> String {
    url.hasPrefix("http://") ? "https://" + url.dropFirst("http://".count) : url
}

/// 由上游回报的类型字段推导编解码名；缺失时回退直链后缀。
public func codecName(_ raw: String?, _ url: String) -> String? {
    let s = (raw ?? "").lowercased().filter { $0.isLetter || $0.isNumber }
    if !s.isEmpty { return s.uppercased() }
    let path = url.split(separator: "?").first.map(String.init) ?? url
    guard let ext = path.split(separator: ".").last.map(String.init)?.lowercased(),
          ext.count >= 2, ext.count <= 4, ext.allSatisfy({ $0.isLetter || $0.isNumber }) else {
        return nil
    }
    return ext.uppercased()
}

private func jsonObj(_ v: Any?) -> [String: Any]? { v as? [String: Any] }
private func str(_ o: [String: Any]?, _ k: String) -> String? { o?[k] as? String }
private func int(_ o: [String: Any]?, _ k: String) -> Int? {
    if let n = o?[k] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.intValue }
    return nil
}

private struct Resolved {
    let url: String?
    let quality: AudioQuality?
}

private func resolveAudio(_ id: String, _ level: AudioLevel, _ cookie: String?) -> Resolved {
    let body = songUrlV1(id: id, level: level.rawValue, cookie: cookie).body
    guard let root = jsonObj(body),
          let data = root["data"] as? [Any],
          let d = data.first as? [String: Any],
          let raw = str(d, "url"), !raw.isEmpty else {
        return Resolved(url: nil, quality: nil)
    }
    let br = int(d, "br").flatMap { $0 > 0 ? $0 : nil }
    let sr = int(d, "sr").flatMap { $0 > 0 ? $0 : nil }
    return Resolved(
        url: toHttps(raw),
        quality: AudioQuality(codec: codecName(str(d, "type") ?? str(d, "encodeType"), raw), br: br, sr: sr))
}

/// 解析播放地址；不可播放（版权受限 / 未登录）返回空数组。
public func songUrl(_ id: String, level: AudioLevel = .defaultLevel, cookie: String? = nil) -> [String] {
    resolveAudio(id, level, cookie).url.map { [$0] } ?? []
}

/// 解析该档位**实际**得到的流参数（上游会降级并如实回报）。
public func audioQuality(_ id: String, level: AudioLevel = .defaultLevel, cookie: String? = nil) -> AudioQuality? {
    resolveAudio(id, level, cookie).quality
}

/// 歌词（含翻译）；失败返回空歌词而不是抛错。
public func getLyric(_ id: String, cookie: String? = nil) -> Lyric {
    let body = lyricNew(id: id, cookie: cookie).body
    guard let root = jsonObj(body) else { return Lyric() }
    let lrc = str(jsonObj(root["lrc"]), "lyric") ?? ""
    let tlyric = str(jsonObj(root["tlyric"]), "lyric")
    return parseLrc(lrc, translation: tlyric)
}

/// 可直接交给播放器的 https 地址（`streamUrl` 的端上等价物）。
public func playableUrl(_ trackId: String, level: AudioLevel = .defaultLevel, cookie: String? = nil) -> String? {
    songUrl(trackId, level: level, cookie: cookie).first
}