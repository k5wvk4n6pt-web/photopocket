package com.k5wvk4n6pt.photopocket.data

import android.content.Context

/** データの出し入れをまとめた窓口 */
class Repo(context: Context) {
    val dao = PocketDb.get(context).dao()

    val categories = dao.categories()
    val folders = dao.folders()
    val items = dao.items()
    fun itemsIn(folderId: Long) = dao.itemsIn(folderId)

    suspend fun addCategory(name: String, symbol: String, color: String, order: Int) =
        dao.insert(Category(name = name, symbol = symbol, colorName = color, sortOrder = order))

    suspend fun addFolder(categoryId: Long?, name: String, color: String, order: Int) =
        dao.insert(Folder(categoryId = categoryId, name = name, colorName = color, sortOrder = order))

    /** 端末の写真をフォルダに入れる（同じフォルダに同じ写真は入れない） */
    suspend fun addMedia(folderId: Long, media: List<LibMedia>, existing: List<Item>): List<Long> {
        val already = existing.filter { it.folderId == folderId }.map { it.mediaId }.toSet()
        val added = mutableListOf<Long>()
        for (m in media) {
            if (m.id in already) continue
            dao.insert(
                Item(
                    folderId = folderId, mediaId = m.id, uri = m.uri.toString(),
                    isVideo = m.isVideo, durationMs = m.durationMs, takenAt = m.takenAt,
                )
            )
            added += m.id
        }
        return added
    }

    suspend fun starterSet() {
        val names = listOf(
            Triple("家族", "house", "pink"), Triple("学校", "school", "orange"), Triple("仕事", "bag", "purple"),
            Triple("友達", "people", "blue"), Triple("趣味", "star", "yellow"), Triple("自然", "flower", "green"),
        )
        names.forEachIndexed { i, (n, s, c) -> addCategory(n, s, c, i) }
    }

    /** フォルダを消す。moveTo を指定すると、中の写真をそちらへ移してから消す */
    suspend fun deleteFolder(folder: Folder, moveTo: Long?) {
        if (moveTo != null) dao.moveItems(folder.id, moveTo) else dao.deleteItemsIn(folder.id)
        dao.deleteFolder(folder.id)
    }

    /** 分類を消す（中のフォルダは「分類なし」に移る） */
    suspend fun deleteCategory(c: Category) {
        dao.detachFolders(c.id)
        dao.deleteCategory(c.id)
    }
}
