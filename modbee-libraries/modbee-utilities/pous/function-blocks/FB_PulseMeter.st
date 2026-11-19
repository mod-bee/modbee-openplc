(* FB_PulseMeter — a pulse flow meter or a hardware pulse counter.

Pins: bPulse (each rising edge is one pulse: at most one pulse per two scans), nHardwareCount (a hardware counter,
e.g. node-uio FB_PulseCounter: each count is one pulse; a wrap past 2^32 or set.nCounterWrapsAt is counted, a drop of
more than half the range is a counter restart), bInputGood (the input can be trusted), refData.
set.eCountFrom picks the input; each pulse adds set.fVolumePerPulse to the total. Nothing is counted while the input is
bad (a counter catches up when it is good again); bad past its delay is a warning and bIsGood FALSE.
Units: set.eMeterUnit (the unit of fVolumePerPulse) and set.eTotalUnit (the unit of the total and the rate), E_Unit volume units
(litre, m3, megalitre, gallon): both set convert each addition; both None = no conversion. One set, or a unit
that is not a volume, is a bad setting (put back).
Batch: tot.fBatchTotal counts like tot.fTotal until bResetBatch (rising edge) / bCmdResetBatch; bBatchDone is TRUE once
it has reached set.fBatchSetpoint (0 = off), until the batch is reset.
Offers I_Meter (an I_Measurement too: its rate): the total and the rate (per hour, over set.tRateWindow). The total and the batch are kept hourly,
when bPumpRunning falls (the pump stops; optional) and on a reset. sts.nPulseCount counts pulses since power-up;
pulses at the input's limit (a pulse every second scan) warn (PulsesTooFast, sts.bPulsesTooFast, held 5 s).
Total commands: bCmdResetTotals (with set.bResetNeedsConfirm, only together with bCmdConfirmReset in the same write) and
bCmdPresetTotal (the total to fPresetTotal, 0 .. 1E12). *)

FUNCTION_BLOCK FB_PulseMeter EXTENDS FB_Object IMPLEMENTS I_Meter
  VAR_INPUT
    bPulse : BOOL := FALSE; (* each rising edge is one pulse (at most one pulse per two scans) *)
    nHardwareCount : UDINT; (* a hardware counter (e.g. node-uio FB_PulseCounter): each count is one pulse *)
    bInputGood : BOOL := TRUE; (* the input can be trusted *)
    bPumpRunning : BOOL := FALSE; (* optional: the pump runs; its fall keeps the totals *)
    bResetBatch : BOOL R_EDGE; (* the batch back to 0 *)
    refData : REFERENCE TO ST_PulseMeterData; (* the block's record *)
  END_VAR
  VAR_OUTPUT
    bBatchDone : BOOL; (* the batch has reached set.fBatchSetpoint *)
  END_VAR
  VAR RETAIN
    stKept : ST_PulseMeterSet;
    nKeptLayout : UINT;
    stKeptTot : ST_PulseMeterTot;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 3;
  END_VAR
  VAR
    stWInputBad : ST_ProtectionWork;
    bPulsePrev : BOOL;
    nScansSince : INT; (* scans since the last pulse *)
    tFastAt : TIME;
    bFastSeen : BOOL;
    nPrev : UDINT;
    bCountValid : BOOL;
    tKeptAt : TIME;
    bRunningWas : BOOL;
    tWindowAt : TIME;
    fWindowTotal : LREAL;
  END_VAR
  VAR_TEMP
    nD : UDINT;
    bTrip : BOOL;
    tWin : TIME;
    fMult : LREAL; (* input unit to output unit *)
    bUnitOk : BOOL;
    fBefore : LREAL;
  END_VAR


(* the first bad setting (None: all good) *)
METHOD PRIVATE SetWhy : E_UtError
  SetWhy := E_UtError.None;
  IF NOT (refData.set.fVolumePerPulse >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.tRateWindow > T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (UnitsOk()) THEN
    SetWhy := E_UtError.ChoiceBad;
  ELSIF NOT (refData.set.fBatchSetpoint >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.fBatchSetpoint <= 1.0E15) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (refData.set.stMeterBadFault.tTripDelay >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (refData.set.stMeterBadFault.tAutoRecoverAfter >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (refData.set.tRetryCountWindow >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  END_IF;
END_METHOD

METHOD PRIVATE UnitsOk : BOOL
  VAR
    bU : BOOL;
    fU : LREAL;
  END_VAR
  fU := F_UnitFactor(eFromUnit := refData.set.eMeterUnit, eToUnit := refData.set.eTotalUnit, bUnitsMatch => bU);
  UnitsOk := bU;
END_METHOD

PROPERTY PUBLIC fActTotal : LREAL    // the lifetime total in its unit
  GET
    IF __ISVALIDREF(refData) THEN fActTotal := refData.tot.fTotal; ELSE fActTotal := 0.0; END_IF;
  END_GET
END_PROPERTY
PROPERTY PUBLIC fActFlowPerHour : REAL    // the rate, per hour
  GET
    IF __ISVALIDREF(refData) THEN fActFlowPerHour := refData.sts.fFlowPerHour; ELSE fActFlowPerHour := 0.0; END_IF;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsGood : BOOL    // the value can be trusted now
  GET
    IF __ISVALIDREF(refData) THEN bIsGood := refData.sts.bGood; ELSE bIsGood := FALSE; END_IF;
  END_GET
END_PROPERTY
(* I_Measurement: the rate (per hour), in set.eTotalUnit per hour, no bands *)
PROPERTY PUBLIC fActValue : REAL    // the value now (the total, in its unit)
  GET
    IF __ISVALIDREF(refData) THEN fActValue := refData.sts.fFlowPerHour; ELSE fActValue := 0.0; END_IF;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bHasValue : BOOL    // a value is available (fitted and read at least once)
  GET
    bHasValue := TRUE;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsFitted : BOOL    // fitted on this site
  GET
    bIsFitted := TRUE;
  END_GET
END_PROPERTY
PROPERTY PUBLIC eUnit : E_Unit    // the unit of the value
  GET
    eUnit := E_Unit.None;
    IF __ISVALIDREF(refData) THEN eUnit := F_UnitPerHour(eUnit := refData.set.eTotalUnit); END_IF;
  END_GET
END_PROPERTY
METHOD PUBLIC Band : BOOL
  VAR_INPUT
    eBand : E_Band;
  END_VAR
  Band := FALSE;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  RETURN;
END_IF;
tNow := TIME();
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
    refData.tot := stKeptTot;
  ELSE
    stKept := refData.set;
    stKeptTot := refData.tot;
    nKeptLayout := cLayout;
  END_IF;
  tKeptAt := tNow;
  tWindowAt := tNow;
  fWindowTotal := refData.tot.fTotal;
  bPulsePrev := bPulse;
ELSIF SetWhy() = E_UtError.None THEN
  stKept := refData.set;
ELSE
  refData.sts.eSettingRefusedErrorId := SetWhy();
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
END_IF;
IF SystemReset() THEN                // the plant reset clears a refused write
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;

(* count *)
fMult := F_UnitFactor(eFromUnit := refData.set.eMeterUnit, eToUnit := refData.set.eTotalUnit, bUnitsMatch => bUnitOk);
fBefore := refData.tot.fTotal;
IF bInputGood THEN
  IF refData.set.eCountFrom = E_PulseSource.Count THEN
    IF NOT bCountValid THEN
      nPrev := nHardwareCount;
      bCountValid := TRUE;
    ELSIF nHardwareCount <> nPrev THEN
      IF nHardwareCount > nPrev THEN
        nD := nHardwareCount - nPrev;
      ELSIF refData.set.nCounterWrapsAt >= 2 AND nPrev < refData.set.nCounterWrapsAt
            AND nHardwareCount + (refData.set.nCounterWrapsAt - nPrev) < refData.set.nCounterWrapsAt / 2 THEN
        nD := nHardwareCount + (refData.set.nCounterWrapsAt - nPrev);
      ELSIF refData.set.nCounterWrapsAt = 0 THEN
        nD := nHardwareCount - nPrev;     // modulo 2^32
        IF nD >= 16#80000000 THEN nD := nHardwareCount; END_IF;   // it restarted from 0
      ELSE
        nD := nHardwareCount;             // a counter restart
      END_IF;
      nPrev := nHardwareCount;
      refData.tot.fTotal := refData.tot.fTotal + UDINT_TO_LREAL(nD) * REAL_TO_LREAL(refData.set.fVolumePerPulse) * fMult;
      refData.sts.nPulseCount := refData.sts.nPulseCount + nD;
    END_IF;
  ELSIF bPulse AND NOT bPulsePrev THEN
    refData.tot.fTotal := refData.tot.fTotal + REAL_TO_LREAL(refData.set.fVolumePerPulse) * fMult;
    refData.sts.nPulseCount := refData.sts.nPulseCount + 1;
    IF nScansSince <= 2 THEN      (* a pulse every second scan: the most the input can count *)
      tFastAt := tNow;
      bFastSeen := TRUE;
    END_IF;
    nScansSince := 0;
  END_IF;
END_IF;
bPulsePrev := bPulse;
IF nScansSince < 32767 THEN nScansSince := nScansSince + 1; END_IF;
IF bFastSeen AND tNow - tFastAt >= T#5s THEN bFastSeen := FALSE; END_IF;
refData.sts.bPulsesTooFast := bFastSeen;
refData.tot.fBatchTotal := refData.tot.fBatchTotal + (refData.tot.fTotal - fBefore);

(* the input bad *)
bTrip := F_Protect(tNow := tNow, bConditionPresent := NOT bInputGood, bResetRequest := SystemReset(), tRetryCountWindow := refData.set.tRetryCountWindow,
                   stSettings := refData.set.stMeterBadFault, stStatus := refData.sts.stMeterBadFault, stWorking := stWInputBad);
refData.sts.bGood := NOT stWInputBad.bActive;

(* rate over the window *)
tWin := tNow - tWindowAt;
IF tWin >= refData.set.tRateWindow THEN
  refData.sts.fFlowPerHour := LREAL_TO_REAL((refData.tot.fTotal - fWindowTotal) * 3600000.0 / TIME_TO_LREAL(tWin));
  fWindowTotal := refData.tot.fTotal;
  tWindowAt := tNow;
END_IF;

(* reset, keep *)
IF refData.bCmdResetTotals AND (refData.bCmdConfirmReset OR NOT refData.set.bResetNeedsConfirm) THEN
  refData.tot.fTotal := 0.0;
  fWindowTotal := 0.0;
  stKeptTot := refData.tot;
  refData.bCmdResetTotals := FALSE;
END_IF;
refData.bCmdResetTotals := FALSE;
refData.bCmdConfirmReset := FALSE;
IF refData.bCmdPresetTotal THEN
  IF refData.fPresetTotal >= 0.0 AND refData.fPresetTotal <= 1.0E12 THEN
    refData.tot.fTotal := refData.fPresetTotal;
    fWindowTotal := refData.fPresetTotal;
    stKeptTot := refData.tot;
  END_IF;
  refData.bCmdPresetTotal := FALSE;
END_IF;
IF bResetBatch OR refData.bCmdResetBatch THEN
  refData.bCmdResetBatch := FALSE;
  refData.tot.fBatchTotal := 0.0;
  stKeptTot := refData.tot;
END_IF;
bBatchDone := refData.set.fBatchSetpoint > 0.0 AND refData.tot.fBatchTotal >= refData.set.fBatchSetpoint;
IF (bRunningWas AND NOT bPumpRunning) OR tNow - tKeptAt >= T#1h THEN
  stKeptTot := refData.tot;
  tKeptAt := tNow;
END_IF;
bRunningWas := bPumpRunning;

bError := stWInputBad.bTripping;
bWarning := stWInputBad.bWarning OR refData.sts.bSettingRefused OR bFastSeen;
IF stWInputBad.bTripping OR stWInputBad.bWarning THEN
  eErrorId := E_UtError.SensorBad;
ELSIF bFastSeen THEN
  eErrorId := E_UtError.PulsesTooFast;
ELSIF refData.sts.bSettingRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF refData.sts.bGood THEN eState := E_State.Running; ELSE eState := E_State.Fault; END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK