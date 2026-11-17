(* FB_PulseMeter — a pulse flow meter or a hardware pulse counter.

Pins: bPulse (each rising edge is one pulse: at most one pulse per two scans), nCount (a hardware counter,
e.g. node-uio PULSE_COUNT: each count is one pulse; a wrap past 2^32 or set.nRolloverAt is counted, a drop of
more than half the range is a counter restart), bInGood (the input can be trusted), refData.
set.eSource picks the input; each pulse adds set.fPerPulse to the total. Nothing is counted while the input is
bad (a counter catches up when it is good again); bad past its delay is a warning and bIsGood FALSE.
Units: set.eInUnit (the unit of fPerPulse) and set.eOutUnit (the unit of the total and the rate), E_Unit volume units
(litre, m3, megalitre, gallon): both set convert each addition; both None = no conversion. One set, or a unit
that is not a volume, is a bad setting (put back).
Batch: tot.fBatch counts like tot.fTotal until bResetBatch (rising edge) / bCmdResetBatch; bBatchDone is TRUE once
it has reached set.fBatchTarget (0 = off), until the batch is reset.
Offers I_Meter (an I_Measurement too: its rate): the total and the rate (per hour, over set.tRateWindow). The total and the batch are kept hourly,
when bRunning falls (the pump stops; optional) and on a reset. *)

FUNCTION_BLOCK FB_PulseMeter EXTENDS FB_Object IMPLEMENTS I_Meter
  VAR_INPUT
    bPulse : BOOL;
    nCount : UDINT;
    bInGood : BOOL := TRUE;
    bRunning : BOOL := FALSE; (* optional: the pump runs; its fall keeps the totals *)
    bResetBatch : BOOL R_EDGE; (* the batch back to 0 *)
    refData : REFERENCE TO ST_PulseMeterData;
  END_VAR
  VAR_OUTPUT
    bBatchDone : BOOL; (* the batch has reached set.fBatchTarget *)
  END_VAR
  VAR RETAIN
    stKept : ST_PulseMeterSet;
    nKeptLayout : UINT;
    stKeptTot : ST_PulseMeterTot;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 2;
  END_VAR
  VAR
    stWInputBad : ST_ProtectionWork;
    bPulsePrev : BOOL;
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


METHOD PRIVATE UnitsOk : BOOL
  VAR
    bU : BOOL;
    fU : LREAL;
  END_VAR
  fU := F_UnitFactor(eFromUnit := refData.set.eInUnit, eToUnit := refData.set.eOutUnit, bOk => bU);
  UnitsOk := bU;
END_METHOD

PROPERTY PUBLIC fActTotal : LREAL
  GET
    IF __ISVALIDREF(refData) THEN fActTotal := refData.tot.fTotal; ELSE fActTotal := 0.0; END_IF;
  END_GET
END_PROPERTY
PROPERTY PUBLIC fActRate : REAL
  GET
    IF __ISVALIDREF(refData) THEN fActRate := refData.sts.fRate; ELSE fActRate := 0.0; END_IF;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsGood : BOOL
  GET
    IF __ISVALIDREF(refData) THEN bIsGood := refData.sts.bGood; ELSE bIsGood := FALSE; END_IF;
  END_GET
END_PROPERTY
(* I_Measurement: the rate (per hour), in set.eOutUnit per hour, no bands *)
PROPERTY PUBLIC fActValue : REAL
  GET
    IF __ISVALIDREF(refData) THEN fActValue := refData.sts.fRate; ELSE fActValue := 0.0; END_IF;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bHasValue : BOOL
  GET
    bHasValue := TRUE;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsFitted : BOOL
  GET
    bIsFitted := TRUE;
  END_GET
END_PROPERTY
PROPERTY PUBLIC eUnit : E_Unit
  GET
    eUnit := E_Unit.None;
    IF __ISVALIDREF(refData) THEN eUnit := F_UnitPerHour(eUnit := refData.set.eOutUnit); END_IF;
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
ELSIF refData.set.fPerPulse >= 0.0 AND refData.set.tRateWindow > T#0s AND UnitsOk() AND refData.set.fBatchTarget >= 0.0
      AND refData.set.fBatchTarget <= 1.0E15
      AND refData.set.stInputBad.tDelay >= T#0s AND refData.set.stInputBad.tRecover >= T#0s THEN
  stKept := refData.set;
ELSE
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
END_IF;

(* count *)
fMult := F_UnitFactor(eFromUnit := refData.set.eInUnit, eToUnit := refData.set.eOutUnit, bOk => bUnitOk);
fBefore := refData.tot.fTotal;
IF bInGood THEN
  IF refData.set.eSource = E_PulseSource.Count THEN
    IF NOT bCountValid THEN
      nPrev := nCount;
      bCountValid := TRUE;
    ELSIF nCount <> nPrev THEN
      IF nCount > nPrev THEN
        nD := nCount - nPrev;
      ELSIF refData.set.nRolloverAt >= 2 AND nPrev < refData.set.nRolloverAt
            AND nCount + (refData.set.nRolloverAt - nPrev) < refData.set.nRolloverAt / 2 THEN
        nD := nCount + (refData.set.nRolloverAt - nPrev);
      ELSIF refData.set.nRolloverAt = 0 THEN
        nD := nCount - nPrev;     // modulo 2^32
        IF nD >= 16#80000000 THEN nD := nCount; END_IF;   // it restarted from 0
      ELSE
        nD := nCount;             // a counter restart
      END_IF;
      nPrev := nCount;
      refData.tot.fTotal := refData.tot.fTotal + UDINT_TO_LREAL(nD) * REAL_TO_LREAL(refData.set.fPerPulse) * fMult;
    END_IF;
  ELSIF bPulse AND NOT bPulsePrev THEN
    refData.tot.fTotal := refData.tot.fTotal + REAL_TO_LREAL(refData.set.fPerPulse) * fMult;
  END_IF;
END_IF;
bPulsePrev := bPulse;
refData.tot.fBatch := refData.tot.fBatch + (refData.tot.fTotal - fBefore);

(* the input bad *)
bTrip := F_Protect(tNow := tNow, bCause := NOT bInGood, bResetReq := SystemReset(), tRetryWindow := T#1h,
                   stSet := refData.set.stInputBad, stSts := refData.sts.stInputBad, stWork := stWInputBad);
refData.sts.bGood := NOT stWInputBad.bActive;

(* rate over the window *)
tWin := tNow - tWindowAt;
IF tWin >= refData.set.tRateWindow THEN
  refData.sts.fRate := LREAL_TO_REAL((refData.tot.fTotal - fWindowTotal) * 3600000.0 / TIME_TO_LREAL(tWin));
  fWindowTotal := refData.tot.fTotal;
  tWindowAt := tNow;
END_IF;

(* reset, keep *)
IF refData.bCmdResetTotal THEN
  refData.tot.fTotal := 0.0;
  fWindowTotal := 0.0;
  stKeptTot := refData.tot;
  refData.bCmdResetTotal := FALSE;
END_IF;
IF bResetBatch OR refData.bCmdResetBatch THEN
  refData.bCmdResetBatch := FALSE;
  refData.tot.fBatch := 0.0;
  stKeptTot := refData.tot;
END_IF;
bBatchDone := refData.set.fBatchTarget > 0.0 AND refData.tot.fBatch >= refData.set.fBatchTarget;
IF (bRunningWas AND NOT bRunning) OR tNow - tKeptAt >= T#1h THEN
  stKeptTot := refData.tot;
  tKeptAt := tNow;
END_IF;
bRunningWas := bRunning;

bError := stWInputBad.bTrip;
bWarning := stWInputBad.bWarn OR refData.sts.bRefused;
IF stWInputBad.bTrip OR stWInputBad.bWarn THEN
  eErrorId := E_UtError.SensorBad;
ELSIF refData.sts.bRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF refData.sts.bGood THEN eState := E_State.Running; ELSE eState := E_State.Fault; END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK