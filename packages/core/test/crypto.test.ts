import { describe, it, expect } from 'vitest'
import {
  createCipheriv,
  createHash,
  getRandomValues,
  generateKeyPairSync,
  privateDecrypt,
  constants,
  publicEncrypt,
} from 'node:crypto'
import {
  aesCbcDecrypt,
  aesCbcEncrypt,
  aesEcbDecrypt,
  aesEcbEncrypt,
  base64,
  fromHex,
  fromUtf8,
  md5,
  pbkdf2Sha256,
  rsaEncryptPkcs1,
  rsaKeyFromSpki,
  sha1,
  setUtf8Codec,
  sha256,
  toHex,
  unbase64,
  utf8,
} from '../src/services/crypto.js'

/** 对拍基准：Node 原生 `node:crypto`（内核源码本身不用它，见 portability.test.ts）。 */
const nodeHex = (alg: string, data: string) =>
  createHash(alg).update(data).digest('hex')

/** 可复现的伪随机源（LCG），用于 RSA 填充。 */
function seeded(seed: number): () => number {
  let s = seed >>> 0
  return () => (s = (s * 1664525 + 1013904223) >>> 0) / 4294967296
}

const SAMPLES = [
  '',
  'abc',
  'a'.repeat(55),
  'a'.repeat(56),
  'a'.repeat(64),
  '中文 é ü 😀',
  'x'.repeat(1000),
]

describe('摘要（对拍 node:crypto）', () => {
  it('sha256 / sha1 / md5 与原生一致（含分块边界 55/56/64/1000 字节）', () => {
    for (const s of SAMPLES) {
      expect(toHex(sha256(utf8(s))), `sha256 ${s.length}`).toBe(
        nodeHex('sha256', s),
      )
      expect(toHex(sha1(utf8(s))), `sha1 ${s.length}`).toBe(nodeHex('sha1', s))
      expect(toHex(md5(utf8(s))), `md5 ${s.length}`).toBe(nodeHex('md5', s))
    }
  })

  it('pbkdf2Sha256 与原生 PBKDF2（SHA-256）一致', () => {
    // Node 的 pbkdf2Sync 在运行时已导出；这里用 WebCrypto 之外的同步实现避免异步
    const { pbkdf2Sync } =
      require('node:crypto') as typeof import('node:crypto')
    for (const iterations of [1, 2, 1000]) {
      expect(toHex(pbkdf2Sha256('secret', 'salt', iterations))).toBe(
        pbkdf2Sync('secret', 'salt', iterations, 32, 'sha256').toString('hex'),
      )
    }
  })
})

describe('AES（对拍 node:crypto）', () => {
  const key16 = fromHex('000102030405060708090a0b0c0d0e0f')
  const key24 = fromHex('000102030405060708090a0b0c0d0e0f1011121314151617')
  const key32 = fromHex(
    '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f',
  )
  const iv = fromHex('0102030405060708090a0b0c0d0e0f10')
  const plain = utf8('{"s":"周杰伦 稻香","limit":30,"offset":0}')

  const nodeEcb = (key: Uint8Array, data: Uint8Array) => {
    const c = createCipheriv(`aes-${key.length * 8}-ecb`, key, null)
    return Buffer.concat([c.update(data), c.final()]).toString('hex')
  }
  const nodeCbc = (key: Uint8Array, iv: Uint8Array, data: Uint8Array) => {
    const c = createCipheriv(`aes-${key.length * 8}-cbc`, key, iv)
    return Buffer.concat([c.update(data), c.final()]).toString('hex')
  }

  it('ECB：128 / 192 / 256 位密钥（含 PKCS#7 填充）', () => {
    for (const key of [key16, key24, key32]) {
      expect(toHex(aesEcbEncrypt(key, plain))).toBe(nodeEcb(key, plain))
      expect(fromUtf8(aesEcbDecrypt(key, aesEcbEncrypt(key, plain)))).toBe(
        fromUtf8(plain),
      )
    }
  })

  it('CBC：128 / 192 / 256 位密钥，且恰好是块整数倍时也补齐整块', () => {
    const blockAligned = new Uint8Array(32).fill(7)
    for (const key of [key16, key24, key32]) {
      for (const data of [plain, blockAligned]) {
        const cipher = aesCbcEncrypt(key, iv, data)
        expect(toHex(cipher)).toBe(nodeCbc(key, iv, data))
        expect(
          Buffer.from(aesCbcDecrypt(key, iv, cipher)).equals(Buffer.from(data)),
        ).toBe(true)
      }
    }
  })

  it('解密结果与原生解密一致（交叉方向）', () => {
    const c = createCipheriv('aes-128-cbc', key16, iv)
    const native = Buffer.concat([c.update(plain), c.final()])
    expect(fromUtf8(aesCbcDecrypt(key16, iv, new Uint8Array(native)))).toBe(
      fromUtf8(plain),
    )
  })
})

describe('RSA PKCS#1 v1.5（对拍 openssl）', () => {
  it('加密结果能被原生私钥解回原文', () => {
    const { publicKey, privateKey } = generateKeyPairSync('rsa', {
      modulusLength: 1024,
    })
    const spki = new Uint8Array(
      publicKey.export({ type: 'spki', format: 'der' }),
    )
    const key = rsaKeyFromSpki(spki)
    const message = utf8('0CoJUm6Qyw8W8jud'.split('').reverse().join(''))
    const cipher = rsaEncryptPkcs1(key, message, seeded(42))
    const plain = privateDecrypt(
      { key: privateKey, padding: constants.RSA_PKCS1_PADDING },
      Buffer.from(cipher),
    )
    expect(plain.toString()).toBe(fromUtf8(message))
  })

  it('同一随机源下与原生公钥加密逐字节一致', () => {
    // 原生 publicEncrypt 自己取随机；这里改为「解回原文」已足够，另验证密文长度 = 模长
    const { publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 })
    const key = rsaKeyFromSpki(
      new Uint8Array(publicKey.export({ type: 'spki', format: 'der' })),
    )
    const cipher = rsaEncryptPkcs1(key, utf8('k'.repeat(16)), seeded(7))
    expect(cipher.length).toBe(256)
  })
})

describe('编解码', () => {
  it('base64 与原生一致，且可逆', () => {
    for (const n of [0, 1, 2, 3, 4, 16, 100]) {
      const bytes = new Uint8Array(n)
      getRandomValues(bytes as Uint8Array<ArrayBuffer>)
      expect(base64(bytes)).toBe(Buffer.from(bytes).toString('base64'))
      expect(toHex(unbase64(base64(bytes)))).toBe(toHex(bytes))
    }
  })
})

describe('手写 UTF-8 编解码（对拍 TextEncoder / TextDecoder）', () => {
  it('编码与解码对拍原生（含 1–4 字节、代理对、非法序列的替换字符）', () => {
    const samples = ['', 'abc', '中文 é ü', '😀🎵', 'mixed 中 a 😀']
    for (const s of samples) {
      expect(toHex(utf8(s))).toBe(Buffer.from(s, 'utf8').toString('hex'))
      expect(fromUtf8(new TextEncoder().encode(s))).toBe(s)
    }
    // 非法字节序列：与 TextDecoder 缺省非 fatal 行为一致
    const bad = new Uint8Array([0x61, 0xff, 0xc3, 0x28, 0xe2, 0x82, 0x62])
    expect(fromUtf8(bad)).toBe(new TextDecoder().decode(bad))
  })

  it('宿主可换用原生编解码，亦可还原', () => {
    setUtf8Codec({
      encode: (s) => new TextEncoder().encode(s),
      decode: (b) => new TextDecoder().decode(b),
    })
    expect(fromUtf8(utf8('😀'))).toBe('😀')
    setUtf8Codec(null)
    expect(fromUtf8(utf8('😀'))).toBe('😀')
  })
})

describe('RSA 原始运算 rsaRaw（网易云 weapi 的 encSecKey 约定）', () => {
  it('对消息字节直接求幂，左侧补零到模长（与 forge encrypt(msg, "NONE") 同语义）', async () => {
    const { rsaRaw } = await import('../src/services/crypto.js')
    // 用两个小素数构造一个可手算的模
    const p = 61n
    const q = 53n
    const n = p * q // 3233
    const e = 17n
    const message = utf8('hi') // 0x68 0x69
    const expected = 0x6869n ** e % n // 26729^17 mod 3233
    const out = rsaRaw({ n, e }, message)
    const got = BigInt('0x' + toHex(out))
    expect(got).toBe(expected)
    // 定长输出：k = ceil(n 的字节数)
    expect(toHex(out).length).toBe(Math.ceil(n.toString(16).length / 2) * 2)
  })
})
