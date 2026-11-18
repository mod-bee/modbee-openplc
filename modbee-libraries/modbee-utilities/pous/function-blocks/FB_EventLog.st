(* FB_EventLog — the last N events (trips, stops, end reasons) with their time, newest first, for "what happened
overnight"; optionally kept over a power cut.
Call it once per source per scan, all calls on the same instance, aBuffer, aSources and refData (one rung each):
  fbLog(nCode := 0, eStop := fbPump1.eStopReason, nSrc := 1, aBuffer := aEvLog, aSources := aEvSrc, refData := stEvLog);
  fbLog(eFault := fbPump1.eErrorId, nCount := stPump1.tot.nTrips, nSrc := 2, ...);
An event is codes, not words: its stop reason (E_StopReason), its error (E_UtError) and a code of your own (INT);
the HMI or SCADA shows the words. A call logs one event (nCode, eStop, eFault) when, for its source: bNew has a
rising edge (any event pulse); nCode changes to a value other than 0, eStop to one other than None, or eFault to
one other than None; or nCount changes (a counter such as a record's trips: every trip is logged, also the same
one again). The calls share one instance, so the block sets its pins back to their defaults after each call (nCode
0, eStop None, eFault None, bNew FALSE, nCount 0, nSrc 1, dtClock unwired): a pin a call leaves unwired never
carries another call's value. What a source shows at its first call after a power-up is its starting point, not
an event; the power-up event (source 0) marks that moment. aSources[nSrc] keeps what was last seen from each
source (the block writes it).
aBuffer is the log, newest first (its first element is the newest event); a new one moves the others down, and
the oldest falls off a full log (sts.nLost). Each event has its time (dtClock, optional; unwired: blank - the
boards have no real-time clock), source, codes and a running number nSeq (0 = an empty slot). set.bLogPowerUp adds
a power-up event (source 0, no codes) at every power-up.
Kept over a power cut (set.bRetained, the default, and set.tSaveEvery above 0): the block's own kept copy (up to
16 events). The first event after a quiet spell (no save for tSaveEvery) is copied at once, with any others of the
same scan; later ones wait until tSaveEvery has passed since that copy, so a burst of events writes the
controller's storage once. The power-up event is copied at once and does not start the wait. At power-up the log
is read back from the kept copy. bCmdClear empties the log (and the kept copy at once). The newest event is in
sts.stLast. One instance is called many times in a scan (TIME() is the same for the whole scan): bNewEvent stays on
for the rest of the scan in which an event came; the command and the saving act once per scan.
Pins: nCode, eStop, eFault, bNew, nCount, nSrc, dtClock, refData, aBuffer, aSources -> nEvents, bNewEvent, plus
FB_Object's outputs (warning BadSetting: no slot, more than 16 while kept; ValueBad: a call's nSrc outside
aSources, ignored). Settings are kept (a retained last-good copy, a bad write put back). *)

FUNCTION_BLOCK FB_EventLog EXTENDS FB_Object
  VAR_INPUT
    nCode : INT; (* a code of your own (0 = none) *)
    eStop : E_StopReason; (* a stop reason *)
    eFault : E_UtError; (* an error *)
    bNew : BOOL; (* rising edge: log the codes now *)
    nCount : UDINT; (* optional counter: each change logs the codes *)
    nSrc : INT := 1; (* the source: the element of aSources this call uses *)
    dtClock : DT := DT#1970-01-01-00:00:00; (* a real-time clock (optional); unwired: stamps stay blank *)
    refData : REFERENCE TO ST_EventLogData;
  END_VAR
  VAR_IN_OUT
    aBuffer : ARRAY [*] OF ST_EVENT; (* the log, newest first: as many slots as declared *)
    aSources : ARRAY [*] OF ST_EVENTSRC; (* what was last seen per source, index = nSrc *)
  END_VAR
  VAR_OUTPUT
    nEvents : INT; (* events in the log *)
    bNewEvent : BOOL; (* on for the scan in which an event was logged *)
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
    bQuiet : BOOL; (* no save within tSaveEvery: the next change is saved at once *)
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
  IF NOT (stS.tSaveEvery >= T#0s) THEN
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
    aB[nJ].nSeq := 0;
    aB[nJ].dtStamp := DT#1970-01-01-00:00:00;
    aB[nJ].nSrc := 0;
    aB[nJ].nCode := 0;
    aB[nJ].eStop := E_StopReason.None;
    aB[nJ].eFault := E_UtError.None;
  END_FOR;
  ClearBuffer := TRUE;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bNewEvent := FALSE;
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();
nBLo := LOWER_BOUND(aBuffer, 1);
nBHi := UPPER_BOUND(aBuffer, 1);
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
    refData.sts.eRefusedWhy := SetWhy(stS := refData.set);
    refData.set := stKept;
    refData.sts.bRefused := TRUE;
    bSetOk := TRUE;
  END_IF;
  IF SystemReset() THEN
    refData.sts.bRefused := FALSE;
    refData.sts.eRefusedWhy := E_UtError.None;
  END_IF;
END_IF;
bKeep := refData.set.bRetained AND refData.set.tSaveEvery > T#0s;
refData.sts.bWrnConfig := nNb < 1 OR (bKeep AND nNb > cMaxSaved);

IF NOT bStarted THEN
  (* the first call, also after a power cut: the kept log (if any), no source seen *)
  bStarted := TRUE;
  bQuiet := TRUE;
  nCnt := 0;
  nSeqNext := 1;
  ClearBuffer(aB := aBuffer);
  IF bKeep THEN
    FOR nI := 0 TO MIN(nNb, cMaxSaved) - 1 DO
      IF aSaved[1 + nI].nSeq = 0 THEN
        EXIT;                     (* the end of the kept log *)
      END_IF;
      aBuffer[nBLo + nI] := aSaved[1 + nI];
      nCnt := nCnt + 1;
    END_FOR;
    IF nCnt > 0 THEN
      nSeqNext := aBuffer[nBLo].nSeq + 1;
    END_IF;
  END_IF;
  FOR nI := nSLo TO nSHi DO
    aSources[nI].bSeen := FALSE;
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
  bNewEvent := FALSE;
  refData.sts.bWrnSrc := FALSE;
  IF refData.bCmdClear AND NOT bClearSeen THEN
    nCnt := 0;
    ClearBuffer(aB := aBuffer);
    bDirty := TRUE;
    bPuOnly := FALSE;
    bQuiet := TRUE;               (* a clear is saved at once *)
  END_IF;
  bClearSeen := refData.bCmdClear;
  refData.bCmdClear := FALSE;
END_IF;

(* the power-up event, then this call's source *)
FOR nM := 0 TO 1 DO
  IF nM = 1 THEN
    bTake := FALSE;
    nS := INT_TO_DINT(nSrc);
    IF nS < nSLo OR nS > nSHi THEN
      refData.sts.bWrnSrc := TRUE;
    ELSE
      IF NOT aSources[nS].bSeen THEN
        aSources[nS].bSeen := TRUE;   (* the first call after a power-up: the starting point, not an event *)
      ELSE
        bTake := (bNew AND NOT aSources[nS].bNewPrev) OR (nCode <> aSources[nS].nCode AND nCode <> 0)
                 OR (eStop <> aSources[nS].eStop AND eStop <> E_StopReason.None)
                 OR (eFault <> aSources[nS].eFault AND eFault <> E_UtError.None)
                 OR nCount <> aSources[nS].nCount;
      END_IF;
      aSources[nS].nCode := nCode;
      aSources[nS].eStop := eStop;
      aSources[nS].eFault := eFault;
      aSources[nS].nCount := nCount;
      aSources[nS].bNewPrev := bNew;
      IF bTake THEN
        bPuOnly := FALSE;
      END_IF;
      nEvSrc := nSrc;
      nEvCode := nCode;
      eEvStop := eStop;
      eEvFault := eFault;
    END_IF;
  END_IF;
  IF bTake AND nNb >= 1 THEN
    (* newest first: the others move down, the oldest falls off a full log *)
    IF nCnt >= nNb THEN
      refData.sts.nLost := refData.sts.nLost + 1;
      nCnt := nNb - 1;
    END_IF;
    FOR nI := nBHi TO nBLo + 1 BY -1 DO
      IF nI - nBLo <= nCnt THEN
        aBuffer[nI] := aBuffer[nI - 1];
      END_IF;
    END_FOR;
    aBuffer[nBLo].nSeq := nSeqNext;
    aBuffer[nBLo].dtStamp := dtClock;
    aBuffer[nBLo].nSrc := nEvSrc;
    aBuffer[nBLo].nCode := nEvCode;
    aBuffer[nBLo].eStop := eEvStop;
    aBuffer[nBLo].eFault := eEvFault;
    nSeqNext := nSeqNext + 1;
    nCnt := nCnt + 1;
    refData.sts.nLogged := refData.sts.nLogged + 1;
    bNewEvent := TRUE;
    bDirty := TRUE;
  END_IF;
  bTake := FALSE;
END_FOR;

(* the kept copy: a change after a quiet spell at once (with the rest of that scan), then at most once per
   tSaveEvery *)
IF bKeep THEN
  IF NOT bQuiet AND tNow - tSave >= refData.set.tSaveEvery THEN
    bQuiet := TRUE;
  END_IF;
  IF bDirty AND (bQuiet OR tNow = tSave) THEN
    FOR nI := 0 TO cMaxSaved - 1 DO
      IF nI < nNb THEN
        aSaved[1 + nI] := aBuffer[nBLo + nI];
      ELSE
        aSaved[1 + nI].nSeq := 0;
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

refData.sts.nEvents := DINT_TO_INT(nCnt);
nEvents := refData.sts.nEvents;
IF nNb >= 1 THEN
  refData.sts.stLast := aBuffer[nBLo];
END_IF;
bError := NOT bSetOk;
bWarning := NOT bError AND (refData.sts.bWrnConfig OR refData.sts.bWrnSrc OR refData.sts.bRefused);
IF bError OR refData.sts.bWrnConfig THEN
  eErrorId := E_UtError.BadSetting;
ELSIF refData.sts.bWrnSrc THEN
  eErrorId := E_UtError.ValueBad;
ELSIF refData.sts.bRefused THEN
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
nCode := 0;
eStop := E_StopReason.None;
eFault := E_UtError.None;
bNew := FALSE;
nCount := 0;
nSrc := 1;
dtClock := DT#1970-01-01-00:00:00;

END_FUNCTION_BLOCK