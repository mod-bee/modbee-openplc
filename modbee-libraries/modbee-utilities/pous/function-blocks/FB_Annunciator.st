(* FB_Annunciator — horn, alarm lamp and first-out for a group of FB_Alarms.
aAlarms is the project's array of the group's alarm records (each FB_Alarm has one element as its refData). The
lamp follows the standard annunciator sequence: fast flash a new alarm not yet acknowledged; slow flash an alarm
that cleared before it was acknowledged; steady alarms present, all acknowledged; off nothing (F_Blink: every
lamp in step). The horn sounds for each new alarm at or above set.eHornFromPriority, until an acknowledge, a silence,
set.tHornStopsAfter, or nothing at that priority is left to acknowledge; set.tHornAgainAfter sounds it again while such an
alarm stays unacknowledged. bAcknowledge acknowledges every alarm in the group (on each alarm's next call). bLampTest: lamp
and horn on while held.
nFirstOutAlarm is the alarm that started the current event (the earliest sts.nRaisedAtMs; 1 = the first element, 0 =
none); the event ends when no alarm is present or waiting for acknowledgement. Shelved, suppressed and
out-of-service alarms are left out. bFailSafeRelay: no Trip alarm present (set.bRelayDropsOnWarning: none at all).
Pins: bAcknowledge, bSilenceHorn, bLampTest, refData, aAlarms -> bHorn, bLamp, bAnyAlarmActive, bAnyUnacknowledged, nFirstOutAlarm, eHighestPriority,
nAlarmsActive, bFailSafeRelay, plus FB_Object's outputs. Settings are kept (a retained last-good copy, a bad write put bAcknowledge). *)

FUNCTION_BLOCK FB_Annunciator EXTENDS FB_Object
  VAR_INPUT
    bAcknowledge : BOOL R_EDGE; (* acknowledge all (panel button) *)
    bSilenceHorn : BOOL R_EDGE; (* silence the horn without acknowledging *)
    bLampTest : BOOL; (* lamp and horn on while held *)
    refData : REFERENCE TO ST_AnnunciatorData; (* the annunciator's record *)
  END_VAR
  VAR_IN_OUT
    aAlarms : ARRAY [*] OF ST_ALARMDATA; (* the FB_Alarm records of the group *)
  END_VAR
  VAR_OUTPUT
    bHorn : BOOL; (* the horn output *)
    bLamp : BOOL; (* the common alarm lamp output *)
    bAnyAlarmActive : BOOL; (* any alarm present *)
    bAnyUnacknowledged : BOOL; (* any alarm waiting to be acknowledged *)
    nFirstOutAlarm : INT; (* the alarm that started this event, 1 = the first element; 0 none *)
    eHighestPriority : E_AlarmPriority; (* the highest priority present *)
    nAlarmsActive : INT; (* alarms present now *)
    bFailSafeRelay : BOOL; (* fail-safe relay: no Trip alarm present *)
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
  IF NOT (stS.tHornStopsAfter >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tHornAgainAfter >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tFastFlash > T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tSlowFlash > T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.eHornFromPriority = E_AlarmPriority.Low OR stS.eHornFromPriority = E_AlarmPriority.Medium
             OR stS.eHornFromPriority = E_AlarmPriority.High OR stS.eHornFromPriority = E_AlarmPriority.Critical) THEN
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
  bFailSafeRelay := FALSE;
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
  refData.sts.eSettingRefusedErrorId := SetWhy(stS := refData.set);
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
  bOk := TRUE;
END_IF;
(* pins act on a rising edge; HMI commands once per write, then cleared *)
bAckReq := bAcknowledge OR (refData.bCmdAcknowledge AND NOT bAckSeen);
bAckSeen := refData.bCmdAcknowledge;
refData.bCmdAcknowledge := FALSE;
bSilenceReq := bSilenceHorn OR (refData.bCmdSilenceHorn AND NOT bSilenceSeen);
bSilenceSeen := refData.bCmdSilenceHorn;
refData.bCmdSilenceHorn := FALSE;
IF bAckReq OR SystemReset() THEN
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;
nHornPrio := PrioNo(ePrio := refData.set.eHornFromPriority);

nLo := LOWER_BOUND(aAlarms, 1);
nHi := UPPER_BOUND(aAlarms, 1);
nAlarmsActive := 0;
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
  nPrio := PrioNo(ePrio := aAlarms[nI].set.ePriority);
  eSt := aAlarms[nI].sts.eAlarmState;
  bOn := eSt = E_IsaState.Unacked OR eSt = E_IsaState.Acked OR eSt = E_IsaState.Latched OR eSt = E_IsaState.Locked;
  IF bOn THEN
    nAlarmsActive := nAlarmsActive + 1;
    IF nPrio > nTopPrio THEN
      nTopPrio := nPrio;
    END_IF;
    IF aAlarms[nI].set.stRowSettings.eActionOnFault = E_Response.Trip THEN
      bTripOn := TRUE;
    END_IF;
  END_IF;
  IF eSt = E_IsaState.Unacked OR eSt = E_IsaState.RtnUnacked THEN
    nUnacked := nUnacked + 1;
    IF nPrio >= nHornPrio THEN
      bHornUnacked := TRUE;
    END_IF;
    IF bAckReq THEN
      aAlarms[nI].bGroupAcknowledge := TRUE;   (* the alarm acknowledges itself on its next call *)
    END_IF;
  END_IF;
  IF eSt = E_IsaState.Unacked THEN
    bAnyNew := TRUE;
    IF nPrio >= nHornPrio AND (NOT bSeqSeen OR UDINT_TO_DINT(aAlarms[nI].sts.nRaisedAtMs - nLastSeq) > 0) THEN
      bNewHorn := TRUE;           (* raised since the last look *)
    END_IF;
  ELSIF eSt = E_IsaState.RtnUnacked THEN
    bAnyRtn := TRUE;
  ELSIF eSt = E_IsaState.Acked THEN
    bAnyAcked := TRUE;
  END_IF;
  IF bOn OR eSt = E_IsaState.RtnUnacked THEN
    (* the earliest sequence; it wraps, so compare the difference *)
    IF nBest < nLo OR UDINT_TO_DINT(aAlarms[nI].sts.nRaisedAtMs - nBestSeq) < 0 THEN
      nBest := nI;
      nBestSeq := aAlarms[nI].sts.nRaisedAtMs;
    END_IF;
  END_IF;
END_FOR;
(* the newest raise seen *)
FOR nI := nLo TO nHi DO
  IF aAlarms[nI].sts.eAlarmState = E_IsaState.Unacked
     AND (NOT bSeqSeen OR UDINT_TO_DINT(aAlarms[nI].sts.nRaisedAtMs - nLastSeq) > 0) THEN
    nLastSeq := aAlarms[nI].sts.nRaisedAtMs;
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
IF bHornOn AND refData.set.tHornStopsAfter > T#0s AND tNow - tHornStart >= refData.set.tHornStopsAfter THEN
  bHornOn := FALSE;
  tHornOffAt := tNow;
END_IF;
IF NOT bHornUnacked THEN
  bHornOn := FALSE;
END_IF;
IF NOT bHornOn AND bHornUnacked AND refData.set.tHornAgainAfter > T#0s AND tNow - tHornOffAt >= refData.set.tHornAgainAfter THEN
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
bAnyAlarmActive := nAlarmsActive > 0;
bAnyUnacknowledged := nUnacked > 0;
nFirstOutAlarm := DINT_TO_INT(nFirst);
CASE nTopPrio OF
1: eHighestPriority := E_AlarmPriority.Medium;
2: eHighestPriority := E_AlarmPriority.High;
3: eHighestPriority := E_AlarmPriority.Critical;
ELSE
  eHighestPriority := E_AlarmPriority.Low;
END_CASE;
bFailSafeRelay := NOT bTripOn AND NOT (refData.set.bRelayDropsOnWarning AND nAlarmsActive > 0);
refData.sts.nFirstOutAlarm := nFirstOutAlarm;
refData.sts.nAlarmsActive := nAlarmsActive;
refData.sts.nAlarmsUnacknowledged := nUnacked;

bError := NOT bOk;
bWarning := NOT bError AND refData.sts.bSettingRefused;
IF NOT bOk THEN
  eErrorId := E_UtError.BadSetting;
ELSIF refData.sts.bSettingRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN
  eState := E_State.Fault;
ELSIF nAlarmsActive > 0 OR nUnacked > 0 THEN
  eState := E_State.Held;
ELSE
  eState := E_State.Running;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK