// 网易云的纯逻辑用例（不碰网络）：自提供 Cookie 解析、封面 URL 归一化、分页收集的上限与停止条件、
// 签名边界。契约向量覆盖不到的规则放在这里，漂移时自测先红。
import Foundation
import PterosaurCore

public enum NeteasePureCases {
    public static func run() throws {
        try expectEqual(parseUserCookie("  "), "", "空白 cookie 串")
        try expectEqual(parseUserCookie("00DE8abcdef"), "MUSIC_U=00DE8abcdef", "只粘 MUSIC_U 的值本身")
        try expectEqual(parseUserCookie("MUSIC_U=abc; foo=bar; __csrf=token"), "MUSIC_U=abc; __csrf=token",
                        "只保留会话必需的 cookie")
        try expectEqual(parseUserCookie("MUSIC_U=\n__csrf=t"), "__csrf=t", "空值的会话 cookie 被丢弃")
        try expectEqual(parseUserCookie("MUSIC_U=a; MUSIC_U=b"), "MUSIC_U=a", "同名 cookie 只取首个")
        try expectEqual(parseUserCookie("=x; MUSIC_A=y"), "MUSIC_A=y", "空名片段丢弃")

        // 封面：镜像主机归一到 p3，查询串只留最后一个 param
        try expectEqual(
            canonicalNeteaseImage("http://p7.music.126.net/a/b.jpg?imageView=1&param=200y200&param=300y300&enlarge=2"),
            "https://p3.music.126.net/a/b.jpg?param=300y300", "网易云封面规范化")
        try expectEqual(canonicalNeteaseImage("http://example.com/a.jpg?param=1"),
                        "http://example.com/a.jpg?param=1", "非网易云地址原样返回")
        try expectEqual(coverAt("https://p1.music.126.net/x.jpg?param=1y1", 300) ?? "",
                        "https://p3.music.126.net/x.jpg?param=300x300", "coverAt 覆盖尺寸参数")

        // 分页收集：不足一页即停；more=false 即停；最多 10 页 / 2000 条
        var calls = 0
        let short = collectAlbumPages { _ in
            calls += 1
            return (list: Array(0..<5), more: true)
        }
        try expectEqual(calls, 1, "不足一页即停")
        try expectEqual(short.count, 5, "不足一页保留已取到的部分")

        calls = 0
        let full = collectAlbumPages { _ in
            calls += 1
            return (list: Array(0..<200), more: true)
        }
        try expectEqual(calls, ARTIST_ALBUM_MAX_PAGES, "最多翻 10 页")
        try expectEqual(full.count, 2000, "合计上限 2000 张")

        calls = 0
        _ = collectAlbumPages { _ in
            calls += 1
            return (list: Array(0..<200), more: false)
        }
        try expectEqual(calls, 1, "more=false 即停")

        calls = 0
        let tolerant = collectAlbumPages { _ in
            calls += 1
            if calls == 2 { throw UpstreamError(0, "boom") }
            return (list: Array(0..<200), more: true)
        }
        try expectEqual(tolerant.count, 200, "单页抛错时保留已取到的部分")

        // 签名：eapi 的 params 是定长大写十六进制，weapi 的 encSecKey 更长于 modulus 宽度
        let eapi = eapiSign(path: "/api/cloudsearch/pc", payload: "{\"s\":\"x\"}")
        try expect(eapi.count % 2 == 0 && eapi.allSatisfy { $0.isHexDigit && !$0.isLowercase },
                   "eapi 签名应是大写十六进制")
        let form = weapiEncrypt(payload: "{}") { 0.5 }
        try expect(!form.params.isEmpty && !form.encSecKey.isEmpty, "weapi 加密产物非空")
    }
}
