// 播放：把 :core 解析出的 https 直链交给 Media3 ExoPlayer。UI 不碰上游域名（ADR-064）。
package im.xrl.pterosaur.player

import android.content.Context
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import im.xrl.pterosaur.core.model.Track
import im.xrl.pterosaur.core.netease.AudioLevel
import im.xrl.pterosaur.core.netease.songUrl
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext

/** 当前播放状态（供 UI 观察）。 */
data class PlaybackState(
    val track: Track? = null,
    val playing: Boolean = false,
    val error: String? = null,
)

/**
 * 播放控制器：持有单个 ExoPlayer，解析地址后播放。
 *
 * 地址解析经 `:core` 的 `songUrl`（上游直链，https）；解析失败（VIP 未登录 / 版权受限）
 * 只置错误态，不崩溃——与 Web 端的降级一致。
 */
class PlaybackController(context: Context) {
    private val player: ExoPlayer = ExoPlayer.Builder(context).build()
    private val _state = MutableStateFlow(PlaybackState())
    val state: StateFlow<PlaybackState> = _state.asStateFlow()

    init {
        player.addListener(object : Player.Listener {
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                _state.value = _state.value.copy(playing = isPlaying)
            }
        })
    }

    /** 播放一首曲目：先解析地址，再交给播放器。在 IO 线程解析。 */
    suspend fun play(track: Track, level: AudioLevel = AudioLevel.DEFAULT) {
        _state.value = PlaybackState(track = track)
        val url = withContext(Dispatchers.IO) { songUrl(track.id, level).firstOrNull() }
        if (url == null) {
            _state.value = _state.value.copy(error = "该曲目暂不可播放")
            return
        }
        player.setMediaItem(MediaItem.fromUri(url))
        player.prepare()
        player.play()
    }

    fun toggle() {
        if (player.isPlaying) player.pause() else player.play()
    }

    fun release() {
        player.release()
    }
}