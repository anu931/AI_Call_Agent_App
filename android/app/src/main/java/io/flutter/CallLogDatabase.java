package io.flutter;

import android.content.ContentValues;
import android.content.Context;
import android.database.sqlite.SQLiteDatabase;
import android.database.sqlite.SQLiteOpenHelper;

public class CallLogDatabase extends SQLiteOpenHelper {

    private static final String DATABASE_NAME = "call_logs.db";
    private static final int DATABASE_VERSION = 1;

    public CallLogDatabase(Context context) {
        super(context, DATABASE_NAME, null, DATABASE_VERSION);
    }

    @Override
    public void onCreate(SQLiteDatabase db) {

        String CREATE_TABLE = "CREATE TABLE logs (" +
                "id INTEGER PRIMARY KEY AUTOINCREMENT," +
                "phone_number TEXT,"+
                "audio_path TEXT," +
                "call_type TEXT," +
                "timestamp DATETIME DEFAULT CURRENT_TIMESTAMP" +
                ")";

        db.execSQL(CREATE_TABLE);
    }

    @Override
    public void onUpgrade(SQLiteDatabase db, int oldVersion, int newVersion) {
        db.execSQL("DROP TABLE IF EXISTS logs");
        onCreate(db);
    }

    public static void insertLog(Context context, String number, String path, String type) {

        CallLogDatabase dbHelper = new CallLogDatabase(context);
        SQLiteDatabase db = dbHelper.getWritableDatabase();

        ContentValues values = new ContentValues();
        values.put("phone_number", number);
        values.put("audio_path", path);
        values.put("call_type", type);

        db.insert("logs", null, values);

        db.close();
    }
}