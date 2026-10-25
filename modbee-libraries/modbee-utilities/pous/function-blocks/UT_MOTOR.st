(* UT_MOTOR — one contactor, soft starter or run relay load; the base of every
motor variant (UT_MOTOR_VSD, _SD, _2SPD, _REV EXTEND it, decision 81b).
Offers the UT_I_MOTOR plug: an owner (a pump, a duty group, a sequencer
step) wires the instance to its Motor pin and calls Request every scan.

Who runs it (decision 55: the motor's own Off / Hand / Auto, never changed
by an owner):
  Off / OOS   nothing
  Hand        the Hand latch: a fresh Start / LocalStart / cmdStart; never
              restarts by itself, none at power-up. Jog (held, Hand only)
              runs it bypassing every PLC protection, delay, permissive and
              owner; only Interlock stops it (jogMax limits it)
  Auto linked the owner's Request (ReqRun); the motor's own Run / Start do
              nothing (warning "Linked: Run ignored"); Stop / cmdStop /
              LocalStop hold it off until the owner's run drops; the owner's
              Hold stops it at once
  Auto        Run per set.run.style (HELD / TOGGLE / KEEPALIVE), Start latch,
              Stop; a local stop in Auto (localStopInAuto) needs the run
              command to cycle
In every mode Interlock FALSE, a trip and a config fault stop it; Permissive
FALSE, the restart delay and a variant's start block hold back a start.

Protections (defaults in the record): overload, thermistor (HoldOff while
either is tripped: the IO map cannot force the coil on), no feedback,
feedback lost, stuck (welded, after stopTime), current high / low, drive
fault relay, external fault (extReason names it: phase failure, seal leak
...), start too long (locked rotor), current reading bad. Current comes
through the Current plug (NULL = not measured). runByCurrent: the CT proves
running.

Settings and the mode are kept by the block (decision 28); a bad write is
put back (decision 62). Trips are forgotten at power-up. Run hours and
starts are kept hourly (tot); cmdPreset sets them (a replacement motor).

Variants (EXTENDS) set the PROTECTED hooks before SUPER(): vStartDone,
vOwnFb / vFeedback, vStartBlock, vPlannedGap, vTrip (UT_PROT_EXT_SUM),
vCfgFault / vCfgHand / vCfgWarn / vCfgId, vStatus / vTime, vDriveCleared;
and read after SUPER(): runReq, linkSpeed, Jogging, handStart, powerUp,
curMode, resetReq. *)

FUNCTION_BLOCK UT_MOTOR IMPLEMENTS UT_I_MOTOR
  VAR_INPUT
    Run : BOOL; (* Auto run want, per set.run.style; ignored while linked *)
    Start : BOOL R_EDGE; (* Hand start (fresh) / Auto latched start *)
    Stop : BOOL R_EDGE; (* stop in Hand and Auto; wins *)
    Reset : BOOL R_EDGE; (* reset trips whose cause has gone *)
    Interlock : BOOL := TRUE; (* FALSE stops in every mode (Jog too) *)
    Permissive : BOOL := TRUE; (* FALSE blocks a start *)
    Mode : INT := -1; (* 0 Off, 1 Hand, 2 Auto, 3 OOS; acts on change *)
    ExpectAuto : BOOL; (* warning "not in Auto" while TRUE and not in Auto *)
    Jog : BOOL; (* held: jog (Hand only) *)
    Feedback : BOOL; (* contactor aux / soft starter running relay *)
    TopOfRamp : BOOL; (* soft starter top-of-ramp (useTopOfRamp) *)
    Overload : BOOL; (* overload relay tripped (NC through NOT) *)
    Thermistor : BOOL; (* PTC relay tripped *)
    DriveFault : BOOL; (* soft starter / drive fault relay *)
    ExtFault : BOOL; (* any other trip relay, named by extReason *)
    Current : UT_I_MEAS; (* motor current; NULL = not measured *)
    SwHand : BOOL; (* panel selector *)
    SwAuto : BOOL;
    LocalStart : BOOL R_EDGE; (* panel buttons *)
    LocalStop : BOOL R_EDGE;
  END_VAR
  VAR_OUTPUT
    Running : BOOL; (* run confirmed *)
    Q : BOOL; (* contactor coil / soft starter run *)
    Fault : BOOL; (* a trip or config fault holds it off *)
    Warning : BOOL;
    Ready : BOOL; (* would start now in Hand or Auto *)
    Auto : BOOL;
    Hand : BOOL;
    Linked : BOOL; (* an owner commands it *)
    HoldOff : BOOL; (* overload / thermistor tripped: hold the coil off (IO map) *)
    Jogging : BOOL;
    State : UT_STATE;
  END_VAR
  VAR_IN_OUT
    Data : UT_MOTOR_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_MOTOR_SET;
    keptGood : BOOL;
    keptTot : UT_MOTOR_TOT;
  END_VAR
  VAR PROTECTED
    vStartDone : BOOL := TRUE; (* the variant's start sequence is done (delta, speed reached) *)
    vOwnFb : BOOL; (* vFeedback replaces the Feedback pin *)
    vFeedback : BOOL;
    vStartBlock : BOOL; (* may not start now (dead time, drive not ready) *)
    vPlannedGap : BOOL; (* a changeover gap: feedback supervision quiet *)
    vTrip : UT_PROT_EXT_SUM; (* the variant's protections *)
    vCfgFault : BOOL; (* a variant setting refuses every run *)
    vCfgHand : BOOL; (* ... refuses Hand *)
    vCfgWarn : BOOL; (* ... warns *)
    vCfgId : UT_FAULT;
    vStatus : UT_STATUS := UT_ST_IDLE; (* what the variant's sequence is doing *)
    vTime : TIME;
    vDriveCleared : BOOL; (* VSD: the fault relay dropped after a reset pulse *)
    vNoJog : BOOL; (* the variant cannot jog now (REV: both directions held) *)
    vJog : BOOL; (* the variant's own jog pin (REV JogRev) *)
    vHandStart : BOOL; (* the variant's own Hand start (2SPD LocalLow / High, REV LocalRev, cmdLow ...) *)
    vStop : BOOL; (* a stop like the Stop pin (REV stopBeforeReverse) *)
    vHold : BOOL; (* hold it off now, no fault (REV end of travel) *)
    runReq : BOOL; (* the motor should run *)
    linkSpeed : REAL; (* the owner's speed (NaN = none) *)
    handStart : BOOL; (* one scan: a Hand start *)
    powerUp : BOOL; (* one scan: first scan after power-up *)
    curMode : UT_MODE; (* the mode this scan *)
    resetReq : BOOL; (* this scan's reset want *)
  END_VAR
  VAR
    keep : UT_KEEP;
    modeSel : UT_MODE_SELECT;
    runIn : UT_RUN_INPUT;
    hoursAcc : UT_HOURS_ACC;
    stOverload : UT_PROT_ST;
    stThermistor : UT_PROT_ST;
    stNoFb : UT_PROT_ST;
    stFbLost : UT_PROT_ST;
    stStuck : UT_PROT_ST;
    stDrive : UT_PROT_ST;
    stExt : UT_PROT_ST;
    stCurBad : UT_PROT_ST;
    stCurHigh : UT_PROT_ST;
    stCurLow : UT_PROT_ST;
    stStartLong : UT_PROT_ST;
    stlProt : UT_PROTECTION; (* startTooLong as a plain protection (top of ramp) *)
    ok : BOOL;
    cfgF : UT_FAULT;
    cfgH : UT_FAULT;
    cfgW : UT_FAULT;
    cfgFault : BOOL;
    cfgId : UT_FAULT;
    hReset : BOOL;
    hStart : BOOL;
    hStop : BOOL;
    hPreset : BOOL;
    cmdStartReq : BOOL;
    cmdStopReq : BOOL;
    tCur : TIME;
    started : BOOL;
    handNow : BOOL;
    autoNow : BOOL;
    supervise : BOOL;
    fb : BOOL;
    fbUse : BOOL;
    fbSup : BOOL;
    confirmed : BOOL;
    runPrev : BOOL;
    runningPrev : BOOL;
    startedAt : TIME;
    stoppedAt : TIME;
    startDone : BOOL;
    startDonePrev : BOOL;
    startDoneAt : TIME;
    curA : REAL;
    curGood : BOOL;
    curMon : BOOL;
    curOpt : BOOL;
    curPct : REAL;
    curEnable : BOOL;
    tripped : BOOL;
    resetDone : BOOL;
    mustCycle : BOOL;
    handLatch : BOOL;
    handMaxHit : BOOL;
    startCmd : BOOL;
    stopCmd : BOOL;
    want : BOOL;
    stopHold : BOOL; (* linked: a stop holds it off until the owner's run drops *)
    held : BOOL;
    ignored : BOOL; (* linked: the motor's own Run / Start were used *)
    rsIn : TIME;
    jogAt : TIME;
    jogUsed : BOOL;
    jogWas : BOOL;
    wasRun : BOOL;
    tripCode : DWORD;
    tripPrev : DWORD;
    newBits : DWORD;
    hms : LINT;
    linkCalls : INT;
    linkLapse : INT := 2;
    linkRun : BOOL;
    linkHold : BOOL;
    linkSpeedIn : REAL;
    linkOwner : STRING(12);
    twoOwners : BOOL;
    x : BOOL;
    stCode : UT_STATUS;
    stF : UT_FAULT;
    stTime : TIME;
    have : BOOL;
    vNormal : BOOL;
    vHeld : BOOL;
    shownSt : UT_STATUS;
    shownF : UT_FAULT;
    zero : REAL;
    mNan : REAL;
    mReady : BOOL;
    mAvail : BOOL;
    mRestartIn : TIME;
    mCurA : REAL;
    mHours : LREAL;
    mStop : UT_STOP;
    mStatus : UT_STATUS;
    mFaultId : UT_FAULT;
    mLocked : BOOL;
    mNe : UT_NE107;
    mRefuse : BOOL;
  END_VAR


METHOD PUBLIC Request : BOOL
  VAR_INPUT
    ReqRun : BOOL;
    Hold : BOOL;
    ReqSpeed : REAL;
    Owner : STRING(12);
  END_VAR
  linkCalls := linkCalls + 1;
  linkRun := ReqRun;
  linkHold := Hold;
  linkSpeedIn := ReqSpeed;
  linkOwner := Owner;
  Request := NOT mRefuse AND linkCalls <= 1;
END_METHOD
METHOD PUBLIC IsRunning : BOOL
  IsRunning := Running;
END_METHOD
METHOD PUBLIC IsReady : BOOL
  IsReady := mReady;
END_METHOD
METHOD PUBLIC IsAvailable : BOOL
  IsAvailable := mAvail;
END_METHOD
METHOD PUBLIC RestartIn : TIME
  RestartIn := mRestartIn;
END_METHOD
METHOD PUBLIC IsAuto : BOOL
  IsAuto := Auto;
END_METHOD
METHOD PUBLIC IsHand : BOOL
  IsHand := Hand;
END_METHOD
METHOD PUBLIC IsVsd : BOOL
  IsVsd := FALSE;
END_METHOD
METHOD PUBLIC GetSpeed : REAL
  IF Running THEN GetSpeed := 100.0; ELSE GetSpeed := 0.0; END_IF;
END_METHOD
METHOD PUBLIC GetCurrent : REAL
  GetCurrent := mCurA;
END_METHOD
METHOD PUBLIC RunHours : LREAL
  RunHours := mHours;
END_METHOD
METHOD PUBLIC StatusCode : UT_STATUS
  StatusCode := mStatus;
END_METHOD
METHOD PUBLIC FaultId : UT_FAULT
  FaultId := mFaultId;
END_METHOD
METHOD PUBLIC StopReason : UT_STOP
  StopReason := mStop;
END_METHOD
METHOD PUBLIC HasFault : BOOL
  HasFault := Fault;
END_METHOD
METHOD PUBLIC HasWarning : BOOL
  HasWarning := Warning;
END_METHOD
METHOD PUBLIC IsLocked : BOOL
  IsLocked := mLocked;
END_METHOD
METHOD PUBLIC IsFitted : BOOL
  IsFitted := TRUE;
END_METHOD
METHOD PUBLIC Ne107 : UT_NE107
  Ne107 := mNe;
END_METHOD

tCur := TIME();
keep(TotalsNow := Data.cmdPreset AND NOT hPreset);
powerUp := keep.PowerUp;
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
IF keep.RestoreTot THEN
  Data.tot := keptTot;
END_IF;
IF powerUp THEN
  Data.simulate := FALSE;
  stoppedAt := tCur;             (* the motor may still be turning: the restart delay counts from now *)
  mNan := zero / zero;
END_IF;

(* settings: a bad write is put back *)
ok := UT_MOTOR_CHECK(S := Data.set, Fault => cfgF, Hand => cfgH, Warn => cfgW);
IF NOT ok AND keptGood AND NOT keep.FirstBoot THEN
  IF cfgF <> UT_F_NONE THEN
    Data.sts.refused := cfgF;
  ELSIF cfgH <> UT_F_NONE THEN
    Data.sts.refused := cfgH;
  ELSE
    Data.sts.refused := cfgW;
  END_IF;
  Data.sts.refusedWhy := UT_F_SETTING;
  Data.set := keptSet;
  ok := UT_MOTOR_CHECK(S := Data.set, Fault => cfgF, Hand => cfgH, Warn => cfgW);
END_IF;
IF keep.SaveSet AND (ok OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := ok;
END_IF;

(* the link: Request calls since the last scan *)
twoOwners := linkCalls > 1;
IF linkCalls > 0 THEN
  linkLapse := 0;
ELSIF linkLapse < 2 THEN
  linkLapse := linkLapse + 1;
END_IF;
linkCalls := 0;
Linked := linkLapse < 2;
IF NOT Linked THEN
  linkRun := FALSE;
  linkHold := FALSE;
  linkSpeedIn := mNan;
END_IF;
linkSpeed := linkSpeedIn;

(* commands: once per want, even when held on *)
cmdStartReq := Data.cmdStart AND NOT hStart;
hStart := Data.cmdStart;
Data.cmdStart := FALSE;
cmdStopReq := Data.cmdStop AND NOT hStop;
hStop := Data.cmdStop;
Data.cmdStop := FALSE;
IF Data.cmdPreset AND NOT hPreset THEN
  IF Data.presetHours >= 0.0 AND Data.presetHours <= 1.0E7 THEN
    Data.tot.runHours := Data.presetHours;
  END_IF;
  Data.tot.starts := Data.presetStarts;
END_IF;
hPreset := Data.cmdPreset;
Data.cmdPreset := FALSE;

(* the mode *)
modeSel(SwAuto := SwAuto, SwHand := SwHand, ForceOff := FALSE, HandOn := Hand AND runningPrev, HandToOff := FALSE,
        AllowOOS := TRUE, Source := Data.set.modeSource, ModeReq := Mode, PowerUp := Data.set.powerUp,
        HandPowerUp := UT_HPU_KEEP, HandMax := MAX(Data.set.handMaxRun, T#0s), CmdMode := Data.cmdMode,
        Choice := Data.set.mode);
curMode := modeSel.Mode;
handNow := curMode = UT_MODE_HAND;
autoNow := curMode = UT_MODE_AUTO;
supervise := curMode <> UT_MODE_OOS;
resetReq := Reset OR (Data.cmdReset AND NOT hReset) OR (Data.set.resetByOff AND modeSel.EnteredOff);
hReset := Data.cmdReset;
Data.cmdReset := FALSE;

(* the current *)
curA := 0.0;
curGood := FALSE;
IF Current <> NULL THEN
  curA := Current.GetValue();
  curGood := Current.IsFitted() AND Current.GoodNow() AND ABS(curA) <= 3.4E38;
END_IF;
curMon := Data.set.fullLoadCurrent > 0.0 AND Data.set.fullLoadCurrent <= 3.4E38 AND Current <> NULL;
curOpt := Data.set.currentHigh.response <> UT_RESP_OFF OR Data.set.currentLow.response <> UT_RESP_OFF
          OR Data.set.runByCurrent OR (Data.set.startTooLong.response <> UT_RESP_OFF AND NOT Data.set.useTopOfRamp);
IF curMon AND curGood THEN
  curPct := curA / Data.set.fullLoadCurrent * 100.0;
ELSE
  curPct := 0.0;
END_IF;

(* the feedback: simulated, the variant's own, or the pin; or the CT *)
IF Data.simulate THEN
  fb := runPrev;
ELSIF vOwnFb THEN
  fb := vFeedback;
ELSE
  fb := Feedback;
END_IF;
fbSup := Data.set.useFeedback OR (Data.set.runByCurrent AND curMon);
fbUse := (Data.set.useFeedback AND fb) OR (Data.set.runByCurrent AND curMon AND curGood
                                           AND curPct >= Data.set.runCurrentPct);
IF Data.simulate THEN
  fbUse := runPrev;
END_IF;
IF NOT runPrev THEN
  confirmed := FALSE;
ELSIF fbUse THEN
  confirmed := TRUE;
END_IF;

(* the start is done: the variant's sequence, and top of ramp / running *)
startDone := runPrev AND vStartDone AND ((Data.set.useTopOfRamp AND TopOfRamp)
                                         OR (NOT Data.set.useTopOfRamp AND (fbUse OR NOT fbSup)));
IF startDone AND NOT startDonePrev THEN
  startDoneAt := tCur;
END_IF;
startDonePrev := startDone;

(* protections (OOS: none) *)
x := UT_PROT_RUN(TNow := tCur, Cause := supervise AND Overload, ResetReq := resetReq,
                 RetryWindow := Data.set.retryWindow, Prot := Data.set.overload, Sts := Data.sts.overload, St := stOverload);
x := UT_PROT_RUN(TNow := tCur, Cause := supervise AND Thermistor, ResetReq := resetReq,
                 RetryWindow := Data.set.retryWindow, Prot := Data.set.thermistor, Sts := Data.sts.thermistor, St := stThermistor);
x := UT_PROT_RUN(TNow := tCur, Cause := supervise AND fbSup AND runPrev AND NOT confirmed AND NOT fbUse AND NOT vPlannedGap,
                 ResetReq := resetReq, RetryWindow := Data.set.retryWindow, Prot := Data.set.noFeedback,
                 Sts := Data.sts.noFeedback, St := stNoFb);
x := UT_PROT_RUN(TNow := tCur, Cause := supervise AND fbSup AND runPrev AND confirmed AND NOT fbUse AND NOT vPlannedGap,
                 ResetReq := resetReq, RetryWindow := Data.set.retryWindow, Prot := Data.set.feedbackLost,
                 Sts := Data.sts.feedbackLost, St := stFbLost);
x := UT_PROT_RUN(TNow := tCur, Cause := supervise AND fbSup AND NOT runPrev AND fbUse AND NOT vPlannedGap
                                        AND tCur - stoppedAt >= Data.set.stopTime,
                 ResetReq := resetReq, RetryWindow := Data.set.retryWindow, Prot := Data.set.stuck,
                 Sts := Data.sts.stuck, St := stStuck);
x := UT_PROT_RUN(TNow := tCur, Cause := supervise AND DriveFault, ResetReq := resetReq OR vDriveCleared,
                 RetryWindow := Data.set.retryWindow, Prot := Data.set.drive, Sts := Data.sts.drive, St := stDrive);
x := UT_PROT_RUN(TNow := tCur, Cause := supervise AND ExtFault, ResetReq := resetReq,
                 RetryWindow := Data.set.retryWindow, Prot := Data.set.extFault, Sts := Data.sts.extFault, St := stExt);
x := UT_PROT_RUN(TNow := tCur, Cause := supervise AND curMon AND curOpt AND NOT curGood, ResetReq := resetReq,
                 RetryWindow := Data.set.retryWindow, Prot := Data.set.currentBad, Sts := Data.sts.currentBad, St := stCurBad);
curEnable := supervise AND curMon AND runPrev AND startDone AND tCur - startDoneAt >= Data.set.currentStartMask;
x := UT_LEVEL_RUN(TNow := tCur, In := curPct, Good := curGood, High := TRUE, UseIn := TRUE, Switch := FALSE,
                  Enable := curEnable, Release := Data.sts.currentBad.active, ResetReq := resetReq,
                  RetryWindow := Data.set.retryWindow, Level := Data.set.currentHigh, Sts := Data.sts.currentHigh,
                  St := stCurHigh);
x := UT_LEVEL_RUN(TNow := tCur, In := curPct, Good := curGood, High := FALSE, UseIn := TRUE, Switch := FALSE,
                  Enable := curEnable, Release := Data.sts.currentBad.active, ResetReq := resetReq,
                  RetryWindow := Data.set.retryWindow, Level := Data.set.currentLow, Sts := Data.sts.currentLow,
                  St := stCurLow);
IF Data.set.useTopOfRamp THEN    (* start too long: no top of ramp in time *)
  stlProt.response := Data.set.startTooLong.response;
  stlProt.delay := Data.set.startTooLong.delay;
  stlProt.reset := Data.set.startTooLong.reset;
  stlProt.recover := Data.set.startTooLong.recover;
  stlProt.maxRetries := Data.set.startTooLong.maxRetries;
  x := UT_PROT_RUN(TNow := tCur, Cause := supervise AND runPrev AND NOT startDone, ResetReq := resetReq,
                   RetryWindow := Data.set.retryWindow, Prot := stlProt, Sts := Data.sts.startTooLong, St := stStartLong);
ELSE                             (* the current still at the starting level: a locked rotor *)
  x := UT_LEVEL_RUN(TNow := tCur, In := curPct, Good := curGood, High := TRUE, UseIn := TRUE, Switch := FALSE,
                    Enable := supervise AND curMon AND runPrev, Release := Data.sts.currentBad.active,
                    ResetReq := resetReq, RetryWindow := Data.set.retryWindow, Level := Data.set.startTooLong,
                    Sts := Data.sts.startTooLong, St := stStartLong);
END_IF;
HoldOff := Data.sts.overload.tripped OR Data.sts.thermistor.tripped;

(* config: the base's, the variant's, two owners *)
cfgFault := cfgF <> UT_F_NONE OR vCfgFault OR twoOwners;
IF twoOwners THEN
  cfgId := UT_F_TWO_OWNERS;
ELSIF cfgF <> UT_F_NONE THEN
  cfgId := cfgF;
ELSIF vCfgFault THEN
  cfgId := vCfgId;
ELSIF cfgH <> UT_F_NONE AND handNow THEN
  cfgId := cfgH;
ELSIF vCfgHand AND handNow THEN
  cfgId := vCfgId;
ELSE
  cfgId := UT_F_NONE;
END_IF;
tripped := stOverload.trip OR stThermistor.trip OR stNoFb.trip OR stFbLost.trip OR stStuck.trip OR stDrive.trip
           OR stExt.trip OR stCurBad.trip OR stCurHigh.trip OR stCurLow.trip OR stStartLong.trip
           OR vTrip.trip <> 0 OR cfgFault OR (handNow AND (cfgH <> UT_F_NONE OR vCfgHand));
resetDone := stOverload.reset OR stThermistor.reset OR stNoFb.reset OR stFbLost.reset OR stStuck.reset
             OR stDrive.reset OR stExt.reset OR stCurBad.reset OR stCurHigh.reset OR stCurLow.reset
             OR stStartLong.reset OR vTrip.resetDone;
Fault := tripped AND supervise;
Warning := supervise AND (stOverload.warn OR stThermistor.warn OR stNoFb.warn OR stFbLost.warn OR stStuck.warn
           OR stDrive.warn OR stExt.warn OR stCurBad.warn OR stCurHigh.warn OR stCurLow.warn OR stStartLong.warn
           OR vTrip.warn <> 0 OR cfgW <> UT_F_NONE OR vCfgWarn OR (ExpectAuto AND NOT autoNow) OR ignored
           OR modeSel.SwFault OR modeSel.BadSetting OR Data.simulate);
IF resetDone AND NOT Data.set.restartAfterReset AND NOT runPrev THEN
  mustCycle := TRUE;             (* a reset that needed one: the command cycles *)
END_IF;

(* the want, per mode. A start must be fresh: none on the first scan *)
startCmd := started AND NOT Stop AND NOT LocalStop AND NOT cmdStopReq AND NOT vStop
            AND (Start OR LocalStart OR cmdStartReq OR vHandStart);
stopCmd := Stop OR LocalStop OR cmdStopReq OR vStop;
handStart := FALSE;
ignored := FALSE;
held := FALSE;
IF modeSel.Changed AND handNow THEN
  handLatch := runPrev AND NOT Jogging;   (* Auto -> Hand is bumpless *)
END_IF;
IF modeSel.Changed THEN
  handMaxHit := FALSE;
END_IF;
runIn(Run := Run, Start := Start, Stop := Stop, CmdStart := cmdStartReq, CmdStop := cmdStopReq,
      Drop := NOT autoNow OR NOT Interlock OR tripped, Linked := Linked, TargetDone := FALSE, HasTarget := FALSE,
      Set := Data.set.run);
CASE curMode OF
UT_MODE_HAND:
  IF stopCmd OR NOT Interlock OR tripped OR (NOT Permissive AND NOT runPrev) OR modeSel.HandUp THEN
    handLatch := FALSE;
    IF modeSel.HandUp THEN
      handMaxHit := TRUE;
    END_IF;
  ELSIF startCmd THEN
    handLatch := TRUE;
    handStart := TRUE;
    handMaxHit := FALSE;
  END_IF;
  IF mustCycle THEN
    handLatch := FALSE;          (* the operator presses start again *)
    mustCycle := FALSE;
  END_IF;
  want := handLatch;
  stopHold := FALSE;
UT_MODE_AUTO:
  handLatch := FALSE;
  IF Linked THEN
    ignored := Run OR Start;
    IF stopCmd OR (Data.set.localStopInAuto AND LocalStop) THEN
      stopHold := TRUE;
    END_IF;
    IF NOT linkRun THEN
      stopHold := FALSE;
      mustCycle := FALSE;
    END_IF;
    held := linkHold;
    want := linkRun AND NOT linkHold AND NOT stopHold;
  ELSE
    stopHold := FALSE;
    want := runIn.Request AND NOT runIn.BadSetting;
    IF Data.set.localStopInAuto AND LocalStop THEN
      mustCycle := TRUE;         (* restart on the next rising edge of the want *)
    END_IF;
    IF NOT want THEN
      mustCycle := FALSE;
    END_IF;
  END_IF;
ELSE
  handLatch := FALSE;
  want := FALSE;
  mustCycle := FALSE;
  stopHold := FALSE;
END_CASE;

(* jog: held, Hand only; only Interlock (and jogMax) stops it *)
IF handNow AND (Jog OR vJog) AND Interlock AND NOT vNoJog AND NOT handLatch THEN
  IF NOT jogWas THEN
    jogAt := tCur;
    jogUsed := FALSE;
  END_IF;
  IF Data.set.jogMax > T#0s AND tCur - jogAt >= Data.set.jogMax THEN
    jogUsed := TRUE;
  END_IF;
  Jogging := NOT jogUsed;
ELSE
  Jogging := FALSE;
END_IF;
jogWas := handNow AND (Jog OR vJog);

(* restart delay: the motor must have been off this long *)
IF runPrev THEN
  rsIn := T#0s;
ELSIF tCur - stoppedAt < Data.set.restartDelay THEN
  rsIn := Data.set.restartDelay - (tCur - stoppedAt);
ELSE
  rsIn := T#0s;
END_IF;
Data.sts.restartBlocked := (rsIn > T#0s OR mustCycle) AND NOT runPrev;

runReq := ((want AND Interlock AND NOT tripped AND NOT mustCycle
            AND (runPrev OR (Permissive AND NOT vStartBlock AND rsIn = T#0s)))
           OR Jogging) AND NOT vHold;
wasRun := runPrev;
IF runReq AND NOT runPrev THEN
  startedAt := tCur;
ELSIF runPrev AND NOT runReq THEN
  stoppedAt := tCur;
END_IF;
runPrev := runReq;
Q := runReq;

(* why the run ended *)
IF wasRun AND NOT runReq THEN
  IF tripped THEN
    Data.sts.stopReason := UT_STOP_FAULT;
  ELSIF NOT Interlock THEN
    Data.sts.stopReason := UT_STOP_INTERLOCK;
  ELSIF curMode = UT_MODE_OFF OR curMode = UT_MODE_OOS THEN
    Data.sts.stopReason := UT_STOP_SWITCHED_OFF;
  ELSIF handMaxHit THEN
    Data.sts.stopReason := UT_STOP_MAX_RUN;
  ELSIF held THEN
    Data.sts.stopReason := UT_STOP_HELD_BY_LINK;
  ELSIF handNow OR mustCycle OR stopHold OR stopCmd THEN
    Data.sts.stopReason := UT_STOP_OPERATOR;
  ELSIF runIn.AliveLost THEN
    Data.sts.stopReason := UT_STOP_COMMS_LOST;
  ELSE
    Data.sts.stopReason := UT_STOP_DEMAND_ENDED;
  END_IF;
END_IF;

IF fbSup THEN
  Running := runReq AND fbUse;
ELSE
  Running := runReq;
END_IF;
IF Running AND NOT runningPrev THEN
  Data.tot.starts := Data.tot.starts + 1;
END_IF;
runningPrev := Running;
hms := UT_HOURS_ADD(Running := Running, TNow := tCur, Acc := hoursAcc);
Data.tot.runHours := Data.tot.runHours + LINT_TO_LREAL(hms) / 3600000.0;
IF keep.SaveTot THEN
  keptTot := Data.tot;
END_IF;

Ready := NOT tripped AND Interlock AND Permissive AND (handNow OR autoNow) AND NOT mustCycle AND NOT held
         AND NOT stopHold AND (runPrev OR (rsIn = T#0s AND NOT vStartBlock));
Data.sts.available := autoNow AND NOT tripped AND Interlock AND Permissive AND NOT held AND NOT mustCycle
                      AND NOT stopHold;
Auto := autoNow;
Hand := handNow;

IF curMode = UT_MODE_OOS THEN
  State := UT_STATE_OOS;
ELSIF tripped THEN
  State := UT_STATE_FAULT;
ELSIF NOT Interlock THEN
  State := UT_STATE_INTERLOCKED;
ELSIF runReq AND NOT Running THEN
  State := UT_STATE_STARTING;
ELSIF Running AND Warning THEN
  State := UT_STATE_WARNING;
ELSIF Running THEN
  State := UT_STATE_ON;
ELSIF fbUse THEN
  State := UT_STATE_STOPPING;
ELSE
  State := UT_STATE_OFF;
END_IF;

(* fault code and the last trip *)
Data.sts.faultCode := vTrip.tripped;
IF cfgFault OR cfgW <> UT_F_NONE OR vCfgWarn THEN Data.sts.faultCode := Data.sts.faultCode OR 16#1000; END_IF;
IF Data.sts.startTooLong.tripped THEN Data.sts.faultCode := Data.sts.faultCode OR 16#4000; END_IF;
IF Data.sts.extFault.tripped THEN Data.sts.faultCode := Data.sts.faultCode OR 16#2000; END_IF;
IF Data.sts.currentBad.tripped THEN Data.sts.faultCode := Data.sts.faultCode OR 16#800; END_IF;
IF Data.sts.drive.tripped THEN Data.sts.faultCode := Data.sts.faultCode OR 16#80; END_IF;
IF Data.sts.currentLow.tripped THEN Data.sts.faultCode := Data.sts.faultCode OR 16#40; END_IF;
IF Data.sts.currentHigh.tripped THEN Data.sts.faultCode := Data.sts.faultCode OR 16#20; END_IF;
IF Data.sts.stuck.tripped THEN Data.sts.faultCode := Data.sts.faultCode OR 16#10; END_IF;
IF Data.sts.feedbackLost.tripped THEN Data.sts.faultCode := Data.sts.faultCode OR 16#8; END_IF;
IF Data.sts.noFeedback.tripped THEN Data.sts.faultCode := Data.sts.faultCode OR 16#4; END_IF;
IF Data.sts.thermistor.tripped THEN Data.sts.faultCode := Data.sts.faultCode OR 16#2; END_IF;
IF Data.sts.overload.tripped THEN Data.sts.faultCode := Data.sts.faultCode OR 16#1; END_IF;
tripCode := vTrip.trip;
IF stOverload.trip THEN tripCode := tripCode OR 16#1; END_IF;
IF stThermistor.trip THEN tripCode := tripCode OR 16#2; END_IF;
IF stNoFb.trip THEN tripCode := tripCode OR 16#4; END_IF;
IF stFbLost.trip THEN tripCode := tripCode OR 16#8; END_IF;
IF stStuck.trip THEN tripCode := tripCode OR 16#10; END_IF;
IF stCurHigh.trip THEN tripCode := tripCode OR 16#20; END_IF;
IF stCurLow.trip THEN tripCode := tripCode OR 16#40; END_IF;
IF stDrive.trip THEN tripCode := tripCode OR 16#80; END_IF;
IF stCurBad.trip THEN tripCode := tripCode OR 16#800; END_IF;
IF cfgFault THEN tripCode := tripCode OR 16#1000; END_IF;
IF stExt.trip THEN tripCode := tripCode OR 16#2000; END_IF;
IF stStartLong.trip THEN tripCode := tripCode OR 16#4000; END_IF;
newBits := tripCode AND NOT tripPrev;
tripPrev := tripCode;
IF newBits <> 0 AND supervise THEN
  Data.sts.trips := Data.sts.trips + 1;
  Data.sts.lastFaultCode := tripCode;
  IF (newBits AND 16#1) <> 0 THEN Data.sts.lastFault := UT_F_OVERLOAD;
  ELSIF (newBits AND 16#2) <> 0 THEN Data.sts.lastFault := UT_F_MOTOR_HOT;
  ELSIF (newBits AND 16#4) <> 0 THEN Data.sts.lastFault := UT_F_NO_FEEDBACK;
  ELSIF (newBits AND 16#8) <> 0 THEN Data.sts.lastFault := UT_F_FEEDBACK_LOST;
  ELSIF (newBits AND 16#10) <> 0 THEN Data.sts.lastFault := UT_F_WELDED;
  ELSIF (newBits AND 16#20) <> 0 THEN Data.sts.lastFault := UT_F_CURRENT_HIGH;
  ELSIF (newBits AND 16#40) <> 0 THEN Data.sts.lastFault := UT_F_CURRENT_LOW;
  ELSIF (newBits AND 16#80) <> 0 THEN Data.sts.lastFault := UT_F_DRIVE;
  ELSIF (newBits AND 16#2000) <> 0 THEN Data.sts.lastFault := Data.set.extReason;
  ELSIF (newBits AND 16#4000) <> 0 THEN Data.sts.lastFault := UT_F_START_TOO_LONG;
  ELSIF (newBits AND 16#800) <> 0 THEN Data.sts.lastFault := UT_F_CURRENT_BAD;
  ELSIF (newBits AND 16#1000) <> 0 THEN Data.sts.lastFault := cfgId;
  ELSE Data.sts.lastFault := vTrip.tripId;
  END_IF;
END_IF;

(* status: config > fault > jog > held / waiting > warning > normal > idle *)
vNormal := vStatus = UT_ST_STAR OR vStatus = UT_ST_LOW_FIRST OR vStatus = UT_ST_SKIP_EDGE;
vHeld := vStatus = UT_ST_DEAD_TIME OR vStatus = UT_ST_WAIT_MAIN_FB OR vStatus = UT_ST_WAIT_OPEN;
have := TRUE;
stF := UT_F_NONE;
stTime := T#0s;
IF Jogging THEN
  stCode := UT_ST_JOG;           (* protections bypassed: shown above everything *)
ELSIF cfgId <> UT_F_NONE AND (cfgFault OR handNow) THEN
  stCode := UT_ST_CONFIG;
  stF := cfgId;
ELSIF Fault THEN
  IF stOverload.trip THEN stF := UT_F_OVERLOAD; stCode := UT_PROT_STATUS(Reset := Data.set.overload.reset, Sts := Data.sts.overload); stTime := Data.sts.overload.timeLeft;
  ELSIF stThermistor.trip THEN stF := UT_F_MOTOR_HOT; stCode := UT_PROT_STATUS(Reset := Data.set.thermistor.reset, Sts := Data.sts.thermistor); stTime := Data.sts.thermistor.timeLeft;
  ELSIF stNoFb.trip THEN stF := UT_F_NO_FEEDBACK; stCode := UT_PROT_STATUS(Reset := Data.set.noFeedback.reset, Sts := Data.sts.noFeedback); stTime := Data.sts.noFeedback.timeLeft;
  ELSIF stFbLost.trip THEN stF := UT_F_FEEDBACK_LOST; stCode := UT_PROT_STATUS(Reset := Data.set.feedbackLost.reset, Sts := Data.sts.feedbackLost); stTime := Data.sts.feedbackLost.timeLeft;
  ELSIF stStuck.trip THEN stF := UT_F_WELDED; stCode := UT_PROT_STATUS(Reset := Data.set.stuck.reset, Sts := Data.sts.stuck); stTime := Data.sts.stuck.timeLeft;
  ELSIF stCurHigh.trip THEN stF := UT_F_CURRENT_HIGH; stCode := UT_PROT_STATUS(Reset := Data.set.currentHigh.reset, Sts := Data.sts.currentHigh); stTime := Data.sts.currentHigh.timeLeft;
  ELSIF stCurLow.trip THEN stF := UT_F_CURRENT_LOW; stCode := UT_PROT_STATUS(Reset := Data.set.currentLow.reset, Sts := Data.sts.currentLow); stTime := Data.sts.currentLow.timeLeft;
  ELSIF stDrive.trip THEN stF := UT_F_DRIVE; stCode := UT_PROT_STATUS(Reset := Data.set.drive.reset, Sts := Data.sts.drive); stTime := Data.sts.drive.timeLeft;
  ELSIF stExt.trip THEN stF := Data.set.extReason; stCode := UT_PROT_STATUS(Reset := Data.set.extFault.reset, Sts := Data.sts.extFault); stTime := Data.sts.extFault.timeLeft;
  ELSIF stStartLong.trip THEN stF := UT_F_START_TOO_LONG; stCode := UT_PROT_STATUS(Reset := Data.set.startTooLong.reset, Sts := Data.sts.startTooLong); stTime := Data.sts.startTooLong.timeLeft;
  ELSIF stCurBad.trip THEN stF := UT_F_CURRENT_BAD; stCode := UT_PROT_STATUS(Reset := Data.set.currentBad.reset, Sts := Data.sts.currentBad); stTime := Data.sts.currentBad.timeLeft;
  ELSE stF := vTrip.tripId; stCode := vTrip.tripStatus; stTime := vTrip.tripTime;
  END_IF;
ELSIF curMode = UT_MODE_OOS THEN
  stCode := UT_ST_OOS;
ELSIF NOT Interlock THEN
  stCode := UT_ST_INTERLOCK;
ELSIF autoNow AND held THEN
  stCode := UT_ST_HELD_BY_LINK;
ELSIF (handNow OR autoNow) AND NOT runReq AND NOT Permissive AND want THEN
  stCode := UT_ST_NOT_PERMITTED;
ELSIF (handNow OR autoNow) AND NOT runReq AND vStatus = UT_ST_DRIVE_NOT_READY THEN
  stCode := UT_ST_DRIVE_NOT_READY;
ELSIF (handNow OR autoNow) AND (mustCycle OR stopHold) AND (want OR linkRun) THEN
  stCode := UT_ST_MUST_CYCLE;
ELSIF (handNow OR autoNow) AND want AND NOT runReq AND rsIn > T#0s THEN
  stCode := UT_ST_RESTART_DELAY;
  stTime := rsIn;
ELSIF (handNow OR autoNow) AND want AND vHeld THEN
  stCode := vStatus;
  stTime := vTime;
ELSIF (handNow OR autoNow) AND want AND NOT runReq AND vStartBlock THEN
  stCode := UT_ST_START_BLOCKED;
ELSIF handNow AND NOT want AND handMaxHit THEN
  stCode := UT_ST_HAND_MAX_RUN;
ELSIF handNow AND NOT want THEN
  stCode := UT_ST_HAND_PRESS_START;
ELSE
  have := FALSE;
END_IF;
IF NOT have AND Warning THEN
  have := TRUE;
  stCode := UT_ST_WARNING;
  IF stOverload.warn THEN stF := UT_F_OVERLOAD;
  ELSIF stThermistor.warn THEN stF := UT_F_MOTOR_HOT;
  ELSIF stNoFb.warn THEN stF := UT_F_NO_FEEDBACK;
  ELSIF stFbLost.warn THEN stF := UT_F_FEEDBACK_LOST;
  ELSIF stStuck.warn THEN stF := UT_F_WELDED;
  ELSIF stCurHigh.warn THEN stF := UT_F_CURRENT_HIGH;
  ELSIF stCurLow.warn THEN stF := UT_F_CURRENT_LOW;
  ELSIF stDrive.warn THEN stF := UT_F_DRIVE;
  ELSIF stExt.warn THEN stF := Data.set.extReason;
  ELSIF stStartLong.warn THEN stF := UT_F_START_TOO_LONG;
  ELSIF stCurBad.warn THEN stF := UT_F_CURRENT_BAD;
  ELSIF vTrip.warn <> 0 THEN stF := vTrip.warnId;
  ELSIF ExpectAuto AND NOT autoNow THEN stF := UT_F_NOT_AUTO;
  ELSIF ignored THEN stF := UT_F_RUN_IGNORED;
  ELSIF modeSel.SwFault THEN stF := UT_F_SELECTOR;
  ELSIF Data.simulate THEN stCode := UT_ST_SIMULATED; stF := UT_F_SIMULATED;
  ELSE
    stCode := UT_ST_WARN_SETTING;
    IF cfgW <> UT_F_NONE THEN
      stF := cfgW;
    ELSIF vCfgWarn THEN
      stF := vCfgId;
    ELSIF modeSel.BadSetting THEN
      stF := UT_F_MODE_CHOICE;
    END_IF;
  END_IF;
END_IF;
IF NOT have THEN
  IF runReq AND vNormal THEN
    stCode := vStatus;
    stTime := vTime;
  ELSIF runReq AND NOT Running THEN
    stCode := UT_ST_STARTING;
  ELSIF Running AND autoNow AND Linked THEN
    stCode := UT_ST_RUN_LINKED;
  ELSIF Running AND handNow THEN
    stCode := UT_ST_RUN_HAND;
    stTime := modeSel.HandLeft;
  ELSIF Running THEN
    stCode := UT_ST_RUN_AUTO;
  ELSIF fbUse THEN
    stCode := UT_ST_STOPPING;
  ELSIF autoNow AND Linked THEN
    stCode := UT_ST_WAIT_GROUP;
  ELSIF autoNow THEN
    stCode := UT_ST_IDLE;
  ELSE
    stCode := UT_ST_OFF;
  END_IF;
END_IF;
IF stTime < T#0s THEN
  stTime := T#0s;
END_IF;
IF stCode <> shownSt OR stF <> shownF OR LEN(Data.sts.statusText) = 0 THEN
  shownSt := stCode;
  shownF := stF;
  Data.sts.statusText := UT_STATUS_TEXT(stCode, stF);
END_IF;
Data.sts.statusCode := stCode;
Data.sts.faultId := stF;
Data.sts.ne107 := UT_NE107_RUN(Fault := Fault,
                               Check := NOT autoNow OR Jogging OR Data.simulate OR (ExpectAuto AND NOT autoNow),
                               OutOfSpec := Warning, Maint := FALSE);

(* status and detail *)
Data.det.timeLeft := stTime;
IF stCode = UT_ST_FAULT OR stCode = UT_ST_FAULT_RETRY THEN
  Data.det.faultClearIn := stTime;
ELSE
  Data.det.faultClearIn := T#0s;
END_IF;
Data.det.restartIn := rsIn;
IF runReq THEN
  Data.det.runTime := tCur - startedAt;
  Data.det.offTime := T#0s;
ELSE
  Data.det.offTime := tCur - stoppedAt;
END_IF;
Data.det.maskLeft := T#0s;
IF runReq AND curMon AND startDone AND tCur - startDoneAt < Data.set.currentStartMask THEN
  Data.det.maskLeft := Data.set.currentStartMask - (tCur - startDoneAt);
END_IF;
Data.sts.linked := Linked;
Data.sts.held := held AND autoNow;
IF Linked THEN
  Data.sts.owner := linkOwner;
ELSE
  Data.sts.owner := '';
END_IF;
Data.sts.mode := curMode;
Data.sts.state := State;
Data.sts.run := runReq;
Data.sts.running := Running;
Data.sts.ready := Ready;
Data.sts.fault := Fault;
Data.sts.warning := Warning;
Data.sts.interlocked := NOT Interlock;
Data.sts.notPermitted := NOT Permissive;
Data.sts.holdOff := HoldOff;
Data.sts.jogging := Jogging;
Data.sts.notAuto := ExpectAuto AND NOT autoNow;
Data.sts.selectorFault := modeSel.SwFault;
Data.sts.wrnConfig := cfgW <> UT_F_NONE OR vCfgWarn OR cfgFault;
IF curMon AND curGood THEN
  Data.sts.current := curA;
ELSE
  Data.sts.current := 0.0;
END_IF;
Data.sts.currentPct := curPct;

(* the plug's answers, and the rest a variant reads *)
mReady := Ready AND autoNow;
mAvail := Data.sts.available;
mRestartIn := rsIn;
IF curMon AND curGood THEN mCurA := curA; ELSE mCurA := mNan; END_IF;
mHours := Data.tot.runHours;
mStop := Data.sts.stopReason;
mStatus := stCode;
mFaultId := stF;
mLocked := Data.sts.overload.locked OR Data.sts.thermistor.locked OR Data.sts.noFeedback.locked
           OR Data.sts.feedbackLost.locked OR Data.sts.stuck.locked OR Data.sts.drive.locked
           OR Data.sts.extFault.locked OR Data.sts.currentHigh.locked OR Data.sts.currentLow.locked
           OR Data.sts.startTooLong.locked OR Data.sts.currentBad.locked OR vTrip.locked;
mNe := Data.sts.ne107;
mRefuse := cfgFault;
started := TRUE;

END_FUNCTION_BLOCK