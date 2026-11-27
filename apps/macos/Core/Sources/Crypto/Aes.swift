// 分组加密：AES-128/192/256 的 ECB / CBC，PKCS#7 填充（契约见 packages/contract/vectors/aes.json）。
//
// CryptoKit 只有 GCM / ChaCha，没有 ECB / CBC —— 走 CommonCrypto 的 CCCrypt，
// `kCCOptionPKCS7Padding` 即所需的填充；ECB 用“不带 IV + kCCOptionECBMode”表达。
import CommonCrypto
import Foundation

public enum Aes {
    private static func crypt(
        _ data: [UInt8],
        key: [UInt8],
        iv: [UInt8]?,
        ecb: Bool,
        encrypt: Bool
    ) -> [UInt8] {
        precondition(key.count == 16 || key.count == 24 || key.count == 32, "AES 密钥长度必须是 16 / 24 / 32 字节")
        if !ecb { precondition(iv?.count == 16, "AES-CBC: IV 必须是 16 字节") }
        if !encrypt { precondition(!data.isEmpty && data.count % 16 == 0, "密文长度必须是 16 的正整数倍") }

        let options: CCOptions = ecb
            ? CCOptions(kCCOptionPKCS7Padding | kCCOptionECBMode)
            : CCOptions(kCCOptionPKCS7Padding)

        var out = [UInt8](repeating: 0, count: data.count + kCCBlockSizeAES128)
        var outLength = 0

        let status: CCCryptorStatus = out.withUnsafeMutableBytes { outBuf in
            data.withUnsafeBytes { dataBuf in
                key.withUnsafeBytes { keyBuf in
                    let ivPtr = iv?.withUnsafeBytes { $0.baseAddress }
                    return CCCrypt(
                        CCOperation(encrypt ? kCCEncrypt : kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        options,
                        keyBuf.baseAddress, key.count,
                        ivPtr,
                        dataBuf.baseAddress, data.count,
                        outBuf.baseAddress, outBuf.count,
                        &outLength)
                }
            }
        }
        precondition(status == kCCSuccess, "AES \(ecb ? "ECB" : "CBC") 失败：\(status)")
        return Array(out.prefix(outLength))
    }

    public static func ecbEncrypt(key: [UInt8], plain: [UInt8]) -> [UInt8] {
        crypt(plain, key: key, iv: nil, ecb: true, encrypt: true)
    }

    public static func ecbDecrypt(key: [UInt8], cipher: [UInt8]) -> [UInt8] {
        crypt(cipher, key: key, iv: nil, ecb: true, encrypt: false)
    }

    public static func cbcEncrypt(key: [UInt8], iv: [UInt8], plain: [UInt8]) -> [UInt8] {
        crypt(plain, key: key, iv: iv, ecb: false, encrypt: true)
    }

    public static func cbcDecrypt(key: [UInt8], iv: [UInt8], cipher: [UInt8]) -> [UInt8] {
        crypt(cipher, key: key, iv: iv, ecb: false, encrypt: false)
    }
}