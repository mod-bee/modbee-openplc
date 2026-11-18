(* FB_ValveMod EXTENDS FB_ValvePos — a modulating valve or damper with a positioner (4-20 mA / 0-10 V). Everything of
FB_ValvePos (where it goes, the feedback, the protections, Hand) plus the signal.
Pins added: refMod (its record), stConfig (the signal's raw span) -> fOut (the demand %, 100 - demand when
set.bReverseActing), nOutRaw (fOut scaled to fRawMin..fRawMax).
The aim is shaped: set.fTightShutoff (below it: 0 %) and fFullOpenAbove (above it: 100 %) win over the clamp
fOutMin..fOutMax; a safe position is not shaped. set.fRampRate limits the demand (per eRateUnit; 0 = off; a safe
position or a hold jumps). Without feedback the position is a travel estimate: the demand followed at a full
stroke per set.tStroke (0 = at once). Its settings are kept by the block (a retained last-good copy): restored
at power-up, a bad write put back. *)

FUNCTION_BLOCK FB_ValveMod EXTENDS FB_ValvePos
  VAR_INPUT
    refMod : REFERENCE TO ST_ValveModData;
    stConfig : ST_ValveModConfig; (* the signal's raw span (set at the declaration) *)
  END_VAR
  VAR_OUTPUT
    fOut : REAL; (* demand % (reverse acting: 100 - demand) *)
    nOutRaw : UINT; (* for %QW *)
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
  IF NOT (stS.fOutMin >= 0.0) THEN
    ModWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fOutMax <= 100.0) THEN
    ModWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.fOutMin <= stS.fOutMax) THEN
    ModWhy := E_UtError.LimitsBad;
  ELSIF NOT (stS.fRampRate >= 0.0) THEN
    ModWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fRampRate <= REAL#3.4E38) THEN
    ModWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.eRateUnit = E_RateUnit.PerSec OR stS.eRateUnit = E_RateUnit.PerMin
             OR stS.eRateUnit = E_RateUnit.PerHour OR stS.eRateUnit = E_RateUnit.PerDay) THEN
    ModWhy := E_UtError.ChoiceBad;
  ELSIF NOT (stS.fTightShutoff >= 0.0) THEN
    ModWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fTightShutoff <= 100.0) THEN
    ModWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.fFullOpenAbove >= 0.0) THEN
    ModWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fFullOpenAbove <= 100.0) THEN
    ModWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.tStroke >= T#0s) THEN
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

IF NOT __ISVALIDREF(refMod) OR NOT __ISVALIDREF(refData) THEN
  fOut := 0.0;
  nOutRaw := 0;
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  RETURN;
END_IF;
IF bModFirst THEN
  IF nKeptModLayout = cLayout THEN
    refMod.set := stKeptMod;
  ELSE
    stKeptMod := refMod.set;
    nKeptModLayout := cLayout;
  END_IF;
  bModFirst := FALSE;
ELSIF ModOk(stS := refMod.set) THEN
  stKeptMod := refMod.set;
ELSIF ModOk(stS := stKeptMod) THEN
  refMod.sts.eRefusedWhy := ModWhy(stS := refMod.set);
  refMod.set := stKeptMod;
  refMod.sts.bRefused := TRUE;
END_IF;
IF bResetThisScan THEN                  // the equipment's reset clears a refused write
  refMod.sts.bRefused := FALSE;
  refMod.sts.eRefusedWhy := E_UtError.None;
END_IF;

(* the demand: the aim shaped (tight shut-off and full open win over the clamp), then ramped *)
fReq := fAim;
IF bAimHold THEN
  fReq := fDemand;
ELSIF bAimShaped THEN
  IF refMod.set.fTightShutoff > 0.0 AND fReq < refMod.set.fTightShutoff THEN
    fReq := 0.0;
  ELSIF refMod.set.fFullOpenAbove < 100.0 AND fReq > refMod.set.fFullOpenAbove THEN
    fReq := 100.0;
  ELSE
    fReq := LIMIT(refMod.set.fOutMin, fReq, refMod.set.fOutMax);
  END_IF;
END_IF;
fReq := LIMIT(0.0, fReq, 100.0);
fbDemand(fIn := fReq, fRateUp := refMod.set.fRampRate, fRateDown := refMod.set.fRampRate,
         eRateUnit := refMod.set.eRateUnit, bTrack := NOT bAimShaped OR refMod.set.fRampRate <= 0.0);
fDemand := fbDemand.fOut;

(* the signal *)
IF refMod.set.bReverseActing THEN
  fOut := 100.0 - fDemand;
ELSE
  fOut := fDemand;
END_IF;
fRaw := F_Scale(fIn := fOut, fInMin := 0.0, fInMax := 100.0, fOutMin := stConfig.fRawMin,
                fOutMax := stConfig.fRawMax, bClamp := FALSE, bSpanBad => bSpanBad);
IF NOT (fRaw >= 0.0) OR bSpanBad THEN
  fRaw := 0.0;
ELSIF fRaw > 65535.0 THEN
  fRaw := 65535.0;
END_IF;
nOutRaw := REAL_TO_UINT(fRaw);

(* the travel estimate: the demand at a full stroke per tStroke *)
fRate := 0.0;
IF refMod.set.tStroke > T#0s THEN
  fRate := 100000.0 / LINT_TO_REAL(TIME_TO_LINT(refMod.set.tStroke));
END_IF;
fbEst(fIn := fDemand, fRateUp := fRate, fRateDown := fRate, eRateUnit := E_RateUnit.PerSec, bTrack := fRate <= 0.0);
fEstimate := fbEst.fOut;
IF bFbOk THEN
  bMoving := fbDemand.bRamping OR ABS(fDemand - fPosition) > refData.set.fDeadband;
ELSE
  bMoving := fbDemand.bRamping OR fbEst.bRamping;
END_IF;
bSettled := NOT fbDemand.bRamping AND NOT fbEst.bRamping;   (* the deviation is judged once the travel is done *)
refData.sts.fDemand := fDemand;
refData.sts.fEstimate := fEstimate;
refData.sts.bMoving := bMoving;
refMod.sts.fOut := fOut;

END_FUNCTION_BLOCK