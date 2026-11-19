(* FB_MotorVsd EXTENDS FB_Motor — a variable speed drive over hard-wired IO.
Everything of FB_Motor (modes, protections, the plug, totals, refData) plus the speed. bRunOutput = the drive's run
command; bRunFeedback = the drive's running relay.

Pins added: bDriveReady (the drive's ready relay: lost while running is a protection; not ready holds a new
start), fSpeedFeedbackPct (actual speed %, < 0 = not wired), refDriveData (its record) -> fSpeedReferencePct (% after clamp, skip band,
ramp), nSpeedReferenceRaw (scaled to set.fRawAtZeroPct..fRawAtFullPct, a Modbus register), bDriveResetPulse (a pulse on an operator
reset), bAtSpeed.
Speed asked for: Auto -> the owner's speed (Request fSpeed, < 0 = set.fAutoSpeedPct); Hand -> set.fHandSpeedPct.
Clamped to fMinSpeedPct..fMaxSpeedPct; a target inside the skip band holds at its near edge; ramped by fAccelPctPerSec /
fDecelPctPerSec (% per set.eRateUnit: second by default, minute, hour or day; 0 = the drive ramps); a start begins from
fMinSpeedPct. A jog (FB_MotorJog) runs at set.fJogSpeedPct (0 = fHandSpeedPct).
Drive protections: driveNotReady (the ready relay lost while running), speedDev (|reference - fSpeedFeedbackPct| past
set.fSpeedDeviationPct while running with the ramp done and set.tDriveOwnRampTime passed since the reference stopped changing,
fSpeedFeedbackPct wired).
bAtSpeed: the ramp done, and by fSpeedFeedbackPct within fSpeedDeviationPct, or without fSpeedFeedbackPct once set.tDriveOwnRampTime (the drive's own
0 -> 100 % ramp time, 0 = none) has passed since the reference stopped changing.
The speed in Hz and rpm (sts.fSpeedHz, sts.fSpeedRpm, for display): the feedback while running when wired, else
the reference, x set.fRatedFrequency / fRatedRpm at 100 % (0 = not shown).
Its settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back. *)

FUNCTION_BLOCK FB_MotorVsd EXTENDS FB_Motor
  VAR_INPUT
    bDriveReady : BOOL := TRUE; (* the drive's ready relay: lost while running is a fault; not ready holds a new start *)
    fSpeedFeedbackPct : REAL := -1.0; (* the actual speed %; below 0 = not wired *)
    refDriveData : REFERENCE TO ST_VsdData; (* the drive record *)
  END_VAR
  VAR_OUTPUT
    fSpeedReferencePct : REAL; (* the speed reference, % after clamp, skip band and ramp *)
    nSpeedReferenceRaw : UINT; (* the speed reference scaled to fRawAtZeroPct..fRawAtFullPct (a Modbus register, %QW) *)
    bDriveResetPulse : BOOL; (* a pulse to the drive's reset input on an operator reset *)
    bAtSpeed : BOOL; (* the speed reference has reached its target *)
  END_VAR
  VAR CONSTANT
    cVsdLayout : UINT := 2; (* the layout of its own kept settings *)
  END_VAR
  VAR RETAIN
    stKeptVsd : ST_VsdSet;
    nKeptVsdLayout : UINT;
  END_VAR
  VAR
    stWNotReady : ST_ProtectionWork;
    stWSpeedDev : ST_ProtectionWork;
    tLastRamp : TIME;
    tResetAt : TIME;
    bQWas : BOOL;
    bVsdFirst : BOOL := TRUE;
    bSettled : BOOL; (* the reference has reached its target and the drive's ramp time has passed *)
    fTargetWas : REAL;
    tTargetAt : TIME; (* when the reference last changed (the drive's ramp counts from here) *)
    bQWasRamp : BOOL;
  END_VAR
  VAR_TEMP
    fTarget : REAL;
    fStep : REAL;
    fDt : REAL;
    fSpan : REAL;
    bRampDone : BOOL;
    bDriveDone : BOOL;
    fShown : REAL;
  END_VAR


(* the first bad setting (None: all good) *)
METHOD PRIVATE VsdWhy : E_UtError
  VsdWhy := E_UtError.None;
  IF NOT (refDriveData.set.fMinSpeedPct >= 0.0) THEN
    VsdWhy := E_UtError.BelowMin;
  ELSIF NOT (refDriveData.set.fMaxSpeedPct <= 100.0) THEN
    VsdWhy := E_UtError.AboveMax;
  ELSIF NOT (refDriveData.set.fMinSpeedPct <= refDriveData.set.fMaxSpeedPct) THEN
    VsdWhy := E_UtError.LimitsBad;
  ELSIF NOT (refDriveData.set.fAccelPctPerSec >= 0.0) THEN
    VsdWhy := E_UtError.BelowMin;
  ELSIF NOT (refDriveData.set.fDecelPctPerSec >= 0.0) THEN
    VsdWhy := E_UtError.BelowMin;
  ELSIF NOT (refDriveData.set.fSkipBandLow <= refDriveData.set.fSkipBandHigh) THEN
    VsdWhy := E_UtError.LimitsBad;
  ELSIF NOT (refDriveData.set.tDriveResetPulse >= T#0s) THEN
    VsdWhy := E_UtError.TimeBad;
  ELSIF NOT (refDriveData.set.fSpeedDeviationPct >= 0.0) THEN
    VsdWhy := E_UtError.BelowMin;
  ELSIF NOT (refDriveData.set.tDriveOwnRampTime >= T#0s) THEN
    VsdWhy := E_UtError.TimeBad;
  ELSIF NOT (refDriveData.set.fRatedFrequency >= 0.0) THEN
    VsdWhy := E_UtError.BelowMin;
  ELSIF NOT (refDriveData.set.fRatedFrequency <= REAL#3.4E38) THEN
    VsdWhy := E_UtError.AboveMax;
  ELSIF NOT (refDriveData.set.fRatedRpm >= 0.0) THEN
    VsdWhy := E_UtError.BelowMin;
  ELSIF NOT (refDriveData.set.fRatedRpm <= REAL#3.4E38) THEN
    VsdWhy := E_UtError.AboveMax;
  ELSIF NOT (refDriveData.set.fJogSpeedPct >= 0.0) THEN
    VsdWhy := E_UtError.BelowMin;
  ELSIF NOT (refDriveData.set.fJogSpeedPct <= 100.0) THEN
    VsdWhy := E_UtError.AboveMax;
  END_IF;
END_METHOD

METHOD PROTECTED OVERRIDE DriveChecks
  VAR_INPUT
    bReset : BOOL;
  END_VAR
  VAR_OUTPUT
    bTrip : BOOL;
    bWarn : BOOL;
    bHold : BOOL;
    eError : E_UtError;
  END_VAR
  VAR
    bX : BOOL;
  END_VAR
  eError := E_UtError.None;
  IF NOT __ISVALIDREF(refDriveData) THEN
    bTrip := TRUE;
    eError := E_UtError.NoRecord;
    RETURN;
  END_IF;
  IF bReset THEN
    tResetAt := tNow;             // a reset pulse to the drive
    bDriveResetPulse := TRUE;
  END_IF;
  bX := F_Protect(tNow := tNow, bConditionPresent := bRunOutput AND NOT bDriveReady, bResetRequest := bReset,
                  tRetryCountWindow := refData.set.tRetryCountWindow, stSettings := refDriveData.set.stDriveNotReadyFault,
                  stStatus := refDriveData.sts.stDriveNotReadyFault, stWorking := stWNotReady);
  bX := F_Protect(tNow := tNow, bConditionPresent := bRunOutput AND fSpeedFeedbackPct >= 0.0 AND bSettled
                                          AND ABS(fSpeedReferencePct - fSpeedFeedbackPct) > refDriveData.set.fSpeedDeviationPct,
                  bResetRequest := bReset, tRetryCountWindow := refData.set.tRetryCountWindow, stSettings := refDriveData.set.stSpeedDeviationFault,
                  stStatus := refDriveData.sts.stSpeedDeviationFault, stWorking := stWSpeedDev);
  bTrip := stWNotReady.bTripping OR stWSpeedDev.bTripping;
  bWarn := stWNotReady.bWarning OR stWSpeedDev.bWarning;
  bHold := NOT bDriveReady;
  IF stWNotReady.bTripping OR stWNotReady.bWarning THEN
    eError := E_UtError.DriveFault;
  ELSIF stWSpeedDev.bTripping OR stWSpeedDev.bWarning THEN
    eError := E_UtError.SpeedDeviation;
  END_IF;
END_METHOD

SUPER^();                         // the motor: modes, protections (with DriveChecks), bRunOutput

IF NOT __ISVALIDREF(refDriveData) THEN
  fSpeedReferencePct := 0.0;
  nSpeedReferenceRaw := 0;
  RETURN;
END_IF;
IF bVsdFirst THEN
  IF nKeptVsdLayout = cVsdLayout THEN
    refDriveData.set := stKeptVsd;
  ELSE
    stKeptVsd := refDriveData.set;
    nKeptVsdLayout := cVsdLayout;
  END_IF;
  tLastRamp := tNow;
  bVsdFirst := FALSE;
ELSIF VsdWhy() = E_UtError.None THEN
  stKeptVsd := refDriveData.set;
ELSE
  refDriveData.sts.eSettingRefusedErrorId := VsdWhy();
  refDriveData.set := stKeptVsd;
  refDriveData.sts.bSettingRefused := TRUE;
END_IF;
IF bResetThisScan THEN                  // the equipment's reset clears a refused write
  refDriveData.sts.bSettingRefused := FALSE;
  refDriveData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;

(* the speed asked for *)
IF __ISVALIDREF(refData) AND refData.set.eMode = E_Mode.Hand THEN
  fTarget := refDriveData.set.fHandSpeedPct;
  IF bJogging AND refDriveData.set.fJogSpeedPct > 0.0 THEN
    fTarget := refDriveData.set.fJogSpeedPct;   // a jog (FB_MotorJog) at its own speed
  END_IF;
ELSIF fSpeedReq >= 0.0 AND fSpeedReq = fSpeedReq THEN
  fTarget := fSpeedReq;
ELSE
  fTarget := refDriveData.set.fAutoSpeedPct;
END_IF;
fTarget := LIMIT(refDriveData.set.fMinSpeedPct, fTarget, refDriveData.set.fMaxSpeedPct);
IF refDriveData.set.fSkipBandHigh > refDriveData.set.fSkipBandLow AND fTarget > refDriveData.set.fSkipBandLow AND fTarget < refDriveData.set.fSkipBandHigh THEN
  IF fTarget - refDriveData.set.fSkipBandLow < refDriveData.set.fSkipBandHigh - fTarget THEN
    fTarget := refDriveData.set.fSkipBandLow;
  ELSE
    fTarget := refDriveData.set.fSkipBandHigh;
  END_IF;
END_IF;

(* the ramp: a start begins from the minimum; across the skip band in one step *)
IF bRunOutput AND NOT bQWas THEN
  fSpeedReferencePct := refDriveData.set.fMinSpeedPct;
END_IF;
bQWas := bRunOutput;
fDt := TIME_TO_REAL(tNow - tLastRamp) / 1000.0;
CASE refDriveData.set.eRateUnit OF          // a rate per minute / hour / day: a smaller step per second
  E_RateUnit.PerMin: fDt := fDt / 60.0;
  E_RateUnit.PerHour: fDt := fDt / 3600.0;
  E_RateUnit.PerDay: fDt := fDt / 86400.0;
ELSE
  ;
END_CASE;
tLastRamp := tNow;
IF NOT bRunOutput THEN
  fSpeedReferencePct := 0.0;
ELSIF fTarget > fSpeedReferencePct THEN
  IF refDriveData.set.fAccelPctPerSec > 0.0 THEN
    fStep := refDriveData.set.fAccelPctPerSec * fDt;
    fSpeedReferencePct := MIN(fTarget, fSpeedReferencePct + fStep);
  ELSE
    fSpeedReferencePct := fTarget;
  END_IF;
ELSIF fTarget < fSpeedReferencePct THEN
  IF refDriveData.set.fDecelPctPerSec > 0.0 THEN
    fStep := refDriveData.set.fDecelPctPerSec * fDt;
    fSpeedReferencePct := MAX(fTarget, fSpeedReferencePct - fStep);
  ELSE
    fSpeedReferencePct := fTarget;
  END_IF;
END_IF;
IF refDriveData.set.fSkipBandHigh > refDriveData.set.fSkipBandLow AND fSpeedReferencePct > refDriveData.set.fSkipBandLow AND fSpeedReferencePct < refDriveData.set.fSkipBandHigh THEN
  IF fTarget >= refDriveData.set.fSkipBandHigh THEN
    fSpeedReferencePct := refDriveData.set.fSkipBandHigh;      // the ramp jumps over the band
  ELSE
    fSpeedReferencePct := refDriveData.set.fSkipBandLow;
  END_IF;
END_IF;
fSpan := refDriveData.set.fRawAtFullPct - refDriveData.set.fRawAtZeroPct;
nSpeedReferenceRaw := REAL_TO_UINT(LIMIT(0.0, refDriveData.set.fRawAtZeroPct + fSpeedReferencePct / 100.0 * fSpan, 65535.0));
IF fSpeedReferencePct <> fTargetWas OR (bRunOutput AND NOT bQWasRamp) THEN
  tTargetAt := tNow;              (* the reference changed (or a start): the drive's own ramp counts again *)
END_IF;
fTargetWas := fSpeedReferencePct;
bQWasRamp := bRunOutput;
bRampDone := bRunOutput AND fSpeedReferencePct = fTarget;
bDriveDone := bRampDone AND tNow - tTargetAt >= refDriveData.set.tDriveOwnRampTime;
bSettled := bDriveDone;
IF fSpeedFeedbackPct >= 0.0 THEN
  bAtSpeed := bRampDone AND ABS(fSpeedReferencePct - fSpeedFeedbackPct) <= refDriveData.set.fSpeedDeviationPct;
ELSE
  bAtSpeed := bDriveDone;
END_IF;
IF fSpeedFeedbackPct >= 0.0 AND fSpeedFeedbackPct <= REAL#3.4E38 AND bRunOutput THEN
  fShown := fSpeedFeedbackPct;
ELSE
  fShown := fSpeedReferencePct;
END_IF;
IF refDriveData.set.fRatedFrequency > 0.0 THEN
  refDriveData.sts.fSpeedHz := fShown / 100.0 * refDriveData.set.fRatedFrequency;
ELSE
  refDriveData.sts.fSpeedHz := 0.0;
END_IF;
IF refDriveData.set.fRatedRpm > 0.0 THEN
  refDriveData.sts.fSpeedRpm := fShown / 100.0 * refDriveData.set.fRatedRpm;
ELSE
  refDriveData.sts.fSpeedRpm := 0.0;
END_IF;
IF bDriveResetPulse AND tNow - tResetAt >= refDriveData.set.tDriveResetPulse THEN
  bDriveResetPulse := FALSE;
END_IF;
refDriveData.sts.fSpeedReferencePct := fSpeedReferencePct;
refDriveData.sts.fSpeedFeedbackPct := fSpeedFeedbackPct;
refDriveData.sts.bAtSpeed := bAtSpeed;
refDriveData.sts.bDriveReady := bDriveReady;

END_FUNCTION_BLOCK