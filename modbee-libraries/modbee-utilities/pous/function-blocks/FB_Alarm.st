(* FB_Alarm — one alarm as its own block, the ISA-18.2 way. Optional: alarm lists, history and notifications are the
HMI / SCADA's. FB_AlarmTable is the lean choice for a panel's alarms; this block adds shelving, suppression, out
of service, priorities, time stamps and the group annunciator (FB_Annunciator).
The condition is bIn (wire a device's bError or bWarning); eCause names it (wire the device's eErrorId; None =
set.stRow.eCode). F_AlarmRun does the rest as an FB_AlarmTable row: on / off delays (stRow.tDelay / tRecover),
Auto / Manual (latched until a reset with the condition gone) / Retry (locks out after stRow.nMaxRetries raises
within set.tRetryWindow), acknowledge, re-arm. sts.eIsaState: Normal, Unacked, Acked, RtnUnacked, Shelved
(bCmdShelve, for set.tShelveFor, at most set.tMaxShelve), Suppressed (bInhibit), OutOfService (bCmdOutOfService),
Latched, Locked. A shelved, suppressed or out-of-service alarm still present comes back as a new one.
set.bLatch: bQ stays on until acknowledged after the condition cleared; set.bAckRequired FALSE: an event that never
needs acknowledging. bAck / bCmdAck / bGrpAck (from FB_Annunciator) acknowledge; bReset / bCmdReset acknowledge and
clear a latched / locked alarm whose condition has gone. dtRaisedAt / dtAckedAt / dtClearedAt from dtClock
(optional; unwired: blank - the boards have no real-time clock, the SCADA stamps on arrival); sts.nSequence (ms)
orders the first-out. HMI commands act once per write.
Pins: bIn, eCause, bInhibit, bAck, bReset, dtClock, refData -> bQ (annunciate), bUnacked, bActive (the condition
after the delays), eCode, plus FB_Object's outputs (bError for a Trip alarm on, bWarning for a Warn one).
Settings are kept (a retained last-good copy, a bad write put back). *)

FUNCTION_BLOCK FB_Alarm EXTENDS FB_Object
  VAR_INPUT
    bIn : BOOL; (* the condition *)
    eCause : E_UtError; (* what it is now (None = set.stRow.eCode) *)
    bInhibit : BOOL; (* suppressed by design *)
    bAck : BOOL R_EDGE;
    bReset : BOOL R_EDGE;
    dtClock : DT := DT#1970-01-01-00:00:00; (* a real-time clock (optional); unwired: the times stay blank *)
    refData : REFERENCE TO ST_AlarmData;
  END_VAR
  VAR_OUTPUT
    bQ : BOOL; (* to annunciate *)
    bUnacked : BOOL;
    bActive : BOOL; (* the condition now (after the delays) *)
    eCode : E_UtError;
  END_VAR
  VAR RETAIN
    stKept : ST_AlarmSettings;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    stRun : ST_Alarm; (* the engine's row *)
    bOos : BOOL;
    bShelved : BOOL;
    tShelveAt : TIME;
    tShelveDur : TIME;
    bAckSeen : BOOL;
    bRstSeen : BOOL;
    bShelveSeen : BOOL;
    bUnshelveSeen : BOOL;
    bOosSeen : BOOL;
    bInSeen : BOOL;
    bCountSeen : BOOL;
    bActivePrev : BOOL;
    tActiveAt : TIME;
    bUnackedPrev : BOOL;
  END_VAR
  VAR_TEMP
    bOk : BOOL;
    bAckReq : BOOL;
    bRstReq : BOOL;
    bDoShelve : BOOL;
    bDoUnshelve : BOOL;
    bDoOos : BOOL;
    bDoIn : BOOL;
    bRemoved : BOOL;
    bRaised : BOOL;
    bTrip : BOOL;
  END_VAR


METHOD PRIVATE SetWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_AlarmSettings;
  END_VAR
  SetWhy := E_UtError.None;
  IF NOT (stS.stRow.eResponse = E_Response.Off OR stS.stRow.eResponse = E_Response.Warn
          OR stS.stRow.eResponse = E_Response.Trip OR stS.stRow.eResponse = E_Response.Signal) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stRow.eReset = E_ResetMode.Auto OR stS.stRow.eReset = E_ResetMode.Manual
             OR stS.stRow.eReset = E_ResetMode.Retry) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stRow.tDelay >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stRow.tRecover >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stRow.tRearm >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.tRetryWindow >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tMaxShelve >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tShelveFor >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.ePriority = E_AlarmPriority.Low OR stS.ePriority = E_AlarmPriority.Medium
             OR stS.ePriority = E_AlarmPriority.High OR stS.ePriority = E_AlarmPriority.Critical) THEN
    SetWhy := E_UtError.ChoiceBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_AlarmSettings;
  END_VAR
  SetOk := SetWhy(stS := stS) = E_UtError.None;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bQ := FALSE;
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

(* commands: once per write *)
bAckReq := bAck OR (refData.bCmdAck AND NOT bAckSeen) OR refData.bGrpAck;
bAckSeen := refData.bCmdAck;
refData.bCmdAck := FALSE;
refData.bGrpAck := FALSE;
bRstReq := bReset OR (refData.bCmdReset AND NOT bRstSeen) OR SystemReset();
bRstSeen := refData.bCmdReset;
refData.bCmdReset := FALSE;
bDoShelve := refData.bCmdShelve AND NOT bShelveSeen;
bShelveSeen := refData.bCmdShelve;
refData.bCmdShelve := FALSE;
bDoUnshelve := refData.bCmdUnshelve AND NOT bUnshelveSeen;
bUnshelveSeen := refData.bCmdUnshelve;
refData.bCmdUnshelve := FALSE;
bDoOos := refData.bCmdOutOfService AND NOT bOosSeen;
bOosSeen := refData.bCmdOutOfService;
refData.bCmdOutOfService := FALSE;
bDoIn := refData.bCmdInService AND NOT bInSeen;
bInSeen := refData.bCmdInService;
refData.bCmdInService := FALSE;
IF refData.bCmdResetCount AND NOT bCountSeen THEN
  refData.sts.nCount := 0;
END_IF;
bCountSeen := refData.bCmdResetCount;
refData.bCmdResetCount := FALSE;
IF bRstReq THEN
  refData.sts.bRefused := FALSE;
  refData.sts.eRefusedWhy := E_UtError.None;
END_IF;

(* out of service and shelving; together, the alarm stays live *)
IF bDoOos AND NOT bDoIn THEN
  bOos := TRUE;
ELSIF bDoIn THEN
  bOos := FALSE;
END_IF;
IF bDoShelve AND NOT bDoUnshelve THEN
  tShelveDur := refData.set.tShelveFor;
  IF tShelveDur <= T#0s OR tShelveDur > refData.set.tMaxShelve THEN
    tShelveDur := refData.set.tMaxShelve;
  END_IF;
  IF tShelveDur > T#0s THEN
    bShelved := TRUE;
    tShelveAt := tNow;
  END_IF;
ELSIF bDoUnshelve THEN
  bShelved := FALSE;
END_IF;
IF bShelved AND tNow - tShelveAt >= MIN(tShelveDur, refData.set.tMaxShelve) THEN
  bShelved := FALSE;
END_IF;
IF bShelved THEN
  refData.det.tShelvedFor := MIN(tShelveDur, refData.set.tMaxShelve) - (tNow - tShelveAt);
ELSE
  refData.det.tShelvedFor := T#0s;
END_IF;

(* the engine *)
IF eCause <> E_UtError.None THEN
  eCode := eCause;
ELSE
  eCode := refData.set.stRow.eCode;
END_IF;
bRemoved := bOos OR bInhibit OR bShelved;
stRun.bIn := bIn AND NOT bRemoved;
bRaised := F_AlarmRun(tNow := tNow, bAck := bAckReq OR bRstReq OR bRemoved OR NOT refData.set.bAckRequired,
                      bRst := bRstReq OR bRemoved, bSil := FALSE, tRetryWindow := refData.set.tRetryWindow,
                      stS := refData.set.stRow, stA := stRun);
IF bRaised THEN
  refData.sts.nCount := refData.sts.nCount + 1;
  refData.sts.nSequence := TIME_TO_UDINT(tNow);
  refData.sts.dtRaisedAt := dtClock;
  refData.sts.eCode := eCode;
END_IF;
IF bUnackedPrev AND NOT stRun.bUnacked AND refData.set.bAckRequired THEN
  refData.sts.dtAckedAt := dtClock;
END_IF;
bUnackedPrev := stRun.bUnacked;
bActive := stRun.bCond;
IF bActive AND NOT bActivePrev THEN
  tActiveAt := tNow;
END_IF;
IF bActivePrev AND NOT bActive THEN
  refData.sts.tLastDuration := tNow - tActiveAt;
  refData.sts.dtClearedAt := dtClock;
END_IF;
bActivePrev := bActive;

(* the ISA-18.2 state *)
IF bOos THEN
  refData.sts.eIsaState := E_IsaState.OutOfService;
ELSIF bInhibit THEN
  refData.sts.eIsaState := E_IsaState.Suppressed;
ELSIF bShelved THEN
  refData.sts.eIsaState := E_IsaState.Shelved;
ELSE
  CASE stRun.eState OF
  E_AlarmState.Active:
    IF stRun.bUnacked THEN
      refData.sts.eIsaState := E_IsaState.Unacked;
    ELSE
      refData.sts.eIsaState := E_IsaState.Acked;
    END_IF;
  E_AlarmState.Returned:
    refData.sts.eIsaState := E_IsaState.RtnUnacked;
  E_AlarmState.Latched:
    refData.sts.eIsaState := E_IsaState.Latched;
  E_AlarmState.Locked:
    refData.sts.eIsaState := E_IsaState.Locked;
  ELSE
    refData.sts.eIsaState := E_IsaState.Normal;
  END_CASE;
END_IF;
bUnacked := stRun.bUnacked AND NOT bRemoved;
bQ := NOT bRemoved AND (stRun.bQ OR (refData.set.bLatch AND stRun.eState = E_AlarmState.Returned));
refData.sts.bActive := bActive;
refData.sts.bUnacked := bUnacked;
refData.sts.bQ := bQ;

bTrip := refData.set.stRow.eResponse = E_Response.Trip;
bError := NOT bOk OR (bQ AND bTrip);
bWarning := NOT bError AND (bQ OR refData.sts.bRefused);
IF NOT bOk THEN
  eErrorId := E_UtError.BadSetting;
ELSIF bQ THEN
  eErrorId := eCode;
ELSIF refData.sts.bRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF NOT bOk THEN
  eState := E_State.Fault;
ELSIF refData.set.stRow.eResponse = E_Response.Off OR bRemoved THEN
  eState := E_State.Off;
ELSIF bQ THEN
  eState := E_State.Held;
ELSE
  eState := E_State.Running;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK