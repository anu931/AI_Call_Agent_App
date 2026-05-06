# FORMAT 4: Student's Progress Report (Every 15 Days)

**Date:** 15th Dec 2025 → 29th Dec 2025

**Dept/Division:** AI/ML – CRM Call Agent | **Activity Completed:** Problem Understanding & Requirements Analysis

**Name of HOD/Supervisor:** Industry Supervisor

---

## Work Details:

## 🎯 Period 1 — Problem Understanding & Requirements Analysis
**Date:** 15th Dec 2025 → 29th Dec 2025

---

### Problem Statement
Build an AI-powered CRM Call Agent App that:
- Monitors incoming/outgoing calls on Android devices
- Automatically logs call metadata (caller, duration, time)
- Uses AI/LLM to transcribe and analyze call conversations
- Stores insights in a PostgreSQL CRM database
- Displays call logs & AI analysis in a Flutter mobile UI

---

### Work Done
| # | Task | Status |
|---|------|--------|
| 1 | Read and understood the full internship problem statement | ✅ Done |
| 2 | Researched existing CRM solutions (Salesforce, Zoho) for reference | ✅ Done |
| 3 | Identified key stakeholders: sales teams, supervisors, CRM admins | ✅ Done |
| 4 | Listed functional requirements: call logging, AI analysis, dashboard | ✅ Done |
| 5 | Listed non-functional requirements: real-time, offline support, security | ✅ Done |
| 6 | Explored Android telephony APIs for call interception | ✅ Done |
| 7 | Investigated Flutter-Android native bridge (MethodChannel) | ✅ Done |
| 8 | Documented all findings in a requirements specification document | ✅ Done |
| 9 | Discussed tech stack options with supervisor | ✅ Done |
| 10 | Set up development environment (Android Studio, VS Code, Flutter) | ✅ Done |

---

### Key Decisions Made
- **Platform:** Android-first (call monitoring requires Android native access)
- **Frontend:** Flutter (cross-platform, single codebase for future iOS support)
- **Backend:** Python (FastAPI) for AI pipeline
- **Database:** PostgreSQL for CRM data
- **AI:** LLM integration for call transcription and sentiment analysis

---

### Challenges Faced
- Android restricts call audio recording on Android 10+ → workaround: use call state detection + manual note entry or SIP/VoIP logging
- Choosing between Room DB (local) and PostgreSQL (server) → decided to use both (local cache + cloud sync)

---

### References
- Android TelephonyManager documentation
- Flutter MethodChannel documentation  
- CRM system design papers


---
*Signature of Industry Supervisor / Proprietor with Company Stamp / Seal*
