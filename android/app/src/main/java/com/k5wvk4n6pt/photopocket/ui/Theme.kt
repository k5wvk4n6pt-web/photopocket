package com.k5wvk4n6pt.photopocket.ui

import android.content.Context
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoStories
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Flight
import androidx.compose.material.icons.filled.LocalFlorist
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.School
import androidx.compose.material.icons.filled.SportsSoccer
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import com.k5wvk4n6pt.photopocket.R

/** アプリの設定（端末に保存） */
object Prefs {
    private lateinit var ctx: Context
    private val sp get() = ctx.getSharedPreferences("prefs", Context.MODE_PRIVATE)

    var blue by mutableStateOf(false)
        private set
    var mode by mutableStateOf("light")   // light / dark / system
        private set
    var sortByAdded by mutableStateOf(true)
        private set
    var gridMode by mutableStateOf(false)
        private set

    fun init(context: Context) {
        ctx = context.applicationContext
        blue = sp.getBoolean("blue", false)
        mode = sp.getString("mode", "light") ?: "light"
        sortByAdded = sp.getBoolean("sortByAdded", true)
        gridMode = sp.getBoolean("gridMode", false)
    }

    fun setBlue(v: Boolean) { blue = v; sp.edit().putBoolean("blue", v).apply() }
    fun setMode(v: String) { mode = v; sp.edit().putString("mode", v).apply() }
    fun setSortByAdded(v: Boolean) { sortByAdded = v; sp.edit().putBoolean("sortByAdded", v).apply() }
    fun setGridMode(v: Boolean) { gridMode = v; sp.edit().putBoolean("gridMode", v).apply() }
}

data class Palette(
    val accent: Color,
    val soft: Color,
    val ink: Color,
    val sub: Color,
    val bgTop: Color,
    val bgBottom: Color,
    val card: Color,
    val stroke: Color,
    val sorterStart: Color,
    val sorterEnd: Color,
    val dark: Boolean,
    val blue: Boolean,
)

val LocalPalette = staticCompositionLocalOf { pinkLight }

private val pinkLight = Palette(
    accent = Color(0xFFF2668A), soft = Color(0xFFFFE5EC), ink = Color(0xFF5C3B21), sub = Color(0xFF9C8475),
    bgTop = Color(0xFFFFE8DE), bgBottom = Color(0xFFFFF5F0), card = Color(0xF5FFFFFF),
    stroke = Color(0x8CEB9EA8), sorterStart = Color(0xFFFFEDED), sorterEnd = Color(0xFFFFDBE3),
    dark = false, blue = false,
)
private val blueLight = Palette(
    accent = Color(0xFF337ADB), soft = Color(0xFFE0EDFF), ink = Color(0xFF243A61), sub = Color(0xFF7A8BA6),
    bgTop = Color(0xFFD6E8FF), bgBottom = Color(0xFFF5FAFF), card = Color(0xF5FFFFFF),
    stroke = Color(0x8C8CB3EB), sorterStart = Color(0xFFEBF2FF), sorterEnd = Color(0xFFD6E6FF),
    dark = false, blue = true,
)
private fun darkOf(p: Palette) = p.copy(
    soft = if (p.blue) Color(0xFF1F2E47) else Color(0xFF4A2630),
    ink = Color(0xFFF2EEE6), sub = Color(0xFFB0A69C),
    bgTop = if (p.blue) Color(0xFF121A26) else Color(0xFF1F1717),
    bgBottom = Color(0xFF141312), card = Color(0xF52B2624),
    stroke = Color(0x24FFFFFF), sorterStart = Color(0xFF2B2624), sorterEnd = Color(0xFF332B29),
    dark = true,
)

@Composable
fun PocketTheme(content: @Composable () -> Unit) {
    val dark = when (Prefs.mode) {
        "dark" -> true
        "system" -> isSystemInDarkTheme()
        else -> false
    }
    val base = if (Prefs.blue) blueLight else pinkLight
    val p = if (dark) darkOf(base) else base
    val scheme = if (dark) darkColorScheme(primary = p.accent, background = p.bgBottom, surface = p.card, onBackground = p.ink, onSurface = p.ink)
                 else lightColorScheme(primary = p.accent, background = p.bgBottom, surface = Color.White, onBackground = p.ink, onSurface = p.ink)
    CompositionLocalProvider(LocalPalette provides p) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}

/** 分類やフォルダの色 */
val namedColors: List<Pair<String, Color>> = listOf(
    "pink" to Color(0xFFEB5C85), "red" to Color(0xFFE05252), "orange" to Color(0xFFEB8C33),
    "yellow" to Color(0xFFE0B020), "green" to Color(0xFF4DAF6A), "mint" to Color(0xFF2FB5A3),
    "blue" to Color(0xFF3D8BE0), "purple" to Color(0xFF7A5AD8), "brown" to Color(0xFF9C6B4A),
)

fun colorOf(name: String): Color = namedColors.firstOrNull { it.first == name }?.second ?: namedColors[0].second

/** 分類のアイコン */
data class CategorySymbol(val key: String, val label: String, val pinkArt: Int?, val blueArt: Int?, val icon: ImageVector?)

val categorySymbols = listOf(
    CategorySymbol("house", "おうち", R.drawable.cat_house, null, null),
    CategorySymbol("cart", "お買い物", R.drawable.cat_cart, R.drawable.blue_tag, null),
    CategorySymbol("bag", "仕事", R.drawable.cat_bag, R.drawable.blue_briefcase, null),
    CategorySymbol("paw", "ペット", R.drawable.cat_paw, null, null),
    CategorySymbol("camera", "カメラ", R.drawable.deco_camera, R.drawable.blue_camera, null),
    CategorySymbol("people", "人", null, R.drawable.blue_people, Icons.Filled.People),
    CategorySymbol("star", "星", null, R.drawable.blue_star, Icons.Filled.Star),
    CategorySymbol("heart", "ハート", R.drawable.deco_heart, null, Icons.Filled.Favorite),
    CategorySymbol("school", "学校", null, null, Icons.Filled.School),
    CategorySymbol("travel", "旅行", null, null, Icons.Filled.Flight),
    CategorySymbol("food", "ごはん", null, null, Icons.Filled.Restaurant),
    CategorySymbol("flower", "お花", R.drawable.deco_sakura, null, Icons.Filled.LocalFlorist),
    CategorySymbol("book", "本", null, null, Icons.Filled.AutoStories),
    CategorySymbol("music", "音楽", null, null, Icons.Filled.MusicNote),
    CategorySymbol("sports", "スポーツ", null, null, Icons.Filled.SportsSoccer),
    CategorySymbol("photo", "写真", R.drawable.deco_photo_icon, R.drawable.blue_picture, Icons.Filled.PhotoCamera),
)

fun symbolOf(key: String) = categorySymbols.firstOrNull { it.key == key } ?: categorySymbols[0]

/** テーマに合わせたイラスト（ブルーでは青いイラストに入れ替え） */
object Art {
    fun camera(p: Palette) = if (p.blue) R.drawable.blue_camera else R.drawable.deco_camera
    fun photos(p: Palette) = if (p.blue) R.drawable.blue_photos else R.drawable.deco_polaroids
    fun folder(p: Palette) = if (p.blue) R.drawable.blue_folder else R.drawable.deco_folder
    fun photoIcon(p: Palette) = if (p.blue) R.drawable.blue_picture else R.drawable.deco_photo_icon
    fun badge(p: Palette) = if (p.blue) R.drawable.blue_shield else R.drawable.deco_badge
    fun crown(p: Palette) = if (p.blue) R.drawable.blue_star else R.drawable.deco_crown
    fun phone(p: Palette) = if (p.blue) R.drawable.blue_phone else R.drawable.deco_phone
    fun cloud(p: Palette) = if (p.blue) R.drawable.blue_cloud else R.drawable.deco_cloud
}
