(* FB_EventLog — the last N events (trips, stops, end reasons) with their time, newest first, for "what happened
overnight"; optionally kept over a power cut.
Call it once per source per scan, all calls on the same instance, aEvents, aSources and refData (one rung each):
  fbLog(nUserCode := 0, eStopReasonToLog := stPump1.sts.eStopReason, nSource := 1, aEvents := aEvLog, aSources := aEvSrc, refData := stEvLog);
  fbLog(eErrorToLog := fbPump1.eErrorId, nCounter := stPump1.sts.stStartFailFault.nTripCount, nSource := 2, ...);
An event is codes, not words: its stop reason (E_StopReason), its error (E_UtError) and a code of your own (INT);
the HMI or SCADA shows the words. A call logs one event (nUserCode, eStopReasonToLog, eErrorToLog) when, for its source: bLogNow has a
rising edge (any event pulse); nUserCode changes to a value other than 0, eStopReasonToLog to one other than None, or eErrorToLog to
one other than None; or nCounter changes (a counter such as a record's trips: every trip is logged, also the same
one again). The calls share one instance, so the block sets its pins back to their defaults after each call (nUserCode
0, eStopReasonToLog None, eErrorToLog None, bLogNow FALSE, nCounter 0, nSource 1, dtLocalTime unwired): a pin a call leaves unwired never
carries another call's value. What a source shows at its first call after a power-up is its starting point, not
an event; the power-up event (source 0) marks that moment. aSources[nSource] keeps what was last seen from each
source (the block writes it).
aEvents is the log, newest first (its first element is the newest event); a new one moves the others down, and
the oldest falls off a full log (sts.nEventLostCount). Each event has its time (dtLocalTime, optional; unwired: blank - the
boards have no real-time clock), source, codes and a running number nEventNumber (0 = an empty slot). set.bLogPowerUp adds
a power-up event (source 0, no codes) at every power-up.
Kept over a power cut (set.bKeepOverPowerCut, the default, and set.tKeptCopyInterval above 0): the block's own kept copy (up to
16 events). The first event after a quiet spell (no save for tKeptCopyInterval) is copied at once, with any others of the
same scan; later ones wait until tKeptCopyInterval has passed since that copy, so a burst of events writes the
controller's storage once. The power-up event is copied at once and does not start the wait. At power-up the log
is read back from the kept copy. bCmdClearLog empties the log (and the kept copy at once). The newest event is in
sts.stNewestEvent. One instance is called many times in a scan (TIME() is the same for the whole scan): bEventLogged stays on
for the rest of the scan in which an event came; the command and the saving act once per scan.
Pins: nUserCode, eStopReasonToLog, eErrorToLog, bLogNow, nCounter, nSource, dtLocalTime, refData, aEvents, aSources -> nEventsInLog, bEventLogged, plus
FB_Object's outputs (warning BadSetting: no slot, more than 16 while kept; ValueBad: a call's nSource outside
aSources, ignored). Settings are kept (a retained last-good copy, a bad write put back). *)

FUNCTION_BLOCK FB_EventLog EXTENDS FB_Object
  VAR_INPUT
    nUserCode : INT; (* a code of your own (0 = none) *)
    eStopReasonToLog : E_StopReason; (* a stop reason *)
    eErrorToLog : E_UtError; (* an error *)
    bLogNow : BOOL; (* rising edge: log the codes now *)
    nCounter : UDINT; (* optional counter: each change logs the codes *)
    nSource : INT := 1; (* the source: the element of aSources this call uses *)
    dtLocalTime : DT := DT#1970-01-01-00:00:00; (* a real-time clock (optional); unwired: stamps stay blank *)
    refData : REFERENCE TO ST_EventLogData; (* the block's record (one rung per source, all with the same record) *)
  END_VAR
  VAR_IN_OUT
    aEvents : ARRAY [*] OF ST_EVENT; (* the log, newest first: as many slots as declared *)
    aSources : ARRAY [*] OF ST_EVENTSRC; (* what was last seen per source, index = nSource *)
  END_VAR
  VAR_OUTPUT
    nEventsInLog : INT; (* events in the log *)
    bEventLogged : BOOL; (* on for the scan in which an event was logged *)
  END_VAR
  VAR RETAIN
    aSaved : ARRAY [1..16] OF ST_EVENT; (* the kept copy (a block cannot size its own variables from the caller) *)
    stKept : ST_EventLogSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
    cMaxSaved : DINT := 16;
  END_VAR
  VAR
    bSetOk : BOOL := TRUE;
    bStarted : BOOL;
    tLast : TIME;
    nCnt : DINT; (* events in the log *)
    nSeqNext : UDINT; (* the next event's running number *)
    bDirty : BOOL; (* the log changed since the last save *)
    tSave : TIME;
    bQuiet : BOOL; (* no save within tKeptCopyInterval: the next change is saved at once *)
    bPuOnly : BOOL; (* the only unsaved change is the power-up event (its save starts no wait) *)
    bClearSeen : BOOL;
    bTake : BOOL;
    nEvCode : INT;
    eEvStop : E_StopReason;
    eEvFault : E_UtError;
    nEvSrc : INT;
  END_VAR
  VAR_TEMP
    bNewScan : BOOL;
    bKeep : BOOL;
    nBLo : DINT;
    nBHi : DINT;
    nNb : DINT;
    nSLo : DINT;
    nSHi : DINT;
    nI : DINT;
    nM : DINT;
    nS : DINT;
  END_VAR


METHOD PRIVATE SetWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_EventLogSet;
  END_VAR
  SetWhy := E_UtError.None;
  IF NOT (stS.tKeptCopyInterval >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_EventLogSet;
  END_VAR
  SetOk := SetWhy(stS := stS) = E_UtError.None;
END_METHOD

METHOD PRIVATE ClearBuffer : BOOL
  VAR_IN_OUT
    aB : ARRAY[*] OF ST_Event;
  END_VAR
  VAR
    nJ : DINT;
  END_VAR
  FOR nJ := LOWER_BOUND(aB, 1) TO UPPER_BOUND(aB, 1) DO
    aB[nJ].nEventNumber := 0;
    aB[nJ].dtTimeStamp := DT#1970-01-01-00:00:00;
    aB[nJ].nSource := 0;
    aB[nJ].nUserCode := 0;
    aB[nJ].eStopReason := E_StopReason.None;
    aB[nJ].eLoggedErrorId := E_UtError.None;
  END_FOR;
  ClearBuffer := TRUE;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bEventLogged := FALSE;
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();
nBLo := LOWER_BOUND(aEvents, 1);
nBHi := UPPER_BOUND(aEvents, 1);
nNb := MAX(nBHi - nBLo + 1, 0);
nSLo := LOWER_BOUND(aSources, 1);
nSHi := UPPER_BOUND(aSources, 1);
bNewScan := NOT bStarted OR tNow <> tLast;
tLast := tNow;
IF bNewScan THEN
  IF bFirstScan THEN
    IF nKeptLayout = cLayout THEN
      refData.set := stKept;
    ELSE
      stKept := refData.set;
      nKeptLayout := cLayout;
    END_IF;
  END_IF;
  bSetOk := SetOk(stS := refData.set);
  IF bSetOk THEN
    stKept := refData.set;
  ELSIF SetOk(stS := stKept) THEN
    refData.sts.eSettingRefusedErrorId := SetWhy(stS := refData.set);
    refData.set := stKept;
    refData.sts.bSettingRefused := TRUE;
    bSetOk := TRUE;
  END_IF;
  IF SystemReset() THEN
    refData.sts.bSettingRefused := FALSE;
    refData.sts.eSettingRefusedErrorId := E_UtError.None;
  END_IF;
END_IF;
bKeep := refData.set.bKeepOverPowerCut AND refData.set.tKeptCopyInterval > T#0s;
refData.sts.bBufferSizeBad := nNb < 1 OR (bKeep AND nNb > cMaxSaved);

IF NOT bStarted THEN
  (* the first call, also after a power cut: the kept log (if any), no source seen *)
  bStarted := TRUE;
  bQuiet := TRUE;
  nCnt := 0;
  nSeqNext := 1;
  ClearBuffer(aB := aEvents);
  IF bKeep THEN
    FOR nI := 0 TO MIN(nNb, cMaxSaved) - 1 DO
      IF aSaved[1 + nI].nEventNumber = 0 THEN
        EXIT;                     (* the end of the kept log *)
      END_IF;
      aEvents[nBLo + nI] := aSaved[1 + nI];
      nCnt := nCnt + 1;
    END_FOR;
    IF nCnt > 0 THEN
      nSeqNext := aEvents[nBLo].nEventNumber + 1;
    END_IF;
  END_IF;
  FOR nI := nSLo TO nSHi DO
    aSources[nI].bEverHeard := FALSE;
  END_FOR;
  IF refData.set.bLogPowerUp AND nNb >= 1 THEN
    bTake := TRUE;                (* logged below, as source 0 *)
    bPuOnly := TRUE;
    nEvSrc := 0;
    nEvCode := 0;
    eEvStop := E_StopReason.None;
    eEvFault := E_UtError.None;
  END_IF;
END_IF;

(* once per scan: the scan's flags and the HMI command (once per write) *)
IF bNewScan THEN
  bEventLogged := FALSE;
  refData.sts.bSourceOutOfRange := FALSE;
  IF refData.bCmdClearLog AND NOT bClearSeen THEN
    nCnt := 0;
    ClearBuffer(aB := aEvents);
    bDirty := TRUE;
    bPuOnly := FALSE;
    bQuiet := TRUE;               (* a clear is saved at once *)
  END_IF;
  bClearSeen := refData.bCmdClearLog;
  refData.bCmdClearLog := FALSE;
END_IF;

(* the power-up event, then this call's source *)
FOR nM := 0 TO 1 DO
  IF nM = 1 THEN
    bTake := FALSE;
    nS := INT_TO_DINT(nSource);
    IF nS < nSLo OR nS > nSHi THEN
      refData.sts.bSourceOutOfRange := TRUE;
    ELSE
      IF NOT aSources[nS].bEverHeard THEN
        aSources[nS].bEverHeard := TRUE;   (* the first call after a power-up: the starting point, not an event *)
      ELSE
        bTake := (bLogNow AND NOT aSources[nS].bLogNowLastScan) OR (nUserCode <> aSources[nS].nLastUserCode AND nUserCode <> 0)
                 OR (eStopReasonToLog <> aSources[nS].eLastStopReason AND eStopReasonToLog <> E_StopReason.None)
                 OR (eErrorToLog <> aSources[nS].eLastErrorId AND eErrorToLog <> E_UtError.None)
                 OR nCounter <> aSources[nS].nLastCounter;
      END_IF;
      aSources[nS].nLastUserCode := nUserCode;
      aSources[nS].eLastStopReason := eStopReasonToLog;
      aSources[nS].eLastErrorId := eErrorToLog;
      aSources[nS].nLastCounter := nCounter;
      aSources[nS].bLogNowLastScan := bLogNow;
      IF bTake THEN
        bPuOnly := FALSE;
      END_IF;
      nEvSrc := nSource;
      nEvCode := nUserCode;
      eEvStop := eStopReasonToLog;
      eEvFault := eErrorToLog;
    END_IF;
  END_IF;
  IF bTake AND nNb >= 1 THEN
    (* newest first: the others move down, the oldest falls off a full log *)
    IF nCnt >= nNb THEN
      refData.sts.nEventLostCount := refData.sts.nEventLostCount + 1;
      nCnt := nNb - 1;
    END_IF;
    FOR nI := nBHi TO nBLo + 1 BY -1 DO
      IF nI - nBLo <= nCnt THEN
        aEvents[nI] := aEvents[nI - 1];
      END_IF;
    END_FOR;
    aEvents[nBLo].nEventNumber := nSeqNext;
    aEvents[nBLo].dtTimeStamp := dtLocalTime;
    aEvents[nBLo].nSource := nEvSrc;
    aEvents[nBLo].nUserCode := nEvCode;
    aEvents[nBLo].eStopReason := eEvStop;
    aEvents[nBLo].eLoggedErrorId := eEvFault;
    nSeqNext := nSeqNext + 1;
    nCnt := nCnt + 1;
    refData.sts.nEventLoggedCount := refData.sts.nEventLoggedCount + 1;
    bEventLogged := TRUE;
    bDirty := TRUE;
  END_IF;
  bTake := FALSE;
END_FOR;

(* the kept copy: a change after a quiet spell at once (with the rest of that scan), then at most once per
   tKeptCopyInterval *)
IF bKeep THEN
  IF NOT bQuiet AND tNow - tSave >= refData.set.tKeptCopyInterval THEN
    bQuiet := TRUE;
  END_IF;
  IF bDirty AND (bQuiet OR tNow = tSave) THEN
    FOR nI := 0 TO cMaxSaved - 1 DO
      IF nI < nNb THEN
        aSaved[1 + nI] := aEvents[nBLo + nI];
      ELSE
        aSaved[1 + nI].nEventNumber := 0;
      END_IF;
    END_FOR;
    bDirty := FALSE;
    IF bQuiet AND NOT bPuOnly THEN
      bQuiet := FALSE;            (* the wait starts *)
      tSave := tNow;
    END_IF;
  END_IF;
  bPuOnly := FALSE;
ELSE
  bDirty := FALSE;
  bPuOnly := FALSE;
END_IF;

refData.sts.nEventsInLog := DINT_TO_INT(nCnt);
nEventsInLog := refData.sts.nEventsInLog;
IF nNb >= 1 THEN
  refData.sts.stNewestEvent := aEvents[nBLo];
END_IF;
bError := NOT bSetOk;
bWarning := NOT bError AND (refData.sts.bBufferSizeBad OR refData.sts.bSourceOutOfRange OR refData.sts.bSettingRefused);
IF bError OR refData.sts.bBufferSizeBad THEN
  eErrorId := E_UtError.BadSetting;
ELSIF refData.sts.bSourceOutOfRange THEN
  eErrorId := E_UtError.ValueBad;
ELSIF refData.sts.bSettingRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN
  eState := E_State.Fault;
ELSE
  eState := E_State.Running;
END_IF;
bFirstScan := FALSE;

(* the calls share this instance: an input a call leaves unwired keeps the last call's value, so each goes back
   to its default for the next call *)
nUserCode := 0;
eStopReasonToLog := E_StopReason.None;
eErrorToLog := E_UtError.None;
bLogNow := FALSE;
nCounter := 0;
nSource := 1;
dtLocalTime := DT#1970-01-01-00:00:00;

END_FUNCTION_BLOCK