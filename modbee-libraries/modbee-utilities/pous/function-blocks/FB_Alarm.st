(* FB_Alarm — one alarm as its own block, the ISA-18.2 way. Optional: alarm lists, history and notifications are the
HMI / SCADA's. FB_AlarmTable is the lean choice for a panel's alarms; this block adds shelving, suppression, out
of service, priorities, time stamps and the group annunciator (FB_Annunciator).
The condition is bConditionPresent (wire a device's bError or bWarning); eAlarmCodeNow names it (wire the device's eErrorId; None =
set.stRowSettings.eAlarmCode). F_AlarmRun does the rest as an FB_AlarmTable row: on / off delays (stRowSettings.tTripDelay / tAutoRecoverAfter),
Auto / Manual (latched until a reset with the condition gone) / Retry (locks out after stRowSettings.nMaxRetriesBeforeLockout raises
within set.tRetryCountWindow), acknowledge, re-arm. sts.eAlarmState: Normal, Unacked, Acked, RtnUnacked, Shelved
(bCmdShelve, for set.tShelveTime, at most set.tMaxShelveTime), Suppressed (bSuppress), OutOfService (bCmdOutOfService),
Latched, Locked. A shelved, suppressed or out-of-service alarm still present comes bAcknowledge as a new one.
set.bLatchUntilAcknowledged: bAlarmOn stays on until acknowledged after the condition cleared; set.bAcknowledgeRequired FALSE: an event that never
needs acknowledging. bAcknowledge / bCmdAcknowledge / bGroupAcknowledge (from FB_Annunciator) acknowledge; bResetFaults / bCmdResetFaults acknowledge and
clear a latched / locked alarm whose condition has gone. dtRaisedAt / dtAcknowledgedAt / dtClearedAt from dtLocalTime
(optional; unwired: blank - the boards have no real-time clock, the SCADA stamps on arrival); sts.nRaisedAtMs (ms)
orders the first-out. HMI commands act once per write.
Pins: bConditionPresent, eAlarmCodeNow, bSuppress, bAcknowledge, bResetFaults, dtLocalTime, refData -> bAlarmOn (annunciate), bUnacknowledged, bConditionActive (the condition
after the delays), eAlarmCode, plus FB_Object's outputs (bError for a Trip alarm on, bWarning for a Warn one).
Settings are kept (a retained last-good copy, a bad write put bAcknowledge). *)

FUNCTION_BLOCK FB_Alarm EXTENDS FB_Object
  VAR_INPUT
    bConditionPresent : BOOL; (* the condition *)
    eAlarmCodeNow : E_UtError; (* what it is now (None = set.stRowSettings.eAlarmCode) *)
    bSuppress : BOOL; (* suppressed by design *)
    bAcknowledge : BOOL R_EDGE; (* rising edge: acknowledge *)
    bResetFaults : BOOL R_EDGE; (* rising edge: acknowledge, and clear a latched or locked alarm whose condition has gone *)
    dtLocalTime : DT := DT#1970-01-01-00:00:00; (* a real-time clock (optional); unwired: the times stay blank *)
    refData : REFERENCE TO ST_AlarmData; (* the alarm's record *)
  END_VAR
  VAR_OUTPUT
    bAlarmOn : BOOL; (* to annunciate *)
    bUnacknowledged : BOOL; (* an alarm is waiting to be acknowledged *)
    bConditionActive : BOOL; (* the condition now (after the delays) *)
    eAlarmCode : E_UtError; (* which alarm is shown now *)
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
  IF NOT (stS.stRowSettings.eActionOnFault = E_Response.Off OR stS.stRowSettings.eActionOnFault = E_Response.Warn
          OR stS.stRowSettings.eActionOnFault = E_Response.Trip OR stS.stRowSettings.eActionOnFault = E_Response.Signal) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stRowSettings.eResetMode = E_ResetMode.Auto OR stS.stRowSettings.eResetMode = E_ResetMode.Manual
             OR stS.stRowSettings.eResetMode = E_ResetMode.Retry) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stRowSettings.tTripDelay >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stRowSettings.tAutoRecoverAfter >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stRowSettings.tReAlarmAfter >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.tRetryCountWindow >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tMaxShelveTime >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tShelveTime >= T#0s) THEN
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
  bAlarmOn := FALSE;
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

(* commands: once per write *)
bAckReq := bAcknowledge OR (refData.bCmdAcknowledge AND NOT bAckSeen) OR refData.bGroupAcknowledge;
bAckSeen := refData.bCmdAcknowledge;
refData.bCmdAcknowledge := FALSE;
refData.bGroupAcknowledge := FALSE;
bRstReq := bResetFaults OR (refData.bCmdResetFaults AND NOT bRstSeen) OR SystemReset();
bRstSeen := refData.bCmdResetFaults;
refData.bCmdResetFaults := FALSE;
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
IF refData.bCmdResetCounters AND NOT bCountSeen THEN
  refData.sts.nRaiseCount := 0;
END_IF;
bCountSeen := refData.bCmdResetCounters;
refData.bCmdResetCounters := FALSE;
IF bRstReq THEN
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;

(* out of service and shelving; together, the alarm stays live *)
IF bDoOos AND NOT bDoIn THEN
  bOos := TRUE;
ELSIF bDoIn THEN
  bOos := FALSE;
END_IF;
IF bDoShelve AND NOT bDoUnshelve THEN
  tShelveDur := refData.set.tShelveTime;
  IF tShelveDur <= T#0s OR tShelveDur > refData.set.tMaxShelveTime THEN
    tShelveDur := refData.set.tMaxShelveTime;
  END_IF;
  IF tShelveDur > T#0s THEN
    bShelved := TRUE;
    tShelveAt := tNow;
  END_IF;
ELSIF bDoUnshelve THEN
  bShelved := FALSE;
END_IF;
IF bShelved AND tNow - tShelveAt >= MIN(tShelveDur, refData.set.tMaxShelveTime) THEN
  bShelved := FALSE;
END_IF;
IF bShelved THEN
  refData.det.tShelveTimeLeft := MIN(tShelveDur, refData.set.tMaxShelveTime) - (tNow - tShelveAt);
ELSE
  refData.det.tShelveTimeLeft := T#0s;
END_IF;

(* the engine *)
IF eAlarmCodeNow <> E_UtError.None THEN
  eAlarmCode := eAlarmCodeNow;
ELSE
  eAlarmCode := refData.set.stRowSettings.eAlarmCode;
END_IF;
bRemoved := bOos OR bSuppress OR bShelved;
stRun.bConditionPresent := bConditionPresent AND NOT bRemoved;
bRaised := F_AlarmRun(tNow := tNow, bAcknowledge := bAckReq OR bRstReq OR bRemoved OR NOT refData.set.bAcknowledgeRequired,
                      bResetRequest := bRstReq OR bRemoved, bSilence := FALSE, tRetryCountWindow := refData.set.tRetryCountWindow,
                      stSettings := refData.set.stRowSettings, stAlarm := stRun);
IF bRaised THEN
  refData.sts.nRaiseCount := refData.sts.nRaiseCount + 1;
  refData.sts.nRaisedAtMs := TIME_TO_UDINT(tNow);
  refData.sts.dtRaisedAt := dtLocalTime;
  refData.sts.eAlarmCode := eAlarmCode;
END_IF;
IF bUnackedPrev AND NOT stRun.bUnacknowledged AND refData.set.bAcknowledgeRequired THEN
  refData.sts.dtAcknowledgedAt := dtLocalTime;
END_IF;
bUnackedPrev := stRun.bUnacknowledged;
bConditionActive := stRun.bConditionConfirmed;
IF bConditionActive AND NOT bActivePrev THEN
  tActiveAt := tNow;
END_IF;
IF bActivePrev AND NOT bConditionActive THEN
  refData.sts.tLastAlarmDuration := tNow - tActiveAt;
  refData.sts.dtClearedAt := dtLocalTime;
END_IF;
bActivePrev := bConditionActive;

(* the ISA-18.2 state *)
IF bOos THEN
  refData.sts.eAlarmState := E_IsaState.OutOfService;
ELSIF bSuppress THEN
  refData.sts.eAlarmState := E_IsaState.Suppressed;
ELSIF bShelved THEN
  refData.sts.eAlarmState := E_IsaState.Shelved;
ELSE
  CASE stRun.eRowState OF
  E_AlarmState.Active:
    IF stRun.bUnacknowledged THEN
      refData.sts.eAlarmState := E_IsaState.Unacked;
    ELSE
      refData.sts.eAlarmState := E_IsaState.Acked;
    END_IF;
  E_AlarmState.Returned:
    refData.sts.eAlarmState := E_IsaState.RtnUnacked;
  E_AlarmState.Latched:
    refData.sts.eAlarmState := E_IsaState.Latched;
  E_AlarmState.Locked:
    refData.sts.eAlarmState := E_IsaState.Locked;
  ELSE
    refData.sts.eAlarmState := E_IsaState.Normal;
  END_CASE;
END_IF;
bUnacknowledged := stRun.bUnacknowledged AND NOT bRemoved;
bAlarmOn := NOT bRemoved AND (stRun.bAlarmOn OR (refData.set.bLatchUntilAcknowledged AND stRun.eRowState = E_AlarmState.Returned));
refData.sts.bConditionActive := bConditionActive;
refData.sts.bUnacknowledged := bUnacknowledged;
refData.sts.bAlarmOn := bAlarmOn;

bTrip := refData.set.stRowSettings.eActionOnFault = E_Response.Trip;
bError := NOT bOk OR (bAlarmOn AND bTrip);
bWarning := NOT bError AND (bAlarmOn OR refData.sts.bSettingRefused);
IF NOT bOk THEN
  eErrorId := E_UtError.BadSetting;
ELSIF bAlarmOn THEN
  eErrorId := eAlarmCode;
ELSIF refData.sts.bSettingRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF NOT bOk THEN
  eState := E_State.Fault;
ELSIF refData.set.stRowSettings.eActionOnFault = E_Response.Off OR bRemoved THEN
  eState := E_State.Off;
ELSIF bAlarmOn THEN
  eState := E_State.Held;
ELSE
  eState := E_State.Running;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK