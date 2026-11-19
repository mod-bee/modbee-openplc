(* FB_Schedule — weekly time-of-day schedule, a local fallback (the platform holds the real calendar).
aWindows (the project's table, one row per time window, at most 16 kept): a window runs from todStartTime to todStopTime
on each day in its nWeekdayBits bits (bit 0 Monday ... bit 6 Sunday); a todStopTime earlier than todStartTime crosses midnight
(the part after midnight belongs to the day it started); todStartTime = todStopTime is empty. nDaysBetweenRuns N (2 or more)
runs it only every N-th day from dStartDate. bScheduleActive is on inside any window; nActiveWindow is the first one on
(1 = the first row), sts.nActiveWindowBits has a bit per window (bit 0 = the first row, up to 32).
Clock: dtLocalTime, local time from F_LocalTime (the boards have no real-time clock: unwired = no clock, the schedule
is off); set.nUtcOffsetMinutes is added. bClockSynced is off when the clock is implausible (F_ClockOk) or has not moved for
5 s: the schedule is then off (an override still works), warning NoClock. bHourPulse / bDayPulse give one scan on
each new hour / at midnight, never doubled by a clock set back.
Overrides (bOverrideOn / bOverrideOff pins, bCmdOverrideOn / bCmdOverrideOff / bCmdCancelOverride, each once per
write): bScheduleActive on / off for set.tOverrideTime (0 = until the schedule next changes); Off wins, then Cancel, then
On. bEnable FALSE (pin or set.bScheduleOn) cancels an override. sts.dtNextChange is the next time the schedule
changes (within 8 days; DT#1970-01-01-00:00:00 = none or no clock).
Kept (a retained last-good copy, restored at power-up, a bad write put back): set and the window rows. A window
with a bad setting and no good copy is left out: warning BadSetting, sts.nBadSettingWindow names it. *)

FUNCTION_BLOCK FB_Schedule EXTENDS FB_Object
  VAR_INPUT
    bEnable : BOOL := TRUE; (* AND-ed with set.bScheduleOn *)
    dtLocalTime : DT := DT#1970-01-01-00:00:00; (* local time (optional): unwired = no clock, the schedule is off *)
    bOverrideOn : BOOL R_EDGE; (* bScheduleActive on for set.tOverrideTime *)
    bOverrideOff : BOOL R_EDGE; (* bScheduleActive off for set.tOverrideTime *)
    refData : REFERENCE TO ST_ScheduleData; (* the block's record *)
  END_VAR
  VAR_IN_OUT
    aWindows : ARRAY [*] OF ST_SCHEDWINDOW; (* the project's table, one row per time window (at most 16 kept) *)
  END_VAR
  VAR_OUTPUT
    bScheduleActive : BOOL; (* the schedule is on now *)
    nActiveWindow : INT; (* the first window on, 1 = the first row; 0 none *)
    bHourPulse : BOOL; (* one scan at each new hour *)
    bDayPulse : BOOL; (* one scan at midnight *)
    bClockSynced : BOOL; (* the clock is set and moving *)
    bOverrideActive : BOOL; (* an override is on *)
  END_VAR
  VAR RETAIN
    stKept : ST_ScheduleSet;
    aKeptWindow : ARRAY [1..16] OF ST_SCHEDWINDOW;
    nKeptMask : WORD; (* bit n-1: slot n holds a good copy (a row bad from the start has none) *)
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 2;
    cMaxKept : DINT := 16;
  END_VAR
  VAR
    nLastSecs : LINT;
    tLastMove : TIME;
    bSeen : BOOL;
    bMarks : BOOL;
    nLastHour : LINT;
    nLastDay : LINT;
    nCalcSecs : LINT := -1;
    bOvState : BOOL;
    tOvStart : TIME;
    bOvSched : BOOL;
    bOnSeen : BOOL;
    bOffSeen : BOOL;
    bCancelSeen : BOOL;
  END_VAR
  VAR_TEMP
    nBit : WORD; (* this row's bit in nKeptMask *)
    bOkSet : BOOL;
    bEn : BOOL;
    nLo : DINT;
    nHi : DINT;
    nI : DINT;
    nJ : DINT;
    nC : INT;
    nSecs : LINT;
    nLocal : LINT;
    nDayNo : LINT;
    nHourNo : LINT;
    nProbe : LINT;
    nCand : LINT;
    nNc : LINT;
    nW : LINT;
    bSched : BOOL;
    bFound : BOOL;
    bReqOn : BOOL;
    bReqOff : BOOL;
    bReqCancel : BOOL;
  END_VAR


METHOD PRIVATE SetWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_ScheduleSet;
  END_VAR
  SetWhy := E_UtError.None;
  IF NOT (stS.tOverrideTime >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.nUtcOffsetMinutes >= -1440) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.nUtcOffsetMinutes <= 1440) THEN
    SetWhy := E_UtError.TimeBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_ScheduleSet;
  END_VAR
  SetOk := SetWhy(stS := stS) = E_UtError.None;
END_METHOD

METHOD PRIVATE WindowWhy : E_UtError
  VAR_INPUT
    stW : REFERENCE TO ST_SchedWindow;
  END_VAR
  WindowWhy := E_UtError.None;
  IF NOT (stW.nDaysBetweenRuns >= 0) THEN
    WindowWhy := E_UtError.BelowMin;
  ELSIF NOT (stW.nDaysBetweenRuns <= 366) THEN
    WindowWhy := E_UtError.AboveMax;
  ELSIF NOT (stW.nWeekdayBits <= 16#7F) THEN
    WindowWhy := E_UtError.AboveMax;
  END_IF;
END_METHOD

METHOD PRIVATE WindowOk : BOOL
  VAR_INPUT
    stW : REFERENCE TO ST_SchedWindow;
  END_VAR
  WindowOk := WindowWhy(stW := stW) = E_UtError.None;
END_METHOD

(* the window is on at this local time (seconds since 1970) *)
METHOD PRIVATE WindowIn : BOOL
  VAR_INPUT
    stW : REFERENCE TO ST_SchedWindow;
    nAt : LINT;
  END_VAR
  VAR
    nDayP : LINT;
    nDow : INT;
    nDowPrev : INT;
    nMs : DINT;
    nSt : DINT;
    nSp : DINT;
    bDayOk : BOOL;
    bPrevOk : BOOL;
    nSDay : LINT;
  END_VAR
  WindowIn := FALSE;
  IF WindowOk(stW := stW) AND stW.bWindowOn AND stW.todStartTime <> stW.todStopTime THEN
    nDayP := nAt / 86400;
    nDow := LINT_TO_INT((nDayP + 3) MOD 7);
    nDowPrev := (nDow + 6) MOD 7;
    nMs := LINT_TO_DINT(nAt MOD 86400) * 1000;
    nSt := TOD_TO_DINT(stW.todStartTime);
    nSp := TOD_TO_DINT(stW.todStopTime);
    bDayOk := (stW.nWeekdayBits AND SHL(BYTE#1, nDow)) <> 0;
    bPrevOk := (stW.nWeekdayBits AND SHL(BYTE#1, nDowPrev)) <> 0;
    IF stW.nDaysBetweenRuns >= 2 THEN
      nSDay := DATE_TO_LINT(stW.dStartDate) / 86400;
      bDayOk := bDayOk AND nDayP >= nSDay AND (nDayP - nSDay) MOD INT_TO_LINT(stW.nDaysBetweenRuns) = 0;
      bPrevOk := bPrevOk AND nDayP - 1 >= nSDay AND (nDayP - 1 - nSDay) MOD INT_TO_LINT(stW.nDaysBetweenRuns) = 0;
    END_IF;
    IF nSt < nSp THEN
      WindowIn := bDayOk AND nMs >= nSt AND nMs < nSp;
    ELSE
      WindowIn := (bDayOk AND nMs >= nSt) OR (bPrevOk AND nMs < nSp);
    END_IF;
  END_IF;
END_METHOD

(* the window's next start or stop after this local time, in seconds (-1 = none) *)
METHOD PRIVATE WindowNext : LINT
  VAR_INPUT
    stW : REFERENCE TO ST_SchedWindow;
    nAt : LINT;
  END_VAR
  VAR
    nDay0 : LINT;
    nA : LINT;
    nB : LINT;
  END_VAR
  WindowNext := -1;
  IF WindowOk(stW := stW) AND stW.bWindowOn AND stW.todStartTime <> stW.todStopTime THEN
    nDay0 := (nAt / 86400) * 86400;
    nA := nDay0 + (TOD_TO_LINT(stW.todStartTime) + 999) / 1000;
    IF nA <= nAt THEN nA := nA + 86400; END_IF;
    nB := nDay0 + (TOD_TO_LINT(stW.todStopTime) + 999) / 1000;
    IF nB <= nAt THEN nB := nB + 86400; END_IF;
    WindowNext := MIN(nA, nB);
  END_IF;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bScheduleActive := FALSE;
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();
nLo := LOWER_BOUND(aWindows, 1);
nHi := UPPER_BOUND(aWindows, 1);

(* kept settings and windows; a bad write is put back *)
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
    FOR nI := 1 TO MIN(nHi - nLo + 1, cMaxKept) DO
      IF (nKeptMask AND SHL(WORD#1, nI - 1)) <> 0 THEN
        aWindows[nLo + nI - 1] := aKeptWindow[nI];
      END_IF;
    END_FOR;
  ELSE
    stKept := refData.set;
    nKeptLayout := cLayout;
  END_IF;
END_IF;
bOkSet := SetOk(stS := refData.set);
IF bOkSet THEN
  stKept := refData.set;
ELSIF SetOk(stS := stKept) THEN
  refData.sts.eSettingRefusedErrorId := SetWhy(stS := refData.set);
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
  bOkSet := TRUE;
END_IF;
refData.sts.nBadSettingWindow := 0;
FOR nI := 1 TO nHi - nLo + 1 DO
  nJ := nLo + nI - 1;
  nBit := 0;
  IF nI <= cMaxKept THEN
    nBit := SHL(WORD#1, nI - 1);
  END_IF;
  IF WindowOk(stW := aWindows[nJ]) THEN
    IF nI <= cMaxKept THEN
      aKeptWindow[nI] := aWindows[nJ];
      nKeptMask := nKeptMask OR nBit;
    END_IF;
  ELSIF nBit <> 0 AND (nKeptMask AND nBit) <> 0 THEN
    refData.sts.eSettingRefusedErrorId := WindowWhy(stW := aWindows[nJ]);
    aWindows[nJ] := aKeptWindow[nI];
    refData.sts.bSettingRefused := TRUE;
  ELSIF refData.sts.nBadSettingWindow = 0 THEN
    refData.sts.nBadSettingWindow := DINT_TO_INT(nI);
  END_IF;
END_FOR;
bHourPulse := FALSE;
bDayPulse := FALSE;
bEn := bEnable AND refData.set.bScheduleOn AND bOkSet;

(* the clock: no real-time clock on the board, unwired = no clock (never the system clock) *)
nSecs := DT_TO_LINT(dtLocalTime);
IF NOT bSeen OR nSecs <> nLastSecs THEN
  bSeen := TRUE;
  nLastSecs := nSecs;
  tLastMove := tNow;
END_IF;
bClockSynced := F_ClockOk(dtClockUtc := dtLocalTime) AND tNow - tLastMove <= T#5s;
nLocal := nSecs + INT_TO_LINT(refData.set.nUtcOffsetMinutes) * 60;
refData.det.dtLocalTime := LINT_TO_DT(nLocal);

(* the windows now *)
bSched := FALSE;
nActiveWindow := 0;
refData.sts.nActiveWindowBits := 0;
IF bClockSynced THEN
  FOR nI := 1 TO nHi - nLo + 1 DO
    IF WindowIn(stW := aWindows[nLo + nI - 1], nAt := nLocal) THEN
      bSched := TRUE;
      IF nActiveWindow = 0 THEN
        nActiveWindow := DINT_TO_INT(nI);
      END_IF;
      IF nI <= 32 THEN
        refData.sts.nActiveWindowBits := refData.sts.nActiveWindowBits OR SHL(DWORD#1, nI - 1);
      END_IF;
    END_IF;
  END_FOR;
END_IF;

IF bClockSynced THEN
  nDayNo := nLocal / 86400;
  nHourNo := nLocal / 3600;
  refData.sts.nDayOfWeek := LINT_TO_INT((nDayNo + 3) MOD 7) + 1;
  IF NOT bMarks THEN
    bMarks := TRUE;
    nLastHour := nHourNo;
    nLastDay := nDayNo;
  ELSE
    IF nHourNo > nLastHour THEN
      bHourPulse := TRUE;
      nLastHour := nHourNo;
    ELSIF nHourNo < nLastHour - 1 THEN
      nLastHour := nHourNo;       (* set back more than an hour: follow it *)
    END_IF;
    IF nDayNo > nLastDay THEN
      bDayPulse := TRUE;
      nLastDay := nDayNo;
    ELSIF nDayNo < nLastDay - 1 THEN
      nLastDay := nDayNo;
    END_IF;
  END_IF;
  (* the next change, once a second: step through the windows' boundaries (8 days at most) *)
  IF nLocal <> nCalcSecs THEN
    nCalcSecs := nLocal;
    nProbe := nLocal;
    nNc := -1;
    FOR nC := 1 TO 64 DO
      nCand := -1;
      FOR nJ := nLo TO nHi DO
        nW := WindowNext(stW := aWindows[nJ], nAt := nProbe);
        IF nW > 0 AND (nCand < 0 OR nW < nCand) THEN
          nCand := nW;
        END_IF;
      END_FOR;
      IF nCand < 0 OR nCand > nLocal + 8 * 86400 THEN
        EXIT;
      END_IF;
      bFound := FALSE;
      FOR nJ := nLo TO nHi DO
        IF WindowIn(stW := aWindows[nJ], nAt := nCand) THEN
          bFound := TRUE;
        END_IF;
      END_FOR;
      IF bFound <> bSched THEN
        nNc := nCand;
        EXIT;
      END_IF;
      nProbe := nCand;
    END_FOR;
    IF nNc >= 0 THEN
      refData.sts.dtNextChange := LINT_TO_DT(nNc);
    ELSE
      refData.sts.dtNextChange := DT#1970-01-01-00:00:00;
    END_IF;
  END_IF;
ELSE
  refData.sts.nDayOfWeek := 0;
  refData.sts.dtNextChange := DT#1970-01-01-00:00:00;
  nCalcSecs := -1;
END_IF;
IF bClockSynced AND DT_TO_LINT(refData.sts.dtNextChange) > nLocal THEN
  refData.det.tNextChangeTimeLeft := LINT_TO_TIME((DT_TO_LINT(refData.sts.dtNextChange) - nLocal) * 1000);
ELSE
  refData.det.tNextChangeTimeLeft := T#0s;
END_IF;

(* overrides: once per request; Off wins, then Cancel, then On *)
bReqOn := bOverrideOn OR (refData.bCmdOverrideOn AND NOT bOnSeen);
bReqOff := bOverrideOff OR (refData.bCmdOverrideOff AND NOT bOffSeen);
bReqCancel := refData.bCmdCancelOverride AND NOT bCancelSeen;
bOnSeen := refData.bCmdOverrideOn;
bOffSeen := refData.bCmdOverrideOff;
bCancelSeen := refData.bCmdCancelOverride;
refData.bCmdOverrideOn := FALSE;
refData.bCmdOverrideOff := FALSE;
refData.bCmdCancelOverride := FALSE;
IF bReqOff THEN
  bOverrideActive := TRUE;
  bOvState := FALSE;
  tOvStart := tNow;
  bOvSched := bSched;
ELSIF bReqCancel THEN
  bOverrideActive := FALSE;
ELSIF bReqOn THEN
  bOverrideActive := TRUE;
  bOvState := TRUE;
  tOvStart := tNow;
  bOvSched := bSched;
END_IF;
refData.det.tOverrideTimeLeft := T#0s;
IF NOT bEn THEN
  bOverrideActive := FALSE;
ELSIF bOverrideActive THEN
  IF refData.set.tOverrideTime > T#0s THEN
    IF tNow - tOvStart >= refData.set.tOverrideTime THEN
      bOverrideActive := FALSE;
    ELSE
      refData.det.tOverrideTimeLeft := refData.set.tOverrideTime - (tNow - tOvStart);
    END_IF;
  ELSIF bSched <> bOvSched THEN
    bOverrideActive := FALSE;         (* untimed: ends when the schedule changes *)
  END_IF;
END_IF;
IF NOT bEn THEN
  bScheduleActive := FALSE;
  nActiveWindow := 0;
ELSIF bOverrideActive THEN
  bScheduleActive := bOvState;
ELSE
  bScheduleActive := bSched;
END_IF;
IF SystemReset() THEN
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;
refData.sts.bScheduleActive := bScheduleActive;
refData.sts.bOverrideActive := bOverrideActive;

bError := NOT bOkSet;
bWarning := NOT bError AND ((bEn AND NOT bClockSynced) OR refData.sts.nBadSettingWindow > 0 OR refData.sts.bSettingRefused);
IF bError THEN
  eErrorId := E_UtError.BadSetting;
ELSIF bEn AND NOT bClockSynced THEN
  eErrorId := E_UtError.NoClock;
ELSIF refData.sts.nBadSettingWindow > 0 THEN
  eErrorId := E_UtError.BadSetting;
ELSIF refData.sts.bSettingRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN
  eState := E_State.Fault;
ELSIF NOT bEn THEN
  eState := E_State.Off;
ELSIF bScheduleActive THEN
  eState := E_State.Running;
ELSE
  eState := E_State.Idle;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK