# FORMAT 4: Student's Progress Report (Every 15 Days)

**Date:** 29th Jan 2026 → 12th Feb 2026

**Dept/Division:** AI/ML – CRM Call Agent | **Activity Completed:** Android Native Module — Call Monitoring & Detection

**Name of HOD/Supervisor:** Industry Supervisor

---

## Work Details:

## 📞 Period 4 — Android Native Call Monitoring (Kotlin)
**Date:** 29th Jan 2026 → 12th Feb 2026

---

### Files Implemented
- `CallReceiver.kt` — BroadcastReceiver for call state changes
- `CallMonitorService.kt` — Foreground Service for persistent monitoring
- `BootReceiver.kt` — Restart service on device reboot
- `CallDatabase.kt` — Room database for local call storage
- `AndroidManifest.xml` — Permissions & service declarations

---

### Work Done
| # | Task | Status |
|---|------|--------|
| 1 | Implemented `CallReceiver.kt` using TelephonyManager states | ✅ Done |
| 2 | Detected CALL_STATE_RINGING, OFFHOOK, IDLE transitions | ✅ Done |
| 3 | Built `CallMonitorService.kt` as a foreground service | ✅ Done |
| 4 | Added persistent notification (PRIORITY_LOW) for service | ✅ Done |
| 5 | Implemented call duration tracking (start/end timestamps) | ✅ Done |
| 6 | Built `BootReceiver.kt` to auto-start service after reboot | ✅ Done |
| 7 | Added all required permissions to AndroidManifest.xml | ✅ Done |
| 8 | Implemented local SQLite storage via Room (CallDatabase.kt) | ✅ Done |
| 9 | Tested on physical device (call detection confirmed working) | ✅ Done |
| 10 | Handled edge cases: declined calls, conference calls | ✅ Done |

---

### Key Permissions Added
```xml
<uses-permission android:name="android.permission.READ_PHONE_STATE"/>
<uses-permission android:name="android.permission.READ_CALL_LOG"/>
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.INTERNET"/>
```

---

### CallMonitorService Architecture
```
CallReceiver (BroadcastReceiver)
    ↓ detects call state change
CallMonitorService (ForegroundService)
    ↓ logs call with metadata
CallDatabase (Room/SQLite)
    ↓ local cache
    → HTTP POST to Python backend (async)
```

---

### Challenges
- Android 10+ restricts background process launching → solved with foreground service
- READ_PHONE_STATE requires runtime permission on Android 6+ → added runtime permission request in MainActivity

---

### Deliverables
- ✅ CallReceiver.kt (call detection)
- ✅ CallMonitorService.kt (background monitoring)
- ✅ BootReceiver.kt (persistence across reboots)
- ✅ CallDatabase.kt (local storage)
- ✅ Tested on Android 12 device


---
*Signature of Industry Supervisor / Proprietor with Company Stamp / Seal*
