// 网易云网页端 / 客户端接口的签名与加密（Swift 版，对应 packages/core/src/sources/neteaseSign.ts）。
//
// 常量与构造方式与 TS 参考实现逐项一致——它们是与上游协商的一部分，不是实现细节。
// 契约：packages/contract/vectors/netease-sign.json。
import CommonCrypto
import CryptoKit
import Foundation

private let PRESET_KEY = "0CoJUm6Qyw8W8jud"
private let IV = "0102030405060708"
private let EAPI_KEY = "e82ckenh8dichen8"
private let EAPI_SEPARATOR = "-36cd479b6b5-"
private let BASE62 = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

private let WEAPI_PUBLIC_KEY_B64 =
    "MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDgtQn2JZ34ZC28NWYpAUd98iZ37BUrX/aKzmFbt7clFSs6sXqHauqKWqdtLkF2KexO40H1YTX8z2lSgBBOAxLsvaklV8k4cBFK9snQXE9/DDaFt6Rr7iVZMldczhC0JNgTz+SHXT6CBHuX3e9SdB1Ua44oncaTWz7OBGLbCiK45wIDAQAB"

private let WEAPI_PUBLIC_KEY: RsaPublicKey? = RsaPublicKey.fromSpki(
    Encoding.fromBase64(WEAPI_PUBLIC_KEY_B64))

public struct WeapiForm {
    public let params: String
    public let encSecKey: String
}

/// eapi 加密的 `params`（大写十六进制）。
public func eapiSign(path: String, payload: String) -> String {
    let digest = Digest.md5(Encoding.utf8("nobody\(path)use\(payload)md5forencrypt"))
    let data = "\(path)\(EAPI_SEPARATOR)\(payload)\(EAPI_SEPARATOR)\(Encoding.toHex(digest))"
    let cipher = Aes.ecbEncrypt(key: Encoding.utf8(EAPI_KEY), plain: Encoding.utf8(data))
    return Encoding.toHex(cipher).uppercased()
}

/// eapi 响应解密（`params` 是十六进制）：取报文里的 JSON 段；解析失败返回 `nil`。
public func eapiDecrypt(_ hex: String) -> String? {
    let plainBytes = Aes.ecbDecrypt(key: Encoding.utf8(EAPI_KEY), cipher: Encoding.fromHex(hex))
    let plain = Encoding.decodeUTF8(plainBytes)
    guard let start = plain.range(of: EAPI_SEPARATOR),
          let end = plain.range(of: EAPI_SEPARATOR, options: .backwards),
          start.upperBound < end.lowerBound else { return nil }
    return String(plain[start.upperBound..<end.lowerBound])
}

/// 生成会话密钥（与 TS `randomSecretKey` 一致）：`round(r * 61)` 取字符。
public func randomSecretKey(_ random: () -> Double) -> String {
    var key = ""
    for _ in 0..<16 {
        let idx = Int((random() * 61).rounded())
        if idx < BASE62.count { key.append(BASE62[BASE62.index(BASE62.startIndex, offsetBy: idx)]) }
    }
    return key
}

/// weapi 加密：明文 → AES-CBC（预设密钥）→ AES-CBC（会话密钥）得 `params`；
/// 会话密钥反转后经**裸 RSA** 得 `encSecKey`（ADR-068）。
public func weapiEncrypt(payload: String, _ random: () -> Double) -> WeapiForm {
    guard let pub = WEAPI_PUBLIC_KEY else { fatalError("weapi 公钥解析失败") }
    let secret = randomSecretKey(random)
    let inner = Encoding.base64(Aes.cbcEncrypt(key: Encoding.utf8(PRESET_KEY), iv: Encoding.utf8(IV), plain: Encoding.utf8(payload)))
    let params = Encoding.base64(Aes.cbcEncrypt(key: Encoding.utf8(secret), iv: Encoding.utf8(IV), plain: Encoding.utf8(inner)))
    let reversed = Encoding.utf8(String(secret.reversed()))
    let encSecKey = Encoding.toHex(rsaRaw(pub, message: reversed))
    return WeapiForm(params: params, encSecKey: encSecKey)
}