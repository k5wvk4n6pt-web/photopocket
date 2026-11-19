package com.k5wvk4n6pt.photopocket.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.k5wvk4n6pt.photopocket.data.AiSummary
import com.k5wvk4n6pt.photopocket.data.Item
import com.k5wvk4n6pt.photopocket.data.KeyInfo
import com.k5wvk4n6pt.photopocket.data.Repo
import com.k5wvk4n6pt.photopocket.data.TextReader
import kotlinx.coroutines.launch

/** 写真の文字（読み取り・AIのまとめ・要点） */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun TextSheet(repo: Repo, item: Item, onClose: () -> Unit) {
    val p = LocalPalette.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var text by remember(item.id) { mutableStateOf(item.recognizedText) }
    var summary by remember(item.id) { mutableStateOf(item.summary) }
    var reading by remember { mutableStateOf(false) }
    var summarizing by remember { mutableStateOf(false) }
    var aiState by remember { mutableStateOf<AiSummary.State?>(null) }
    var message by remember { mutableStateOf<String?>(null) }

    fun read() = scope.launch {
        reading = true
        text = runCatching { TextReader.read(context, Uri.parse(item.uri)) }.getOrElse { "" }
        reading = false
        if (text.isBlank()) message = "文字が見つかりませんでした"
    }
    LaunchedEffect(item.id) {
        aiState = AiSummary.state(context)
        if (text.isBlank()) read()
    }

    androidx.compose.ui.window.Dialog(
        onDismissRequest = onClose,
        properties = androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Box(Modifier.fillMaxSize().background(p.bgBottom).statusBarsPadding().imePadding()) {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    PillButton("閉じる", onClick = onClose)
                    Spacer(Modifier.weight(1f))
                    Text("写真の文字", color = p.ink, fontWeight = FontWeight.Black, fontSize = 17.sp)
                    Spacer(Modifier.weight(1f))
                    PillButton("保存", filled = true) {
                        scope.launch { repo.dao.update(item.copy(recognizedText = text, summary = summary)) }
                        onClose()
                    }
                }

                // AIのまとめ
                if (aiState != null && aiState != AiSummary.State.Unavailable) {
                    Column(Modifier.fillMaxWidth().pocketCard(p, 18.dp).padding(14.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Filled.AutoAwesome, null, tint = p.accent)
                            Text(" AIのまとめ", color = p.ink, fontWeight = FontWeight.Black)
                            Spacer(Modifier.weight(1f))
                            if (!summarizing) Text(
                                if (summary.isBlank()) "要約する" else "作り直す", color = p.accent, fontWeight = FontWeight.Bold,
                                modifier = Modifier.clickable {
                                    if (text.length < 400) { message = "AIのまとめは、400文字以上の文章で使えます"; return@clickable }
                                    scope.launch {
                                        summarizing = true
                                        if (aiState != AiSummary.State.Available) message = "AIの準備をしています。初回は時間がかかります…"
                                        summary = runCatching { AiSummary.summarize(context, text) }.getOrElse { message = "まとめられませんでした"; summary }
                                        summarizing = false
                                        aiState = AiSummary.State.Available
                                    }
                                },
                            )
                        }
                        when {
                            summarizing -> Row(Modifier.padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                                CircularProgressIndicator(Modifier.padding(end = 10.dp), strokeWidth = 2.dp)
                                Text("まとめています…", color = p.sub)
                            }
                            summary.isNotBlank() -> Text(summary, color = p.ink, fontSize = 14.sp, lineHeight = 22.sp, modifier = Modifier.padding(top = 8.dp))
                            else -> Text("文章をAIが短くまとめます（端末の中で処理します）", color = p.sub, fontSize = 13.sp, modifier = Modifier.padding(top = 6.dp))
                        }
                    }
                }

                // 要点
                val groups = KeyInfo.extract(text)
                if (groups.isNotEmpty()) {
                    Column(Modifier.fillMaxWidth().pocketCard(p, 18.dp).padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("✦ 要点", color = p.accent, fontWeight = FontWeight.Black)
                        groups.forEach { g ->
                            Text(g.label, color = p.sub, fontSize = 11.sp)
                            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                g.items.forEach { v ->
                                    Text(
                                        v, color = p.ink, fontWeight = FontWeight.Bold, fontSize = 13.sp,
                                        modifier = Modifier.clip(RoundedCornerShape(8.dp)).background(p.soft)
                                            .clickable { copy(context, v); message = "コピーしました" }
                                            .padding(horizontal = 8.dp, vertical = 4.dp),
                                    )
                                }
                            }
                        }
                        Text("タップでコピーできます", color = p.sub, fontSize = 11.sp)
                    }
                }

                // 読み取った文字
                if (reading) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        CircularProgressIndicator(Modifier.padding(end = 10.dp), strokeWidth = 2.dp)
                        Text("文字を読み取っています…", color = p.sub)
                    }
                } else {
                    OutlinedTextField(text, { text = it }, label = { Text("読み取った文字（直せます）") },
                        modifier = Modifier.fillMaxWidth().heightIn(min = 180.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        PillButton("コピー") { copy(context, text); message = "コピーしました" }
                        PillButton("もう一度読み取る") { read() }
                    }
                }
                message?.let { Text(it, color = p.accent, fontWeight = FontWeight.Bold, fontSize = 13.sp) }
            }
        }
    }
}

private fun copy(context: Context, s: String) {
    val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    cm.setPrimaryClip(ClipData.newPlainText("text", s))
}
