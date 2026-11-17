(* F_ReportRun — the report-by-exception decision of one value (private to FB_Report and FB_ReportArray): the rules of
FB_Report. tHeartbeat and bOnStart are the ones in force (FB_ReportArray: the array's when the item's are off).
Returns stM.bReport. *)

FUNCTION F_ReportRun : BOOL
  VAR_INPUT
    tNow : TIME;
    fIn : REAL;
    bInGood : BOOL;
    bForceReq : BOOL;
    bEnable : BOOL;
    tHeartbeat : TIME;
    bOnStart : BOOL;
  END_VAR
  VAR_IN_OUT
    stS : ST_ReportSet;
    stM : ST_ReportMem;
    stSts : ST_ReportSts;
  END_VAR
  VAR
    fV : REAL;
    bQ : BOOL;
    fDb : REAL;
    fR : LREAL;
    bSend : BOOL;
  END_VAR


(* the value: NaN fails every comparison; infinity is beyond any real *)
bSend := FALSE;
IF NOT (ABS(fIn) <= REAL#3.4E38) THEN
  fV := stM.fGoodV;
  bQ := FALSE;
ELSE
  fV := fIn;
  IF stS.fResolution > 0.0 THEN
    fR := REAL_TO_LREAL(fV) / REAL_TO_LREAL(stS.fResolution);
    IF fR < 1.0E15 AND fR > -1.0E15 THEN
      fV := LREAL_TO_REAL(LINT_TO_LREAL(LREAL_TO_LINT(fR)) * REAL_TO_LREAL(stS.fResolution));
    END_IF;
  END_IF;
  stM.fGoodV := fV;
  bQ := bInGood;
END_IF;
IF bForceReq THEN
  stM.bForcePend := bEnable;
END_IF;
IF NOT bEnable THEN
  stM.bStarted := FALSE;
  stM.bForcePend := FALSE;
  stM.bChange := FALSE;
  stM.bHeld := FALSE;
ELSIF NOT stM.bStarted THEN
  stM.bStarted := TRUE;
  stM.bForcePend := FALSE;
  stM.bChange := FALSE;
  stM.bHeld := FALSE;
  IF bOnStart THEN
    bSend := TRUE;
    stM.eReason := E_ReportReason.First;
  ELSE
    stSts.fLastValue := fV;   (* the starting point for changes *)
    stSts.bLastGood := bQ;
    stM.tLastAt := tNow;
  END_IF;
ELSE
  fDb := MAX(stS.fDeadband, 0.0);
  IF stS.eDeadbandMode = E_DeadbandMode.PctValue THEN
    fDb := ABS(stSts.fLastValue) * fDb / 100.0;
  ELSIF stS.eDeadbandMode = E_DeadbandMode.PctSpan THEN
    IF stS.fSpan > 0.0 THEN
      fDb := stS.fSpan * fDb / 100.0;
    ELSE
      fDb := 0.0;
    END_IF;
  END_IF;
  IF ABS(fV - stSts.fLastValue) > fDb OR bQ <> stSts.bLastGood THEN
    stM.bChange := TRUE;
  END_IF;
  IF tNow - stM.tLastAt >= stS.tMinInterval THEN
    IF stM.bForcePend THEN
      bSend := TRUE;
      stM.eReason := E_ReportReason.Forced;
    ELSIF stM.bChange THEN
      bSend := TRUE;
      stM.eReason := E_ReportReason.Change;
    ELSIF tHeartbeat > T#0s AND tNow - stM.tLastAt >= tHeartbeat THEN
      bSend := TRUE;
      stM.eReason := E_ReportReason.Heartbeat;
    END_IF;
  ELSIF (stM.bForcePend OR stM.bChange) AND NOT stM.bHeld THEN
    stM.bHeld := TRUE;
    stSts.nSuppressed := stSts.nSuppressed + 1;
  END_IF;
END_IF;
stM.bReport := bSend;
IF bSend THEN
  stM.fValue := fV;
  stM.bGood := bQ;
  stSts.eReason := stM.eReason;
  stSts.fLastValue := fV;
  stSts.bLastGood := bQ;
  stSts.nReports := stSts.nReports + 1;
  stM.tLastAt := tNow;
  stM.bForcePend := FALSE;
  stM.bChange := FALSE;
  stM.bHeld := FALSE;
END_IF;
IF stM.bStarted THEN
  stSts.tSinceLast := tNow - stM.tLastAt;
END_IF;
F_ReportRun := bSend;

END_FUNCTION