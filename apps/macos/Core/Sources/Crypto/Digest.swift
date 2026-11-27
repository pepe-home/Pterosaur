// 摘要与密钥派生：MD5 / SHA-1 / SHA-256 / PBKDF2-HMAC-SHA256（契约见 packages/contract/vectors/digest.json）。
//
// 走 Apple 的 CryptoKit（SHA 系列）与 CommonCrypto（MD5 / PBKDF2 —— CryptoKit 不含）。
// 都以 `public` 暴露，供 App 层与测试使用。
import CommonCrypto
import CryptoKit
import Foundation

public enum Digest {
    /// MD5 摘要（B 站 wbi 签名、网易云 eapi 报文摘要用）。
    public static func md5(_ data: [UInt8]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes { buf in
            _ = CC_MD5(buf.baseAddress, CC_LONG(buf.count), &out)
        }
        return out
    }

    /// SHA-1 摘要（凭证指纹用）。
    public static func sha1(_ data: [UInt8]) -> [UInt8] {
        [UInt8](Insecure.SHA1.hash(data: Data(data)))
    }

    /// SHA-256 摘要。
    public static func sha256(_ data: [UInt8]) -> [UInt8] {
        [UInt8](SHA256.hash(data: Data(data)))
    }

    /// PBKDF2-HMAC-SHA256，输出 32 字节。
    public static func pbkdf2Sha256(password: String, salt: String, iterations: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 32)
        let saltBytes = Encoding.utf8(salt)
        let result = saltBytes.withUnsafeBytes { saltBuf in
            password.withCString { pwPtr in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    pwPtr, strlen(pwPtr),
                    saltBuf.bindMemory(to: UInt8.self).baseAddress, saltBytes.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(iterations),
                    &out, out.count
                )
            }
        }
        precondition(result == kCCSuccess, "PBKDF2 失败：\(result)")
        return out
    }
}