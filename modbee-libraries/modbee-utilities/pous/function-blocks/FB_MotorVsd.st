(* FB_MotorVsd EXTENDS FB_Motor — a variable speed drive over hard-wired IO.
Everything of FB_Motor (modes, protections, the plug, totals, refData) plus the speed. bQ = the drive's run
command; bFeedback = the drive's running relay.

Pins added: bDriveReady (the drive's ready relay: lost while running is a protection; not ready holds a new
start), fSpeedFb (actual speed %, < 0 = not wired), refVsd (its record) -> fSpeedRef (% after clamp, skip band,
ramp), nSpeedRefRaw (scaled to set.fRawMin..fRawMax, a Modbus register), bDriveReset (a pulse on an operator
reset), bAtSpeed.
Speed asked for: Auto -> the owner's speed (Request fSpeed, < 0 = set.fAutoSpeed); Hand -> set.fHandSpeed.
Clamped to fMinSpeed..fMaxSpeed; a target inside the skip band holds at its near edge; ramped by fAccelRate /
fDecelRate (% per set.eRateUnit: second by default, minute, hour or day; 0 = the drive ramps); a start begins from
fMinSpeed. A jog (FB_MotorJog) runs at set.fJogSpeed (0 = fHandSpeed).
Drive protections: driveNotReady (the ready relay lost while running), speedDev (|reference - fSpeedFb| past
set.fDevBand while running with the ramp done and set.tDriveRamp passed since the reference stopped changing,
fSpeedFb wired).
bAtSpeed: the ramp done, and by fSpeedFb within fDevBand, or without fSpeedFb once set.tDriveRamp (the drive's own
0 -> 100 % ramp time, 0 = none) has passed since the reference stopped changing.
The speed in Hz and rpm (sts.fSpeedHz, sts.fSpeedRpm, for display): the feedback while running when wired, else
the reference, x set.fRatedHz / fRatedRpm at 100 % (0 = not shown).
Its settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back. *)

FUNCTION_BLOCK FB_MotorVsd EXTENDS FB_Motor
  VAR_INPUT
    bDriveReady : BOOL := TRUE;
    fSpeedFb : REAL := -1.0;
    refVsd : REFERENCE TO ST_VsdData;
  END_VAR
  VAR_OUTPUT
    fSpeedRef : REAL;
    nSpeedRefRaw : UINT;
    bDriveReset : BOOL;
    bAtSpeed : BOOL;
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
  IF NOT (refVsd.set.fMinSpeed >= 0.0) THEN
    VsdWhy := E_UtError.BelowMin;
  ELSIF NOT (refVsd.set.fMaxSpeed <= 100.0) THEN
    VsdWhy := E_UtError.AboveMax;
  ELSIF NOT (refVsd.set.fMinSpeed <= refVsd.set.fMaxSpeed) THEN
    VsdWhy := E_UtError.LimitsBad;
  ELSIF NOT (refVsd.set.fAccelRate >= 0.0) THEN
    VsdWhy := E_UtError.BelowMin;
  ELSIF NOT (refVsd.set.fDecelRate >= 0.0) THEN
    VsdWhy := E_UtError.BelowMin;
  ELSIF NOT (refVsd.set.fSkipLow <= refVsd.set.fSkipHigh) THEN
    VsdWhy := E_UtError.LimitsBad;
  ELSIF NOT (refVsd.set.tResetPulse >= T#0s) THEN
    VsdWhy := E_UtError.TimeBad;
  ELSIF NOT (refVsd.set.fDevBand >= 0.0) THEN
    VsdWhy := E_UtError.BelowMin;
  ELSIF NOT (refVsd.set.tDriveRamp >= T#0s) THEN
    VsdWhy := E_UtError.TimeBad;
  ELSIF NOT (refVsd.set.fRatedHz >= 0.0) THEN
    VsdWhy := E_UtError.BelowMin;
  ELSIF NOT (refVsd.set.fRatedHz <= REAL#3.4E38) THEN
    VsdWhy := E_UtError.AboveMax;
  ELSIF NOT (refVsd.set.fRatedRpm >= 0.0) THEN
    VsdWhy := E_UtError.BelowMin;
  ELSIF NOT (refVsd.set.fRatedRpm <= REAL#3.4E38) THEN
    VsdWhy := E_UtError.AboveMax;
  ELSIF NOT (refVsd.set.fJogSpeed >= 0.0) THEN
    VsdWhy := E_UtError.BelowMin;
  ELSIF NOT (refVsd.set.fJogSpeed <= 100.0) THEN
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
  IF NOT __ISVALIDREF(refVsd) THEN
    bTrip := TRUE;
    eError := E_UtError.NoRecord;
    RETURN;
  END_IF;
  IF bReset THEN
    tResetAt := tNow;             // a reset pulse to the drive
    bDriveReset := TRUE;
  END_IF;
  bX := F_Protect(tNow := tNow, bCause := bQ AND NOT bDriveReady, bResetReq := bReset,
                  tRetryWindow := T#1h, stSet := refVsd.set.stDriveNotReady,
                  stSts := refVsd.sts.stDriveNotReady, stWork := stWNotReady);
  bX := F_Protect(tNow := tNow, bCause := bQ AND fSpeedFb >= 0.0 AND bSettled
                                          AND ABS(fSpeedRef - fSpeedFb) > refVsd.set.fDevBand,
                  bResetReq := bReset, tRetryWindow := T#1h, stSet := refVsd.set.stSpeedDev,
                  stSts := refVsd.sts.stSpeedDev, stWork := stWSpeedDev);
  bTrip := stWNotReady.bTrip OR stWSpeedDev.bTrip;
  bWarn := stWNotReady.bWarn OR stWSpeedDev.bWarn;
  bHold := NOT bDriveReady;
  IF stWNotReady.bTrip OR stWNotReady.bWarn THEN
    eError := E_UtError.DriveFault;
  ELSIF stWSpeedDev.bTrip OR stWSpeedDev.bWarn THEN
    eError := E_UtError.SpeedDeviation;
  END_IF;
END_METHOD

SUPER^();                         // the motor: modes, protections (with DriveChecks), bQ

IF NOT __ISVALIDREF(refVsd) THEN
  fSpeedRef := 0.0;
  nSpeedRefRaw := 0;
  RETURN;
END_IF;
IF bVsdFirst THEN
  IF nKeptVsdLayout = cVsdLayout THEN
    refVsd.set := stKeptVsd;
  ELSE
    stKeptVsd := refVsd.set;
    nKeptVsdLayout := cVsdLayout;
  END_IF;
  tLastRamp := tNow;
  bVsdFirst := FALSE;
ELSIF VsdWhy() = E_UtError.None THEN
  stKeptVsd := refVsd.set;
ELSE
  refVsd.sts.eRefusedWhy := VsdWhy();
  refVsd.set := stKeptVsd;
  refVsd.sts.bRefused := TRUE;
END_IF;
IF bResetThisScan THEN                  // the equipment's reset clears a refused write
  refVsd.sts.bRefused := FALSE;
  refVsd.sts.eRefusedWhy := E_UtError.None;
END_IF;

(* the speed asked for *)
IF __ISVALIDREF(refData) AND refData.set.eMode = E_Mode.Hand THEN
  fTarget := refVsd.set.fHandSpeed;
  IF bJogging AND refVsd.set.fJogSpeed > 0.0 THEN
    fTarget := refVsd.set.fJogSpeed;   // a jog (FB_MotorJog) at its own speed
  END_IF;
ELSIF fSpeedReq >= 0.0 AND fSpeedReq = fSpeedReq THEN
  fTarget := fSpeedReq;
ELSE
  fTarget := refVsd.set.fAutoSpeed;
END_IF;
fTarget := LIMIT(refVsd.set.fMinSpeed, fTarget, refVsd.set.fMaxSpeed);
IF refVsd.set.fSkipHigh > refVsd.set.fSkipLow AND fTarget > refVsd.set.fSkipLow AND fTarget < refVsd.set.fSkipHigh THEN
  IF fTarget - refVsd.set.fSkipLow < refVsd.set.fSkipHigh - fTarget THEN
    fTarget := refVsd.set.fSkipLow;
  ELSE
    fTarget := refVsd.set.fSkipHigh;
  END_IF;
END_IF;

(* the ramp: a start begins from the minimum; across the skip band in one step *)
IF bQ AND NOT bQWas THEN
  fSpeedRef := refVsd.set.fMinSpeed;
END_IF;
bQWas := bQ;
fDt := TIME_TO_REAL(tNow - tLastRamp) / 1000.0;
CASE refVsd.set.eRateUnit OF          // a rate per minute / hour / day: a smaller step per second
  E_RateUnit.PerMin: fDt := fDt / 60.0;
  E_RateUnit.PerHour: fDt := fDt / 3600.0;
  E_RateUnit.PerDay: fDt := fDt / 86400.0;
ELSE
  ;
END_CASE;
tLastRamp := tNow;
IF NOT bQ THEN
  fSpeedRef := 0.0;
ELSIF fTarget > fSpeedRef THEN
  IF refVsd.set.fAccelRate > 0.0 THEN
    fStep := refVsd.set.fAccelRate * fDt;
    fSpeedRef := MIN(fTarget, fSpeedRef + fStep);
  ELSE
    fSpeedRef := fTarget;
  END_IF;
ELSIF fTarget < fSpeedRef THEN
  IF refVsd.set.fDecelRate > 0.0 THEN
    fStep := refVsd.set.fDecelRate * fDt;
    fSpeedRef := MAX(fTarget, fSpeedRef - fStep);
  ELSE
    fSpeedRef := fTarget;
  END_IF;
END_IF;
IF refVsd.set.fSkipHigh > refVsd.set.fSkipLow AND fSpeedRef > refVsd.set.fSkipLow AND fSpeedRef < refVsd.set.fSkipHigh THEN
  IF fTarget >= refVsd.set.fSkipHigh THEN
    fSpeedRef := refVsd.set.fSkipHigh;      // the ramp jumps over the band
  ELSE
    fSpeedRef := refVsd.set.fSkipLow;
  END_IF;
END_IF;
fSpan := refVsd.set.fRawMax - refVsd.set.fRawMin;
nSpeedRefRaw := REAL_TO_UINT(LIMIT(0.0, refVsd.set.fRawMin + fSpeedRef / 100.0 * fSpan, 65535.0));
IF fSpeedRef <> fTargetWas OR (bQ AND NOT bQWasRamp) THEN
  tTargetAt := tNow;              (* the reference changed (or a start): the drive's own ramp counts again *)
END_IF;
fTargetWas := fSpeedRef;
bQWasRamp := bQ;
bRampDone := bQ AND fSpeedRef = fTarget;
bDriveDone := bRampDone AND tNow - tTargetAt >= refVsd.set.tDriveRamp;
bSettled := bDriveDone;
IF fSpeedFb >= 0.0 THEN
  bAtSpeed := bRampDone AND ABS(fSpeedRef - fSpeedFb) <= refVsd.set.fDevBand;
ELSE
  bAtSpeed := bDriveDone;
END_IF;
IF fSpeedFb >= 0.0 AND fSpeedFb <= REAL#3.4E38 AND bQ THEN
  fShown := fSpeedFb;
ELSE
  fShown := fSpeedRef;
END_IF;
IF refVsd.set.fRatedHz > 0.0 THEN
  refVsd.sts.fSpeedHz := fShown / 100.0 * refVsd.set.fRatedHz;
ELSE
  refVsd.sts.fSpeedHz := 0.0;
END_IF;
IF refVsd.set.fRatedRpm > 0.0 THEN
  refVsd.sts.fSpeedRpm := fShown / 100.0 * refVsd.set.fRatedRpm;
ELSE
  refVsd.sts.fSpeedRpm := 0.0;
END_IF;
IF bDriveReset AND tNow - tResetAt >= refVsd.set.tResetPulse THEN
  bDriveReset := FALSE;
END_IF;
refVsd.sts.fSpeedRef := fSpeedRef;
refVsd.sts.fSpeedFb := fSpeedFb;
refVsd.sts.bAtSpeed := bAtSpeed;
refVsd.sts.bDriveReady := bDriveReady;

END_FUNCTION_BLOCK