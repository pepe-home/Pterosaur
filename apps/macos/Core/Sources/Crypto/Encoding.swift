// 编解码：UTF-8 / base64 / hex / 表单编码（Swift 版，契约见 packages/contract/vectors/encoding.json）。
//
// 与 TS 参考实现（packages/shared/src/url.ts + services/crypto.ts）语义一致：
// 表单编码遵循 WHATWG（空格 → `+`，字符集 `A-Za-z0-9*-._` 之外一律百分号编码）。
import Foundation

public enum Encoding {
    private static let hexDigits = Array("0123456789abcdef")

    /// 字节 → 小写十六进制。
    public static func toHex(_ bytes: [UInt8]) -> String {
        var out = ""
        out.reserveCapacity(bytes.count * 2)
        for b in bytes {
            out.append(hexDigits[Int(b >> 4)])
            out.append(hexDigits[Int(b & 0x0f)])
        }
        return out
    }

    /// 十六进制 → 字节（大小写均可，忽略非十六进制字符）。
    public static func fromHex(_ hex: String) -> [UInt8] {
        let clean = hex.filter { $0.isHexDigit }
        var out = [UInt8]()
        out.reserveCapacity(clean.count / 2)
        var iter = clean.makeIterator()
        while let hi = iter.next(), let lo = iter.next() {
            out.append(UInt8(String([hi, lo]), radix: 16) ?? 0)
        }
        return out
    }

    /// 字符串 → UTF-8 字节。
    public static func utf8(_ s: String) -> [UInt8] { Array(s.utf8) }

    /// UTF-8 字节 → 字符串（非法序列替换为 U+FFFD，与 TextDecoder 缺省一致）。
    public static func decodeUTF8(_ bytes: [UInt8]) -> String {
        String(decoding: bytes, as: UTF8.self)
    }

    /// 标准 base64 编码（补 `=`）。
    public static func base64(_ bytes: [UInt8]) -> String { Data(bytes).base64EncodedString() }

    /// base64 解码（容忍 URL-safe 字母表与缺失的 `=`）。
    public static func fromBase64(_ s: String) -> [UInt8] {
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let pad = t.count % 4
        if pad == 2 { t += "==" } else if pad == 3 { t += "=" }
        return [UInt8](Data(base64Encoded: t, options: .ignoreUnknownCharacters) ?? Data())
    }

    /// 表单值编码（`application/x-www-form-urlencoded`，WHATWG），与 `URLSearchParams.toString()` 逐字节一致。
    public static func formUrlEncode(_ value: String) -> String {
        var out = ""
        for b in utf8(value) {
            let c = b
            switch c {
            case 0x41...0x5A, 0x61...0x7A, 0x30...0x39: // A-Z a-z 0-9
                out.append(Character(UnicodeScalar(c)))
            case 0x20: // space
                out.append("+")
            case 0x2A, 0x2D, 0x2E, 0x5F: // * - . _
                out.append(Character(UnicodeScalar(c)))
            default:
                out.append("%")
                out.append(Character(UnicodeScalar(hexDigits[Int(c >> 4)].asciiValue!)))
                out.append(Character(UnicodeScalar(hexDigits[Int(c & 0x0f)].asciiValue!)).uppercased())
            }
        }
        return out
    }
}