(* FB_Report — report by exception: decides when one value is worth sending to SCADA / IoT (src-v2 UT_REPORT, the same
rules). bReport pulses for one scan when:
  First      the block starts, or bEnable comes back (link up), with set.bReportOnStart
  Change     fIn moved more than the deadband from the last value sent, or bInGood changed
  Heartbeat  set.tHeartbeat passed since the last report (0 = off, the default)
  Forced     bForce / bCmdForce
set.tMinInterval (0 = none, the default: no rate cap) keeps two reports apart; a change or a force during it is
sent when it ends, with the value then (sts.nSuppressed counts them). An fIn that is not a number is sent as not
good with the last good value. The deadband is in the value's units (Abs), a % of the last value sent (PctValue),
or a % of set.fSpan (PctSpan); set.fResolution rounds the value first (0 = off).
Pins: fIn (BOOL / INT: convert to REAL), bInGood, bForce, bEnable, refData -> bReport, fValue (held from the
report), bGood (its quality), eReason, plus FB_Object's outputs. Settings are kept (a retained last-good copy, a
bad write put back). Note: the 0.2 comms libraries (modbee-mqtt Record) decide reporting themselves; this block
is for a value sent by other means. *)

FUNCTION_BLOCK FB_Report EXTENDS FB_Object
  VAR_INPUT
    fIn : REAL;
    bInGood : BOOL := TRUE;
    bForce : BOOL R_EDGE; (* report now *)
    bEnable : BOOL := TRUE; (* link up / born: on again = report First *)
    refData : REFERENCE TO ST_ReportData;
  END_VAR
  VAR_OUTPUT
    bReport : BOOL; (* one scan: send now *)
    fValue : REAL; (* held from the report *)
    bGood : BOOL; (* its quality *)
    eReason : E_ReportReason; (* held from the report *)
  END_VAR
  VAR RETAIN
    stKept : ST_ReportSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    stMem : ST_ReportMem;
    bCmdSeen : BOOL;
  END_VAR
  VAR_TEMP
    bOk : BOOL;
    bForceReq : BOOL;
  END_VAR


METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_ReportSet;
  END_VAR
  SetOk := F_ReportSetOk(stS := stS);
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bReport := FALSE;
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
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
  bOk := TRUE;
END_IF;
bForceReq := bForce OR (refData.bCmdForce AND NOT bCmdSeen);
bCmdSeen := refData.bCmdForce;
refData.bCmdForce := FALSE;
IF bForceReq OR SystemReset() THEN
  refData.sts.bRefused := FALSE;
END_IF;

bReport := F_ReportRun(tNow := tNow, fIn := fIn, bInGood := bInGood, bForceReq := bForceReq, bEnable := bEnable,
                       tHeartbeat := refData.set.tHeartbeat, bOnStart := refData.set.bReportOnStart,
                       stS := refData.set, stM := stMem, stSts := refData.sts);
fValue := stMem.fValue;
bGood := stMem.bGood;
eReason := stMem.eReason;
bError := NOT bOk;
bWarning := NOT bError AND refData.sts.bRefused;
IF NOT bOk THEN eErrorId := E_UtError.BadSetting;
ELSIF refData.sts.bRefused THEN eErrorId := E_UtError.SettingRefused;
ELSE eErrorId := E_UtError.None;
END_IF;
IF bError THEN eState := E_State.Fault;
ELSIF NOT bEnable THEN eState := E_State.Off;
ELSE eState := E_State.Running;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK