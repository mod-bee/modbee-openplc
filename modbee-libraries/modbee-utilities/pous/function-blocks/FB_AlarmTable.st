(* FB_AlarmTable — the site's on-panel alarms in one block, with the lamps, the beacon, the horn and the fail-safe
relay. Optional: alarm lists, history and notifications are the HMI / SCADA's; the blocks detect and act
without this.
Pins: bSilenceHorn, bResetFaults (acknowledge everything; clear the latched / locked rows whose condition has gone),
bLampTest (held: every light and the horn on), refData, and the tables the project declares (VAR_IN_OUT, the
same size, at most 32 rows): aAlarmSettings (each alarm's settings) and aAlarms (each alarm's live row: the project
writes aAlarms[i].bConditionPresent on the alarm's own rung) -> bFaultLamp, bWarningLamp (fast flash new, slow flash returned,
steady acknowledged; all lamps in step), bBeacon, bHorn (with set.tHornStopsAfter; a new alarm sounds again),
bFailSafeRelay (the common alarm relay: TRUE while no trip, fail-safe; set.bRelayDropsOnWarning: no warning either), nAlarmsActive.
Each row: eActionOnFault Off / Warn / Trip; the condition after tTripDelay (on) and tAutoRecoverAfter (off); eResetMode Auto (clears
itself), Manual (latches until a reset with the condition gone), Retry (clears itself, locks out after
nMaxRetriesBeforeLockout raises within set.tRetryCountWindow); bHorn; tReAlarmAfter (silenced or acknowledged but still on after this
long: it annunciates again; 0 = never); eAlarmCode (the HMI's text for it; the project's, set at the declaration).
The row number is the alarm's number for the HMI. Bad times act as 0 (louder, never quieter).
Kept (a retained last-good copy, restored at power-up, a bad write put back, sts.bSettingRefused / eSettingRefusedErrorId): set, and
each row's
settings but eAlarmCode packed into two DWORDs for the first 32 rows (tTripDelay in 10 ms steps up to 46 h, tAutoRecoverAfter in
100 ms steps up to 109 min, tReAlarmAfter in seconds up to 18 h, nMaxRetriesBeforeLockout 0..7). Nothing else is kept: a condition
still present raises again after a power cut.
bAlarmsChanged is TRUE for one scan when an alarm comes, goes or is acknowledged (counts or the latest row change). *)

FUNCTION_BLOCK FB_AlarmTable EXTENDS FB_Object
  VAR_INPUT
    bSilenceHorn : BOOL R_EDGE; (* rising edge: silence the horn *)
    bResetFaults : BOOL R_EDGE; (* acknowledge all; clear latched / locked rows whose condition has gone *)
    bLampTest : BOOL; (* held: every lamp and the horn on *)
    refData : REFERENCE TO ST_AlarmTableData; (* the table's record *)
  END_VAR
  VAR_IN_OUT
    aAlarmSettings : ARRAY [*] OF ST_ALARMSET; (* each alarm's settings (same size as aAlarm, at most 32) *)
    aAlarms : ARRAY [*] OF ST_ALARM; (* each alarm's live row; the project writes aAlarm[i].bConditionPresent *)
  END_VAR
  VAR_OUTPUT
    bFaultLamp : BOOL; (* fault lamp: fast flash new, slow flash cleared, steady acknowledged *)
    bWarningLamp : BOOL; (* warning lamp: fast flash new, slow flash cleared, steady acknowledged *)
    bBeacon : BOOL; (* the beacon output *)
    bHorn : BOOL; (* the horn output *)
    bFailSafeRelay : BOOL; (* the common alarm relay (fail-safe) *)
    nAlarmsActive : INT; (* rows on now *)
    bAlarmsChanged : BOOL; (* one scan: an alarm came, went or was acknowledged *)
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
  IF NOT (stS.tHornStopsAfter >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tFastFlash > T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tSlowFlash > T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tRetryCountWindow >= T#0s) THEN
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
  IF NOT (stS.eActionOnFault = E_Response.Off OR stS.eActionOnFault = E_Response.Warn OR stS.eActionOnFault = E_Response.Trip
          OR stS.eActionOnFault = E_Response.Signal) THEN
    RowWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.eResetMode = E_ResetMode.Auto OR stS.eResetMode = E_ResetMode.Manual OR stS.eResetMode = E_ResetMode.Retry) THEN
    RowWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.tTripDelay >= T#0s) THEN
    RowWhy := E_UtError.TimeBad;
  ELSIF NOT (TIME_TO_LINT(stS.tTripDelay) / 10 <= 16#FFFFFF) THEN
    RowWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tAutoRecoverAfter >= T#0s) THEN
    RowWhy := E_UtError.TimeBad;
  ELSIF NOT (TIME_TO_LINT(stS.tAutoRecoverAfter) / 100 <= 16#FFFF) THEN
    RowWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tReAlarmAfter >= T#0s) THEN
    RowWhy := E_UtError.TimeBad;
  ELSIF NOT (TIME_TO_LINT(stS.tReAlarmAfter) / 1000 <= 16#FFFF) THEN
    RowWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.nMaxRetriesBeforeLockout >= 0 AND stS.nMaxRetriesBeforeLockout <= 7) THEN
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
  aKeptRow[2 * nRow - 1] := USINT_TO_DWORD(TO_USINT(stS.eActionOnFault)) OR SHL(USINT_TO_DWORD(TO_USINT(stS.eResetMode)), 2)
                            OR SHL(BOOL_TO_DWORD(stS.bSoundsHorn), 4) OR SHL(INT_TO_DWORD(stS.nMaxRetriesBeforeLockout), 5)
                            OR SHL(LINT_TO_DWORD(TIME_TO_LINT(stS.tTripDelay) / 10), 8);
  aKeptRow[2 * nRow] := LINT_TO_DWORD(TIME_TO_LINT(stS.tAutoRecoverAfter) / 100)
                        OR SHL(LINT_TO_DWORD(TIME_TO_LINT(stS.tReAlarmAfter) / 1000), 16);
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
    0: stS.eActionOnFault := E_Response.Off;
    1: stS.eActionOnFault := E_Response.Warn;
    2: stS.eActionOnFault := E_Response.Trip;
  ELSE
    stS.eActionOnFault := E_Response.Signal;
  END_CASE;
  CASE DWORD_TO_USINT(SHR(nW1, 2) AND DWORD#16#3) OF
    0: stS.eResetMode := E_ResetMode.Manual;
    1: stS.eResetMode := E_ResetMode.Retry;
  ELSE
    stS.eResetMode := E_ResetMode.Auto;
  END_CASE;
  stS.bSoundsHorn := (SHR(nW1, 4) AND DWORD#16#1) <> DWORD#0;
  stS.nMaxRetriesBeforeLockout := DWORD_TO_INT(SHR(nW1, 5) AND DWORD#16#7);
  stS.tTripDelay := LINT_TO_TIME(DWORD_TO_LINT(SHR(nW1, 8)) * 10);
  stS.tAutoRecoverAfter := LINT_TO_TIME(DWORD_TO_LINT(nW2 AND DWORD#16#FFFF) * 100);
  stS.tReAlarmAfter := LINT_TO_TIME(DWORD_TO_LINT(SHR(nW2, 16)) * 1000);
  Unpack := TRUE;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bFailSafeRelay := FALSE;
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();
nRows := DINT_TO_INT(UPPER_BOUND(aAlarms, 1) - LOWER_BOUND(aAlarms, 1) + 1);
bCfgBad := nRows < 1 OR nRows > cMaxRows
           OR UPPER_BOUND(aAlarmSettings, 1) - LOWER_BOUND(aAlarmSettings, 1) + 1 <> INT_TO_DINT(nRows);
IF bCfgBad THEN
  nRows := 0;
END_IF;

(* kept settings; a bad write is put back *)
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
    FOR nI := 1 TO MIN(nRows, nKeptRows) DO
      nS := LOWER_BOUND(aAlarmSettings, 1) + nI - 1;
      Unpack(nRow := nI, stS := aAlarmSettings[nS]);
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
bRowsOk := TRUE;
FOR nI := 1 TO nRows DO
  nS := LOWER_BOUND(aAlarmSettings, 1) + nI - 1;
  IF RowOk(stS := aAlarmSettings[nS]) THEN
    Pack(nRow := nI, stS := aAlarmSettings[nS]);
  ELSIF nI <= nKeptRows THEN
    refData.sts.eSettingRefusedErrorId := RowWhy(stS := aAlarmSettings[nS]);
    Unpack(nRow := nI, stS := aAlarmSettings[nS]);
    refData.sts.bSettingRefused := TRUE;
  ELSE
    bRowsOk := FALSE;
  END_IF;
END_FOR;
IF nRows > nKeptRows AND bRowsOk THEN
  nKeptRows := nRows;
END_IF;

(* the commands: acknowledge and reset together, silence *)
bRst := bResetFaults OR SystemReset() OR (refData.bCmdResetFaults AND NOT bRstSeen);   (* once per write *)
bAck := bRst;
bSil := bSilenceHorn OR (refData.bCmdSilenceHorn AND NOT bSilSeen);
bRstSeen := refData.bCmdResetFaults;
bSilSeen := refData.bCmdSilenceHorn;
refData.bCmdResetFaults := FALSE;
refData.bCmdSilenceHorn := FALSE;
IF bRst THEN
  refData.sts.nFirstOutRow := 0;
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;

(* each alarm *)
nAlarmsActive := 0;
nTrips := 0;
nUnacked := 0;
nFirstTrip := 0;
nFirstWarn := 0;
bAnySound := FALSE;
bTripNew := FALSE; bTripRet := FALSE; bTripOn := FALSE;
bWarnNew := FALSE; bWarnRet := FALSE; bWarnOn := FALSE;
FOR nI := 1 TO nRows DO
  nR := LOWER_BOUND(aAlarms, 1) + nI - 1;
  nS := LOWER_BOUND(aAlarmSettings, 1) + nI - 1;
  bRaise := F_AlarmRun(tNow := tNow, bAcknowledge := bAck, bResetRequest := bRst, bSilence := bSil, tRetryCountWindow := refData.set.tRetryCountWindow,
                       stSettings := aAlarmSettings[nS], stAlarm := aAlarms[nR]);
  bSounding := aAlarms[nR].bCallsForHorn;
  IF bRaise THEN
    refData.sts.nLatestAlarmRow := nI;
    refData.sts.eLatestAlarmCode := aAlarmSettings[nS].eAlarmCode;
    IF refData.sts.nFirstOutRow = 0 THEN
      refData.sts.nFirstOutRow := nI;
    END_IF;
  END_IF;

  (* into the summary *)
  bTrip := aAlarmSettings[nS].eActionOnFault = E_Response.Trip;
  IF aAlarms[nR].bAlarmOn THEN
    nAlarmsActive := nAlarmsActive + 1;
    IF bTrip THEN
      nTrips := nTrips + 1;
      IF nFirstTrip = 0 THEN nFirstTrip := nI; END_IF;
    ELSIF nFirstWarn = 0 THEN
      nFirstWarn := nI;
    END_IF;
  END_IF;
  IF aAlarms[nR].bUnacknowledged THEN
    nUnacked := nUnacked + 1;
  END_IF;
  IF bTrip THEN
    bTripNew := bTripNew OR (aAlarms[nR].bAlarmOn AND aAlarms[nR].bUnacknowledged);
    bTripRet := bTripRet OR (NOT aAlarms[nR].bAlarmOn AND aAlarms[nR].bUnacknowledged);
    bTripOn := bTripOn OR (aAlarms[nR].bAlarmOn AND NOT aAlarms[nR].bUnacknowledged);
  ELSIF aAlarmSettings[nS].eActionOnFault <> E_Response.Off THEN
    bWarnNew := bWarnNew OR (aAlarms[nR].bAlarmOn AND aAlarms[nR].bUnacknowledged);
    bWarnRet := bWarnRet OR (NOT aAlarms[nR].bAlarmOn AND aAlarms[nR].bUnacknowledged);
    bWarnOn := bWarnOn OR (aAlarms[nR].bAlarmOn AND NOT aAlarms[nR].bUnacknowledged);
  END_IF;
  bAnySound := bAnySound OR bSounding;
END_FOR;

(* the lamps, beacon, horn and fail-safe relay *)
bFast := F_Blink(tOnTime := refData.set.tFastFlash, tOffTime := refData.set.tFastFlash);
bSlow := F_Blink(tOnTime := refData.set.tSlowFlash, tOffTime := refData.set.tSlowFlash);
bFaultLamp := (bTripNew AND bFast) OR (bTripRet AND NOT bTripNew AND bSlow) OR (bTripOn AND NOT bTripNew AND NOT bTripRet);
bWarningLamp := (bWarnNew AND bFast) OR (bWarnRet AND NOT bWarnNew AND bSlow) OR (bWarnOn AND NOT bWarnNew AND NOT bWarnRet);
bBeacon := nTrips > 0 OR bTripNew OR bTripRet
           OR (refData.set.bBeaconOnWarning AND (nAlarmsActive > nTrips OR bWarnNew OR bWarnRet));
IF bAnySound AND NOT bSoundPrev THEN
  tSirenAt := tNow;               (* a new alarm sounds again *)
END_IF;
bSoundPrev := bAnySound;
bHorn := bAnySound AND (refData.set.tHornStopsAfter <= T#0s OR tNow - tSirenAt < refData.set.tHornStopsAfter);
bFailSafeRelay := nTrips = 0 AND NOT (refData.set.bRelayDropsOnWarning AND nAlarmsActive > 0) AND NOT bCfgBad;
IF bLampTest THEN
  bFaultLamp := TRUE;
  bWarningLamp := TRUE;
  bBeacon := TRUE;
  bHorn := TRUE;
END_IF;

(* status *)
IF nFirstTrip > 0 THEN
  refData.sts.nTopAlarmRow := nFirstTrip;
ELSE
  refData.sts.nTopAlarmRow := nFirstWarn;
END_IF;
IF refData.sts.nTopAlarmRow > 0 THEN
  refData.sts.eTopAlarmCode := aAlarmSettings[LOWER_BOUND(aAlarmSettings, 1) + refData.sts.nTopAlarmRow - 1].eAlarmCode;
ELSE
  refData.sts.eTopAlarmCode := E_UtError.None;
END_IF;
bAlarmsChanged := NOT bFirstScan AND (nAlarmsActive <> refData.sts.nAlarmsActive OR nUnacked <> refData.sts.nAlarmsUnacknowledged
                                OR nTrips <> refData.sts.nTripsActive OR refData.sts.nLatestAlarmRow <> nLatestWas);
nLatestWas := refData.sts.nLatestAlarmRow;
refData.sts.nAlarmsActive := nAlarmsActive;
refData.sts.nTripsActive := nTrips;
refData.sts.nAlarmsUnacknowledged := nUnacked;
bError := bCfgBad OR NOT bRowsOk OR NOT bOkSet;
bWarning := NOT bError AND refData.sts.bSettingRefused;
IF bError THEN
  eErrorId := E_UtError.BadSetting;
ELSIF refData.sts.bSettingRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN eState := E_State.Fault; ELSIF nAlarmsActive > 0 THEN eState := E_State.Held; ELSE eState := E_State.Running; END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK