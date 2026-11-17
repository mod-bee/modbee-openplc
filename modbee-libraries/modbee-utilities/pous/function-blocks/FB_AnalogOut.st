(* FB_AnalogOut — an engineering demand to an analog output card.
Pins: fIn (the demand, Auto), bInterlock (FALSE: set.fFailValue at once, or hold with set.bHoldOnInterlock),
bManual (held: Manual while TRUE, a panel switch, not kept) -> fOut (the engineering value output), nOutRaw (for
%QW), bLimited (clamped or ramping), plus FB_Object's bError / bWarning / eErrorId / eState. refData: its record.
stConfig: the raw span of the card, set once at the declaration.

Auto: fOut follows fIn. Manual (the bManual pin held, or the kept choice set.bManual from bCmdManual /
bCmdAuto): fOut is set.fManualValue; at the change to Manual, fManualValue takes the present fOut (bumpless). The
demand is clamped to fOutMin..fOutMax and ramped by fRampUp / fRampDown (engineering units per eRateUnit; 0 = no
ramp; FB_Ramp, exact at any rate). bInterlock FALSE gives fFailValue at once (or holds), in Manual too; when it
returns the output ramps back from there. A NaN demand holds the output (warning ValueBad). nOutRaw =
fRawMin..fRawMax over fEngMin..fEngMax, clamped to 0..65535. A span that is not usable: bError BadSetting, fOut
at fEngMin. Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put
back. *)

FUNCTION_BLOCK FB_AnalogOut EXTENDS FB_Object
  VAR_INPUT
    fIn : REAL; (* engineering demand (Auto) *)
    bInterlock : BOOL := TRUE; (* FALSE: fFailValue at once (or hold) *)
    bManual : BOOL; (* held: Manual while TRUE (a panel switch; not kept) *)
    refData : REFERENCE TO ST_AnalogOutData;
    stConfig : ST_AnalogOutConfig; (* the card's raw span (set at the declaration) *)
  END_VAR
  VAR_OUTPUT
    fOut : REAL; (* engineering value actually output *)
    nOutRaw : UINT; (* for %QW *)
    bLimited : BOOL; (* clamped or ramping *)
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
METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_AnalogOutSet;
  END_VAR
  SetOk := ABS(stS.fEngMax - stS.fEngMin) > 0.0 AND ABS(stS.fEngMax - stS.fEngMin) <= REAL#3.4E38
           AND ABS(stS.fOutMin) <= REAL#3.4E38 AND ABS(stS.fOutMax) <= REAL#3.4E38
           AND stS.fRampUp >= 0.0 AND stS.fRampUp <= REAL#3.4E38
           AND stS.fRampDown >= 0.0 AND stS.fRampDown <= REAL#3.4E38
           AND (stS.eRateUnit = E_RateUnit.PerSec OR stS.eRateUnit = E_RateUnit.PerMin
                OR stS.eRateUnit = E_RateUnit.PerHour OR stS.eRateUnit = E_RateUnit.PerDay)
           AND ABS(stS.fFailValue) <= REAL#3.4E38 AND ABS(stS.fManualValue) <= REAL#3.4E38;
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
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
  bOkSet := TRUE;
END_IF;
IF refData.bCmdReset OR SystemReset() THEN
  refData.bCmdReset := FALSE;
  refData.sts.bRefused := FALSE;
END_IF;
bCfgBad := NOT (ABS(refData.set.fEngMax - refData.set.fEngMin) > 0.0
                AND ABS(refData.set.fEngMax - refData.set.fEngMin) <= REAL#3.4E38)
           OR NOT (ABS(stConfig.fRawMin) <= REAL#3.4E38 AND ABS(stConfig.fRawMax) <= REAL#3.4E38);

(* Manual / Auto: the HMI once, the pin while held *)
IF refData.bCmdManual THEN refData.set.bManual := TRUE; refData.bCmdManual := FALSE; END_IF;
IF refData.bCmdAuto THEN refData.set.bManual := FALSE; refData.bCmdAuto := FALSE; END_IF;
bManualNow := bManual OR refData.set.bManual;
IF bManualNow AND NOT bManualPrev AND NOT bFirstScan THEN
  refData.set.fManualValue := fOut;   (* bumpless into Manual *)
END_IF;
bManualPrev := bManualNow;
IF bManualNow THEN
  fDemand := refData.set.fManualValue;
ELSE
  fDemand := fIn;
END_IF;
bBadIn := NOT (ABS(fDemand) <= REAL#3.4E38);
IF refData.set.fOutMin <= refData.set.fOutMax THEN
  fLo := refData.set.fOutMin;
  fHi := refData.set.fOutMax;
ELSE
  fLo := refData.set.fOutMax;
  fHi := refData.set.fOutMin;
END_IF;
bClamped := FALSE;
IF bCfgBad THEN
  fbRamp(fIn := refData.set.fEngMin, bTrack := TRUE);
ELSIF NOT bInterlock THEN
  IF refData.set.bHoldOnInterlock THEN
    fbRamp(fIn := fOut, bTrack := TRUE);
  ELSE
    fbRamp(fIn := refData.set.fFailValue, bTrack := TRUE);   (* at once, no ramp *)
  END_IF;
ELSIF bBadIn THEN
  fbRamp(fIn := fOut, bTrack := TRUE);                       (* hold *)
ELSE
  fTarget := fDemand;
  IF fTarget > fHi THEN
    fTarget := fHi;
    bClamped := TRUE;
  ELSIF fTarget < fLo THEN
    fTarget := fLo;
    bClamped := TRUE;
  END_IF;
  fbRamp(fIn := fTarget, fRateUp := refData.set.fRampUp, fRateDown := refData.set.fRampDown,
         eRateUnit := refData.set.eRateUnit, bTrack := FALSE);
END_IF;
fOut := fbRamp.fOut;

(* the raw value for the card *)
fRaw := F_Scale(fIn := fOut, fInMin := refData.set.fEngMin, fInMax := refData.set.fEngMax,
                fOutMin := stConfig.fRawMin, fOutMax := stConfig.fRawMax, bClamp := FALSE, bSpanBad => bSpanBad);
IF NOT (fRaw >= 0.0) THEN
  bClamped := TRUE;
  fRaw := 0.0;
ELSIF fRaw > 65535.0 THEN
  bClamped := TRUE;
  fRaw := 65535.0;
END_IF;
nOutRaw := REAL_TO_UINT(fRaw);
bLimited := bClamped OR fbRamp.bRamping;

(* errors *)
bError := bCfgBad;
bWarning := NOT bError AND (bBadIn OR NOT bOkSet OR refData.sts.bRefused);
IF bCfgBad THEN
  eErrorId := E_UtError.BadSetting;
ELSIF bBadIn THEN
  eErrorId := E_UtError.ValueBad;
ELSIF NOT bOkSet THEN
  eErrorId := E_UtError.BadSetting;
ELSIF refData.sts.bRefused THEN
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
refData.sts.fOut := fOut;
refData.sts.bManual := bManualNow;
refData.sts.bBadInput := bBadIn;
refData.nRaw := nOutRaw;
bFirstScan := FALSE;

END_FUNCTION_BLOCK