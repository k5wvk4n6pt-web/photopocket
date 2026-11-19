package com.k5wvk4n6pt.photopocket.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.SwapVert
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.k5wvk4n6pt.photopocket.data.Category
import com.k5wvk4n6pt.photopocket.data.Folder
import com.k5wvk4n6pt.photopocket.data.Item
import com.k5wvk4n6pt.photopocket.data.Repo
import kotlinx.coroutines.launch

@Composable
fun CategoryScreen(
    repo: Repo,
    category: Category,
    categories: List<Category>,
    allFolders: List<Folder>,
    items: List<Item>,
    onBack: () -> Unit,
    onOpenFolder: (Long) -> Unit,
) {
    val p = LocalPalette.current
    val scope = rememberCoroutineScope()
    val folders = allFolders.filter { it.categoryId == category.id }
    val accent = colorOf(category.colorName)
    var menu by remember { mutableStateOf(false) }
    var adding by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf<Folder?>(null) }
    var deleting by remember { mutableStateOf<Folder?>(null) }
    var moveSource by remember { mutableStateOf<Folder?>(null) }
    var reorder by remember { mutableStateOf(false) }
    var pickEdit by remember { mutableStateOf(false) }
    var pickDelete by remember { mutableStateOf(false) }

    Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(accent.copy(alpha = 0.16f), Color.Transparent), endY = 900f))) {
        LazyVerticalGrid(
            columns = GridCells.Fixed(2),
            contentPadding = PaddingValues(start = 18.dp, end = 18.dp, bottom = 110.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            item(span = { GridItemSpan(2) }) {
                Column(Modifier.statusBarsPadding()) {
                    Row(Modifier.fillMaxWidth().padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                        BackButton(onBack)
                        Spacer(Modifier.weight(1f))
                        Box {
                            CircleButton(Icons.Filled.MoreHoriz, "メニュー") { menu = true }
                            DropdownMenu(menu, { menu = false }) {
                                DropdownMenuItem(text = { Text("フォルダを追加") }, leadingIcon = { Icon(Icons.Filled.Add, null) }, onClick = { menu = false; adding = true })
                                DropdownMenuItem(text = { Text("フォルダを編集") }, leadingIcon = { Icon(Icons.Filled.Edit, null) }, enabled = folders.isNotEmpty(), onClick = { menu = false; pickEdit = true })
                                DropdownMenuItem(text = { Text("フォルダを並び替え") }, leadingIcon = { Icon(Icons.Filled.SwapVert, null) }, enabled = folders.size > 1, onClick = { menu = false; reorder = true })
                                DropdownMenuItem(text = { Text("フォルダを削除") }, leadingIcon = { Icon(Icons.Filled.Delete, null) }, enabled = folders.isNotEmpty(), onClick = { menu = false; pickDelete = true })
                            }
                        }
                    }
                    Row(Modifier.padding(top = 14.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                        CategoryIcon(category.symbol, accent, 56.dp)
                        Spacer(Modifier.width(12.dp))
                        Column {
                            Text(category.name, color = p.ink, fontSize = 28.sp, fontWeight = FontWeight.Black)
                            Text("フォルダ${folders.size}つ・${items.count { i -> folders.any { it.id == i.folderId } }}枚", color = p.sub, fontSize = 13.sp)
                        }
                    }
                }
            }
            items(folders, key = { it.id }) { f ->
                FolderCard(f, items.filter { it.folderId == f.id }) { onOpenFolder(f.id) }
            }
            item {
                Column(
                    Modifier.aspectRatio(0.95f).clip(RoundedCornerShape(22.dp))
                        .background(p.card.copy(alpha = 0.5f)).clickable { adding = true },
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center,
                ) {
                    Box(Modifier.size(48.dp).clip(RoundedCornerShape(50)).background(p.accent), contentAlignment = Alignment.Center) {
                        Icon(Icons.Filled.Add, null, tint = Color.White)
                    }
                    Spacer(Modifier.height(10.dp))
                    Text("フォルダを追加", color = p.ink, fontWeight = FontWeight.Bold)
                }
            }
        }
    }

    if (adding) NameColorDialog("フォルダを追加", "", category.colorName, null, { adding = false }, { n, c, _ ->
        scope.launch { repo.addFolder(category.id, n, c, folders.size) }; adding = false
    })
    editing?.let { f ->
        NameColorDialog("フォルダを編集", f.name, f.colorName, null, { editing = null }, { n, c, _ ->
            scope.launch { repo.dao.update(f.copy(name = n, colorName = c)) }; editing = null
        }, onDelete = { editing = null; deleting = f })
    }
    if (pickEdit || pickDelete) {
        FolderChooserSheet(
            title = if (pickEdit) "どのフォルダを編集しますか？" else "どのフォルダを削除しますか？",
            categories = listOf(category), folders = folders,
            onDismiss = { pickEdit = false; pickDelete = false },
        ) { f -> if (pickEdit) editing = f else deleting = f; pickEdit = false; pickDelete = false }
    }
    deleting?.let { f ->
        val count = items.count { it.folderId == f.id }
        if (count == 0) {
            ConfirmDialog("フォルダ「${f.name}」を削除しますか？", "このフォルダは空です。", "削除", onDismiss = { deleting = null }) {
                scope.launch { repo.deleteFolder(f, null) }; deleting = null
            }
        } else {
            ConfirmDialog(
                "フォルダ「${f.name}」を削除しますか？",
                "中に写真が${count}枚あります。写真アプリ（ギャラリー）の写真は消えません。フォルダ分けを残したいときは、別のフォルダに移してから削除してください。",
                "フォルダだけ削除",
                onDismiss = { deleting = null },
                onConfirm = { scope.launch { repo.deleteFolder(f, null) }; deleting = null },
                extra = {
                    if (allFolders.size > 1) TextButton(onClick = { moveSource = f; deleting = null }) {
                        Text("写真を別のフォルダに移してから削除", fontWeight = FontWeight.Bold)
                    }
                },
            )
        }
    }
    moveSource?.let { src ->
        FolderChooserSheet("写真をどのフォルダに移しますか？", categories, allFolders, excluding = src.id, onDismiss = { moveSource = null }) { dest ->
            scope.launch { repo.deleteFolder(src, dest.id) }; moveSource = null
        }
    }
    if (reorder) ReorderDialog("フォルダを並び替え", folders.map { it.name }, { reorder = false }) { order ->
        scope.launch { repo.dao.updateFolders(order.mapIndexed { i, idx -> folders[idx].copy(sortOrder = i) }) }
        reorder = false
    }
}

@Composable
private fun FolderCard(f: Folder, items: List<Item>, onClick: () -> Unit) {
    val p = LocalPalette.current
    val color = colorOf(f.colorName)
    Column(Modifier.pocketCard(p, 22.dp).clickable(onClick = onClick).padding(12.dp)) {
        Box(Modifier.fillMaxWidth().aspectRatio(1.25f)) {
            Box(Modifier.fillMaxSize().padding(top = 12.dp).clip(RoundedCornerShape(16.dp)).background(color.copy(alpha = 0.85f)))
            val first = items.firstOrNull()
            if (first != null) {
                MediaThumb(first.uri, first.isVideo, first.durationMs,
                    Modifier.align(Alignment.TopCenter).fillMaxWidth(0.55f).aspectRatio(0.8f).offset(y = (-4).dp), 6.dp)
            } else {
                Image(painterResource(Art.photos(p)), null, Modifier.align(Alignment.Center).size(64.dp))
            }
            Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(40.dp).clip(RoundedCornerShape(14.dp)).background(color))
        }
        Spacer(Modifier.height(8.dp))
        Text(f.name, color = p.ink, fontSize = 17.sp, fontWeight = FontWeight.Black, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text("${items.size}枚", color = p.sub, fontSize = 13.sp)
    }
}

/** 上下の矢印で並び替えるダイアログ（並び順の番号リストを返す） */
@Composable
fun ReorderDialog(title: String, names: List<String>, onDismiss: () -> Unit, onSave: (List<Int>) -> Unit) {
    val p = LocalPalette.current
    var order by remember { mutableStateOf(names.indices.toList()) }
    androidx.compose.material3.AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title, fontWeight = FontWeight.Black) },
        text = {
            LazyColumn(Modifier.height(380.dp)) {
                itemsIndexed(order) { pos, idx ->
                    Row(Modifier.fillMaxWidth().padding(vertical = 2.dp).clip(RoundedCornerShape(12.dp)).background(p.soft).padding(horizontal = 10.dp, vertical = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(names[idx], color = p.ink, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f), maxLines = 1)
                        IconButton(enabled = pos > 0, onClick = { order = order.toMutableList().also { val t = it[pos]; it[pos] = it[pos - 1]; it[pos - 1] = t } }) { Icon(Icons.Filled.KeyboardArrowUp, "上へ") }
                        IconButton(enabled = pos < order.size - 1, onClick = { order = order.toMutableList().also { val t = it[pos]; it[pos] = it[pos + 1]; it[pos + 1] = t } }) { Icon(Icons.Filled.KeyboardArrowDown, "下へ") }
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = { onSave(order) }) { Text("完了", fontWeight = FontWeight.Bold) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("キャンセル") } },
    )
}
