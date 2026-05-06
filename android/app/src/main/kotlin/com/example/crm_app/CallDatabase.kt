package com.example.crm_app

import android.content.Context
import androidx.room.*

// ── Entity ────────────────────────────────────────────────────────────────────
@Entity(tableName = "call_logs")
data class CallLogEntity(
    @PrimaryKey(autoGenerate = true) val id: Int = 0,
    val phoneNumber:   String,
    val recordingPath: String,
    val duration:      Int,
    val callTime:      Long,
    val isIncoming:    Boolean,
    val date:          String,
    val time:          String,
)

// ── DAO ───────────────────────────────────────────────────────────────────────
@Dao
interface CallLogDao {
    @Query("SELECT * FROM call_logs ORDER BY callTime DESC")
    fun getAll(): List<CallLogEntity>

    @Insert
    fun insert(log: CallLogEntity)

    @Query("DELETE FROM call_logs WHERE id = :id")
    fun deleteById(id: Int)
}

// ── Database ──────────────────────────────────────────────────────────────────
@Database(entities = [CallLogEntity::class], version = 1)
abstract class CallDatabase : RoomDatabase() {
    abstract fun callLogDao(): CallLogDao

    companion object {
        @Volatile private var INSTANCE: CallDatabase? = null

        fun getInstance(context: Context): CallDatabase =
            INSTANCE ?: synchronized(this) {
                INSTANCE ?: Room.databaseBuilder(
                    context.applicationContext,
                    CallDatabase::class.java,
                    "crm_calls.db"
                )
                .allowMainThreadQueries()
                .build()
                .also { INSTANCE = it }
            }
    }
}