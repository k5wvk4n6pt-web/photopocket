package com.k5wvk4n6pt.photopocket.ui

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.k5wvk4n6pt.photopocket.data.Category
import com.k5wvk4n6pt.photopocket.data.Folder
import com.k5wvk4n6pt.photopocket.data.Handled
import com.k5wvk4n6pt.photopocket.data.Item
import com.k5wvk4n6pt.photopocket.data.LibMedia
import com.k5wvk4n6pt.photopocket.data.MediaLibrary
import com.k5wvk4n6pt.photopocket.data.Repo
import com.k5wvk4n6pt.photopocket.data.formatDuration
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlin.math.abs
import kotlin.math.roundToInt

private sealed class SortAction {
    data class Delete(val ids: List<Long>) : SortAction()
    data class Keep(val ids: List<Long>) : SortAction()
    data class Move(val ids: List<Long>, val folderId: Long, val added: List<Long>) : SortAction()
}

@Composable
fun SorterScreen(
    repo: Repo,
    categories: List<Category>,
    folders: List<Folder>,
    items: List<Item>,
    onClose: () -> Unit,
) {
    val p = LocalPalette.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()

    var hasAccess by remember { mutableStateOf(MediaLibrary.hasAnyAccess(context)) }
    var all by remember { mutableStateOf<List<LibMedia>?>(null) }
    var handled by remember { mutableStateOf(emptySet<Long>()) }
    val pending = remember { mutableStateListOf<Long>() }
    val history = remember { mutableStateListOf<SortAction>() }
    var recent by remember { mutableStateOf(listOf<Long>()) }
    var selected by remember { mutableStateOf(emptySet<Long>()) }
    var chooser by remember { mutableStateOf<List<LibMedia>?>(null) }
    var newFolderFor by remember { mutableStateOf<List<LibMedia>?>(null) }
    var preview by remember { mutableStateOf<LibMedia?>(null) }
    var settingsMenu by remember { mutableStateOf(false) }
    var exitConfirm by remember { mutableStateOf(false) }
    var notice by remember { mutableStateOf<String?>(null) }
    var reloadKey by remember { mutableStateOf(0) }

    val permLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        hasAccess = MediaLibrary.hasAnyAccess(context)
        reloadKey++
    }
    val trashLauncher = rememberLauncherForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { r ->
        if (r.resultCode == Activity.RESULT_OK) {
            val n = pending.size
            pending.clear()
            history.removeAll { it is SortAction.Delete }
            notice = "${n}枚をゴミ箱に移しました（30日間は戻せます）"
            reloadKey++
        }
    }

    LaunchedEffect(hasAccess, reloadKey, Prefs.sortByAdded) {
        if (!hasAccess) return@LaunchedEffect
        handled = (repo.dao.handledIds() + repo.dao.itemMediaIds()).toSet()
        all = MediaLibrary.load(context, Prefs.sortByAdded)
    }

    val remaining = (all ?: emptyList()).filter { it.id !in handled && it.id !in pending }
    val current = remaining.firstOrNull()
    val chipFolders = (recent.mapNotNull { id -> folders.firstOrNull { it.id == id } } + folders).distinctBy { it.id }.take(8)

    fun keep(list: List<LibMedia>) = scope.launch {
        list.forEach { repo.dao.insert(Handled(it.id)) }
        handled = handled + list.map { it.id }
        history += SortAction.Keep(list.map { it.id })
        notice = if (list.size == 1) "写真アプリに残しました" else "${list.size}枚を残しました"
    }
    fun delete(list: List<LibMedia>) {
        pending += list.map { it.id }
        history += SortAction.Delete(list.map { it.id })
        notice = if (list.size == 1) "削除予定に入れました" else "${list.size}枚を削除予定に入れました"
    }
    fun move(list: List<LibMedia>, folder: Folder) = scope.launch {
        val added = repo.addMedia(folder.id, list, items)
        list.forEach { repo.dao.insert(Handled(it.id)) }
        handled = handled + list.map { it.id }
        history += SortAction.Move(list.map { it.id }, folder.id, added)
        recent = (listOf(folder.id) + recent).distinct().take(6)
        notice = "「${folder.name}」に${if (list.size > 1) "${list.size}枚" else ""}入れました"
    }
    fun undo() = scope.launch {
        when (val a = history.removeLastOrNull() ?: return@launch) {
            is SortAction.Delete -> pending.removeAll(a.ids.toSet())
            is SortAction.Keep -> { a.ids.forEach { repo.dao.unhandle(it) }; handled = handled - a.ids.toSet() }
            is SortAction.Move -> {
                if (a.added.isNotEmpty()) repo.dao.deleteItemsFor(a.folderId, a.added)
                a.ids.forEach { repo.dao.unhandle(it) }
                handled = handled - a.ids.toSet()
            }
        }
        notice = "元に戻しました"
    }
    fun commitDeletes() {
        val uris = (all ?: emptyList()).filter { it.id in pending }.map { it.uri }
        if (uris.isEmpty()) return
        trashLauncher.launch(IntentSenderRequest.Builder(MediaLibrary.trashRequest(context, uris).intentSender).build())
    }
    fun tryClose() { if (pending.isNotEmpty()) exitConfirm = true else onClose() }

    BackHandler { tryClose() }
    LaunchedEffect(notice) { if (notice != null) { kotlinx.coroutines.delay(1800); notice = null } }

    Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().padding(horizontal = 16.dp)) {
        // 上のバー
        Row(Modifier.fillMaxWidth().padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            PillButton("閉じる") { tryClose() }
            Spacer(Modifier.weight(1f))
            Text("写真を仕分ける", color = p.ink, fontWeight = FontWeight.Black, fontSize = 17.sp)
            Spacer(Modifier.weight(1f))
            Box {
                CircleButton(Icons.Filled.Settings, "設定") { settingsMenu = true }
                DropdownMenu(settingsMenu, { settingsMenu = false }) {
                    DropdownMenuItem(text = { Text((if (Prefs.sortByAdded) "✓ " else "　") + "保存した順") }, onClick = { Prefs.setSortByAdded(true); settingsMenu = false })
                    DropdownMenuItem(text = { Text((if (!Prefs.sortByAdded) "✓ " else "　") + "撮影日順") }, onClick = { Prefs.setSortByAdded(false); settingsMenu = false })
                }
            }
        }
        // 1枚ずつ／一覧
        Row(Modifier.fillMaxWidth().padding(top = 12.dp).clip(RoundedCornerShape(12.dp)).background(p.ink.copy(alpha = 0.07f)).padding(3.dp)) {
            listOf(false to "1枚ずつ", true to "一覧でまとめて").forEach { (g, label) ->
                Box(
                    Modifier.weight(1f).clip(RoundedCornerShape(10.dp))
                        .background(if (Prefs.gridMode == g) p.card else Color.Transparent)
                        .clickable { Prefs.setGridMode(g) }.padding(vertical = 7.dp),
                    contentAlignment = Alignment.Center,
                ) { Text(label, color = p.ink, fontWeight = FontWeight.Bold, fontSize = 13.sp) }
            }
        }
        Row(Modifier.fillMaxWidth().padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                if (all == null) "" else "まだ仕分けていない写真 ${remaining.size}枚",
                color = p.sub, fontWeight = FontWeight.Bold, fontSize = 13.sp,
            )
            Spacer(Modifier.weight(1f))
            notice?.let { Text(it, color = p.accent, fontWeight = FontWeight.Bold, fontSize = 12.sp) }
        }

        Box(Modifier.weight(1f).fillMaxWidth().padding(vertical = 10.dp)) {
            when {
                !hasAccess -> AccessRequest { permLauncher.launch(MediaLibrary.permissions) }
                all == null -> Text("読み込み中…", color = p.sub, modifier = Modifier.align(Alignment.Center))
                current == null -> Done(pending.size)
                Prefs.gridMode -> LibraryGrid(remaining, selected, { selected = it }, Modifier.fillMaxSize().clip(RoundedCornerShape(14.dp)))
                else -> SwipeCard(
                    media = current,
                    onLeft = { delete(listOf(current)) },
                    onRight = { chooser = listOf(current) },
                    onUp = { keep(listOf(current)) },
                    onTap = { preview = current },
                )
            }
        }

        if (hasAccess && current != null) {
            val targets: () -> List<LibMedia> = {
                if (Prefs.gridMode) remaining.filter { it.id in selected } else listOf(current)
            }
            val enabled = !Prefs.gridMode || selected.isNotEmpty()
            if (Prefs.gridMode) {
                Text(
                    if (selected.isEmpty()) "タップで選択・長押ししてなぞるとまとめて選択" else "${selected.size}枚を選択中",
                    color = p.sub, fontSize = 12.sp, fontWeight = FontWeight.Bold,
                )
            } else {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
                    Text("← 左で削除", color = p.sub, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                    Text("右でフォルダへ →", color = p.sub, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                    Text("↑ 上で残す", color = p.sub, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                }
            }
            if (chipFolders.isNotEmpty()) {
                LazyRow(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(chipFolders, key = { it.id }) { f ->
                        Row(
                            Modifier.clip(RoundedCornerShape(50)).background(colorOf(f.colorName).copy(alpha = if (enabled) 0.18f else 0.08f))
                                .clickable(enabled = enabled) { val t = targets(); move(t, f); selected = emptySet() }
                                .padding(horizontal = 14.dp, vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Icon(Icons.Filled.Folder, null, tint = colorOf(f.colorName), modifier = Modifier.size(16.dp))
                            Spacer(Modifier.size(5.dp))
                            Text(f.name, color = p.ink, fontWeight = FontWeight.Bold, fontSize = 13.sp, maxLines = 1)
                        }
                    }
                }
            }
            Row(Modifier.fillMaxWidth().padding(vertical = 12.dp), horizontalArrangement = Arrangement.SpaceEvenly, verticalAlignment = Alignment.Bottom) {
                RoundAction(Icons.AutoMirrored.Filled.Undo, "戻す", Color.Gray, 46, history.isNotEmpty()) { undo() }
                RoundAction(Icons.Filled.Close, "削除", Color(0xFFE5484D), 60, enabled) { delete(targets()); selected = emptySet() }
                RoundAction(Icons.Filled.ArrowUpward, "残す", Color(0xFF2F80ED), 52, enabled) { keep(targets()); selected = emptySet() }
                RoundAction(Icons.Filled.Folder, "フォルダへ", Color(0xFF3BB273), 60, enabled) { chooser = targets() }
            }
        }
        if (pending.isNotEmpty()) {
            Row(
                Modifier.fillMaxWidth().padding(bottom = 8.dp).clip(RoundedCornerShape(16.dp)).background(Color(0xFFE5484D).copy(alpha = 0.12f)).padding(horizontal = 14.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("削除予定 ${pending.size}枚", color = Color(0xFFC9363B), fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                TextButton(onClick = { commitDeletes() }) { Text("まとめて削除", color = Color(0xFFC9363B), fontWeight = FontWeight.Black) }
            }
        }
    }

    chooser?.let { list ->
        FolderChooserSheet(
            "どのフォルダに入れますか？", categories, folders,
            onDismiss = { chooser = null },
            onNewFolder = { newFolderFor = list; chooser = null },
        ) { f -> move(list, f); selected = emptySet(); chooser = null }
    }
    newFolderFor?.let { list ->
        NameColorDialog("新しいフォルダ", "", "orange", null, { newFolderFor = null }, { n, c, _ ->
            scope.launch {
                val id = repo.addFolder(categories.firstOrNull()?.id, n, c, folders.size)
                move(list, Folder(id = id, categoryId = categories.firstOrNull()?.id, name = n, colorName = c))
                selected = emptySet()
            }
            newFolderFor = null
        })
    }
    preview?.let { m -> MediaPreview(m.uri, m.isVideo) { preview = null } }
    if (exitConfirm) {
        ConfirmDialog(
            "削除予定の${pending.size}枚があります",
            "写真アプリ（ギャラリー）から削除しますか？ゴミ箱に移るので、30日間は戻せます。",
            "削除する",
            onDismiss = { exitConfirm = false },
            onConfirm = { exitConfirm = false; commitDeletes() },
            extra = { TextButton(onClick = { exitConfirm = false; pending.clear(); onClose() }) { Text("削除せずに閉じる") } },
        )
    }
}

@Composable
private fun SwipeCard(media: LibMedia, onLeft: () -> Unit, onRight: () -> Unit, onUp: () -> Unit, onTap: () -> Unit) {
    val p = LocalPalette.current
    val scope = rememberCoroutineScope()
    val dx = remember(media.id) { Animatable(0f) }
    val dy = remember(media.id) { Animatable(0f) }
    val stamp = when {
        dx.value < -80 -> "削除" to Color(0xFFE5484D)
        dx.value > 80 -> "フォルダへ" to Color(0xFF3BB273)
        dy.value < -80 -> "残す" to Color(0xFF2F80ED)
        else -> null
    }
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(
            Modifier
                .fillMaxSize()
                .offset { IntOffset(dx.value.roundToInt(), dy.value.roundToInt()) }
                .rotate(dx.value / 40f)
                .pocketCard(p, 24.dp)
                .pointerInput(media.id) {
                    detectDragGestures(
                        onDragEnd = {
                            scope.launch {
                                when {
                                    dx.value < -220 -> onLeft()
                                    dx.value > 220 -> { onRight(); dx.animateTo(0f); dy.animateTo(0f) }
                                    dy.value < -220 && abs(dx.value) < 200 -> onUp()
                                    else -> { launch { dx.animateTo(0f) }; dy.animateTo(0f) }
                                }
                            }
                        },
                    ) { change, drag ->
                        change.consume()
                        scope.launch { dx.snapTo(dx.value + drag.x); dy.snapTo(dy.value + drag.y) }
                    }
                }
                .clickable(onClick = onTap)
                .padding(12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Box(Modifier.weight(1f).fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(Color(0x11000000))) {
                AsyncImage(media.uri, null, contentScale = ContentScale.Fit, modifier = Modifier.fillMaxSize())
                if (media.isVideo) {
                    Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(Icons.Filled.PlayCircle, null, tint = Color.White, modifier = Modifier.size(64.dp))
                        Text(
                            formatDuration(media.durationMs), color = Color.White, fontWeight = FontWeight.Black,
                            modifier = Modifier.clip(RoundedCornerShape(50)).background(Color(0x8C000000)).padding(horizontal = 12.dp, vertical = 3.dp),
                        )
                    }
                }
                stamp?.let { (t, c) ->
                    Text(
                        t, color = c, fontWeight = FontWeight.Black, fontSize = 26.sp,
                        modifier = Modifier.align(Alignment.TopCenter).padding(20.dp).rotate(-10f)
                            .border(4.dp, c, RoundedCornerShape(12.dp)).background(Color.White.copy(alpha = 0.75f), RoundedCornerShape(12.dp))
                            .padding(horizontal = 12.dp, vertical = 4.dp),
                    )
                }
            }
            Text(
                Instant.ofEpochMilli(media.takenAt).atZone(ZoneId.systemDefault()).format(DateTimeFormatter.ofPattern("yyyy年M月d日 H:mm")) +
                    if (media.isVideo) "・タップで再生" else "・タップで拡大",
                color = p.sub, fontSize = 12.sp, modifier = Modifier.padding(top = 8.dp),
            )
        }
    }
}

@Composable
private fun RoundAction(icon: ImageVector, label: String, color: Color, size: Int, enabled: Boolean, onClick: () -> Unit) {
    val p = LocalPalette.current
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            Modifier.size(size.dp).shadow(if (enabled) 6.dp else 0.dp, CircleShape).clip(CircleShape)
                .background(p.card).clickable(enabled = enabled, onClick = onClick),
            contentAlignment = Alignment.Center,
        ) { Icon(icon, label, tint = if (enabled) color else color.copy(alpha = 0.3f), modifier = Modifier.size((size * 0.45).dp)) }
        Text(label, color = p.sub, fontSize = 11.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 4.dp))
    }
}

@Composable
private fun AccessRequest(onRequest: () -> Unit) {
    val p = LocalPalette.current
    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        Text("写真へのアクセスを許可してください", color = p.ink, fontWeight = FontWeight.Black, fontSize = 17.sp)
        Text("端末の写真を1枚ずつ見ながら仕分けるために使います。「すべて許可」がおすすめです。", color = p.sub, fontSize = 13.sp, modifier = Modifier.padding(16.dp))
        PillButton("許可する", filled = true, onClick = onRequest)
    }
}

@Composable
private fun Done(pendingCount: Int) {
    val p = LocalPalette.current
    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        Text("🎉", fontSize = 48.sp)
        Text("仕分けが終わりました", color = p.ink, fontWeight = FontWeight.Black, fontSize = 18.sp)
        if (pendingCount > 0) Text("下の「まとめて削除」で、削除予定の写真を消せます。", color = p.sub, fontSize = 13.sp, modifier = Modifier.padding(12.dp))
    }
}

/** 写真を大きく表示（ピンチで拡大）／動画はほかのアプリで再生 */
@Composable
fun MediaPreview(uri: Uri, isVideo: Boolean, onDismiss: () -> Unit) {
    val context = LocalContext.current
    if (isVideo) {
        LaunchedEffect(uri) {
            val i = Intent(Intent.ACTION_VIEW).setDataAndType(uri, "video/*").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            runCatching { context.startActivity(i) }
            onDismiss()
        }
        return
    }
    androidx.compose.ui.window.Dialog(
        onDismissRequest = onDismiss,
        properties = androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            ZoomableImage(uri.toString(), Modifier.fillMaxSize())
            Box(Modifier.statusBarsPadding().padding(12.dp)) { PillButton("閉じる", onClick = onDismiss) }
        }
    }
}
