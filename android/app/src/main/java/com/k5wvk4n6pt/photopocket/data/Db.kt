package com.k5wvk4n6pt.photopocket.data

import android.content.Context
import androidx.room.ColumnInfo
import androidx.room.Dao
import androidx.room.Database
import androidx.room.Delete
import androidx.room.Entity
import androidx.room.Index
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.PrimaryKey
import androidx.room.Query
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

/** 分類（家族・旅行など） */
@Entity
data class Category(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val name: String,
    val symbol: String = "house",
    val colorName: String = "pink",
    val sortOrder: Int = 0,
    val createdAt: Long = System.currentTimeMillis(),
)

/** フォルダ（分類の中に入る） */
@Entity(indices = [Index("categoryId")])
data class Folder(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val categoryId: Long?,
    val name: String,
    val colorName: String = "orange",
    val sortOrder: Int = 0,
    val createdAt: Long = System.currentTimeMillis(),
)

/**
 * フォルダに入れた写真・動画。
 * 写真の本体はコピーせず、端末の写真（MediaStore）の場所だけを覚える。
 */
@Entity(indices = [Index("folderId"), Index("mediaId")])
data class Item(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val folderId: Long,
    val mediaId: Long,
    val uri: String,
    val isVideo: Boolean = false,
    val durationMs: Long = 0,
    val takenAt: Long = 0,
    val addedAt: Long = System.currentTimeMillis(),
    val memo: String = "",
    val recognizedText: String = "",
    val summary: String = "",
    /** 自分で直した要点（「ラベル\t内容」を1行ずつ）。空なら文字から自動で取り出す */
    @ColumnInfo(defaultValue = "") val keyPoints: String = "",
)

/** スワイプの仕分けで「残す」「フォルダへ」にした写真（次から出さない） */
@Entity
data class Handled(@PrimaryKey val mediaId: Long)

data class FolderCount(val folderId: Long, val count: Int)

@Dao
interface PocketDao {
    @Query("SELECT * FROM Category ORDER BY sortOrder, createdAt")
    fun categories(): Flow<List<Category>>

    @Query("SELECT * FROM Folder ORDER BY sortOrder, createdAt")
    fun folders(): Flow<List<Folder>>

    @Query("SELECT * FROM Item ORDER BY takenAt DESC, addedAt DESC")
    fun items(): Flow<List<Item>>

    @Query("SELECT * FROM Item WHERE folderId = :folderId ORDER BY takenAt DESC, addedAt DESC")
    fun itemsIn(folderId: Long): Flow<List<Item>>

    @Query("SELECT mediaId FROM Handled")
    suspend fun handledIds(): List<Long>

    @Query("SELECT mediaId FROM Item")
    suspend fun itemMediaIds(): List<Long>

    @Query("SELECT COUNT(*) FROM Item")
    suspend fun itemCount(): Int

    @Insert suspend fun insert(c: Category): Long
    @Insert suspend fun insert(f: Folder): Long
    @Insert suspend fun insert(i: Item): Long
    @Insert(onConflict = OnConflictStrategy.IGNORE) suspend fun insert(h: Handled)
    @Update suspend fun update(c: Category)
    @Update suspend fun update(f: Folder)
    @Update suspend fun update(i: Item)
    @Update suspend fun updateCategories(list: List<Category>)
    @Update suspend fun updateFolders(list: List<Folder>)
    @Delete suspend fun delete(i: Item)

    @Query("DELETE FROM Handled WHERE mediaId = :mediaId")
    suspend fun unhandle(mediaId: Long)

    @Query("DELETE FROM Item WHERE folderId = :folderId")
    suspend fun deleteItemsIn(folderId: Long)

    @Query("UPDATE Item SET folderId = :to WHERE folderId = :from")
    suspend fun moveItems(from: Long, to: Long)

    @Query("DELETE FROM Folder WHERE id = :id")
    suspend fun deleteFolder(id: Long)

    @Query("UPDATE Folder SET categoryId = NULL WHERE categoryId = :categoryId")
    suspend fun detachFolders(categoryId: Long)

    @Query("DELETE FROM Category WHERE id = :id")
    suspend fun deleteCategory(id: Long)

    @Query("DELETE FROM Item WHERE folderId = :folderId AND mediaId IN (:mediaIds)")
    suspend fun deleteItemsFor(folderId: Long, mediaIds: List<Long>)

    @Query("DELETE FROM Item WHERE mediaId IN (:mediaIds)")
    suspend fun deleteItemsForMedia(mediaIds: List<Long>)
}

/** 要点を保存する欄を追加 */
val MIGRATION_1_2 = object : androidx.room.migration.Migration(1, 2) {
    override fun migrate(db: androidx.sqlite.db.SupportSQLiteDatabase) {
        db.execSQL("ALTER TABLE Item ADD COLUMN keyPoints TEXT NOT NULL DEFAULT ''")
    }
}

@Database(entities = [Category::class, Folder::class, Item::class, Handled::class], version = 2, exportSchema = false)
abstract class PocketDb : RoomDatabase() {
    abstract fun dao(): PocketDao

    companion object {
        @Volatile private var instance: PocketDb? = null
        fun get(context: Context): PocketDb = instance ?: synchronized(this) {
            instance ?: Room.databaseBuilder(context.applicationContext, PocketDb::class.java, "photopocket.db")
                .addMigrations(MIGRATION_1_2)
                .build().also { instance = it }
        }
    }
}
