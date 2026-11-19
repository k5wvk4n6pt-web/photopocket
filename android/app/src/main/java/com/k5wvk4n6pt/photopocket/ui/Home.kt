package com.k5wvk4n6pt.photopocket.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.SwapVert
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.k5wvk4n6pt.photopocket.R
import com.k5wvk4n6pt.photopocket.data.Category
import com.k5wvk4n6pt.photopocket.data.Folder
import com.k5wvk4n6pt.photopocket.data.Item
import com.k5wvk4n6pt.photopocket.data.Repo
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.util.Locale

@Composable
fun HomeScreen(
    repo: Repo,
    categories: List<Category>,
    folders: List<Folder>,
    items: List<Item>,
    onOpenCategory: (Long) -> Unit,
    onSorter: () -> Unit,
    onSettings: () -> Unit,
    onReorder: () -> Unit,
) {
    val p = LocalPalette.current
    val scope = rememberCoroutineScope()
    var adding by remember { mutableStateOf(false) }

    LazyVerticalGrid(
        columns = GridCells.Fixed(2),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(start = 18.dp, end = 18.dp, bottom = 110.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item(span = { GridItemSpan(2) }) { HomeHeader(onSettings) }
        item(span = { GridItemSpan(2) }) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                StatTile(Art.photoIcon(p), "${items.size}", "写真", Art.photos(p), if (p.blue) Color(0xFFE0EDFF) else Color(0xFFFFE6EB), Modifier.weight(1f))
                StatTile(Art.folder(p), "${folders.size}", "フォルダ", Art.folder(p), Color(0xFFFFF2D6), Modifier.weight(1f))
                StatTile(Art.badge(p), "フル版", "プラン", Art.crown(p), Color(0xFFE6EFFF), Modifier.weight(1f))
            }
        }
        item(span = { GridItemSpan(2) }) { SorterCard(onSorter) }
        item(span = { GridItemSpan(2) }) {
            Row(Modifier.padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                SectionTitle("分類", "${categories.size}こ")
                Spacer(Modifier.weight(1f))
                if (categories.isNotEmpty()) PillButton("編集・並び替え", Icons.Filled.SwapVert, onClick = onReorder)
                Spacer(Modifier.width(8.dp))
                PillButton("追加", Icons.Filled.Add, filled = true) { adding = true }
            }
        }
        if (categories.isEmpty()) {
            item(span = { GridItemSpan(2) }) {
                Column(
                    Modifier.fillMaxWidth().pocketCard(p).padding(20.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Image(painterResource(Art.folder(p)), null, Modifier.size(70.dp))
                    Text("まだ分類がありません", color = p.ink, fontWeight = FontWeight.Black)
                    Text("「家族」「旅行」など、写真を分ける大きなまとまりを作りましょう。", color = p.sub, fontSize = 13.sp)
                    PillButton("おすすめの分類で始める", filled = true) { scope.launch { repo.starterSet() } }
                }
            }
        }
        items(categories, key = { it.id }) { c ->
            val fs = folders.filter { it.categoryId == c.id }
            val ids = fs.map { it.id }.toSet()
            val its = items.filter { it.folderId in ids }
            CategoryCard(c, fs.size, its) { onOpenCategory(c.id) }
        }
    }

    if (adding) {
        NameColorDialog("分類を追加", "", "pink", "house", onDismiss = { adding = false }, onSave = { n, col, sym ->
            scope.launch { repo.addCategory(n, sym ?: "house", col, categories.size) }
            adding = false
        })
    }
}

@Composable
private fun HomeHeader(onSettings: () -> Unit) {
    val p = LocalPalette.current
    var menu by remember { mutableStateOf(false) }
    val date = LocalDate.now().format(DateTimeFormatter.ofPattern("M月d日 EEEE", Locale.JAPAN))
    val hour = LocalTime.now().hour
    val greeting = when (hour) { in 4..10 -> "おはよう"; in 11..17 -> "こんにちは"; else -> "こんばんは" }
    Box(Modifier.fillMaxWidth().statusBarsPadding()) {
        if (!p.blue) {
            Image(
                painterResource(R.drawable.deco_sprig), null,
                Modifier.size(96.dp).offset(x = (-40).dp, y = (-10).dp).rotate(-28f),
            )
        }
        Column {
            Row(Modifier.fillMaxWidth().height(44.dp), horizontalArrangement = Arrangement.End, verticalAlignment = Alignment.CenterVertically) {
                Box {
                    Icon(Icons.Filled.Palette, "色とモード", tint = p.ink, modifier = Modifier.size(40.dp).clip(RoundedCornerShape(50)).clickable { menu = true }.padding(9.dp))
                    DropdownMenu(menu, onDismissRequest = { menu = false }) {
                        DropdownMenuItem(text = { Text((if (!Prefs.blue) "✓ " else "　") + "ピンク") }, onClick = { Prefs.setBlue(false); menu = false })
                        DropdownMenuItem(text = { Text((if (Prefs.blue) "✓ " else "　") + "ブルー") }, onClick = { Prefs.setBlue(true); menu = false })
                        listOf("light" to "ライトモード", "dark" to "ダークモード", "system" to "端末に合わせる").forEach { (k, l) ->
                            DropdownMenuItem(text = { Text((if (Prefs.mode == k) "✓ " else "　") + l) }, onClick = { Prefs.setMode(k); menu = false })
                        }
                    }
                }
                Icon(Icons.Filled.Settings, "設定", tint = p.ink, modifier = Modifier.size(40.dp).clip(RoundedCornerShape(50)).clickable(onClick = onSettings).padding(9.dp))
            }
            Box(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(end = 110.dp)) {
                    Text("$date ・ $greeting", color = p.sub, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                    Text("フォトポケット", color = p.ink, fontSize = 30.sp, fontWeight = FontWeight.Black, maxLines = 1)
                    Box(Modifier.padding(top = 2.dp).width(200.dp).height(3.dp).clip(RoundedCornerShape(2.dp)).background(p.accent.copy(alpha = 0.35f)))
                }
                Image(painterResource(Art.photos(p)), null, Modifier.align(Alignment.TopEnd).size(84.dp).offset(x = 6.dp, y = (-22).dp))
                Image(painterResource(Art.camera(p)), null, Modifier.align(Alignment.TopEnd).size(72.dp).offset(x = (-44).dp, y = 8.dp))
            }
        }
    }
}

@Composable
private fun StatTile(icon: Int, value: String, label: String, deco: Int, tint: Color, modifier: Modifier) {
    val p = LocalPalette.current
    Box(modifier.pocketCard(p, 20.dp).background(Brush.linearGradient(listOf(Color.Transparent, tint.copy(alpha = if (p.dark) 0.15f else 0.9f)))).padding(12.dp)) {
        Column {
            Box(Modifier.size(30.dp).clip(RoundedCornerShape(10.dp)).background(tint), contentAlignment = Alignment.Center) {
                Image(painterResource(icon), null, Modifier.size(24.dp))
            }
            Spacer(Modifier.height(6.dp))
            Text(value, color = p.ink, fontSize = 21.sp, fontWeight = FontWeight.Black, maxLines = 1)
            Text(label, color = p.sub, fontSize = 12.sp)
        }
        Image(painterResource(deco), null, Modifier.align(Alignment.BottomEnd).size(46.dp).offset(x = 8.dp, y = 8.dp))
    }
}

@Composable
private fun SorterCard(onClick: () -> Unit) {
    val p = LocalPalette.current
    Box(Modifier.fillMaxWidth().padding(top = 14.dp)) {
        Row(
            Modifier.fillMaxWidth()
                .pocketCard(p, 24.dp)
                .background(Brush.horizontalGradient(listOf(p.sorterStart, p.sorterEnd)))
                .clickable(onClick = onClick)
                .padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Image(painterResource(Art.phone(p)), null, Modifier.size(width = 62.dp, height = 70.dp))
            Spacer(Modifier.width(8.dp))
            Column(Modifier.weight(1f)) {
                Text("写真を仕分ける", color = p.ink, fontSize = 17.sp, fontWeight = FontWeight.Black)
                Text("左で削除・右でフォルダへ。\nスワイプでどんどん整理", color = p.sub, fontSize = 12.sp, lineHeight = 17.sp)
            }
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = p.ink)
        }
        if (!p.blue) {
            Image(painterResource(R.drawable.deco_bear), null, Modifier.align(Alignment.TopEnd).size(width = 62.dp, height = 54.dp).offset(x = (-24).dp, y = (-30).dp))
        }
    }
}

@Composable
private fun CategoryCard(c: Category, folderCount: Int, items: List<Item>, onClick: () -> Unit) {
    val p = LocalPalette.current
    val accent = colorOf(c.colorName)
    Column(Modifier.pocketCard(p, 24.dp, tint = accent).clickable(onClick = onClick).padding(12.dp)) {
        Row(verticalAlignment = Alignment.Top) {
            CategoryIcon(c.symbol, accent, 42.dp)
            Spacer(Modifier.width(9.dp))
            Column(Modifier.weight(1f)) {
                Text(c.name, color = p.ink, fontSize = 17.sp, fontWeight = FontWeight.Black, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text("フォルダ${folderCount}つ・${items.size}枚", color = p.sub, fontSize = 11.sp, maxLines = 1)
            }
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = p.sub, modifier = Modifier.size(18.dp))
        }
        Spacer(Modifier.height(10.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            for (i in 0 until 3) {
                val it = items.getOrNull(i)
                if (it != null) MediaThumb(it.uri, it.isVideo, it.durationMs, Modifier.weight(1f).aspectRatio(1f), 8.dp)
                else Box(Modifier.weight(1f).aspectRatio(1f).clip(RoundedCornerShape(8.dp)).background(accent.copy(alpha = 0.08f)))
            }
        }
    }
}
