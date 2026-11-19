(* F_ReportRun — the report-by-exception decision of one value (private to FB_Report and FB_ReportArray): the rules of
FB_Report. tHeartbeatInterval and bReportOnStart are the ones in force (FB_ReportArray: the array's when the item's are off).
Returns stMemory.bSendNow. *)

FUNCTION F_ReportRun : BOOL
  VAR_INPUT
    tNow : TIME; (* TIME() of this scan *)
    fIn : REAL; (* the value *)
    bInputGood : BOOL; (* its quality *)
    bReportNow : BOOL; (* report now asked this scan *)
    bEnable : BOOL; (* link up / node born *)
    tHeartbeatInterval : TIME; (* the heartbeat in use *)
    bReportOnStart : BOOL; (* report when it starts *)
  END_VAR
  VAR_IN_OUT
    stSettings : ST_ReportSet; (* the item's settings (read only) *)
    stMemory : ST_ReportMem; (* the item's results and memory *)
    stStatus : ST_ReportSts; (* the item's status *)
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
  fV := stMemory.fLastNumber;
  bQ := FALSE;
ELSE
  fV := fIn;
  IF stSettings.fRoundToStep > 0.0 THEN
    fR := REAL_TO_LREAL(fV) / REAL_TO_LREAL(stSettings.fRoundToStep);
    IF fR < 1.0E15 AND fR > -1.0E15 THEN
      fV := LREAL_TO_REAL(LINT_TO_LREAL(LREAL_TO_LINT(fR)) * REAL_TO_LREAL(stSettings.fRoundToStep));
    END_IF;
  END_IF;
  stMemory.fLastNumber := fV;
  bQ := bInputGood;
END_IF;
IF bReportNow THEN
  stMemory.bForcePending := bEnable;
END_IF;
IF NOT bEnable THEN
  stMemory.bStarted := FALSE;
  stMemory.bForcePending := FALSE;
  stMemory.bChangePending := FALSE;
  stMemory.bHeldByMinInterval := FALSE;
ELSIF NOT stMemory.bStarted THEN
  stMemory.bStarted := TRUE;
  stMemory.bForcePending := FALSE;
  stMemory.bChangePending := FALSE;
  stMemory.bHeldByMinInterval := FALSE;
  IF bReportOnStart THEN
    bSend := TRUE;
    stMemory.eReportReason := E_ReportReason.First;
  ELSE
    stStatus.fReportedValue := fV;   (* the starting point for changes *)
    stStatus.bReportedGood := bQ;
    stMemory.tLastReportAt := tNow;
  END_IF;
ELSE
  fDb := MAX(stSettings.fDeadband, 0.0);
  IF stSettings.eDeadbandMode = E_DeadbandMode.PctValue THEN
    fDb := ABS(stStatus.fReportedValue) * fDb / 100.0;
  ELSIF stSettings.eDeadbandMode = E_DeadbandMode.PctSpan THEN
    IF stSettings.fSpan > 0.0 THEN
      fDb := stSettings.fSpan * fDb / 100.0;
    ELSE
      fDb := 0.0;
    END_IF;
  END_IF;
  IF ABS(fV - stStatus.fReportedValue) > fDb OR bQ <> stStatus.bReportedGood THEN
    stMemory.bChangePending := TRUE;
  END_IF;
  IF tNow - stMemory.tLastReportAt >= stSettings.tMinInterval THEN
    IF stMemory.bForcePending THEN
      bSend := TRUE;
      stMemory.eReportReason := E_ReportReason.Forced;
    ELSIF stMemory.bChangePending THEN
      bSend := TRUE;
      stMemory.eReportReason := E_ReportReason.Change;
    ELSIF tHeartbeatInterval > T#0s AND tNow - stMemory.tLastReportAt >= tHeartbeatInterval THEN
      bSend := TRUE;
      stMemory.eReportReason := E_ReportReason.Heartbeat;
    END_IF;
  ELSIF (stMemory.bForcePending OR stMemory.bChangePending) AND NOT stMemory.bHeldByMinInterval THEN
    stMemory.bHeldByMinInterval := TRUE;
    stStatus.nSuppressedCount := stStatus.nSuppressedCount + 1;
  END_IF;
END_IF;
stMemory.bSendNow := bSend;
IF bSend THEN
  stMemory.fReportedValue := fV;
  stMemory.bReportedGood := bQ;
  stStatus.eReportReason := stMemory.eReportReason;
  stStatus.fReportedValue := fV;
  stStatus.bReportedGood := bQ;
  stStatus.nSentCount := stStatus.nSentCount + 1;
  stMemory.tLastReportAt := tNow;
  stMemory.bForcePending := FALSE;
  stMemory.bChangePending := FALSE;
  stMemory.bHeldByMinInterval := FALSE;
END_IF;
IF stMemory.bStarted THEN
  stStatus.tSinceLastReport := tNow - stMemory.tLastReportAt;
END_IF;
F_ReportRun := bSend;

END_FUNCTION