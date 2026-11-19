package com.k5wvk4n6pt.photopocket

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil.Coil
import coil.ImageLoader
import coil.decode.VideoFrameDecoder
import com.k5wvk4n6pt.photopocket.data.Repo
import com.k5wvk4n6pt.photopocket.ui.AllFoldersScreen
import com.k5wvk4n6pt.photopocket.ui.AllPhotosScreen
import com.k5wvk4n6pt.photopocket.ui.BackButton
import com.k5wvk4n6pt.photopocket.ui.Backdrop
import com.k5wvk4n6pt.photopocket.ui.CategoryManageDialog
import com.k5wvk4n6pt.photopocket.ui.CategoryScreen
import com.k5wvk4n6pt.photopocket.ui.FolderScreen
import com.k5wvk4n6pt.photopocket.ui.HomeScreen
import com.k5wvk4n6pt.photopocket.ui.LocalPalette
import com.k5wvk4n6pt.photopocket.ui.PocketTheme
import com.k5wvk4n6pt.photopocket.ui.Prefs
import com.k5wvk4n6pt.photopocket.ui.SorterScreen
import com.k5wvk4n6pt.photopocket.ui.TabBar
import com.k5wvk4n6pt.photopocket.ui.pocketCard

/** 今どの画面を開いているか */
sealed class Screen {
    data object Tabs : Screen()
    data class CategoryS(val id: Long) : Screen()
    data class FolderS(val id: Long) : Screen()
    data object Sorter : Screen()
    data object SettingsS : Screen()
}

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        Prefs.init(this)
        Coil.setImageLoader(
            ImageLoader.Builder(this)
                .components { add(VideoFrameDecoder.Factory()) }
                .crossfade(true)
                .build()
        )
        val repo = Repo(this)
        setContent {
            PocketTheme {
                Backdrop { App(repo) }
            }
        }
    }
}

@Composable
fun App(repo: Repo) {
    val categories by repo.categories.collectAsStateWithLifecycle(emptyList())
    val folders by repo.folders.collectAsStateWithLifecycle(emptyList())
    val items by repo.items.collectAsStateWithLifecycle(emptyList())
    var stack by remember { mutableStateOf(listOf<Screen>(Screen.Tabs)) }
    var tab by rememberSaveable { mutableStateOf(0) }
    var manageCategories by remember { mutableStateOf(false) }

    fun push(s: Screen) { stack = stack + s }
    fun pop() { if (stack.size > 1) stack = stack.dropLast(1) }
    BackHandler(enabled = stack.size > 1) { pop() }

    when (val s = stack.last()) {
        is Screen.Tabs -> Box(Modifier.fillMaxSize()) {
            when (tab) {
                0 -> HomeScreen(
                    repo, categories, folders, items,
                    onOpenCategory = { push(Screen.CategoryS(it)) },
                    onSorter = { push(Screen.Sorter) },
                    onSettings = { push(Screen.SettingsS) },
                    onReorder = { manageCategories = true },
                    onTab = { tab = it },
                )
                1 -> AllPhotosScreen(repo, items, categories, folders, recent = false)
                2 -> AllFoldersScreen(categories, folders, items) { push(Screen.FolderS(it)) }
                else -> AllPhotosScreen(repo, items, categories, folders, recent = true)
            }
            TabBar(tab, { tab = it }, Modifier.align(Alignment.BottomCenter))
        }
        is Screen.CategoryS -> {
            val c = categories.firstOrNull { it.id == s.id }
            if (c == null) androidx.compose.runtime.LaunchedEffect(Unit) { pop() } else CategoryScreen(repo, c, categories, folders, items, ::pop) { push(Screen.FolderS(it)) }
        }
        is Screen.FolderS -> {
            val f = folders.firstOrNull { it.id == s.id }
            if (f == null) androidx.compose.runtime.LaunchedEffect(Unit) { pop() } else FolderScreen(repo, f, categories, folders, items, ::pop)
        }
        is Screen.Sorter -> SorterScreen(repo, categories, folders, items, ::pop)
        is Screen.SettingsS -> SettingsScreen(folders.size, items.size, ::pop)
    }
    if (manageCategories) CategoryManageDialog(repo, categories) { manageCategories = false }
}

@Composable
fun SettingsScreen(folderCount: Int, itemCount: Int, onBack: () -> Unit) {
    val p = LocalPalette.current
    val context = LocalContext.current
    Column(Modifier.fillMaxSize().statusBarsPadding().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            BackButton(onBack)
            Spacer(Modifier.weight(1f))
        }
        Text("設定", color = p.ink, fontSize = 28.sp, fontWeight = FontWeight.Black)

        Section("色のテーマ") {
            Choice(listOf(false to "ピンク", true to "ブルー"), Prefs.blue) { Prefs.updateBlue(it) }
        }
        Section("画面のモード") {
            Choice(listOf("light" to "ライト", "dark" to "ダーク", "system" to "端末に合わせる"), Prefs.mode) { Prefs.updateMode(it) }
        }
        Section("仕分けの並び順") {
            Choice(listOf(true to "保存した順", false to "撮影日順"), Prefs.sortByAdded) { Prefs.updateSortByAdded(it) }
        }
        Section("保存状況") {
            Text("フォルダ：${folderCount}つ", color = p.ink)
            Text("フォルダの写真：${itemCount}枚", color = p.ink)
        }
        Section("写真について") {
            Text(
                "写真の本体はギャラリー（写真アプリ）に残したまま、フォルダに並べます。アプリを削除しても写真は消えません。" +
                    "ギャラリーから削除するときは確認画面が出て、ゴミ箱に30日間残ります。",
                color = p.sub, fontSize = 13.sp,
            )
            Text(
                "写真へのアクセス設定を開く", color = p.accent, fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(top = 8.dp).clickable {
                    context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null)))
                },
            )
        }
        Text("フォトポケット Android版 ${BuildConfigCompat.version(context)}", color = p.sub, fontSize = 12.sp)
    }
}

@Composable
private fun Section(title: String, content: @Composable () -> Unit) {
    val p = LocalPalette.current
    Column {
        Text(title, color = p.ink, fontWeight = FontWeight.Black, fontSize = 15.sp, modifier = Modifier.padding(bottom = 6.dp))
        Column(Modifier.fillMaxWidth().pocketCard(p, 18.dp).padding(14.dp)) { content() }
    }
}

@Composable
private fun <T> Choice(options: List<Pair<T, String>>, current: T, onPick: (T) -> Unit) {
    val p = LocalPalette.current
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        options.forEach { (v, label) ->
            val on = v == current
            Text(
                label, color = if (on) androidx.compose.ui.graphics.Color.White else p.ink, fontWeight = FontWeight.Bold, fontSize = 13.sp,
                modifier = Modifier
                    .clickable { onPick(v) }
                    .let { m -> if (on) m.pocketCard(p.copy(card = p.accent), 50.dp) else m.pocketCard(p, 50.dp) }
                    .padding(horizontal = 14.dp, vertical = 8.dp),
            )
        }
    }
}

object BuildConfigCompat {
    fun version(context: android.content.Context): String = runCatching {
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        "${info.versionName} (${info.longVersionCode})"
    }.getOrDefault("")
}
