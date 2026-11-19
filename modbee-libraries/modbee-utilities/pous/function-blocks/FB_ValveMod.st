(* FB_ValveMod EXTENDS FB_ValvePos — a modulating valve or damper with a positioner (4-20 mA / 0-10 V). Everything of
FB_ValvePos (where it goes, the feedback, the protections, Hand) plus the signal.
Pins added: refModulatingData (its record), stConfig (the signal's raw span) -> fOutputPct (the demand %, 100 - demand when
set.bReverseActing), nRawOutput (fOutputPct scaled to fRawAtZeroPct..fRawAtFullPct).
The aim is shaped: set.fTightShutoffBelowPct (below it: 0 %) and fFullOpenAbovePct (above it: 100 %) win over the clamp
fMinDemandPct..fMaxDemandPct; a safe position is not shaped. set.fRampRate limits the demand (per eRateUnit; 0 = off; a safe
position or a hold jumps). Without feedback the position is a travel estimate: the demand followed at a full
stroke per set.tFullStrokeTime (0 = at once). Its settings are kept by the block (a retained last-good copy): restored
at power-up, a bad write put back. *)

FUNCTION_BLOCK FB_ValveMod EXTENDS FB_ValvePos
  VAR_INPUT
    refModulatingData : REFERENCE TO ST_ValveModData; (* the modulating valve record *)
    stConfig : ST_ValveModConfig; (* the signal's raw span (set at the declaration) *)
  END_VAR
  VAR_OUTPUT
    fOutputPct : REAL; (* demand % (reverse acting: 100 - demand) *)
    nRawOutput : UINT; (* for %QW *)
  END_VAR
  VAR RETAIN
    stKeptMod : ST_ValveModSet;
    nKeptModLayout : UINT;
  END_VAR
  VAR
    fbDemand : FB_Ramp;
    fbEst : FB_Ramp;
    bModFirst : BOOL := TRUE;
  END_VAR
  VAR_TEMP
    fReq : REAL;
    fRate : REAL;
    fRaw : REAL;
    bMoving : BOOL;
    bSpanBad : BOOL;
  END_VAR


METHOD PRIVATE ModWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_ValveModSet;
  END_VAR
  ModWhy := E_UtError.None;
  IF NOT (stS.fMinDemandPct >= 0.0) THEN
    ModWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fMaxDemandPct <= 100.0) THEN
    ModWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.fMinDemandPct <= stS.fMaxDemandPct) THEN
    ModWhy := E_UtError.LimitsBad;
  ELSIF NOT (stS.fRampRate >= 0.0) THEN
    ModWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fRampRate <= REAL#3.4E38) THEN
    ModWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.eRateUnit = E_RateUnit.PerSec OR stS.eRateUnit = E_RateUnit.PerMin
             OR stS.eRateUnit = E_RateUnit.PerHour OR stS.eRateUnit = E_RateUnit.PerDay) THEN
    ModWhy := E_UtError.ChoiceBad;
  ELSIF NOT (stS.fTightShutoffBelowPct >= 0.0) THEN
    ModWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fTightShutoffBelowPct <= 100.0) THEN
    ModWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.fFullOpenAbovePct >= 0.0) THEN
    ModWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fFullOpenAbovePct <= 100.0) THEN
    ModWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.tFullStrokeTime >= T#0s) THEN
    ModWhy := E_UtError.TimeBad;
  END_IF;
END_METHOD

METHOD PRIVATE ModOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_ValveModSet;
  END_VAR
  ModOk := ModWhy(stS := stS) = E_UtError.None;
END_METHOD

SUPER^();                         // the valve: modes, the aim, the feedback, protections

IF NOT __ISVALIDREF(refModulatingData) OR NOT __ISVALIDREF(refData) THEN
  fOutputPct := 0.0;
  nRawOutput := 0;
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  RETURN;
END_IF;
IF bModFirst THEN
  IF nKeptModLayout = cLayout THEN
    refModulatingData.set := stKeptMod;
  ELSE
    stKeptMod := refModulatingData.set;
    nKeptModLayout := cLayout;
  END_IF;
  bModFirst := FALSE;
ELSIF ModOk(stS := refModulatingData.set) THEN
  stKeptMod := refModulatingData.set;
ELSIF ModOk(stS := stKeptMod) THEN
  refModulatingData.sts.eSettingRefusedErrorId := ModWhy(stS := refModulatingData.set);
  refModulatingData.set := stKeptMod;
  refModulatingData.sts.bSettingRefused := TRUE;
END_IF;
IF bResetThisScan THEN                  // the equipment's reset clears a refused write
  refModulatingData.sts.bSettingRefused := FALSE;
  refModulatingData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;

(* the demand: the aim shaped (tight shut-off and full open win over the clamp), then ramped *)
fReq := fAim;
IF bAimHold THEN
  fReq := fDemand;
ELSIF bAimShaped THEN
  IF refModulatingData.set.fTightShutoffBelowPct > 0.0 AND fReq < refModulatingData.set.fTightShutoffBelowPct THEN
    fReq := 0.0;
  ELSIF refModulatingData.set.fFullOpenAbovePct < 100.0 AND fReq > refModulatingData.set.fFullOpenAbovePct THEN
    fReq := 100.0;
  ELSE
    fReq := LIMIT(refModulatingData.set.fMinDemandPct, fReq, refModulatingData.set.fMaxDemandPct);
  END_IF;
END_IF;
fReq := LIMIT(0.0, fReq, 100.0);
fbDemand(fSetpoint := fReq, fRampUpRate := refModulatingData.set.fRampRate, fRampDownRate := refModulatingData.set.fRampRate,
         eRateUnit := refModulatingData.set.eRateUnit, bFollowAtOnce := NOT bAimShaped OR refModulatingData.set.fRampRate <= 0.0);
fDemand := fbDemand.fOut;

(* the signal *)
IF refModulatingData.set.bReverseActing THEN
  fOutputPct := 100.0 - fDemand;
ELSE
  fOutputPct := fDemand;
END_IF;
fRaw := F_Scale(fIn := fOutputPct, fInputLow := 0.0, fInputHigh := 100.0, fOutputLow := stConfig.fRawAtZeroPct,
                fOutputHigh := stConfig.fRawAtFullPct, bClampToOutput := FALSE, bInputSpanBad => bSpanBad);
IF NOT (fRaw >= 0.0) OR bSpanBad THEN
  fRaw := 0.0;
ELSIF fRaw > 65535.0 THEN
  fRaw := 65535.0;
END_IF;
nRawOutput := REAL_TO_UINT(fRaw);

(* the travel estimate: the demand at a full stroke per tFullStrokeTime *)
fRate := 0.0;
IF refModulatingData.set.tFullStrokeTime > T#0s THEN
  fRate := 100000.0 / LINT_TO_REAL(TIME_TO_LINT(refModulatingData.set.tFullStrokeTime));
END_IF;
fbEst(fSetpoint := fDemand, fRampUpRate := fRate, fRampDownRate := fRate, eRateUnit := E_RateUnit.PerSec, bFollowAtOnce := fRate <= 0.0);
fEstimate := fbEst.fOut;
IF bFbOk THEN
  bMoving := fbDemand.bRamping OR ABS(fDemand - fPositionPct) > refData.set.fPositionDeadbandPct;
ELSE
  bMoving := fbDemand.bRamping OR fbEst.bRamping;
END_IF;
bSettled := NOT fbDemand.bRamping AND NOT fbEst.bRamping;   (* the deviation is judged once the travel is done *)
refData.sts.fDemandPct := fDemand;
refData.sts.fEstimatedPct := fEstimate;
refData.sts.bTravelling := bMoving;
refModulatingData.sts.fOutputPct := fOutputPct;

END_FUNCTION_BLOCK