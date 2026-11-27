// RSA 与网易云 weapi 的 `encSecKey`（ADR-068）：**裸 RSA**，不是 PKCS#1 v1.5。
//
// Security 框架不提供 RAW 填充模式（只有 PKCS#1 v1.5 / OAEP），也没有内置大整数。
// 故这里带一个最小的大整数：`UInt32` limb、大端无符号、平方-乘模幂、逐位长除。
//
// 规模评估：RSA-1024、e = 65537（17 位 1）→ 约 1000 次 2048 位模乘 + 约 1100 次 2048 位取模。
// 逐位长除模式下约 2×10⁶ 次 limb 运算，macOS 上毫秒量级——对每次请求一次足够。
import Foundation

public struct RsaPublicKey: Sendable {
    /// 大端无符号模数。
    public let modulus: [UInt8]
    /// 大端无符号指数。
    public let exponent: [UInt8]

    public var modulusBytes: Int { modulus.count }

    /// 从 SPKI（DER，即 PEM 主体 base64 解码后）解析 RSA 公钥。
    public static func fromSpki(_ der: [UInt8]) -> RsaPublicKey? {
        guard var top = Der(bytes: der), let spki = top.read(0x30) else { return nil }
        guard var outer = Der(bytes: spki) else { return nil }
        guard outer.read(0x30) != nil else { return nil }          // AlgorithmIdentifier
        guard let bits = outer.read(0x03) else { return nil }       // BIT STRING
        guard var rs = Der(bytes: Array(bits.dropFirst())), let seq = rs.read(0x30) else { return nil }
        guard var ints = Der(bytes: seq), var mod = ints.read(0x02), let exp = ints.read(0x02) else { return nil }
        if mod.first == 0 { mod.removeFirst() }
        return RsaPublicKey(modulus: mod, exponent: exp)
    }
}

/* ============================ 最小 DER 读取 ============================ */

/// 极简 ASN.1 DER 读取（只支持单字节 tag 与短 / 长式长度）。
private struct Der {
    private let bytes: [UInt8]
    private var index = 0

    init?(bytes: [UInt8]) {
        guard !bytes.isEmpty else { return nil }
        self.bytes = bytes
    }

    /// 读取一个 `tag` 标识的 TLV 的**内容**（不含 tag 与长度头）。
    mutating func read(_ tag: UInt8) -> [UInt8]? {
        guard index + 2 <= bytes.count, bytes[index] == tag else { return nil }
        var pos = index + 1
        var len = Int(bytes[pos])
        pos += 1
        if len & 0x80 != 0 {
            let n = len & 0x7f
            guard n <= 4, pos + n <= bytes.count else { return nil }
            len = 0
            for _ in 0..<n {
                len = (len << 8) | Int(bytes[pos])
                pos += 1
            }
        }
        guard pos + len <= bytes.count else { return nil }
        let out = Array(bytes[pos..<(pos + len)])
        index = pos + len
        return out
    }
}

/* ============================ 最小大整数 ============================ */

private struct Big {
    /// 小端 limb（下标 0 为最低 32 位）；自动去掉高位零，至少 1 个 limb。
    var limbs: [UInt32]

    init(_ bytes: [UInt8]) {
        var b = bytes
        while !b.isEmpty && b.first == 0 { b.removeFirst() }
        var out = [UInt32]()
        var i = b.count
        while i > 0 {
            let start = max(0, i - 4)
            var v: UInt32 = 0
            for j in start..<i { v = (v << 8) | UInt32(b[j]) }
            out.append(v)
            i = start
        }
        limbs = out.isEmpty ? [0] : out
    }

    init(_ v: UInt32) { limbs = [v] }

    init(limbs: [UInt32]) {
        var l = limbs
        while l.count > 1 && l.last == 0 { l.removeLast() }
        self.limbs = l.isEmpty ? [0] : l
    }

    mutating func trim() {
        while limbs.count > 1 && limbs.last == 0 { limbs.removeLast() }
    }

    static func compare(_ a: Big, _ b: Big) -> Int {
        if a.limbs.count != b.limbs.count { return a.limbs.count < b.limbs.count ? -1 : 1 }
        for i in stride(from: a.limbs.count - 1, through: 0, by: -1) {
            if a.limbs[i] != b.limbs[i] { return a.limbs[i] < b.limbs[i] ? -1 : 1 }
        }
        return 0
    }

    static func sub(_ a: Big, _ b: Big) -> Big {
        var out = [UInt32](repeating: 0, count: a.limbs.count)
        var borrow: Int64 = 0
        for i in 0..<a.limbs.count {
            let av = Int64(a.limbs[i])
            let bv = i < b.limbs.count ? Int64(b.limbs[i]) : 0
            var cur = av - bv - borrow
            if cur < 0 { cur += 0x1_0000_0000; borrow = 1 } else { borrow = 0 }
            out[i] = UInt32(cur)
        }
        var v = Big(limbs: out)
        v.trim()
        return v
    }

    static func mul(_ a: Big, _ b: Big) -> Big {
        var out = [UInt64](repeating: 0, count: a.limbs.count + b.limbs.count)
        for i in 0..<a.limbs.count {
            var carry: UInt64 = 0
            for j in 0..<b.limbs.count {
                let cur = out[i + j] + UInt64(a.limbs[i]) * UInt64(b.limbs[j]) + carry
                out[i + j] = cur & 0xFFFF_FFFF
                carry = cur >> 32
            }
            var k = i + b.limbs.count
            while carry > 0 {
                let cur = out[k] + carry
                out[k] = cur & 0xFFFF_FFFF
                carry = cur >> 32
                k += 1
            }
        }
        var v = Big(limbs: out.map { UInt32($0) })
        v.trim()
        return v
    }

    /// `x mod m`：逐位移入余数、必要时减模（长除）。要求 `x < m * 2^32 * 32`? —— 通用。
    static func mod(_ x: Big, _ m: Big) -> Big {
        var rem = Big(0)
        let totalBits = x.limbs.count * 32
        for bit in stride(from: totalBits - 1, through: 0, by: -1) {
            // rem = rem * 2 + bit
            var carry: UInt32 = (x.limbs[bit / 32] >> UInt32(bit % 32)) & 1
            for i in 0..<rem.limbs.count {
                let next = rem.limbs[i] >> 31
                rem.limbs[i] = (rem.limbs[i] << 1) | carry
                carry = next
            }
            if carry != 0 { rem.limbs.append(carry) }
            if compare(rem, m) >= 0 { rem = sub(rem, m) }
        }
        rem.trim()
        return rem
    }

    var bitLength: Int {
        guard let top = limbs.last, top != 0 else { return 0 }
        var n = (limbs.count - 1) * 32
        var t = top
        while t != 0 { n += 1; t >>= 1 }
        return n
    }

    func bit(_ i: Int) -> Bool {
        let limb = i / 32
        if limb >= limbs.count { return false }
        return (limbs[limb] >> UInt32(i % 32)) & 1 == 1
    }

    /// 定长大端输出（左侧补零到 `count` 字节）。
    func bytes(count: Int) -> [UInt8] {
        var raw = [UInt8]()
        for limb in limbs.reversed() {
            raw.append(UInt8((limb >> 24) & 0xff))
            raw.append(UInt8((limb >> 16) & 0xff))
            raw.append(UInt8((limb >> 8) & 0xff))
            raw.append(UInt8(limb & 0xff))
        }
        while !raw.isEmpty && raw.first == 0 { raw.removeFirst() }
        if raw.count > count { return Array(raw.suffix(count)) }
        return [UInt8](repeating: 0, count: count - raw.count) + raw
    }
}


/// 裸 RSA：`c = m^e mod n`，消息字节直接当整数、左侧补零到模长。
public func rsaRaw(_ key: RsaPublicKey, message: [UInt8]) -> [UInt8] {
    let m = Big(key.modulus)
    let e = Big(key.exponent)
    var base = Big(message)
    if Big.compare(base, m) >= 0 { base = Big.mod(base, m) }
    var result = Big(1)
    for bit in stride(from: e.bitLength - 1, through: 0, by: -1) {
        result = Big.mod(Big.mul(result, result), m)
        if e.bit(bit) { result = Big.mod(Big.mul(result, base), m) }
    }
    return result.bytes(count: key.modulusBytes)
}