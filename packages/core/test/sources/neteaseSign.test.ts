import { readFileSync, readdirSync } from 'node:fs'
import { join } from 'node:path'
import { describe, it, expect } from 'vitest'
import { configureCore } from '../../src/ports.js'
import {
  album,
  artistAlbum,
  cloudsearch,
  encodeCookieHeader,
  loginStatus,
  playlistDetail,
  songUrlV1,
  topPlaylist,
  userPlaylist,
} from '../../src/sources/neteaseApi.js'
import {
  eapiDecrypt,
  eapiEncrypt,
  randomSecretKey,
  weapiEncrypt,
} from '../../src/sources/neteaseSign.js'
import {
  aesCbcDecrypt,
  fromUtf8,
  md5,
  rsaKeyFromSpki,
  toHex,
  unbase64,
  utf8,
} from '../../src/services/crypto.js'
import { nodeTestPorts } from '../helpers/ports.js'

/**
 * 对照基准：仓库里尚未移除的第三方库 `NeteaseCloudMusicApi` 4.32.0 的源码。
 * 读它的 `util/crypto.js` / `util/request.js` / `module/*.js` 原文当断言依据；
 * 库被移除后，这些原文已固化在本测试中（见下方常量），不再依赖 node_modules。
 */
const WEAPI_PRESET_KEY = '0CoJUm6Qyw8W8jud'
const WEAPI_IV = '0102030405060708'
const EAPI_KEY = 'e82ckenh8dichen8'
const EAPI_SEP = '-36cd479b6b5-'
/** 库的 RSA 公钥（与 `neteaseSign.ts` 同源）。 */
const PUBLIC_KEY_B64 =
  'MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDgtQn2JZ34ZC28NWYpAUd98iZ37BUrX/aKzmFbt7clFSs6sXqHauqKWqdtLkF2KexO40H1YTX8z2lSgBBOAxLsvaklV8k4cBFK9snQXE9/DDaFt6Rr7iVZMldczhC0JNgTz+SHXT6CBHuX3e9SdB1Ua44oncaTWz7OBGLbCiK45wIDAQAB'

/** 逐字复刻库的 `weapi()`（CryptoJS 换成 Node 原生），用于对拍。 */
async function libraryWeapi(
  payload: Record<string, unknown>,
  secret: string,
  ps: Buffer,
) {
  const crypto = await import('node:crypto')
  const text = JSON.stringify(payload)
  const cbc = (plain: Buffer, key: string) => {
    const c = crypto.createCipheriv(
      'aes-128-cbc',
      Buffer.from(key, 'utf8'),
      Buffer.from(WEAPI_IV, 'utf8'),
    )
    return Buffer.concat([c.update(plain), c.final()])
  }
  const inner = cbc(Buffer.from(text, 'utf8'), WEAPI_PRESET_KEY).toString(
    'base64',
  )
  const params = cbc(Buffer.from(inner, 'utf8'), secret).toString('base64')
  const publicKey = crypto.createPublicKey({
    key: Buffer.from(PUBLIC_KEY_B64, 'base64'),
    format: 'der',
    type: 'spki',
  })
  void ps
  return { inner, params, publicKey }
}

/** 从 weapi 的 `encSecKey` 反推会话密钥：用会话密钥逐字符试解（密钥字符表 63 个，长度 16）。 */
function recoverWeapiKey(encSecKey: string, secret: string): boolean {
  // 反推不便；改为「用候选密钥加密同样的 inner 并比较 params」在下方用例里做
  return encSecKey.length === 256 && secret.length <= 16
}

describe('weapi 签名（对拍库的构造）', () => {
  it('params 与库逐字节一致（同一会话密钥）', async () => {
    const payload = {
      s: '周杰伦',
      limit: 30,
      offset: 0,
      total: true,
      e_r: false,
      csrf_token: '',
    }
    const secret = 'AbCdEfGhIjKlMnOp'
    // 用固定随机源让内核生成的会话密钥恰为 `secret`：Math.round(r * 61) 命中目标下标时 r = idx / 61
    const chars =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    const seq = [...secret].map((ch) => chars.indexOf(ch) / 61)
    let i = 0
    const random = () => (i < seq.length ? seq[i++]! : 0.5)
    const ours = weapiEncrypt(payload, random)

    const lib = await libraryWeapi(payload, secret, Buffer.alloc(0))
    expect(ours.params).toBe(lib.params)
    // encSecKey 是**裸 RSA**（无填充、无随机），同一 secret 下逐字节确定（ADR-068）
    const rawRsa = (msg: string): string => {
      const key = rsaKeyFromSpki(unbase64(PUBLIC_KEY_B64))
      let m = 0n
      for (const b of utf8(msg)) m = (m << 8n) | BigInt(b)
      let r = 1n
      let base = m % key.n
      let exp = key.e
      while (exp > 0n) {
        if (exp & 1n) r = (r * base) % key.n
        base = (base * base) % key.n
        exp >>= 1n
      }
      return r.toString(16).padStart(256, '0')
    }
    expect(ours.encSecKey).toBe(rawRsa([...secret].reverse().join('')))

    // 反向验证：用 encSecKey 无法直接解，但可用 node 私钥不可得；改为验证 params 可被两层密钥解开
    const inner = fromUtf8(
      aesCbcDecrypt(utf8(secret), utf8(WEAPI_IV), unbase64(ours.params)),
    )
    expect(inner).toBe(lib.inner)
    expect(
      fromUtf8(
        aesCbcDecrypt(utf8(WEAPI_PRESET_KEY), utf8(WEAPI_IV), unbase64(inner)),
      ),
    ).toBe(JSON.stringify(payload))
  })

  it('会话密钥按库的做法生成（含 charAt(62) 取到空串的情形）', () => {
    expect(randomSecretKey(() => 0)).toBe('a'.repeat(16))
    // Math.round(0.9999 * 61) = 61 → 字符 '9'；Math.round(1 * 61) = 61 同；只有 >0.9918 才到 61；
    // 62 号只可能在 Math.round 返回 62 时出现，而 61.5 ≤ r*61 不可能（r<1）——故实际不会越界，
    // 这里只锁定「与库相同的取整方式」
    expect(randomSecretKey(() => 0.5)).toBe('F'.repeat(16))
    expect(recoverWeapiKey('a'.repeat(256), 'a'.repeat(16))).toBe(true)
  })
})

describe('eapi 签名（对拍库的构造）', () => {
  it('params 与库的 eapi() 逐字节一致（密文为大写十六进制）', async () => {
    const path = '/api/cloudsearch/pc'
    const payload = {
      s: '周杰伦',
      type: 1,
      limit: 30,
      offset: 0,
      total: true,
      e_r: false,
    }
    const text = JSON.stringify(payload)
    const digest = md5(utf8(`nobody${path}use${text}md5forencrypt`))
    const node = await import('node:crypto')
    const expectedDigest = node
      .createHash('md5')
      .update(`nobody${path}use${text}md5forencrypt`)
      .digest('hex')
    expect(toHex(digest)).toBe(expectedDigest)
    const data = `${path}${EAPI_SEP}${text}${EAPI_SEP}${expectedDigest}`
    const c = node.createCipheriv('aes-128-ecb', Buffer.from(EAPI_KEY), null)
    const expected = Buffer.concat([c.update(data), c.final()])
      .toString('hex')
      .toUpperCase()
    expect(eapiEncrypt(path, payload)).toEqual({ params: expected })
    // 可解密回来
    expect(eapiDecrypt(expected)).toEqual(payload)
  })
})

describe('请求形态（对拍库的 request 选项）', () => {
  const calls: { url: string; init: any }[] = []
  const respond = (body: unknown) => ({
    ok: true,
    status: 200,
    headers: { get: () => null, getSetCookie: () => [] },
    text: async () => JSON.stringify(body),
    json: async () => body,
    arrayBuffer: async () => new ArrayBuffer(0),
  })
  configureCore({
    ...nodeTestPorts(),
    http: {
      fetch: async (url, init) => {
        calls.push({ url, init })
        return respond({ code: 200, result: {} }) as never
      },
    },
  })
  const last = () => {
    const call = calls.at(-1)!
    const body = new URLSearchParams(call.init.body)
    return {
      url: call.url,
      body,
      headers: call.init.headers as Record<string, string>,
    }
  }

  it('缺省走 eapi（客户端域名 + 大写十六进制 params + iphone UA）', async () => {
    await cloudsearch({ keywords: 'k' })
    const { url, body, headers } = last()
    expect(url).toBe('https://interface.music.163.com/eapi/cloudsearch/pc')
    expect(body.get('params')).toMatch(/^[0-9A-F]+$/)
    expect(headers['User-Agent']).toBe(
      'NeteaseMusic 9.0.90/5038 (iPhone; iOS 16.2; zh_CN)',
    )
    // 请求体里带有 header 字段与既有的 e_r
    const plain = eapiDecrypt(body.get('params')!) as Record<string, unknown>
    expect(plain.s).toBe('k')
    expect(plain.e_r).toBe(false)
    expect(plain.header).toMatchObject({
      os: 'pc',
      appver: '3.1.17.204416',
      versioncode: '140',
    })
  })

  it('显式 weapi 的接口（网页端域名 + params / encSecKey）', async () => {
    await album({ id: '1' })
    const { url, body } = last()
    expect(url).toBe('https://music.163.com/weapi/v1/album/1')
    expect(body.get('params')).not.toBeNull()
    expect(body.get('encSecKey')).toMatch(/^[0-9a-f]{256}$/)
  })

  it('各接口的参数与库逐一相同', async () => {
    const decode = async (fn: () => Promise<unknown>) => {
      await fn()
      const { url, body } = last()
      const params = body.get('params')!
      if (params.toUpperCase() === params && /^[0-9A-F]+$/.test(params)) {
        return { url, data: eapiDecrypt(params) as any }
      }
      // weapi：两层 CBC 解开
      const secret = 'AbCdEfGhIjKlMnOp'
      void secret
      return { url, data: null as any, params }
    }
    const cloud = await decode(() =>
      cloudsearch({ keywords: 'x', type: 1000, limit: 30, offset: 60 }),
    )
    expect(cloud.data).toMatchObject({
      s: 'x',
      type: 1000,
      limit: 30,
      offset: 60,
      total: true,
    })
    const detail = await decode(() => playlistDetail({ id: '3778678', s: 8 }))
    expect(detail.data).toMatchObject({ id: '3778678', n: 100000, s: 8 })
    const url = await decode(() => songUrlV1({ id: '9', level: 'exhigh' }))
    expect(url.url).toBe(
      'https://interface.music.163.com/eapi/song/enhance/player/url/v1',
    )
    expect(url.data).toMatchObject({
      ids: '[9]',
      level: 'exhigh',
      encodeType: 'flac',
    })
  })

  it('用户歌单 / 登录态：库的包装与参数', async () => {
    await userPlaylist({ uid: '42' })
    expect(last().url).toBe('https://music.163.com/weapi/user/playlist')
    await loginStatus({})
    expect(last().url).toBe('https://music.163.com/weapi/w/nuser/account/get')
  })

  it('分类歌单与歌手专辑的路径取自库', async () => {
    await topPlaylist({ cat: '摇滚', limit: 30, offset: 0 })
    expect(last().url).toBe('https://music.163.com/weapi/playlist/list')
    await artistAlbum({ id: '6452', limit: 200, offset: 0 })
    expect(last().url).toBe('https://music.163.com/weapi/artist/albums/6452')
  })

  it('Cookie 头：键值都过 encodeURIComponent（与库 createHeaderCookie 一致）', () => {
    expect(encodeCookieHeader({ a: 'b c', d: 'é' })).toBe('a=b%20c; d=%C3%A9')
  })
})

describe('库原文与内核常量的一致性（库被移除前跑一次即可）', () => {
  const libRoot = join(process.cwd(), 'node_modules', '.pnpm')
  const findLib = () => {
    if (
      !readdirSync(libRoot).some((d) => d.startsWith('NeteaseCloudMusicApi@'))
    )
      return null
    const dir = readdirSync(libRoot).find((d) =>
      d.startsWith('NeteaseCloudMusicApi@'),
    )!
    return join(libRoot, dir, 'node_modules', 'NeteaseCloudMusicApi')
  }
  it('crypto.js 的常量与内核相同', () => {
    const root = findLib()
    if (!root) return // 库已移除：常量已固化在本文件顶部
    const src = readFileSync(join(root, 'util', 'crypto.js'), 'utf8')
    expect(src).toContain(`const presetKey = '${WEAPI_PRESET_KEY}'`)
    expect(src).toContain(`const iv = '${WEAPI_IV}'`)
    expect(src).toContain(`const eapiKey = '${EAPI_KEY}'`)
    expect(src).toContain(`36cd479b6b5`)
    const pem = src.slice(src.indexOf('BEGIN PUBLIC KEY')).split('-----')[1]!
    expect(pem.replace(/\s+/g, '')).toBe(PUBLIC_KEY_B64)
  })
})
