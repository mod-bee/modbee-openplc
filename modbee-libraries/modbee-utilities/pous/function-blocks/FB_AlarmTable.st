(* FB_AlarmTable — the site's on-panel alarms in one block, with the lamps, the beacon, the siren and the healthy
relay. Optional: alarm lists, history and notifications are the HMI / SCADA's; the blocks detect and act
without this.
Pins: bSilence, bReset (acknowledge everything; clear the latched / locked rows whose condition has gone),
bLampTest (held: every light and the siren on), refData, and the tables the project declares (VAR_IN_OUT, the
same size, at most 32 rows): aAlarmSet (each alarm's settings) and aAlarm (each alarm's live row: the project
writes aAlarm[i].bIn on the alarm's own rung) -> bFaultLamp, bWarnLamp (fast flash new, slow flash returned,
steady acknowledged; all lamps in step), bBeacon, bSiren (with set.tSirenTimeout; a new alarm sounds again),
bHealthy (the common alarm relay: TRUE while no trip, fail-safe; set.bRelayOnWarning: no warning either), nOn.
Each row: eResponse Off / Warn / Trip; the condition after tDelay (on) and tRecover (off); eReset Auto (clears
itself), Manual (latches until a reset with the condition gone), Retry (clears itself, locks out after
nMaxRetries raises within set.tRetryWindow); bSiren; tRearm (silenced or acknowledged but still on after this
long: it annunciates again; 0 = never); eCode (the HMI's text for it; the project's, set at the declaration).
The row number is the alarm's number for the HMI. Bad times act as 0 (louder, never quieter).
Kept (a retained last-good copy, restored at power-up, a bad write put back, sts.bRefused / eRefusedWhy): set, and
each row's
settings but eCode packed into two DWORDs for the first 32 rows (tDelay in 10 ms steps up to 46 h, tRecover in
100 ms steps up to 109 min, tRearm in seconds up to 18 h, nMaxRetries 0..7). Nothing else is kept: a condition
still present raises again after a power cut.
bChanged is TRUE for one scan when an alarm comes, goes or is acknowledged (counts or the latest row change). *)

FUNCTION_BLOCK FB_AlarmTable EXTENDS FB_Object
  VAR_INPUT
    bSilence : BOOL R_EDGE;
    bReset : BOOL R_EDGE; (* acknowledge all; clear latched / locked rows whose condition has gone *)
    bLampTest : BOOL;
    refData : REFERENCE TO ST_AlarmTableData;
  END_VAR
  VAR_IN_OUT
    aAlarmSet : ARRAY [*] OF ST_ALARMSET;
    aAlarm : ARRAY [*] OF ST_ALARM;
  END_VAR
  VAR_OUTPUT
    bFaultLamp : BOOL;
    bWarnLamp : BOOL;
    bBeacon : BOOL;
    bSiren : BOOL;
    bHealthy : BOOL; (* the common alarm relay (fail-safe) *)
    nOn : INT;
    bChanged : BOOL; (* one scan: an alarm came, went or was acknowledged *)
  END_VAR
  VAR RETAIN
    stKept : ST_AlarmTableSet;
    aKeptRow : ARRAY [1..64] OF DWORD; (* two per row *)
    nKeptRows : INT;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
    cMaxRows : INT := 32;
  END_VAR
  VAR
    nLatestWas : INT;
    bRstSeen : BOOL; (* the commands act once per write (a master that keeps writing TRUE) *)
    bSilSeen : BOOL;
    tSirenAt : TIME;
    bSoundPrev : BOOL;
  END_VAR
  VAR_TEMP
    bOkSet : BOOL;
    bRowsOk : BOOL;
    bCfgBad : BOOL;
    bAck : BOOL;
    bRst : BOOL;
    bSil : BOOL;
    bRaise : BOOL;
    bTrip : BOOL;
    bSounding : BOOL;
    bAnySound : BOOL;
    bTripNew : BOOL;
    bTripRet : BOOL;
    bTripOn : BOOL;
    bWarnNew : BOOL;
    bWarnRet : BOOL;
    bWarnOn : BOOL;
    bFast : BOOL;
    bSlow : BOOL;
    nRows : INT;
    nI : INT;
    nR : DINT;
    nS : DINT;
    nFirstTrip : INT;
    nFirstWarn : INT;
    nTrips : INT;
    nUnacked : INT;
  END_VAR


METHOD PRIVATE SetWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_AlarmTableSet;
  END_VAR
  SetWhy := E_UtError.None;
  IF NOT (stS.tSirenTimeout >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tFastFlash > T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tSlowFlash > T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tRetryWindow >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_AlarmTableSet;
  END_VAR
  SetOk := SetWhy(stS := stS) = E_UtError.None;
END_METHOD

(* one row's settings are usable and fit the kept form *)
METHOD PRIVATE RowWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_AlarmSet;
  END_VAR
  RowWhy := E_UtError.None;
  IF NOT (stS.eResponse = E_Response.Off OR stS.eResponse = E_Response.Warn OR stS.eResponse = E_Response.Trip
          OR stS.eResponse = E_Response.Signal) THEN
    RowWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.eReset = E_ResetMode.Auto OR stS.eReset = E_ResetMode.Manual OR stS.eReset = E_ResetMode.Retry) THEN
    RowWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.tDelay >= T#0s) THEN
    RowWhy := E_UtError.TimeBad;
  ELSIF NOT (TIME_TO_LINT(stS.tDelay) / 10 <= 16#FFFFFF) THEN
    RowWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tRecover >= T#0s) THEN
    RowWhy := E_UtError.TimeBad;
  ELSIF NOT (TIME_TO_LINT(stS.tRecover) / 100 <= 16#FFFF) THEN
    RowWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tRearm >= T#0s) THEN
    RowWhy := E_UtError.TimeBad;
  ELSIF NOT (TIME_TO_LINT(stS.tRearm) / 1000 <= 16#FFFF) THEN
    RowWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.nMaxRetries <= 7) THEN
    RowWhy := E_UtError.ProtectionBad;
  END_IF;
END_METHOD

METHOD PRIVATE RowOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_AlarmSet;
  END_VAR
  RowOk := RowWhy(stS := stS) = E_UtError.None;
END_METHOD

METHOD PRIVATE Pack : BOOL
  VAR_INPUT
    nRow : INT;
    stS : REFERENCE TO ST_AlarmSet;
  END_VAR
  aKeptRow[2 * nRow - 1] := USINT_TO_DWORD(TO_USINT(stS.eResponse)) OR SHL(USINT_TO_DWORD(TO_USINT(stS.eReset)), 2)
                            OR SHL(BOOL_TO_DWORD(stS.bSiren), 4) OR SHL(USINT_TO_DWORD(stS.nMaxRetries), 5)
                            OR SHL(LINT_TO_DWORD(TIME_TO_LINT(stS.tDelay) / 10), 8);
  aKeptRow[2 * nRow] := LINT_TO_DWORD(TIME_TO_LINT(stS.tRecover) / 100)
                        OR SHL(LINT_TO_DWORD(TIME_TO_LINT(stS.tRearm) / 1000), 16);
  Pack := TRUE;
END_METHOD

METHOD PRIVATE Unpack : BOOL
  VAR_INPUT
    nRow : INT;
    stS : REFERENCE TO ST_AlarmSet;
  END_VAR
  VAR
    nW1 : DWORD;
    nW2 : DWORD;
  END_VAR
  nW1 := aKeptRow[2 * nRow - 1];
  nW2 := aKeptRow[2 * nRow];
  CASE DWORD_TO_USINT(nW1 AND DWORD#16#3) OF
    0: stS.eResponse := E_Response.Off;
    1: stS.eResponse := E_Response.Warn;
    2: stS.eResponse := E_Response.Trip;
  ELSE
    stS.eResponse := E_Response.Signal;
  END_CASE;
  CASE DWORD_TO_USINT(SHR(nW1, 2) AND DWORD#16#3) OF
    0: stS.eReset := E_ResetMode.Manual;
    1: stS.eReset := E_ResetMode.Retry;
  ELSE
    stS.eReset := E_ResetMode.Auto;
  END_CASE;
  stS.bSiren := (SHR(nW1, 4) AND DWORD#16#1) <> DWORD#0;
  stS.nMaxRetries := DWORD_TO_USINT(SHR(nW1, 5) AND DWORD#16#7);
  stS.tDelay := LINT_TO_TIME(DWORD_TO_LINT(SHR(nW1, 8)) * 10);
  stS.tRecover := LINT_TO_TIME(DWORD_TO_LINT(nW2 AND DWORD#16#FFFF) * 100);
  stS.tRearm := LINT_TO_TIME(DWORD_TO_LINT(SHR(nW2, 16)) * 1000);
  Unpack := TRUE;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bHealthy := FALSE;
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();
nRows := DINT_TO_INT(UPPER_BOUND(aAlarm, 1) - LOWER_BOUND(aAlarm, 1) + 1);
bCfgBad := nRows < 1 OR nRows > cMaxRows
           OR UPPER_BOUND(aAlarmSet, 1) - LOWER_BOUND(aAlarmSet, 1) + 1 <> INT_TO_DINT(nRows);
IF bCfgBad THEN
  nRows := 0;
END_IF;

(* kept settings; a bad write is put back *)
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
    FOR nI := 1 TO MIN(nRows, nKeptRows) DO
      nS := LOWER_BOUND(aAlarmSet, 1) + nI - 1;
      Unpack(nRow := nI, stS := aAlarmSet[nS]);
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
  refData.sts.eRefusedWhy := SetWhy(stS := refData.set);
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
  bOkSet := TRUE;
END_IF;
bRowsOk := TRUE;
FOR nI := 1 TO nRows DO
  nS := LOWER_BOUND(aAlarmSet, 1) + nI - 1;
  IF RowOk(stS := aAlarmSet[nS]) THEN
    Pack(nRow := nI, stS := aAlarmSet[nS]);
  ELSIF nI <= nKeptRows THEN
    refData.sts.eRefusedWhy := RowWhy(stS := aAlarmSet[nS]);
    Unpack(nRow := nI, stS := aAlarmSet[nS]);
    refData.sts.bRefused := TRUE;
  ELSE
    bRowsOk := FALSE;
  END_IF;
END_FOR;
IF nRows > nKeptRows AND bRowsOk THEN
  nKeptRows := nRows;
END_IF;

(* the commands: acknowledge and reset together, silence *)
bRst := bReset OR SystemReset() OR (refData.bCmdReset AND NOT bRstSeen);   (* once per write *)
bAck := bRst;
bSil := bSilence OR (refData.bCmdSilence AND NOT bSilSeen);
bRstSeen := refData.bCmdReset;
bSilSeen := refData.bCmdSilence;
refData.bCmdReset := FALSE;
refData.bCmdSilence := FALSE;
IF bRst THEN
  refData.sts.nFirstOut := 0;
  refData.sts.bRefused := FALSE;
  refData.sts.eRefusedWhy := E_UtError.None;
END_IF;

(* each alarm *)
nOn := 0;
nTrips := 0;
nUnacked := 0;
nFirstTrip := 0;
nFirstWarn := 0;
bAnySound := FALSE;
bTripNew := FALSE; bTripRet := FALSE; bTripOn := FALSE;
bWarnNew := FALSE; bWarnRet := FALSE; bWarnOn := FALSE;
FOR nI := 1 TO nRows DO
  nR := LOWER_BOUND(aAlarm, 1) + nI - 1;
  nS := LOWER_BOUND(aAlarmSet, 1) + nI - 1;
  bRaise := F_AlarmRun(tNow := tNow, bAck := bAck, bRst := bRst, bSil := bSil, tRetryWindow := refData.set.tRetryWindow,
                       stS := aAlarmSet[nS], stA := aAlarm[nR]);
  bSounding := aAlarm[nR].bSounding;
  IF bRaise THEN
    refData.sts.nLatest := nI;
    refData.sts.eLatestCode := aAlarmSet[nS].eCode;
    IF refData.sts.nFirstOut = 0 THEN
      refData.sts.nFirstOut := nI;
    END_IF;
  END_IF;

  (* into the summary *)
  bTrip := aAlarmSet[nS].eResponse = E_Response.Trip;
  IF aAlarm[nR].bQ THEN
    nOn := nOn + 1;
    IF bTrip THEN
      nTrips := nTrips + 1;
      IF nFirstTrip = 0 THEN nFirstTrip := nI; END_IF;
    ELSIF nFirstWarn = 0 THEN
      nFirstWarn := nI;
    END_IF;
  END_IF;
  IF aAlarm[nR].bUnacked THEN
    nUnacked := nUnacked + 1;
  END_IF;
  IF bTrip THEN
    bTripNew := bTripNew OR (aAlarm[nR].bQ AND aAlarm[nR].bUnacked);
    bTripRet := bTripRet OR (NOT aAlarm[nR].bQ AND aAlarm[nR].bUnacked);
    bTripOn := bTripOn OR (aAlarm[nR].bQ AND NOT aAlarm[nR].bUnacked);
  ELSIF aAlarmSet[nS].eResponse <> E_Response.Off THEN
    bWarnNew := bWarnNew OR (aAlarm[nR].bQ AND aAlarm[nR].bUnacked);
    bWarnRet := bWarnRet OR (NOT aAlarm[nR].bQ AND aAlarm[nR].bUnacked);
    bWarnOn := bWarnOn OR (aAlarm[nR].bQ AND NOT aAlarm[nR].bUnacked);
  END_IF;
  bAnySound := bAnySound OR bSounding;
END_FOR;

(* the lamps, beacon, siren and healthy relay *)
bFast := F_Blink(tOnTime := refData.set.tFastFlash, tOffTime := refData.set.tFastFlash);
bSlow := F_Blink(tOnTime := refData.set.tSlowFlash, tOffTime := refData.set.tSlowFlash);
bFaultLamp := (bTripNew AND bFast) OR (bTripRet AND NOT bTripNew AND bSlow) OR (bTripOn AND NOT bTripNew AND NOT bTripRet);
bWarnLamp := (bWarnNew AND bFast) OR (bWarnRet AND NOT bWarnNew AND bSlow) OR (bWarnOn AND NOT bWarnNew AND NOT bWarnRet);
bBeacon := nTrips > 0 OR bTripNew OR bTripRet
           OR (refData.set.bBeaconWarnings AND (nOn > nTrips OR bWarnNew OR bWarnRet));
IF bAnySound AND NOT bSoundPrev THEN
  tSirenAt := tNow;               (* a new alarm sounds again *)
END_IF;
bSoundPrev := bAnySound;
bSiren := bAnySound AND (refData.set.tSirenTimeout <= T#0s OR tNow - tSirenAt < refData.set.tSirenTimeout);
bHealthy := nTrips = 0 AND NOT (refData.set.bRelayOnWarning AND nOn > 0) AND NOT bCfgBad;
IF bLampTest THEN
  bFaultLamp := TRUE;
  bWarnLamp := TRUE;
  bBeacon := TRUE;
  bSiren := TRUE;
END_IF;

(* status *)
IF nFirstTrip > 0 THEN
  refData.sts.nFirst := nFirstTrip;
ELSE
  refData.sts.nFirst := nFirstWarn;
END_IF;
IF refData.sts.nFirst > 0 THEN
  refData.sts.eFirstCode := aAlarmSet[LOWER_BOUND(aAlarmSet, 1) + refData.sts.nFirst - 1].eCode;
ELSE
  refData.sts.eFirstCode := E_UtError.None;
END_IF;
bChanged := NOT bFirstScan AND (nOn <> refData.sts.nOn OR nUnacked <> refData.sts.nUnacked
                                OR nTrips <> refData.sts.nTrips OR refData.sts.nLatest <> nLatestWas);
nLatestWas := refData.sts.nLatest;
refData.sts.nOn := nOn;
refData.sts.nTrips := nTrips;
refData.sts.nUnacked := nUnacked;
bError := bCfgBad OR NOT bRowsOk OR NOT bOkSet;
bWarning := NOT bError AND refData.sts.bRefused;
IF bError THEN
  eErrorId := E_UtError.BadSetting;
ELSIF refData.sts.bRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN eState := E_State.Fault; ELSIF nOn > 0 THEN eState := E_State.Held; ELSE eState := E_State.Running; END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK