(* FB_Watchdog — comms / heartbeat monitor and generator (src-v2 UT_WATCHDOG).
Pins: bBeat (a heartbeat bit from the remote, either edge) or nCounter (a counter / register, any change),
bEnable, bReset (reset a held failure) -> bOk (remote alive), bCommsFail, bHeartbeatOut, nHeartbeatCount, plus
FB_Object's bError / bWarning / eErrorId / eState. refData: its record.

Watches a value that should keep changing (a remote PLC's heartbeat, a Modbus register, an MQTT message
counter). When neither bBeat nor nCounter has changed for set.tTimeout the link is dead: bCommsFail, bError,
LinkLost. The failure is a protection trip (F_Protect) with set.eFailReset:
  Auto    clears once the link has been alive set.tRecover
  Retry   as Auto, three times an hour, then as Manual
  Manual  stays until a reset (bReset, bCmdReset) with the link alive; a reset while it is dead is refused
bOk is on while the link is alive and has been for tRecover (so it is off at start until the first change).
bHeartbeatOut toggles and nHeartbeatCount counts up every set.tBeatPeriod, for the other side to watch; they
keep going when bEnable is off. sts.stFail.nCount (failures) and det.tDownTime (time dead, from the timeout to
the next change) are not kept over a power cut; bCmdResetCount clears both. Settings are kept by the block (a
retained last-good copy): restored at power-up, a bad write put back. *)

FUNCTION_BLOCK FB_Watchdog EXTENDS FB_Object
  VAR_INPUT
    bBeat : BOOL; (* heartbeat bit from the remote (any change counts) *)
    nCounter : DINT; (* or a counter / register from the remote (any change counts) *)
    bEnable : BOOL := TRUE;
    bReset : BOOL R_EDGE; (* reset a held failure (Manual) *)
    refData : REFERENCE TO ST_WatchdogData;
  END_VAR
  VAR_OUTPUT
    bOk : BOOL; (* remote alive *)
    bCommsFail : BOOL; (* no change for tTimeout *)
    bHeartbeatOut : BOOL; (* toggles every tBeatPeriod; send this to the remote *)
    nHeartbeatCount : DINT; (* counts up every tBeatPeriod *)
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
    bResetSeen : BOOL; (* bCmdReset was TRUE last scan: a held command acts once *)
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
METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_WatchdogSet;
  END_VAR
  SetOk := stS.tTimeout > T#0s AND stS.tRecover >= T#0s AND stS.tBeatPeriod >= T#0s
           AND (stS.eFailReset = E_ResetMode.Auto OR stS.eFailReset = E_ResetMode.Retry
                OR stS.eFailReset = E_ResetMode.Manual);
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bOk := FALSE;
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
  bBeatPrev := bBeat;
  nCounterPrev := nCounter;
  tLastChangeAt := tNow;
  tBeatAt := tNow;
END_IF;
bOkSet := SetOk(stS := refData.set);
IF bOkSet THEN
  stKept := refData.set;
ELSIF SetOk(stS := stKept) THEN
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
  bOkSet := TRUE;
END_IF;

(* HMI commands act once per write, then are cleared; one the master keeps writing acts once *)
bResetReq := bReset OR SystemReset() OR (refData.bCmdReset AND NOT bResetSeen);
IF refData.bCmdReset AND NOT bResetSeen THEN
  refData.sts.bRefused := FALSE;
END_IF;
bResetSeen := refData.bCmdReset;
refData.bCmdReset := FALSE;

(* heartbeat for the other side *)
IF refData.set.tBeatPeriod > T#0s THEN
  IF tNow - tBeatAt >= refData.set.tBeatPeriod THEN
    bHeartbeatOut := NOT bHeartbeatOut;
    IF nHeartbeatCount = 2147483647 THEN
      nHeartbeatCount := 0;
    ELSE
      nHeartbeatCount := nHeartbeatCount + 1;
    END_IF;
    tBeatAt := tBeatAt + refData.set.tBeatPeriod;
    IF tNow - tBeatAt >= refData.set.tBeatPeriod THEN
      tBeatAt := tNow;            (* the scan is slower than tBeatPeriod *)
    END_IF;
  END_IF;
ELSE
  bHeartbeatOut := FALSE;
  tBeatAt := tNow;
END_IF;

(* the remote *)
bChanged := bBeat <> bBeatPrev OR nCounter <> nCounterPrev;
bBeatPrev := bBeat;
nCounterPrev := nCounter;
stProt.tDelay := T#0s;
stProt.eReset := refData.set.eFailReset;
stProt.tRecover := refData.set.tRecover;
stProt.nMaxRetries := 3;
IF NOT bEnable THEN
  bSeen := FALSE;
  tLastChangeAt := tNow;
  stProt.eResponse := E_Response.Off;
  F_Protect(tNow := tNow, bCause := FALSE, bResetReq := FALSE, tRetryWindow := T#1h,
            stSet := stProt, stSts := refData.sts.stFail, stWork := stWork);
  bOk := FALSE;
  bCommsFail := FALSE;
ELSE
  (* time dead since the previous scan, up to now or the change seen now *)
  tSinceNow := tNow - tLastChangeAt;
  tSincePrev := tPrev - tLastChangeAt;
  IF tSinceNow > refData.set.tTimeout THEN
    IF tSincePrev > refData.set.tTimeout THEN
      tDown := tDown + (tSinceNow - tSincePrev);
    ELSE
      tDown := tDown + (tSinceNow - refData.set.tTimeout);
    END_IF;
  END_IF;
  IF bChanged THEN
    bSeen := TRUE;
    tLastChangeAt := tNow;
  END_IF;
  bDead := tNow - tLastChangeAt >= refData.set.tTimeout;
  IF bDead OR NOT bSeen THEN
    tAliveSince := tNow;          (* alive counts from the last dead scan, as the protection's recover *)
  END_IF;
  stProt.eResponse := E_Response.Trip;
  bCommsFail := F_Protect(tNow := tNow, bCause := bDead, bResetReq := bResetReq, tRetryWindow := T#1h,
                          stSet := stProt, stSts := refData.sts.stFail, stWork := stWork);
  bOk := NOT bCommsFail AND NOT bDead AND bSeen AND tNow - tAliveSince >= refData.set.tRecover;
END_IF;
tPrev := tNow;
IF refData.bCmdResetCount AND NOT bCountSeen THEN
  refData.sts.stFail.nCount := 0;
  tDown := T#0s;
END_IF;
bCountSeen := refData.bCmdResetCount;
refData.bCmdResetCount := FALSE;

(* errors *)
bError := NOT bOkSet OR bCommsFail;
bWarning := NOT bError AND refData.sts.bRefused;
IF NOT bOkSet THEN
  eErrorId := E_UtError.BadSetting;
ELSIF bCommsFail THEN
  eErrorId := E_UtError.LinkLost;
ELSIF refData.sts.bRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN
  eState := E_State.Fault;
ELSIF NOT bEnable THEN
  eState := E_State.Off;
ELSIF bOk THEN
  eState := E_State.Running;
ELSE
  eState := E_State.Waiting;
END_IF;
refData.sts.bOk := bOk;
refData.sts.bCommsFail := bCommsFail;
refData.det.tLastChange := tNow - tLastChangeAt;
refData.det.tDownTime := tDown;
bFirstScan := FALSE;

END_FUNCTION_BLOCK