package com.k5wvk4n6pt.photopocket.data

import android.Manifest
import android.app.PendingIntent
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.core.content.ContextCompat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** 端末の写真・動画1つ分 */
data class LibMedia(
    val id: Long,
    val uri: Uri,
    val isVideo: Boolean,
    val durationMs: Long,
    val takenAt: Long,
    val addedAt: Long,
)

object MediaLibrary {
    /** 写真へのアクセス許可で求める権限 */
    val permissions: Array<String>
        get() = when {
            Build.VERSION.SDK_INT >= 34 -> arrayOf(
                Manifest.permission.READ_MEDIA_IMAGES,
                Manifest.permission.READ_MEDIA_VIDEO,
                Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
            )
            Build.VERSION.SDK_INT >= 33 -> arrayOf(
                Manifest.permission.READ_MEDIA_IMAGES,
                Manifest.permission.READ_MEDIA_VIDEO,
            )
            else -> arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        }

    fun hasFullAccess(context: Context): Boolean = when {
        Build.VERSION.SDK_INT >= 33 ->
            granted(context, Manifest.permission.READ_MEDIA_IMAGES)
        else -> granted(context, Manifest.permission.READ_EXTERNAL_STORAGE)
    }

    fun hasAnyAccess(context: Context): Boolean =
        hasFullAccess(context) ||
            (Build.VERSION.SDK_INT >= 34 && granted(context, Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED))

    private fun granted(context: Context, p: String) =
        ContextCompat.checkSelfPermission(context, p) == PackageManager.PERMISSION_GRANTED

    /**
     * 写真・動画の一覧。
     * byAdded=true：端末に保存した順（新しい順）、false：撮影日の新しい順
     */
    suspend fun load(context: Context, byAdded: Boolean = true): List<LibMedia> = withContext(Dispatchers.IO) {
        val collection = MediaStore.Files.getContentUri("external")
        val projection = arrayOf(
            MediaStore.Files.FileColumns._ID,
            MediaStore.Files.FileColumns.MEDIA_TYPE,
            MediaStore.Files.FileColumns.DATE_ADDED,
            MediaStore.MediaColumns.DATE_TAKEN,
            MediaStore.MediaColumns.DURATION,
        )
        val selection = "${MediaStore.Files.FileColumns.MEDIA_TYPE} IN (?, ?)"
        val args = arrayOf(
            MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE.toString(),
            MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO.toString(),
        )
        val order = if (byAdded) "${MediaStore.Files.FileColumns.DATE_ADDED} DESC"
                    else "${MediaStore.MediaColumns.DATE_TAKEN} DESC"
        val list = mutableListOf<LibMedia>()
        context.contentResolver.query(collection, projection, selection, args, order)?.use { c ->
            val idCol = c.getColumnIndexOrThrow(MediaStore.Files.FileColumns._ID)
            val typeCol = c.getColumnIndexOrThrow(MediaStore.Files.FileColumns.MEDIA_TYPE)
            val addedCol = c.getColumnIndexOrThrow(MediaStore.Files.FileColumns.DATE_ADDED)
            val takenCol = c.getColumnIndexOrThrow(MediaStore.MediaColumns.DATE_TAKEN)
            val durCol = c.getColumnIndexOrThrow(MediaStore.MediaColumns.DURATION)
            while (c.moveToNext()) {
                val id = c.getLong(idCol)
                val video = c.getInt(typeCol) == MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO
                val base = if (video) MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                           else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                val added = c.getLong(addedCol) * 1000
                val taken = c.getLong(takenCol).takeIf { it > 0 } ?: added
                list += LibMedia(
                    id = id,
                    uri = ContentUris.withAppendedId(base, id),
                    isVideo = video,
                    durationMs = if (video) c.getLong(durCol) else 0,
                    takenAt = taken,
                    addedAt = added,
                )
            }
        }
        list
    }

    /** まだ端末に残っている写真のID（写真アプリで消された写真を見分ける） */
    suspend fun existingIds(context: Context): Set<Long> = load(context).map { it.id }.toSet()

    /**
     * 端末の写真をゴミ箱へ移す（30日間は「ゴミ箱」から戻せる）。
     * Androidの確認画面を出すためのPendingIntentを返す。
     */
    fun trashRequest(context: Context, uris: List<Uri>): PendingIntent =
        MediaStore.createTrashRequest(context.contentResolver, uris, true)
}

fun formatDuration(ms: Long): String {
    val total = ms / 1000
    val h = total / 3600
    val m = (total % 3600) / 60
    val s = total % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%d:%02d".format(m, s)
}
