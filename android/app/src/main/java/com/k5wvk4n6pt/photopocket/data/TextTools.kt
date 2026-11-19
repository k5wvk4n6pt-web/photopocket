package com.k5wvk4n6pt.photopocket.data

import android.content.Context
import android.net.Uri
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.summarization.Summarization
import com.google.mlkit.genai.summarization.SummarizationRequest
import com.google.mlkit.genai.summarization.SummarizerOptions
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** 写真の文字の読み取り（端末の中で処理） */
object TextReader {
    suspend fun read(context: Context, uri: Uri): String = withContext(Dispatchers.IO) {
        val recognizer = TextRecognition.getClient(JapaneseTextRecognizerOptions.Builder().build())
        try {
            val image = InputImage.fromFilePath(context, uri)
            val result = Tasks.await(recognizer.process(image))
            result.textBlocks.joinToString("\n") { b -> b.lines.joinToString("\n") { it.text } }.trim()
        } finally {
            recognizer.close()
        }
    }
}

/** AIのまとめ（Gemini Nano。対応する機種だけで使える） */
object AiSummary {
    enum class State { Unavailable, Downloadable, Downloading, Available }

    private fun client(context: Context) = Summarization.getClient(
        SummarizerOptions.builder(context)
            .setInputType(SummarizerOptions.InputType.ARTICLE)
            .setOutputType(SummarizerOptions.OutputType.THREE_BULLETS)
            .setLanguage(SummarizerOptions.Language.JAPANESE)
            .build()
    )

    suspend fun state(context: Context): State = withContext(Dispatchers.IO) {
        runCatching {
            val c = client(context)
            try {
                when (c.checkFeatureStatus().get()) {
                    FeatureStatus.AVAILABLE -> State.Available
                    FeatureStatus.DOWNLOADING -> State.Downloading
                    FeatureStatus.DOWNLOADABLE -> State.Downloadable
                    else -> State.Unavailable
                }
            } finally { c.close() }
        }.getOrDefault(State.Unavailable)
    }

    /** 400文字以上の文章で使える。まだ準備ができていなければ自動でダウンロードしてから要約する */
    suspend fun summarize(context: Context, text: String): String = withContext(Dispatchers.IO) {
        val c = client(context)
        try {
            val request = SummarizationRequest.builder(text.take(3000)).build()
            clean(c.runInference(request).get().summary)
        } finally { c.close() }
    }

    fun clean(s: String): String = s.lines()
        .map { it.replace("**", "").trim().removePrefix("* ").removePrefix("- ").removePrefix("• ").trim() }
        .filter { it.isNotEmpty() }
        .joinToString("\n") { "・$it" }
}

/** 文字から要点（日付・時間・金額など）を取り出す */
object KeyInfo {
    data class Group(val label: String, val items: List<String>)

    fun extract(text: String): List<Group> {
        fun matches(pattern: String): List<String> =
            Regex(pattern).findAll(text).map { it.value.trim() }.filter { it.isNotEmpty() }.distinct().toList()
        fun lines(pattern: String, limit: Int): List<String> {
            val re = Regex(pattern)
            return text.lines().filter { re.containsMatchIn(it) }.map { it.take(50).trim() }
                .filter { it.isNotEmpty() }.distinct().take(limit)
        }
        val wd = "(?:\\s*[（(][月火水木金土日](?:曜日?)?[)）])?"
        return listOf(
            Group("期限・大事な行", lines("まで|締切|締め切り|〆切|期限|提出|持ち物|持参", 5)),
            Group("日付", matches("(?:令和|平成)?\\d{1,4}年\\s*\\d{1,2}月\\s*\\d{1,2}日$wd|\\d{1,2}月\\s*\\d{1,2}日$wd|\\b\\d{1,2}/\\d{1,2}\\b")),
            Group("時間", matches("(?:午前|午後)?\\s*\\d{1,2}[:：]\\d{2}(?:\\s*[〜~～-]\\s*\\d{1,2}[:：]\\d{2})?|(?:午前|午後)\\d{1,2}時(?:\\d{1,2}分)?")),
            Group("金額", matches("[¥￥]\\s?\\d{1,3}(?:[,，]\\d{3})+|[¥￥]\\s?\\d+|\\d{1,3}(?:[,，]\\d{3})+\\s?円|\\d+\\s?円")),
            Group("電話番号", matches("0\\d{1,4}[-－‐ー(（]\\d{1,4}[-－‐ー)）]\\d{3,4}|0[5789]0\\d{8}|\\b0\\d{9}\\b")),
            Group("住所", lines("(都|道|府|県).{1,8}(市|区|町|村)|[市区町村].{0,12}\\d+[-－‐丁]", 3)),
            Group("URL", matches("https?://[^\\s　]+|www\\.[^\\s　]+")),
            Group("メール", matches("[\\w.+-]+@[\\w-]+\\.[\\w.]+")),
        ).filter { it.items.isNotEmpty() }
    }
}
