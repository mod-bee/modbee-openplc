(* FB_Annunciator — horn, alarm lamp and first-out for a group of FB_Alarms.
aAlarm is the project's array of the group's alarm records (each FB_Alarm has one element as its refData). The
lamp follows the standard annunciator sequence: fast flash a new alarm not yet acknowledged; slow flash an alarm
that cleared before it was acknowledged; steady alarms present, all acknowledged; off nothing (F_Blink: every
lamp in step). The horn sounds for each new alarm at or above set.eHornPriority, until an acknowledge, a silence,
set.tHornTimeout, or nothing at that priority is left to acknowledge; set.tReHorn sounds it again while such an
alarm stays unacknowledged. bAck acknowledges every alarm in the group (on each alarm's next call). bLampTest: lamp
and horn on while held.
nFirstOut is the alarm that started the current event (the earliest sts.nSequence; 1 = the first element, 0 =
none); the event ends when no alarm is present or waiting for acknowledgement. Shelved, suppressed and
out-of-service alarms are left out. bHealthy: no Trip alarm present (set.bRelayOnWarning: none at all).
Pins: bAck, bSilence, bLampTest, refData, aAlarm -> bHorn, bLamp, bAnyActive, bAnyUnacked, nFirstOut, eHighest,
nActive, bHealthy, plus FB_Object's outputs. Settings are kept (a retained last-good copy, a bad write put back). *)

FUNCTION_BLOCK FB_Annunciator EXTENDS FB_Object
  VAR_INPUT
    bAck : BOOL R_EDGE; (* acknowledge all (panel button) *)
    bSilence : BOOL R_EDGE; (* silence the horn without acknowledging *)
    bLampTest : BOOL; (* lamp and horn on while held *)
    refData : REFERENCE TO ST_AnnunciatorData;
  END_VAR
  VAR_IN_OUT
    aAlarm : ARRAY [*] OF ST_ALARMDATA;
  END_VAR
  VAR_OUTPUT
    bHorn : BOOL;
    bLamp : BOOL;
    bAnyActive : BOOL;
    bAnyUnacked : BOOL;
    nFirstOut : INT; (* the alarm that started this event, 1 = the first element; 0 none *)
    eHighest : E_AlarmPriority; (* the highest priority present *)
    nActive : INT;
    bHealthy : BOOL; (* fail-safe relay: no Trip alarm present *)
  END_VAR
  VAR RETAIN
    stKept : ST_AnnunciatorSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    nLastSeq : UDINT; (* the newest raise seen (the horn sounds for newer ones) *)
    bSeqSeen : BOOL;
    bEventOn : BOOL;
    nFirst : DINT;
    bHornOn : BOOL;
    tHornStart : TIME;
    tHornOffAt : TIME;
    bAckSeen : BOOL;
    bSilenceSeen : BOOL;
  END_VAR
  VAR_TEMP
    bOk : BOOL;
    bAckReq : BOOL;
    bSilenceReq : BOOL;
    nI : DINT;
    nLo : DINT;
    nHi : DINT;
    eSt : E_IsaState;
    nPrio : INT;
    nHornPrio : INT;
    nTopPrio : INT;
    nUnacked : INT;
    bOn : BOOL;
    bAnyNew : BOOL;
    bAnyRtn : BOOL;
    bAnyAcked : BOOL;
    bNewHorn : BOOL;
    bHornUnacked : BOOL;
    bTripOn : BOOL;
    nBest : DINT;
    nBestSeq : UDINT;
  END_VAR


METHOD PRIVATE SetWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_AnnunciatorSet;
  END_VAR
  SetWhy := E_UtError.None;
  IF NOT (stS.tHornTimeout >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tReHorn >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tFastFlash > T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tSlowFlash > T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.eHornPriority = E_AlarmPriority.Low OR stS.eHornPriority = E_AlarmPriority.Medium
             OR stS.eHornPriority = E_AlarmPriority.High OR stS.eHornPriority = E_AlarmPriority.Critical) THEN
    SetWhy := E_UtError.ChoiceBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_AnnunciatorSet;
  END_VAR
  SetOk := SetWhy(stS := stS) = E_UtError.None;
END_METHOD

METHOD PRIVATE PrioNo : INT
  VAR_INPUT
    ePrio : E_AlarmPriority;
  END_VAR
  CASE ePrio OF
  E_AlarmPriority.Medium: PrioNo := 1;
  E_AlarmPriority.High: PrioNo := 2;
  E_AlarmPriority.Critical: PrioNo := 3;
  ELSE
    PrioNo := 0;
  END_CASE;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bHorn := FALSE;
  bHealthy := FALSE;
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
  ELSE
    stKept := refData.set;
    nKeptLayout := cLayout;
  END_IF;
END_IF;
bOk := SetOk(stS := refData.set);
IF bOk THEN
  stKept := refData.set;
ELSIF SetOk(stS := stKept) THEN
  refData.sts.eRefusedWhy := SetWhy(stS := refData.set);
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
  bOk := TRUE;
END_IF;
(* pins act on a rising edge; HMI commands once per write, then cleared *)
bAckReq := bAck OR (refData.bCmdAck AND NOT bAckSeen);
bAckSeen := refData.bCmdAck;
refData.bCmdAck := FALSE;
bSilenceReq := bSilence OR (refData.bCmdSilence AND NOT bSilenceSeen);
bSilenceSeen := refData.bCmdSilence;
refData.bCmdSilence := FALSE;
IF bAckReq OR SystemReset() THEN
  refData.sts.bRefused := FALSE;
  refData.sts.eRefusedWhy := E_UtError.None;
END_IF;
nHornPrio := PrioNo(ePrio := refData.set.eHornPriority);

nLo := LOWER_BOUND(aAlarm, 1);
nHi := UPPER_BOUND(aAlarm, 1);
nActive := 0;
nUnacked := 0;
nTopPrio := 0;
bAnyNew := FALSE;
bAnyRtn := FALSE;
bAnyAcked := FALSE;
bNewHorn := FALSE;
bHornUnacked := FALSE;
bTripOn := FALSE;
nBest := nLo - 1;
FOR nI := nLo TO nHi DO
  nPrio := PrioNo(ePrio := aAlarm[nI].set.ePriority);
  eSt := aAlarm[nI].sts.eIsaState;
  bOn := eSt = E_IsaState.Unacked OR eSt = E_IsaState.Acked OR eSt = E_IsaState.Latched OR eSt = E_IsaState.Locked;
  IF bOn THEN
    nActive := nActive + 1;
    IF nPrio > nTopPrio THEN
      nTopPrio := nPrio;
    END_IF;
    IF aAlarm[nI].set.stRow.eResponse = E_Response.Trip THEN
      bTripOn := TRUE;
    END_IF;
  END_IF;
  IF eSt = E_IsaState.Unacked OR eSt = E_IsaState.RtnUnacked THEN
    nUnacked := nUnacked + 1;
    IF nPrio >= nHornPrio THEN
      bHornUnacked := TRUE;
    END_IF;
    IF bAckReq THEN
      aAlarm[nI].bGrpAck := TRUE;   (* the alarm acknowledges itself on its next call *)
    END_IF;
  END_IF;
  IF eSt = E_IsaState.Unacked THEN
    bAnyNew := TRUE;
    IF nPrio >= nHornPrio AND (NOT bSeqSeen OR UDINT_TO_DINT(aAlarm[nI].sts.nSequence - nLastSeq) > 0) THEN
      bNewHorn := TRUE;           (* raised since the last look *)
    END_IF;
  ELSIF eSt = E_IsaState.RtnUnacked THEN
    bAnyRtn := TRUE;
  ELSIF eSt = E_IsaState.Acked THEN
    bAnyAcked := TRUE;
  END_IF;
  IF bOn OR eSt = E_IsaState.RtnUnacked THEN
    (* the earliest sequence; it wraps, so compare the difference *)
    IF nBest < nLo OR UDINT_TO_DINT(aAlarm[nI].sts.nSequence - nBestSeq) < 0 THEN
      nBest := nI;
      nBestSeq := aAlarm[nI].sts.nSequence;
    END_IF;
  END_IF;
END_FOR;
(* the newest raise seen *)
FOR nI := nLo TO nHi DO
  IF aAlarm[nI].sts.eIsaState = E_IsaState.Unacked
     AND (NOT bSeqSeen OR UDINT_TO_DINT(aAlarm[nI].sts.nSequence - nLastSeq) > 0) THEN
    nLastSeq := aAlarm[nI].sts.nSequence;
    bSeqSeen := TRUE;
  END_IF;
END_FOR;
(* first-out: taken when an event starts, kept until it is over *)
IF nBest >= nLo THEN
  IF NOT bEventOn THEN
    bEventOn := TRUE;
    nFirst := nBest - nLo + 1;
  END_IF;
ELSE
  bEventOn := FALSE;
  nFirst := 0;
END_IF;
(* the horn *)
IF bNewHorn THEN
  bHornOn := TRUE;
  tHornStart := tNow;
END_IF;
IF bAckReq OR bSilenceReq THEN
  bHornOn := FALSE;
  tHornOffAt := tNow;
END_IF;
IF bHornOn AND refData.set.tHornTimeout > T#0s AND tNow - tHornStart >= refData.set.tHornTimeout THEN
  bHornOn := FALSE;
  tHornOffAt := tNow;
END_IF;
IF NOT bHornUnacked THEN
  bHornOn := FALSE;
END_IF;
IF NOT bHornOn AND bHornUnacked AND refData.set.tReHorn > T#0s AND tNow - tHornOffAt >= refData.set.tReHorn THEN
  bHornOn := TRUE;
  tHornStart := tNow;
END_IF;
(* the lamp *)
IF bAnyNew THEN
  bLamp := F_Blink(tOnTime := refData.set.tFastFlash, tOffTime := refData.set.tFastFlash);
ELSIF bAnyRtn THEN
  bLamp := F_Blink(tOnTime := refData.set.tSlowFlash, tOffTime := refData.set.tSlowFlash);
ELSE
  bLamp := bAnyAcked;
END_IF;
bHorn := bHornOn OR bLampTest;
bLamp := bLamp OR bLampTest;
bAnyActive := nActive > 0;
bAnyUnacked := nUnacked > 0;
nFirstOut := DINT_TO_INT(nFirst);
CASE nTopPrio OF
1: eHighest := E_AlarmPriority.Medium;
2: eHighest := E_AlarmPriority.High;
3: eHighest := E_AlarmPriority.Critical;
ELSE
  eHighest := E_AlarmPriority.Low;
END_CASE;
bHealthy := NOT bTripOn AND NOT (refData.set.bRelayOnWarning AND nActive > 0);
refData.sts.nFirstOut := nFirstOut;
refData.sts.nActive := nActive;
refData.sts.nUnacked := nUnacked;

bError := NOT bOk;
bWarning := NOT bError AND refData.sts.bRefused;
IF NOT bOk THEN
  eErrorId := E_UtError.BadSetting;
ELSIF refData.sts.bRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN
  eState := E_State.Fault;
ELSIF nActive > 0 OR nUnacked > 0 THEN
  eState := E_State.Held;
ELSE
  eState := E_State.Running;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK