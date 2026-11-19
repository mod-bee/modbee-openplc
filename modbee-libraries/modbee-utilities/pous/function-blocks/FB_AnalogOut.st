(* FB_AnalogOut — an engineering demand to an analog output card.
Pins: fAutoDemand (the demand, Auto), bInterlock (FALSE: set.fValueWhenInterlocked at once, or hold with set.bHoldWhenInterlocked),
bSelectorManual (held: Manual while TRUE, a panel switch, not kept) -> fOutput (the engineering value output), nRawOutput (for
%QW), bClampedOrRamping (clamped or ramping), plus FB_Object's bError / bWarning / eErrorId / eState. refData: its record.
stConfig: the raw span of the card, set once at the declaration.

Auto: fOutput follows fAutoDemand. Manual (the bSelectorManual pin held, or the kept choice set.bManualSelected from bCmdSelectManual /
bCmdSelectAuto): fOutput is set.fManualOutput; at the change to Manual, fManualOutput takes the present fOutput (bumpless). The
demand is clamped to fMinOutput..fMaxOutput and ramped by fRampUpRate / fRampDownRate (engineering units per eRateUnit; 0 = no
ramp; FB_Ramp, exact at any rate). bInterlock FALSE gives fValueWhenInterlocked at once (or holds), in Manual too; when it
returns the output ramps back from there. A NaN demand holds the output (warning ValueBad). nRawOutput =
fRawAtSignalLow..fRawAtSignalHigh over fValueAtSignalLow..fValueAtSignalHigh, clamped to 0..65535. A span that is not usable: bError BadSetting, fOutput
at fValueAtSignalLow. Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put
back. *)

FUNCTION_BLOCK FB_AnalogOut EXTENDS FB_Object
  VAR_INPUT
    fAutoDemand : REAL; (* engineering demand (Auto) *)
    bInterlock : BOOL := TRUE; (* FALSE: fValueWhenInterlocked at once (or hold) *)
    bSelectorManual : BOOL; (* held: Manual while TRUE (a panel switch; not kept) *)
    refData : REFERENCE TO ST_AnalogOutData; (* the block's record *)
    stConfig : ST_AnalogOutConfig; (* the card's raw span (set at the declaration) *)
  END_VAR
  VAR_OUTPUT
    fOutput : REAL; (* engineering value actually output *)
    nRawOutput : UINT; (* for %QW *)
    bClampedOrRamping : BOOL; (* clamped or ramping *)
  END_VAR
  VAR RETAIN
    stKept : ST_AnalogOutSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    fbRamp : FB_Ramp;
    bManualPrev : BOOL;
  END_VAR
  VAR_TEMP
    bOkSet : BOOL;
    bCfgBad : BOOL;
    bBadIn : BOOL;
    bClamped : BOOL;
    bManualNow : BOOL;
    bSpanBad : BOOL;
    fDemand : REAL;
    fTarget : REAL;
    fLo : REAL;
    fHi : REAL;
    fRaw : REAL;
  END_VAR


(* the settings are usable: the span, and every limit and ramp a number *)
METHOD PRIVATE SetWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_AnalogOutSet;
  END_VAR
  SetWhy := E_UtError.None;
  IF NOT (ABS(stS.fValueAtSignalHigh - stS.fValueAtSignalLow) > 0.0) THEN   // no span
    SetWhy := E_UtError.LimitsBad;
  ELSIF NOT (ABS(stS.fValueAtSignalHigh - stS.fValueAtSignalLow) <= REAL#3.4E38) THEN
    SetWhy := E_UtError.ValueBad;
  ELSIF NOT (ABS(stS.fMinOutput) <= REAL#3.4E38) THEN
    SetWhy := E_UtError.ValueBad;
  ELSIF NOT (ABS(stS.fMaxOutput) <= REAL#3.4E38) THEN
    SetWhy := E_UtError.ValueBad;
  ELSIF NOT (stS.fRampUpRate >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fRampUpRate <= REAL#3.4E38) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.fRampDownRate >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fRampDownRate <= REAL#3.4E38) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.eRateUnit = E_RateUnit.PerSec OR stS.eRateUnit = E_RateUnit.PerMin
             OR stS.eRateUnit = E_RateUnit.PerHour OR stS.eRateUnit = E_RateUnit.PerDay) THEN
    SetWhy := E_UtError.ChoiceBad;
  ELSIF NOT (ABS(stS.fValueWhenInterlocked) <= REAL#3.4E38) THEN
    SetWhy := E_UtError.ValueBad;
  ELSIF NOT (ABS(stS.fManualOutput) <= REAL#3.4E38) THEN
    SetWhy := E_UtError.ValueBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_AnalogOutSet;
  END_VAR
  SetOk := SetWhy(stS := stS) = E_UtError.None;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
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
IF refData.bCmdClearRefused OR SystemReset() THEN
  refData.bCmdClearRefused := FALSE;
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;
bCfgBad := NOT (ABS(refData.set.fValueAtSignalHigh - refData.set.fValueAtSignalLow) > 0.0
                AND ABS(refData.set.fValueAtSignalHigh - refData.set.fValueAtSignalLow) <= REAL#3.4E38)
           OR NOT (ABS(stConfig.fRawAtSignalLow) <= REAL#3.4E38 AND ABS(stConfig.fRawAtSignalHigh) <= REAL#3.4E38);

(* Manual / Auto: the HMI once, the pin while held *)
IF refData.bCmdSelectManual THEN refData.set.bManualSelected := TRUE; refData.bCmdSelectManual := FALSE; END_IF;
IF refData.bCmdSelectAuto THEN refData.set.bManualSelected := FALSE; refData.bCmdSelectAuto := FALSE; END_IF;
bManualNow := bSelectorManual OR refData.set.bManualSelected;
IF bManualNow AND NOT bManualPrev AND NOT bFirstScan THEN
  refData.set.fManualOutput := fOutput;   (* bumpless into Manual *)
END_IF;
bManualPrev := bManualNow;
IF bManualNow THEN
  fDemand := refData.set.fManualOutput;
ELSE
  fDemand := fAutoDemand;
END_IF;
bBadIn := NOT (ABS(fDemand) <= REAL#3.4E38);
IF refData.set.fMinOutput <= refData.set.fMaxOutput THEN
  fLo := refData.set.fMinOutput;
  fHi := refData.set.fMaxOutput;
ELSE
  fLo := refData.set.fMaxOutput;
  fHi := refData.set.fMinOutput;
END_IF;
bClamped := FALSE;
IF bCfgBad THEN
  fbRamp(fSetpoint := refData.set.fValueAtSignalLow, bFollowAtOnce := TRUE);
ELSIF NOT bInterlock THEN
  IF refData.set.bHoldWhenInterlocked THEN
    fbRamp(fSetpoint := fOutput, bFollowAtOnce := TRUE);
  ELSE
    fbRamp(fSetpoint := refData.set.fValueWhenInterlocked, bFollowAtOnce := TRUE);   (* at once, no ramp *)
  END_IF;
ELSIF bBadIn THEN
  fbRamp(fSetpoint := fOutput, bFollowAtOnce := TRUE);                       (* hold *)
ELSE
  fTarget := fDemand;
  IF fTarget > fHi THEN
    fTarget := fHi;
    bClamped := TRUE;
  ELSIF fTarget < fLo THEN
    fTarget := fLo;
    bClamped := TRUE;
  END_IF;
  fbRamp(fSetpoint := fTarget, fRampUpRate := refData.set.fRampUpRate, fRampDownRate := refData.set.fRampDownRate,
         eRateUnit := refData.set.eRateUnit, bFollowAtOnce := FALSE);
END_IF;
fOutput := fbRamp.fOut;

(* the raw value for the card *)
fRaw := F_Scale(fIn := fOutput, fInputLow := refData.set.fValueAtSignalLow, fInputHigh := refData.set.fValueAtSignalHigh,
                fOutputLow := stConfig.fRawAtSignalLow, fOutputHigh := stConfig.fRawAtSignalHigh, bClampToOutput := FALSE, bInputSpanBad => bSpanBad);
IF NOT (fRaw >= 0.0) THEN
  bClamped := TRUE;
  fRaw := 0.0;
ELSIF fRaw > 65535.0 THEN
  bClamped := TRUE;
  fRaw := 65535.0;
END_IF;
nRawOutput := REAL_TO_UINT(fRaw);
bClampedOrRamping := bClamped OR fbRamp.bRamping;

(* errors *)
bError := bCfgBad;
bWarning := NOT bError AND (bBadIn OR NOT bOkSet OR refData.sts.bSettingRefused);
IF bCfgBad THEN
  eErrorId := E_UtError.BadSetting;
ELSIF bBadIn THEN
  eErrorId := E_UtError.ValueBad;
ELSIF NOT bOkSet THEN
  eErrorId := E_UtError.BadSetting;
ELSIF refData.sts.bSettingRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN
  eState := E_State.Fault;
ELSIF NOT bInterlock OR bBadIn THEN
  eState := E_State.Held;
ELSE
  eState := E_State.Running;
END_IF;
refData.sts.fOutput := fOutput;
refData.sts.bInManual := bManualNow;
refData.sts.bDemandNotANumber := bBadIn;
refData.nRawOutput := nRawOutput;
bFirstScan := FALSE;

END_FUNCTION_BLOCK