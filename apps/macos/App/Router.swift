// 路由（导航栈）：首页 / 搜索 / 歌单与磁带详情 / 艺人 / 专辑 / 排行榜 / 资料库各分区。
import Foundation
import PterosaurCore

enum Route: Hashable {
    case discover
    case search(query: String)
    case topLists
    case playlist(source: String, id: String)
    case artist(id: String)
    case album(id: String)
    case favorites
    case recent
    case savedPlaylists
    case savedArtists
    case savedAlbums
    case localPlaylist(id: String)
}
