package com.k5wvk4n6pt.photopocket.ui

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.rememberTransformableState
import androidx.compose.foundation.gestures.transformable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DriveFileMove
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.EditNote
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.RemoveCircleOutline
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.TextFields
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.k5wvk4n6pt.photopocket.data.Category
import com.k5wvk4n6pt.photopocket.data.Folder
import com.k5wvk4n6pt.photopocket.data.Item
import com.k5wvk4n6pt.photopocket.data.LibMedia
import com.k5wvk4n6pt.photopocket.data.MediaLibrary
import com.k5wvk4n6pt.photopocket.data.Repo
import kotlinx.coroutines.launch

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun FolderScreen(
    repo: Repo,
    folder: Folder,
    categories: List<Category>,
    folders: List<Folder>,
    allItems: List<Item>,
    onBack: () -> Unit,
) {
    val p = LocalPalette.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val items = allItems.filter { it.folderId == folder.id }
    var picking by remember { mutableStateOf(false) }
    var viewerIndex by remember { mutableStateOf<Int?>(null) }
    var selecting by remember { mutableStateOf(false) }
    var selected by remember { mutableStateOf(emptySet<Long>()) }
    var moving by remember { mutableStateOf<List<Item>?>(null) }
    var removing by remember { mutableStateOf<List<Item>?>(null) }
    var missing by remember { mutableStateOf(emptySet<Long>()) }

    // 写真アプリ（ギャラリー）で消された写真を見分ける
    LaunchedEffect(items.size) {
        if (MediaLibrary.hasAnyAccess(context)) {
            val exist = MediaLibrary.existingIds(context)
            missing = items.filter { it.mediaId !in exist }.map { it.id }.toSet()
        }
    }
    BackHandler(enabled = selecting) { selecting = false; selected = emptySet() }

    if (picking) {
        LibraryPicker(onCancel = { picking = false }) { list ->
            scope.launch { repo.addMedia(folder.id, list, allItems) }
            picking = false
        }
        return
    }

    Box(Modifier.fillMaxSize()) {
        LazyVerticalGrid(
            columns = GridCells.Fixed(3),
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 120.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            item(span = { GridItemSpan(3) }) {
                Column(Modifier.statusBarsPadding()) {
                    Row(Modifier.fillMaxWidth().padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                        BackButton(onBack)
                        Spacer(Modifier.weight(1f))
                        if (items.isNotEmpty()) PillButton(if (selecting) "完了" else "選択") { selecting = !selecting; selected = emptySet() }
                    }
                    Text(folder.name, color = p.ink, fontSize = 28.sp, fontWeight = FontWeight.Black, modifier = Modifier.padding(top = 14.dp))
                    Text("${items.count { !it.isVideo }}枚" + (items.count { it.isVideo }.takeIf { it > 0 }?.let { "・動画${it}本" } ?: ""),
                        color = p.sub, fontSize = 13.sp, modifier = Modifier.padding(bottom = 12.dp))
                    if (items.isEmpty()) {
                        Column(Modifier.fillMaxWidth().pocketCard(p).padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                            Text("まだ写真がありません", color = p.ink, fontWeight = FontWeight.Black)
                            Text("下のボタンから、写真や動画を選んで入れましょう。", color = p.sub, fontSize = 13.sp, modifier = Modifier.padding(top = 6.dp))
                        }
                    }
                }
            }
            items(items, key = { it.id }) { it ->
                val idx = items.indexOf(it)
                val on = it.id in selected
                Box(
                    Modifier.aspectRatio(1f).combinedClickable(
                        onClick = {
                            if (selecting) selected = if (on) selected - it.id else selected + it.id
                            else viewerIndex = idx
                        },
                        onLongClick = { selecting = true; selected = selected + it.id },
                    )
                ) {
                    if (it.id in missing) {
                        Box(Modifier.fillMaxSize().clip(RoundedCornerShape(10.dp)).background(p.soft), contentAlignment = Alignment.Center) {
                            Text("写真アプリから\n削除済み", color = p.sub, fontSize = 10.sp)
                        }
                    } else MediaThumb(it.uri, it.isVideo, it.durationMs, Modifier.fillMaxSize())
                    if (it.memo.isNotBlank()) Icon(Icons.Filled.EditNote, null, tint = Color.White,
                        modifier = Modifier.align(Alignment.BottomStart).padding(4.dp).size(20.dp).background(Color(0x8C000000), CircleShape).padding(2.dp))
                    if (on) {
                        Box(Modifier.fillMaxSize().clip(RoundedCornerShape(10.dp)).background(Color.White.copy(alpha = 0.35f)).border(3.dp, p.accent, RoundedCornerShape(10.dp)))
                        Icon(Icons.Filled.CheckCircle, null, tint = p.accent, modifier = Modifier.align(Alignment.TopEnd).padding(4.dp).size(22.dp).background(Color.White, CircleShape))
                    }
                }
            }
        }

        // 下のボタン
        Box(Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(bottom = 16.dp)) {
            if (selecting) {
                Row(
                    Modifier.pocketCard(p, 28.dp).padding(horizontal = 10.dp, vertical = 6.dp),
                    horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("${selected.size}枚", color = p.ink, fontWeight = FontWeight.Bold, modifier = Modifier.padding(horizontal = 8.dp))
                    val sel = items.filter { it.id in selected }
                    IconButton(enabled = sel.isNotEmpty(), onClick = { moving = sel }) { Icon(Icons.AutoMirrored.Filled.DriveFileMove, "移動", tint = p.ink) }
                    IconButton(enabled = sel.isNotEmpty(), onClick = { share(context, sel) }) { Icon(Icons.Filled.Share, "共有", tint = p.ink) }
                    IconButton(enabled = sel.isNotEmpty(), onClick = { removing = sel }) { Icon(Icons.Filled.RemoveCircleOutline, "フォルダから外す", tint = Color(0xFFE5484D)) }
                }
            } else {
                PillButton("写真・動画を入れる", Icons.Filled.Add, filled = true) { picking = true }
            }
        }
    }

    viewerIndex?.let { start ->
        ItemViewer(repo, items, start, categories, folders, onClose = { viewerIndex = null })
    }
    moving?.let { list ->
        FolderChooserSheet("どのフォルダに移しますか？", categories, folders, excluding = folder.id, onDismiss = { moving = null }) { dest ->
            scope.launch { list.forEach { repo.dao.update(it.copy(folderId = dest.id)) } }
            moving = null; selecting = false; selected = emptySet()
        }
    }
    removing?.let { list ->
        ConfirmDialog(
            "${list.size}枚をフォルダから外しますか？",
            "写真アプリ（ギャラリー）の写真は消えません。", "外す",
            onDismiss = { removing = null },
        ) {
            scope.launch { list.forEach { repo.dao.delete(it) } }
            removing = null; selecting = false; selected = emptySet()
        }
    }
}

fun share(context: android.content.Context, items: List<Item>) {
    val uris = ArrayList(items.map { Uri.parse(it.uri) })
    val intent = if (uris.size == 1) Intent(Intent.ACTION_SEND).putExtra(Intent.EXTRA_STREAM, uris[0])
                 else Intent(Intent.ACTION_SEND_MULTIPLE).putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
    intent.type = if (items.all { it.isVideo }) "video/*" else if (items.any { it.isVideo }) "*/*" else "image/*"
    intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    context.startActivity(Intent.createChooser(intent, "共有"))
}

/** 端末の写真から選んでフォルダに入れる画面 */
@Composable
fun LibraryPicker(onCancel: () -> Unit, onDone: (List<LibMedia>) -> Unit) {
    val p = LocalPalette.current
    val context = LocalContext.current
    var hasAccess by remember { mutableStateOf(MediaLibrary.hasAnyAccess(context)) }
    var media by remember { mutableStateOf<List<LibMedia>?>(null) }
    var selected by remember { mutableStateOf(emptySet<Long>()) }
    val perm = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { hasAccess = MediaLibrary.hasAnyAccess(context) }
    LaunchedEffect(hasAccess) { if (hasAccess) media = MediaLibrary.load(context) }
    BackHandler(onBack = onCancel)
    Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()) {
        Row(Modifier.fillMaxWidth().padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
            PillButton("キャンセル", onClick = onCancel)
            Spacer(Modifier.weight(1f))
            Text(if (selected.isEmpty()) "写真・動画を選ぶ" else "${selected.size}枚を選択", color = p.ink, fontWeight = FontWeight.Black)
            Spacer(Modifier.weight(1f))
            PillButton("入れる", filled = true) { onDone((media ?: emptyList()).filter { it.id in selected }) }
        }
        when {
            !hasAccess -> Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                Text("写真へのアクセスを許可してください", color = p.ink, fontWeight = FontWeight.Black)
                Spacer(Modifier.height(12.dp))
                PillButton("許可する", filled = true) { perm.launch(MediaLibrary.permissions) }
            }
            media == null -> Text("読み込み中…", color = p.sub, modifier = Modifier.padding(20.dp))
            else -> LibraryGrid(media!!, selected, { selected = it }, Modifier.fillMaxSize())
        }
    }
}

/** フォルダの写真を1枚ずつ見る画面（左右にめくる・ピンチで拡大） */
@Composable
fun ItemViewer(repo: Repo, items: List<Item>, start: Int, categories: List<Category>, folders: List<Folder>, onClose: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    if (items.isEmpty()) { LaunchedEffect(Unit) { onClose() }; return }
    val pager = rememberPagerState(initialPage = start.coerceIn(0, items.size - 1)) { items.size }
    var memoFor by remember { mutableStateOf<Item?>(null) }
    var moving by remember { mutableStateOf<Item?>(null) }
    var removing by remember { mutableStateOf<Item?>(null) }
    var trashed by remember { mutableStateOf<Item?>(null) }
    var textFor by remember { mutableStateOf<Item?>(null) }
    val trash = rememberLauncherForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { r ->
        if (r.resultCode == Activity.RESULT_OK) trashed?.let { t -> scope.launch { repo.dao.deleteItemsForMedia(listOf(t.mediaId)) } }
        trashed = null
    }
    androidx.compose.ui.window.Dialog(
        onDismissRequest = onClose,
        properties = androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            HorizontalPager(pager, Modifier.fillMaxSize()) { page ->
                val it = items[page]
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    if (it.isVideo) {
                        if (page == pager.currentPage) VideoPlayer(Uri.parse(it.uri), Modifier.fillMaxSize().padding(vertical = 70.dp))
                        else AsyncImage(it.uri, null, contentScale = ContentScale.Fit, modifier = Modifier.fillMaxSize())
                    } else ZoomableImage(it.uri, Modifier.fillMaxSize())
                }
            }
            val current = items.getOrNull(pager.currentPage)
            Row(Modifier.statusBarsPadding().padding(12.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                PillButton("閉じる", onClick = onClose)
                Spacer(Modifier.weight(1f))
                Text("${pager.currentPage + 1} / ${items.size}", color = Color.White, fontWeight = FontWeight.Bold)
            }
            if (current != null) {
                Column(Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(12.dp)) {
                    if (current.memo.isNotBlank()) Text(
                        current.memo, color = Color.White, fontSize = 14.sp,
                        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Color(0x99000000)).padding(12.dp),
                    )
                    Row(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalArrangement = Arrangement.SpaceEvenly) {
                        ViewerButton(Icons.Filled.Share, "共有") { share(context, listOf(current)) }
                        if (!current.isVideo) ViewerButton(Icons.Filled.TextFields, "文字・要点") { textFor = current }
                        ViewerButton(Icons.Filled.EditNote, "メモ") { memoFor = current }
                        ViewerButton(Icons.AutoMirrored.Filled.DriveFileMove, "移動") { moving = current }
                        ViewerButton(Icons.Filled.RemoveCircleOutline, "外す") { removing = current }
                        ViewerButton(Icons.Filled.Delete, "削除") {
                            trashed = current
                            trash.launch(IntentSenderRequest.Builder(MediaLibrary.trashRequest(context, listOf(Uri.parse(current.uri))).intentSender).build())
                        }
                    }
                }
            }
        }
    }
    textFor?.let { TextSheet(repo, it) { textFor = null } }
    memoFor?.let { it ->
        var text by remember(it.id) { mutableStateOf(it.memo) }
        AlertDialog(
            onDismissRequest = { memoFor = null },
            title = { Text("メモ", fontWeight = FontWeight.Black) },
            text = { OutlinedTextField(text, { text = it }, modifier = Modifier.fillMaxWidth().height(160.dp)) },
            confirmButton = { TextButton(onClick = { scope.launch { repo.dao.update(it.copy(memo = text)) }; memoFor = null }) { Text("保存", fontWeight = FontWeight.Bold) } },
            dismissButton = { TextButton(onClick = { memoFor = null }) { Text("キャンセル") } },
        )
    }
    moving?.let { it ->
        FolderChooserSheet("どのフォルダに移しますか？", categories, folders, excluding = it.folderId, onDismiss = { moving = null }) { dest ->
            scope.launch { repo.dao.update(it.copy(folderId = dest.id)) }; moving = null
        }
    }
    removing?.let { it ->
        ConfirmDialog("フォルダから外しますか？", "写真アプリ（ギャラリー）の写真は消えません。", "外す", onDismiss = { removing = null }) {
            scope.launch { repo.dao.delete(it) }; removing = null
        }
    }
}

@Composable
private fun ViewerButton(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, onClick: () -> Unit) {
    Column(Modifier.clip(RoundedCornerShape(12.dp)).clickable(onClick = onClick).padding(8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(icon, label, tint = Color.White)
        Text(label, color = Color.White, fontSize = 11.sp)
    }
}

/** ピンチで拡大・ダブルタップで拡大／元に戻す画像（拡大していないときは左右にめくれる） */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ZoomableImage(model: String, modifier: Modifier = Modifier) {
    var scale by remember(model) { mutableFloatStateOf(1f) }
    var offset by remember(model) { mutableStateOf(Offset.Zero) }
    val state = rememberTransformableState { zoom, pan, _ ->
        scale = (scale * zoom).coerceIn(1f, 5f)
        offset = if (scale == 1f) Offset.Zero else offset + pan
    }
    AsyncImage(
        model = model, contentDescription = null, contentScale = ContentScale.Fit,
        modifier = modifier
            .pointerInput(model) {
                detectTapGestures(onDoubleTap = {
                    if (scale > 1f) { scale = 1f; offset = Offset.Zero } else scale = 2.5f
                })
            }
            .transformable(state, canPan = { scale > 1f })
            .graphicsLayer { scaleX = scale; scaleY = scale; translationX = offset.x; translationY = offset.y },
    )
}
