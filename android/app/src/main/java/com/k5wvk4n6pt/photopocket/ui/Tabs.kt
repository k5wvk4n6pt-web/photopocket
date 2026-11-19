package com.k5wvk4n6pt.photopocket.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.AlertDialog
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
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.k5wvk4n6pt.photopocket.data.Category
import com.k5wvk4n6pt.photopocket.data.Folder
import com.k5wvk4n6pt.photopocket.data.Item
import com.k5wvk4n6pt.photopocket.data.Repo
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId

/** 下のタブ */
@Composable
fun TabBar(tab: Int, onTab: (Int) -> Unit, modifier: Modifier = Modifier) {
    val p = LocalPalette.current
    val tabs = listOf(Icons.Filled.Home to "ホーム", Icons.Filled.PhotoLibrary to "すべての写真", Icons.Filled.Folder to "フォルダ", Icons.Filled.Schedule to "最近の写真")
    Row(
        modifier.navigationBarsPadding().padding(horizontal = 14.dp, vertical = 10.dp).fillMaxWidth()
            .shadow(8.dp, RoundedCornerShape(32.dp)).clip(RoundedCornerShape(32.dp)).background(p.card).padding(6.dp),
        horizontalArrangement = Arrangement.SpaceAround,
    ) {
        tabs.forEachIndexed { i, (icon, label) ->
            Column(
                Modifier.clip(RoundedCornerShape(24.dp)).background(if (i == tab) p.soft else Color.Transparent)
                    .clickable { onTab(i) }.padding(horizontal = 12.dp, vertical = 6.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Icon(icon, label, tint = if (i == tab) p.accent else p.ink, modifier = Modifier.size(22.dp))
                Text(label, color = if (i == tab) p.accent else p.ink, fontSize = 10.sp, fontWeight = FontWeight.Bold)
            }
        }
    }
}

/** すべての写真（月ごと）／最近入れた写真 */
@Composable
fun AllPhotosScreen(repo: Repo, items: List<Item>, categories: List<Category>, folders: List<Folder>, recent: Boolean) {
    val p = LocalPalette.current
    val list = if (recent) items.sortedByDescending { it.addedAt }.take(60) else items.distinctBy { it.mediaId }
    var viewer by remember { mutableStateOf<Int?>(null) }
    val groups = if (recent) listOf("" to list) else list.groupBy {
        val d = Instant.ofEpochMilli(it.takenAt).atZone(ZoneId.systemDefault())
        "${d.year}年${d.monthValue}月"
    }.toList()
    LazyVerticalGrid(
        columns = GridCells.Fixed(3),
        contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 110.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        item(span = { GridItemSpan(3) }) {
            Column(Modifier.statusBarsPadding().padding(top = 16.dp, bottom = 8.dp)) {
                Text(if (recent) "最近の写真" else "すべての写真", color = p.ink, fontSize = 28.sp, fontWeight = FontWeight.Black)
                Text(if (recent) "最近フォルダに入れた写真" else "${list.size}枚", color = p.sub, fontSize = 13.sp)
            }
        }
        if (list.isEmpty()) item(span = { GridItemSpan(3) }) {
            Text("まだ写真がありません。分類とフォルダを作って、写真を入れましょう。", color = p.sub, modifier = Modifier.padding(top = 20.dp))
        }
        groups.forEach { (title, its) ->
            if (title.isNotEmpty()) item(span = { GridItemSpan(3) }) {
                Text(title, color = p.ink, fontWeight = FontWeight.Black, fontSize = 16.sp, modifier = Modifier.padding(top = 10.dp))
            }
            items(its, key = { "${title}_${it.id}" }) { it ->
                MediaThumb(it.uri, it.isVideo, it.durationMs, Modifier.aspectRatio(1f).clickable { viewer = list.indexOf(it) })
            }
        }
    }
    viewer?.let { ItemViewer(repo, list, it, categories, folders) { viewer = null } }
}

/** すべてのフォルダ */
@Composable
fun AllFoldersScreen(categories: List<Category>, folders: List<Folder>, items: List<Item>, onOpen: (Long) -> Unit) {
    val p = LocalPalette.current
    LazyColumn(contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 110.dp)) {
        item {
            Column(Modifier.statusBarsPadding().padding(top = 16.dp, bottom = 8.dp)) {
                Text("フォルダ", color = p.ink, fontSize = 28.sp, fontWeight = FontWeight.Black)
                Text("${folders.size}つ", color = p.sub, fontSize = 13.sp)
            }
        }
        val groups = categories.map { c -> c.name to folders.filter { it.categoryId == c.id } } +
            listOf("分類なし" to folders.filter { f -> categories.none { it.id == f.categoryId } })
        groups.filter { it.second.isNotEmpty() }.forEach { (name, list) ->
            item { Text(name, color = p.sub, fontWeight = FontWeight.Bold, fontSize = 13.sp, modifier = Modifier.padding(top = 14.dp, bottom = 4.dp)) }
            items(list, key = { it.id }) { f ->
                val its = items.filter { it.folderId == f.id }
                Row(
                    Modifier.fillMaxWidth().padding(vertical = 4.dp).pocketCard(p, 18.dp).clickable { onOpen(f.id) }.padding(10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    val first = its.firstOrNull()
                    if (first != null) MediaThumb(first.uri, first.isVideo, first.durationMs, Modifier.size(52.dp))
                    else Icon(Icons.Filled.Folder, null, tint = colorOf(f.colorName), modifier = Modifier.size(52.dp))
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(f.name, color = p.ink, fontWeight = FontWeight.Black)
                        Text("${its.size}枚", color = p.sub, fontSize = 12.sp)
                    }
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = p.sub)
                }
            }
        }
    }
}

/** 分類の編集・並び替え */
@Composable
fun CategoryManageDialog(repo: Repo, categories: List<Category>, onDismiss: () -> Unit) {
    val p = LocalPalette.current
    val scope = rememberCoroutineScope()
    var order by remember(categories) { mutableStateOf(categories) }
    var editing by remember { mutableStateOf<Category?>(null) }
    var deleting by remember { mutableStateOf<Category?>(null) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("分類の編集・並び替え", fontWeight = FontWeight.Black) },
        text = {
            LazyColumn(Modifier.height(400.dp)) {
                itemsIndexed(order, key = { _, c -> c.id }) { pos, c ->
                    Row(
                        Modifier.fillMaxWidth().padding(vertical = 3.dp).clip(RoundedCornerShape(12.dp)).background(p.soft).padding(start = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        CategoryIcon(c.symbol, colorOf(c.colorName), 32.dp)
                        Spacer(Modifier.width(8.dp))
                        Text(c.name, color = p.ink, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f), maxLines = 1)
                        IconButton(onClick = { editing = c }) { Icon(Icons.Filled.Edit, "編集", tint = p.ink) }
                        IconButton(enabled = pos > 0, onClick = { order = order.toMutableList().also { val t = it[pos]; it[pos] = it[pos - 1]; it[pos - 1] = t } }) { Icon(Icons.Filled.KeyboardArrowUp, "上へ") }
                        IconButton(enabled = pos < order.size - 1, onClick = { order = order.toMutableList().also { val t = it[pos]; it[pos] = it[pos + 1]; it[pos + 1] = t } }) { Icon(Icons.Filled.KeyboardArrowDown, "下へ") }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = {
                scope.launch { repo.dao.updateCategories(order.mapIndexed { i, c -> c.copy(sortOrder = i) }) }
                onDismiss()
            }) { Text("完了", fontWeight = FontWeight.Bold) }
        },
    )
    editing?.let { c ->
        NameColorDialog("分類を編集", c.name, c.colorName, c.symbol, { editing = null }, { n, col, sym ->
            scope.launch { repo.dao.update(c.copy(name = n, colorName = col, symbol = sym ?: c.symbol)) }; editing = null
        }, onDelete = { editing = null; deleting = c })
    }
    deleting?.let { c ->
        ConfirmDialog("分類「${c.name}」を削除しますか？", "中のフォルダと写真は消えず、「分類なし」に移ります。", "削除", onDismiss = { deleting = null }) {
            scope.launch { repo.deleteCategory(c) }; deleting = null
        }
    }
}
