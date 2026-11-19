(* FB_Watchdog — comms / heartbeat monitor and generator.
Pins: bHeartbeatIn (a heartbeat bit from the remote, either edge) or nCounterIn (a counter / register, any change),
bEnable, bResetFaults (reset a held failure) -> bAlive (remote alive), bCommsFail, bHeartbeatOut, nHeartbeatCount, plus
FB_Object's bError / bWarning / eErrorId / eState. refData: its record.

Watches a value that should keep changing (a remote PLC's heartbeat, a Modbus register, an MQTT message
counter). When neither bHeartbeatIn nor nCounterIn has changed for set.tHeartbeatTimeout the link is dead: bCommsFail, bError,
LinkLost. The failure is a protection (F_Protect, set.stCommsFailFault, default a trip) with its eResetMode:
  Auto    clears once the link has been alive set.stCommsFailFault.tAutoRecoverAfter
  Retry   as Auto, nMaxRetriesBeforeLockout times within set.tRetryCountWindow, then as Manual
  Manual  stays until a reset (bResetFaults, bCmdResetFaults) with the link alive; a reset while it is dead is refused
bAlive is on while the link is alive and has been for tAutoRecoverAfter (so it is off at start until the first change).
bHeartbeatOut toggles and nHeartbeatCount counts up every set.tHeartbeatInterval, for the other side to watch; they
keep going when bEnable is off. sts.stCommsFailFault.nTripCount (failures) and det.tTotalOutageTime (time dead, from the timeout to
the next change) are not kept over a power cut; bCmdResetCounters clears both. Settings are kept by the block (a
retained last-good copy): restored at power-up, a bad write put back.
bHeartbeatReceived is TRUE for one scan at each change of the remote's beat. *)

FUNCTION_BLOCK FB_Watchdog EXTENDS FB_Object
  VAR_INPUT
    bHeartbeatIn : BOOL; (* heartbeat bit from the remote (any change counts) *)
    nCounterIn : DINT; (* or a counter / register from the remote (any change counts) *)
    bEnable : BOOL := TRUE; (* works only while TRUE *)
    bResetFaults : BOOL R_EDGE; (* reset a held failure (Manual) *)
    refData : REFERENCE TO ST_WatchdogData; (* the block's record *)
  END_VAR
  VAR_OUTPUT
    bAlive : BOOL; (* remote alive *)
    bCommsFail : BOOL; (* no change for tHeartbeatTimeout *)
    bHeartbeatOut : BOOL; (* toggles every tHeartbeatInterval; send this to the remote *)
    nHeartbeatCount : DINT; (* counts up every tHeartbeatInterval *)
    bHeartbeatReceived : BOOL; (* one scan: the remote's beat changed *)
  END_VAR
  VAR RETAIN
    stKept : ST_WatchdogSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    stProt : ST_ProtectionSet;
    stWork : ST_ProtectionWork;
    tPrev : TIME;
    bBeatPrev : BOOL;
    nCounterPrev : DINT;
    bSeen : BOOL; (* a change seen since start / enable *)
    tLastChangeAt : TIME;
    tAliveSince : TIME;
    tDown : TIME;
    tBeatAt : TIME;
    bResetSeen : BOOL; (* bCmdResetFaults was TRUE last scan: a held command acts once *)
    bCountSeen : BOOL;
  END_VAR
  VAR_TEMP
    bOkSet : BOOL;
    bResetReq : BOOL;
    bChanged : BOOL;
    bDead : BOOL;
    tSinceNow : TIME; (* since the last change, now *)
    tSincePrev : TIME; (* and at the previous scan *)
  END_VAR


(* the settings are usable *)
METHOD PRIVATE SetWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_WatchdogSet;
  END_VAR
  SetWhy := E_UtError.None;
  IF NOT (stS.tHeartbeatTimeout > T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tHeartbeatInterval >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.stCommsFailFault.tTripDelay >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stCommsFailFault.tAutoRecoverAfter >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stCommsFailFault.nMaxRetriesBeforeLockout >= 0) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stCommsFailFault.eResetMode = E_ResetMode.Auto OR stS.stCommsFailFault.eResetMode = E_ResetMode.Retry
             OR stS.stCommsFailFault.eResetMode = E_ResetMode.Manual) THEN
    SetWhy := E_UtError.ChoiceBad;
  ELSIF NOT (stS.tRetryCountWindow >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_WatchdogSet;
  END_VAR
  SetOk := SetWhy(stS := stS) = E_UtError.None;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bAlive := FALSE;
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();

(* kept settings; a bad write is put back *)
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
  ELSE
    stKept := refData.set;
    nKeptLayout := cLayout;
  END_IF;
  tPrev := tNow;
  bBeatPrev := bHeartbeatIn;
  nCounterPrev := nCounterIn;
  tLastChangeAt := tNow;
  tBeatAt := tNow;
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

(* HMI commands act once per write, then are cleared; one the master keeps writing acts once *)
bResetReq := bResetFaults OR SystemReset() OR (refData.bCmdResetFaults AND NOT bResetSeen);
IF refData.bCmdResetFaults AND NOT bResetSeen THEN
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;
bResetSeen := refData.bCmdResetFaults;
refData.bCmdResetFaults := FALSE;

(* heartbeat for the other side *)
IF refData.set.tHeartbeatInterval > T#0s THEN
  IF tNow - tBeatAt >= refData.set.tHeartbeatInterval THEN
    bHeartbeatOut := NOT bHeartbeatOut;
    IF nHeartbeatCount = 2147483647 THEN
      nHeartbeatCount := 0;
    ELSE
      nHeartbeatCount := nHeartbeatCount + 1;
    END_IF;
    tBeatAt := tBeatAt + refData.set.tHeartbeatInterval;
    IF tNow - tBeatAt >= refData.set.tHeartbeatInterval THEN
      tBeatAt := tNow;            (* the scan is slower than tHeartbeatInterval *)
    END_IF;
  END_IF;
ELSE
  bHeartbeatOut := FALSE;
  tBeatAt := tNow;
END_IF;

(* the remote *)
bChanged := bHeartbeatIn <> bBeatPrev OR nCounterIn <> nCounterPrev;
bBeatPrev := bHeartbeatIn;
nCounterPrev := nCounterIn;
stProt := refData.set.stCommsFailFault;
IF NOT bEnable THEN
  bSeen := FALSE;
  tLastChangeAt := tNow;
  stProt.eActionOnFault := E_Response.Off;
  F_Protect(tNow := tNow, bConditionPresent := FALSE, bResetRequest := FALSE, tRetryCountWindow := refData.set.tRetryCountWindow,
            stSettings := stProt, stStatus := refData.sts.stCommsFailFault, stWorking := stWork);
  bAlive := FALSE;
  bCommsFail := FALSE;
ELSE
  (* time dead since the previous scan, up to now or the change seen now *)
  tSinceNow := tNow - tLastChangeAt;
  tSincePrev := tPrev - tLastChangeAt;
  IF tSinceNow > refData.set.tHeartbeatTimeout THEN
    IF tSincePrev > refData.set.tHeartbeatTimeout THEN
      tDown := tDown + (tSinceNow - tSincePrev);
    ELSE
      tDown := tDown + (tSinceNow - refData.set.tHeartbeatTimeout);
    END_IF;
  END_IF;
  bHeartbeatReceived := bChanged;
  IF bChanged THEN
    bSeen := TRUE;
    tLastChangeAt := tNow;
  END_IF;
  bDead := tNow - tLastChangeAt >= refData.set.tHeartbeatTimeout;
  IF bDead OR NOT bSeen THEN
    tAliveSince := tNow;          (* alive counts from the last dead scan, as the protection's recover *)
  END_IF;
  bCommsFail := F_Protect(tNow := tNow, bConditionPresent := bDead, bResetRequest := bResetReq, tRetryCountWindow := refData.set.tRetryCountWindow,
                          stSettings := stProt, stStatus := refData.sts.stCommsFailFault, stWorking := stWork);
  bAlive := NOT bCommsFail AND NOT bDead AND bSeen AND tNow - tAliveSince >= refData.set.stCommsFailFault.tAutoRecoverAfter;
END_IF;
tPrev := tNow;
IF refData.bCmdResetCounters AND NOT bCountSeen THEN
  refData.sts.stCommsFailFault.nTripCount := 0;
  tDown := T#0s;
END_IF;
bCountSeen := refData.bCmdResetCounters;
refData.bCmdResetCounters := FALSE;

(* errors *)
bError := NOT bOkSet OR bCommsFail;
bWarning := NOT bError AND refData.sts.bSettingRefused;
IF NOT bOkSet THEN
  eErrorId := E_UtError.BadSetting;
ELSIF bCommsFail THEN
  eErrorId := E_UtError.LinkLost;
ELSIF refData.sts.bSettingRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN
  eState := E_State.Fault;
ELSIF NOT bEnable THEN
  eState := E_State.Off;
ELSIF bAlive THEN
  eState := E_State.Running;
ELSE
  eState := E_State.Waiting;
END_IF;
refData.sts.bAlive := bAlive;
refData.sts.bCommsFail := bCommsFail;
refData.det.tSinceLastHeard := tNow - tLastChangeAt;
refData.det.tTotalOutageTime := tDown;
bFirstScan := FALSE;

END_FUNCTION_BLOCK