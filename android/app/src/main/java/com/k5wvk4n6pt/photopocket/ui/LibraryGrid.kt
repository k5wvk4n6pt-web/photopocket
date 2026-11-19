package com.k5wvk4n6pt.photopocket.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import com.k5wvk4n6pt.photopocket.data.LibMedia
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive

/**
 * 端末の写真を一覧で表示して、まとめて選べるグリッド。
 * ・タップ：選ぶ／外す
 * ・長押ししてなぞる：なぞった範囲をまとめて選ぶ（端に近づくと自動でスクロール）
 */
@Composable
fun LibraryGrid(
    media: List<LibMedia>,
    selected: Set<Long>,
    onSelectedChange: (Set<Long>) -> Unit,
    modifier: Modifier = Modifier,
) {
    val p = LocalPalette.current
    val state = rememberLazyGridState()
    val currentSelected by rememberUpdatedState(selected)
    val currentMedia by rememberUpdatedState(media)
    var dragStart by remember { mutableStateOf<Int?>(null) }
    var dragBase by remember { mutableStateOf(emptySet<Long>()) }
    var dragSelecting by remember { mutableStateOf(true) }
    var autoScroll by remember { mutableFloatStateOf(0f) }
    var lastPos by remember { mutableStateOf(Offset.Zero) }
    var lastDragEnd by remember { mutableStateOf(0L) }

    fun indexAt(pos: Offset): Int? = state.layoutInfo.visibleItemsInfo.firstOrNull { info ->
        val o = info.offset
        pos.x >= o.x && pos.x < o.x + info.size.width && pos.y >= o.y && pos.y < o.y + info.size.height
    }?.index

    fun applyRange(end: Int) {
        val start = dragStart ?: return
        val range = minOf(start, end)..maxOf(start, end)
        val ids = range.mapNotNull { currentMedia.getOrNull(it)?.id }
        val next = if (dragSelecting) dragBase + ids else dragBase - ids.toSet()
        if (next != currentSelected) onSelectedChange(next)
    }

    LaunchedEffect(autoScroll) {
        while (isActive && autoScroll != 0f) {
            state.scrollBy(autoScroll)
            indexAt(lastPos)?.let { applyRange(it) }
            delay(16)
        }
    }

    LazyVerticalGrid(
        columns = GridCells.Fixed(4),
        state = state,
        contentPadding = PaddingValues(2.dp),
        horizontalArrangement = Arrangement.spacedBy(2.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp),
        modifier = modifier
            .pointerInput(Unit) {
                detectTapGestures(onTap = { pos ->
                    if (dragStart != null || System.currentTimeMillis() - lastDragEnd < 500) return@detectTapGestures
                    val i = indexAt(pos) ?: return@detectTapGestures
                    val m = currentMedia.getOrNull(i) ?: return@detectTapGestures
                    onSelectedChange(if (m.id in currentSelected) currentSelected - m.id else currentSelected + m.id)
                })
            }
            .pointerInput(Unit) {
                detectDragGesturesAfterLongPress(
                    onDragStart = { pos ->
                        val i = indexAt(pos) ?: return@detectDragGesturesAfterLongPress
                        dragStart = i
                        dragBase = currentSelected
                        dragSelecting = currentMedia.getOrNull(i)?.id !in currentSelected
                        lastPos = pos
                        applyRange(i)
                    },
                    onDrag = { change, _ ->
                        lastPos = change.position
                        indexAt(change.position)?.let { applyRange(it) }
                        val h = size.height
                        autoScroll = when {
                            change.position.y < 80f -> -14f
                            change.position.y > h - 80f -> 14f
                            else -> 0f
                        }
                    },
                    onDragEnd = { dragStart = null; autoScroll = 0f; lastDragEnd = System.currentTimeMillis() },
                    onDragCancel = { dragStart = null; autoScroll = 0f; lastDragEnd = System.currentTimeMillis() },
                )
            },
    ) {
        itemsIndexed(media, key = { _, m -> m.id }) { _, m ->
            val on = m.id in selected
            Box(Modifier.aspectRatio(1f)) {
                MediaThumb(m.uri.toString(), m.isVideo, m.durationMs, Modifier.fillMaxSize(), 0.dp)
                if (on) {
                    Box(Modifier.fillMaxSize().background(Color.White.copy(alpha = 0.35f)).border(3.dp, p.accent))
                    Icon(
                        Icons.Filled.CheckCircle, null, tint = p.accent,
                        modifier = Modifier.align(Alignment.TopEnd).padding(4.dp).size(22.dp).background(Color.White, CircleShape),
                    )
                }
            }
        }
    }
}
