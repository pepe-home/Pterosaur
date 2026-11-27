// B 站（磁带）的纯逻辑用例：标题清洗、时长解析、分P / 磁带构造、候选 CDN 排序、选轨规则、
// 字幕对齐、wbi 签名、登录 cookie 汇总。
import Foundation
import PterosaurCore

public enum BilibiliPureCases {
    public static func run() throws {
        try expectEqual(decodeTitle("<em class=\"keyword\">周杰伦</em> &amp; 朋友  "), "周杰伦 & 朋友", "标题去高亮标签")
        try expectEqual(parseDuration("222:28"), 13348, "长时长解析")
        try expectEqual(parseDuration("abc"), 0, "非法时长回 0")
        try expectEqual(parseDuration(nil), 0, "缺失时长回 0")

        // 分P：多P 取分P 名，缺名回落视频标题；id 为 bvid:cid
        let view: JSON = [
            "bvid": "BV1xy", "title": "合集标题", "pic": "//i2.hdslb.com/bfs/c.jpg",
            "owner": ["name": "UP"],
            "pages": [["cid": 11, "page": 1, "part": "第一集", "duration": 60],
                      ["cid": 12, "page": 2, "part": "  ", "duration": 70]],
            "desc": " 简介 ", "stat": ["view": 1234],
        ]
        let parts = buildParts(view)
        try expectEqual(parts.count, 2, "分P 条数")
        try expectEqual(parts[0].id, "BV1xy:11", "分P id")
        try expectEqual(parts[0].title, "第一集", "分P 标题")
        try expectEqual(parts[1].title, "合集标题", "分P 名缺失回落视频标题")
        try expectEqual(parts[0].cover, "https://i0.hdslb.com/bfs/c.jpg", "封面归一")
        let cassette = buildCassette(view)
        try expectEqual(cassette.trackCount, 2, "磁带的 trackCount = 分P 数")
        try expectEqual(cassette.creator, "UP", "磁带的 creator = UP 主")
        try expectEqual(cassette.description, "简介", "磁带简介去空白")
        try expectEqual(cassette.playCount, 1234, "磁带播放量")

        // 单P：标题取视频标题
        let single: JSON = ["bvid": "BV1s", "title": "单集", "pic": "", "pages": [["cid": 1, "duration": 5]]]
        try expectEqual(buildParts(single).map(\.title), ["单集"], "单P 标题")
        // 分P 缺失：trackCount 留空而非 0
        try expectEqual(buildCassette(["bvid": "BV1q", "title": "x"]).trackCount, nil, "分P 缺失留空")

        // 候选 CDN：官方 upos 优先、mcdn 殿后、去重
        let ranked = rankAudioUrls([
            "https://upos-sz-mirror08c.bilivideo.com/a",
            "https://xy1x2x3x4x5.mcdn.bilivideo.cn/b",
            "https://upos-sz-mirror08c.bilivideo.com/a",
            "https://other.bilivideo.cn/c",
            "https://third.example.com/d",
        ])
        try expectEqual(ranked, [
            "https://upos-sz-mirror08c.bilivideo.com/a",
            "https://other.bilivideo.cn/c",
            "https://third.example.com/d",
            "https://xy1x2x3x4x5.mcdn.bilivideo.cn/b",
        ], "候选 CDN 排序")

        // 档位挑选：最接近目标码率
        let audios: [JSON] = [["bandwidth": 64_000, "id": 30216], ["bandwidth": 132_000, "id": 30232], ["bandwidth": 192_000, "id": 30280]]
        try expectEqual((pickAudio(audios, .exhigh)?["id"] as? Int), 30280, "exhigh 挑 192k")
        try expectEqual((pickAudio(audios, .lossless)?["id"] as? Int), 30280, "无损不可得时挑最高")

        // 选轨：人工英文原文 → 人工中文译；AI 轨不作原文候选
        let tracks: [JSON] = [
            ["lan": "zh", "subtitle_url": "//s/zh", "type": 0],
            ["lan": "en", "subtitle_url": "//s/en", "type": 0],
            ["lan": "ai-zh", "subtitle_url": "//s/aizh", "type": 1],
        ]
        let pick = pickSubtitleTracks(tracks)
        try expectEqual(pick?.main["lan"] as? String, "en", "主轨为首条非中文人工轨")
        try expectEqual(pick?.zh?["lan"] as? String, "zh", "译文轨优先人工中文")
        let onlyAI = pickSubtitleTracks([["lan": "ai-zh", "subtitle_url": "//s/aizh", "type": 1]])
        try expectEqual(onlyAI?.zh == nil, true, "主轨已中文则不叠翻译")
        try expect(pickSubtitleTracks([["lan": "en"]]) == nil, "无 subtitle_url 的轨不参与")

        // 字幕对齐：最大重叠挂载；无重叠丢弃
        let lyric = buildLyricFromSubtitles(
            [["from": 0, "to": 2, "content": "Hello"], ["from": 2, "to": 4, "content": "World"]],
            [["from": 0.5, "to": 1.5, "content": "你好"], ["from": 2.5, "to": 3.5, "content": "世界"],
             ["from": 10, "to": 11, "content": "孤行"]])
        try expectEqual(lyric.timed, true, "字幕歌词带时间轴")
        try expectEqual(lyric.lines.map(\.translation), ["你好", "世界"], "按时间窗重叠挂翻译")
        try expectEqual(buildLyricFromSubtitles([]).lines.count, 0, "空字幕回空歌词")

        // wbi：混入盐表取前 32 位；签名串按键排序并追加 wts / w_rid
        try expectEqual(extractWbiKey("https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png"),
                        "7cd084941338484aae1ad9425b84077c", "取 wbi key")
        let signed = signWbi([("bvid", "BV1xx"), ("cid", "123")], key: "k", wts: 1_700_000_000)
        try expectEqual(signed, "bvid=BV1xx&cid=123&wts=1700000000&w_rid=\(Encoding.toHex(Digest.md5(Encoding.utf8("bvid=BV1xx&cid=123&wts=1700000000k"))))",
                        "wbi 签名")
        try expect(mixinKey(String(repeating: "a", count: 32), String(repeating: "b", count: 32)).count == 32, "混淆密钥 32 位")

        // 登录：poll 的 Set-Cookie 优先，缺失项从回跳 URL 查询串补齐且**不解码**
        let cookies = collectLoginCookies(["bili_jct=j"], "https://b/poll?SESSDATA=abc%2Cdef&DedeUserID=1")
        try expectEqual(cookies, ["bili_jct=j", "SESSDATA=abc%2Cdef", "DedeUserID=1"], "登录 cookie 汇总保持原文")
        try expectEqual(bilibiliCookieHeaderFromSetCookies(["SESSDATA=x; Path=/; HttpOnly", "foo=1"]),
                        "SESSDATA=x", "Set-Cookie 收敛为会话名单")
    }
}
