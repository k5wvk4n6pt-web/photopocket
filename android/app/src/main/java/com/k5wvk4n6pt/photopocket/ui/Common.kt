package com.k5wvk4n6pt.photopocket.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.k5wvk4n6pt.photopocket.data.Category
import com.k5wvk4n6pt.photopocket.data.Folder
import com.k5wvk4n6pt.photopocket.data.formatDuration

/** 画面の背景（上から下へのやさしいグラデーション） */
@Composable
fun Backdrop(content: @Composable () -> Unit) {
    val p = LocalPalette.current
    Box(
        Modifier
            .fillMaxSize()
            .background(Brush.verticalGradient(listOf(p.bgTop, p.bgBottom)))
    ) { content() }
}

/** 白いカード（枠線と影つき） */
fun Modifier.pocketCard(p: Palette, radius: Dp = 22.dp, tint: Color? = null): Modifier {
    val shape = RoundedCornerShape(radius)
    val base = this
        .shadow(6.dp, shape, ambientColor = Color(0x22733F33), spotColor = Color(0x22733F33))
        .clip(shape)
        .background(p.card)
    val tinted = if (tint != null) base.background(
        Brush.linearGradient(listOf(tint.copy(alpha = 0.04f), tint.copy(alpha = 0.16f)))
    ) else base
    return tinted.border(BorderStroke(1.5.dp, tint?.copy(alpha = 0.45f) ?: p.stroke), shape)
}

@Composable
fun CircleButton(icon: ImageVector, desc: String, onClick: () -> Unit) {
    val p = LocalPalette.current
    Box(
        Modifier
            .size(42.dp)
            .shadow(4.dp, CircleShape)
            .clip(CircleShape)
            .background(p.card)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { Icon(icon, desc, tint = p.ink) }
}

@Composable
fun BackButton(onBack: () -> Unit) = CircleButton(Icons.AutoMirrored.Filled.ArrowBack, "戻る", onBack)

@Composable
fun PillButton(text: String, icon: ImageVector? = null, filled: Boolean = false, onClick: () -> Unit) {
    val p = LocalPalette.current
    Row(
        Modifier
            .clip(RoundedCornerShape(50))
            .background(if (filled) p.accent else p.card)
            .border(1.dp, if (filled) Color.Transparent else p.stroke, RoundedCornerShape(50))
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        if (icon != null) Icon(icon, null, tint = if (filled) Color.White else p.ink, modifier = Modifier.size(16.dp))
        Text(text, color = if (filled) Color.White else p.ink, fontWeight = FontWeight.Bold, fontSize = 13.sp)
    }
}

/** 分類のアイコン（イラストがあればイラスト、なければマーク） */
@Composable
fun CategoryIcon(symbol: String, color: Color, size: Dp) {
    val p = LocalPalette.current
    val s = symbolOf(symbol)
    val art = if (p.blue) s.blueArt else s.pinkArt
    Box(
        Modifier.size(size).clip(RoundedCornerShape(size * 0.32f)).background(color.copy(alpha = 0.16f)),
        contentAlignment = Alignment.Center,
    ) {
        when {
            art != null -> Image(painterResource(art), null, Modifier.size(size * 0.72f))
            s.icon != null -> Icon(s.icon, null, tint = color, modifier = Modifier.size(size * 0.55f))
        }
    }
}

/** 写真・動画のサムネイル */
@Composable
fun MediaThumb(uri: String, isVideo: Boolean, durationMs: Long, modifier: Modifier = Modifier, radius: Dp = 10.dp) {
    Box(modifier.clip(RoundedCornerShape(radius)).background(Color(0x14000000))) {
        AsyncImage(
            model = uri, contentDescription = null, contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize(),
        )
        if (isVideo) {
            Row(
                Modifier
                    .align(Alignment.BottomEnd)
                    .padding(4.dp)
                    .clip(RoundedCornerShape(50))
                    .background(Color(0x8C000000))
                    .padding(horizontal = 5.dp, vertical = 1.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Filled.PlayArrow, null, tint = Color.White, modifier = Modifier.size(10.dp))
                Text(formatDuration(durationMs), color = Color.White, fontSize = 10.sp, fontWeight = FontWeight.Bold)
            }
        }
    }
}

@Composable
fun SectionTitle(text: String, sub: String? = null) {
    val p = LocalPalette.current
    Row(verticalAlignment = Alignment.Bottom) {
        Text(text, color = p.ink, fontSize = 20.sp, fontWeight = FontWeight.Black)
        if (sub != null) {
            Spacer(Modifier.width(6.dp))
            Text(sub, color = p.sub, fontSize = 13.sp)
        }
    }
}

// MARK: - 入力ダイアログ

@Composable
fun NameColorDialog(
    title: String,
    initialName: String,
    initialColor: String,
    initialSymbol: String?,       // nullならアイコンの選択を出さない
    onDismiss: () -> Unit,
    onSave: (name: String, color: String, symbol: String?) -> Unit,
    onDelete: (() -> Unit)? = null,
) {
    val p = LocalPalette.current
    var name by remember { mutableStateOf(initialName) }
    var color by remember { mutableStateOf(initialColor) }
    var symbol by remember { mutableStateOf(initialSymbol) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title, fontWeight = FontWeight.Black) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(name, { name = it }, label = { Text("名前") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                Text("色", fontWeight = FontWeight.Bold, color = p.sub, fontSize = 13.sp)
                LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(namedColors) { (key, c) ->
                        Box(
                            Modifier.size(30.dp).clip(CircleShape).background(c)
                                .border(3.dp, if (key == color) p.ink else Color.Transparent, CircleShape)
                                .clickable { color = key },
                            contentAlignment = Alignment.Center,
                        ) { if (key == color) Icon(Icons.Filled.Check, null, tint = Color.White, modifier = Modifier.size(16.dp)) }
                    }
                }
                if (symbol != null) {
                    Text("アイコン", fontWeight = FontWeight.Bold, color = p.sub, fontSize = 13.sp)
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        items(categorySymbols) { s ->
                            Box(
                                Modifier.clip(RoundedCornerShape(14.dp))
                                    .border(2.dp, if (s.key == symbol) p.accent else Color.Transparent, RoundedCornerShape(14.dp))
                                    .clickable { symbol = s.key }
                                    .padding(3.dp)
                            ) { CategoryIcon(s.key, colorOf(color), 40.dp) }
                        }
                    }
                }
                if (onDelete != null) {
                    TextButton(onClick = onDelete) { Text("削除する", color = Color(0xFFE5484D), fontWeight = FontWeight.Bold) }
                }
            }
        },
        confirmButton = {
            TextButton(enabled = name.isNotBlank(), onClick = { onSave(name.trim(), color, symbol) }) {
                Text("保存", fontWeight = FontWeight.Bold)
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("キャンセル") } },
    )
}

@Composable
fun ConfirmDialog(
    title: String, message: String, confirm: String, destructive: Boolean = true,
    onDismiss: () -> Unit,
    extra: (@Composable () -> Unit)? = null,
    onConfirm: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title, fontWeight = FontWeight.Black) },
        text = { Column { Text(message); extra?.invoke() } },
        confirmButton = {
            TextButton(onClick = onConfirm) {
                Text(confirm, color = if (destructive) Color(0xFFE5484D) else LocalPalette.current.accent, fontWeight = FontWeight.Bold)
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("キャンセル") } },
    )
}

/** フォルダを選ぶシート（分類ごとに並べる） */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FolderChooserSheet(
    title: String,
    categories: List<Category>,
    folders: List<Folder>,
    excluding: Long? = null,
    onDismiss: () -> Unit,
    onNewFolder: (() -> Unit)? = null,
    onPick: (Folder) -> Unit,
) {
    val p = LocalPalette.current
    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = p.bgBottom) {
        Text(title, color = p.ink, fontWeight = FontWeight.Black, fontSize = 18.sp, modifier = Modifier.padding(horizontal = 20.dp))
        LazyColumn(Modifier.fillMaxWidth().height(460.dp), contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp)) {
            val groups = categories.map { c -> c.name to folders.filter { it.categoryId == c.id && it.id != excluding } } +
                listOf("分類なし" to folders.filter { f -> f.id != excluding && categories.none { it.id == f.categoryId } })
            groups.filter { it.second.isNotEmpty() }.forEach { (name, list) ->
                item { Text(name, color = p.sub, fontWeight = FontWeight.Bold, fontSize = 13.sp, modifier = Modifier.padding(top = 10.dp, bottom = 4.dp)) }
                items(list) { f ->
                    Row(
                        Modifier.fillMaxWidth().padding(vertical = 3.dp).pocketCard(p, 14.dp)
                            .clickable { onPick(f) }.padding(14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Filled.Folder, null, tint = colorOf(f.colorName))
                        Spacer(Modifier.width(10.dp))
                        Text(f.name, color = p.ink, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
            if (onNewFolder != null) item {
                Row(
                    Modifier.fillMaxWidth().padding(top = 12.dp).clip(RoundedCornerShape(14.dp))
                        .background(p.soft).clickable { onNewFolder() }.padding(14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Filled.Add, null, tint = p.accent)
                    Spacer(Modifier.width(8.dp))
                    Text("新しいフォルダを作る", color = p.accent, fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}
