// 应用主界面：搜索 / 结果列表 / 播放条。数据来自 :core 的接口与归一化。
//
// 铁律（ADR-064）：UI 层不直接发网络请求——所有上游调用都经 :core。
package im.xrl.pterosaur.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.compose.ui.platform.LocalContext
import im.xrl.pterosaur.player.PlaybackController
import androidx.compose.runtime.DisposableEffect
import androidx.compose.material3.IconButton as M3IconButton
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Pause
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import im.xrl.pterosaur.core.model.Track
import im.xrl.pterosaur.core.netease.cloudsearch
import im.xrl.pterosaur.core.netease.normalizeTrack
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject

/** 搜索页状态。 */
sealed interface SearchState {
    data object Idle : SearchState
    data object Loading : SearchState
    data class Done(val tracks: List<Track>) : SearchState
    data class Failed(val message: String) : SearchState
}

/** 搜索的 ViewModel：调 :core 的接口并归一化。 */
class SearchViewModel : ViewModel() {
    private val _state = MutableStateFlow<SearchState>(SearchState.Idle)
    val state: StateFlow<SearchState> = _state.asStateFlow()

    fun search(keyword: String) {
        if (keyword.isBlank()) return
        _state.value = SearchState.Loading
        viewModelScope.launch {
            _state.value = withContext(Dispatchers.IO) {
                try {
                    // 网络与解析都在 IO 线程；:core 不依赖 Android SDK
                    val body = cloudsearch(keywords = keyword, limit = 30).body.jsonObject
                    val songs = body["result"]?.jsonObject?.get("songs")?.jsonArray ?: return@withContext SearchState.Done(emptyList())
                    SearchState.Done(songs.map { normalizeTrack(it.jsonObject) })
                } catch (e: Exception) {
                    SearchState.Failed(e.message ?: "搜索失败")
                }
            }
        }
    }
}

@Composable
fun PterosaurApp(vm: SearchViewModel = viewModel()) {
    val state by vm.state.collectAsStateWithLifecycle()
    val searchScope = androidx.compose.runtime.rememberCoroutineScope()
    val context = LocalContext.current
    val controller = remember { PlaybackController(context) }
    DisposableEffect(Unit) { onDispose { controller.release() } }
    val playback by controller.state.collectAsStateWithLifecycle()
    var keyword by remember { mutableStateOf("") }

    Scaffold(bottomBar = { PlayerBar(playback, onToggle = { controller.toggle() }) }) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            Text(
                "搜索",
                style = MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.Bold),
                modifier = Modifier.padding(start = 20.dp, top = 16.dp, bottom = 8.dp),
            )
            TextField(
                value = keyword,
                onValueChange = { keyword = it },
                placeholder = { Text("歌曲、专辑、艺人") },
                leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                singleLine = true,
                shape = RoundedCornerShape(12.dp),
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                    unfocusedContainerColor = MaterialTheme.colorScheme.surfaceVariant,
                    focusedIndicatorColor = androidx.compose.ui.graphics.Color.Transparent,
                    unfocusedIndicatorColor = androidx.compose.ui.graphics.Color.Transparent,
                ),
                modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp),
                trailingIcon = {
                    IconButton(onClick = { vm.search(keyword) }) {
                        Icon(Icons.Filled.Search, contentDescription = "搜索")
                    }
                },
            )
            Spacer(Modifier.height(12.dp))
            when (val s = state) {
                SearchState.Idle -> EmptyHint("输入关键词开始搜索")
                SearchState.Loading -> Row(Modifier.fillMaxWidth().padding(24.dp), horizontalArrangement = Arrangement.Center) {
                    CircularProgressIndicator(Modifier.size(24.dp))
                }
                is SearchState.Failed -> EmptyHint(s.message)
                is SearchState.Done ->
                    if (s.tracks.isEmpty()) EmptyHint("没有结果")
                    else LazyColumn {
                        items(s.tracks, key = { it.source + ":" + it.id }) { t ->
                            TrackRow(t) { searchScope.launch { controller.play(t) } }
                        }
                    }
            }
        }
    }
}

@Composable
private fun EmptyHint(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(24.dp),
    )
}

@Composable
private fun TrackRow(track: Track, onClick: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 20.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Surface(
            color = MaterialTheme.colorScheme.surfaceVariant,
            shape = RoundedCornerShape(6.dp),
            modifier = Modifier.size(44.dp),
        ) {
            Icon(
                Icons.Filled.MusicNote,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(10.dp),
            )
        }
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(track.title, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodyLarge)
            Text(
                "${track.artist} — ${track.album}",
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        if (track.fee == "vip") {
            Text("VIP", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
        }
    }
}

/** 播放条（占位）：接入 Media3 之前的固定底栏。 */
@Composable
private fun PlayerBar(playback: im.xrl.pterosaur.player.PlaybackState, onToggle: () -> Unit) {
    Surface(color = MaterialTheme.colorScheme.surfaceVariant) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Filled.MusicNote, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    playback.track?.title ?: playback.error ?: "未在播放",
                    style = MaterialTheme.typography.bodyMedium,
                    color = if (playback.error != null) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                playback.track?.let {
                    Text(it.artist, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
                }
            }
            if (playback.track != null && playback.error == null) {
                IconButton(onClick = onToggle) {
                    Icon(if (playback.playing) Icons.Filled.Pause else Icons.Filled.PlayArrow, contentDescription = "播放 / 暂停")
                }
            }
        }
    }
}
