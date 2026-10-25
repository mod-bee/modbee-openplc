(* UT_PUMP — ONE pump: its run request, its protections, prime, the motor
link and its status (decision 12). The element of a station's or cascade's
Pumps list (call each pump before its group). The process (levels, stages,
pressure) is the station's / cascade's; a single pump that empties or
fills a tank is a one-pump station.

The pump has its OWN Off / Hand / Auto (decision 55); its motor has its own
too and the pump commands the motor through the Motor plug only while the
motor is in Auto. A motor in Hand bypasses all pump control: "Motor in
Hand", not available to the owner. Off: no request. Hand: Start / Stop run
the motor with the pump's protections. Auto linked: the owner's Request
after the pump's delays, min off, StartHold, PowerUpHold and starts limit
(own Run / Start / Exercise ignored, warning); Stop holds it off until the
owner's run drops. Auto: Run per set.run.style, Start / Stop. Inhibit is
never overridden (decision 54). Interlock FALSE holds the motor and stops.

Protections: pressure / flow / suction four levels each (UT_MEAS: switches
on the pins, values and bands through the plugs; a bad reading is ridden
through, then sensorBad), seal leak, external fault, prime timeout, max
run, start fail (asked, motor ready, not running), dropped (stopped by
itself while asked: WARN latched until Reset, never holds the pump).
Prime: on every start (prime.enable) or the next (PrimeNext / cmdPrimeNext; withdrawn by PrimeCancel /
cmdPrimeCancel before that start - a prime already running carries on),
done by pressure L clear, flow L clear, the PrimeDone pin, or a time; the
low levels with maskAtStart are masked while priming and for startMask.
Starts limit (set.starts): an owner's overflow call (Request Urgent) starts at
once (overflow protection beats anti-cycling). Otherwise a start waits for a permit ("Waiting: starts
limit"), counted as waiting by the owner, never as missing. Exercise: an
idle pump in Auto not linked runs exerciseTime after exerciseInterval.
ExpectAuto (e.g. the system in Auto): warning "not in Auto" while the pump
or its motor is in Off or Hand. Settings kept; a bad write is put back. Run hours and starts are the
motor's. *)

FUNCTION_BLOCK UT_PUMP IMPLEMENTS UT_I_STATUS
  VAR_INPUT
    Run : BOOL; (* Auto run request per set.run.style; ignored while linked *)
    Start : BOOL R_EDGE; (* Hand start / latched Auto start (not linked) *)
    Stop : BOOL R_EDGE; (* stop in Hand and Auto; linked: held off until the owner's run drops *)
    Reset : BOOL R_EDGE; (* reset pump trips whose cause has gone; clears `dropped` *)
    Interlock : BOOL := TRUE; (* FALSE: the motor is held and the pump stops *)
    Permissive : BOOL := TRUE; (* FALSE blocks a start; not available *)
    Inhibit : BOOL; (* locked out for a reason: stops, unavailable, never overridden *)
    Mode : INT := -1; (* 0 Off, 1 Hand, 2 Auto *)
    SwHand : BOOL;
    SwAuto : BOOL;
    StartHold : BOOL; (* a start waits (Auto and Hand); stays available *)
    ExpectAuto : BOOL; (* warning "not in Auto" while TRUE and the pump or its motor is not in Auto *)
    PowerUpHold : BOOL; (* power-on delay: a start waits; dry run / suction low masked *)
    PrimeNext : BOOL R_EDGE; (* prime on the next start only *)
    PrimeCancel : BOOL R_EDGE; (* withdraw PrimeNext before that start *)
    Exercise : BOOL R_EDGE; (* exercise run now (idle, Auto, not linked) *)
    PrimeDone : BOOL; (* pipe filled (prime.doneBy INPUT) *)
    PressureHigh : BOOL; (* pressure switches (pressure.highSwitch / lowSwitch) *)
    PressureLow : BOOL;
    FlowSwitch : BOOL; (* TRUE = flow *)
    DryRun : BOOL; (* dry-run float / probe (suction LL) *)
    SealLeak : BOOL;
    ExtFault : BOOL;
    Speed : REAL := -1.0; (* VSD speed % when the owner gives none; < 0 = the motor's own *)
    Motor : UT_I_MOTOR; (* the motor instance; required *)
    Pressure : UT_I_MEAS; (* NULL = not fitted *)
    Flow : UT_I_MEAS;
    Suction : UT_I_MEAS;
  END_VAR
  VAR_OUTPUT
    Running : BOOL;
    Ready : BOOL;
    Available : BOOL;
    Auto : BOOL; (* pump AND motor in Auto *)
    Hand : BOOL; (* pump OR motor in Hand *)
    Linked : BOOL;
    Priming : BOOL;
    FlowProven : BOOL; (* running, past mask and prime, flow L clear *)
    Fault : BOOL;
    Warning : BOOL;
    State : UT_STATE;
  END_VAR
  VAR_IN_OUT
    Data : UT_PUMP_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_PUMP_SET;
    keptGood : BOOL;
  END_VAR
  VAR
    keep : UT_KEEP;
    modeSel : UT_MODE_SELECT;
    runIn : UT_RUN_INPUT;
    lim : UT_START_LIMIT;
    mP : UT_MEAS_ST;
    mF : UT_MEAS_ST;
    mS : UT_MEAS_ST;
    pSeal : UT_PROT_ST;
    pExt : UT_PROT_ST;
    pPrime : UT_PROT_ST;
    pMaxRun : UT_PROT_ST;
    pStartFail : UT_PROT_ST;
    pDropped : UT_PROT_ST;
    ok : BOOL;
    cfgF : UT_FAULT;
    cfgW : UT_FAULT;
    cfgOn : BOOL;
    cfgWhich : UT_FAULT;
    tCur : TIME;
    started : BOOL;
    x : BOOL;
    resetReq : BOOL;
    hReset : BOOL;
    hStart : BOOL;
    hStop : BOOL;
    hEx : BOOL;
    hPrime : BOOL;
    hPrimeCancel : BOOL;
    primeEnd : TIME; (* when this prime ends at the latest (run time by TIME, else the timeout) *)
    cStart : BOOL;
    cStop : BOOL;
    exReq : BOOL;
    handNow : BOOL;
    autoNow : BOOL;
    motorOk : BOOL; (* a motor is linked *)
    mAutoNow : BOOL; (* the motor is in Auto *)
    mHandNow : BOOL;
    mReady : BOOL;
    mRunning : BOOL;
    mRestartIn : TIME;
    v : REAL;
    g : BOOL;
    hasV : BOOL;
    fit : BOOL;
    bHH : BOOL;
    bH : BOOL;
    bL : BOOL;
    bLL : BOOL;
    lnkP : BOOL;
    lnkF : BOOL;
    lnkS : BOOL;
    missP : BOOL; (* a sensor chosen in the settings whose plug says it is not on this site *)
    missF : BOOL;
    missS : BOOL;
    runningPrev : BOOL;
    runAt : TIME;
    primeAt : TIME;
    primed : BOOL;
    primeThis : BOOL;
    primeCond : BOOL;
    primeCondPrev : BOOL;
    primeCondAt : TIME;
    masked : BOOL;
    tripped : BOOL;
    warned : BOOL;
    tripMask : DWORD;
    warnMask : DWORD;
    firstTrip : INT;
    firstWarn : INT;
    i : INT;
    want : BOOL;
    wantPrev : BOOL;
    wantAt : TIME;
    demandOn : BOOL;
    handLatch : BOOL;
    stopHold : BOOL;
    ignored : BOOL;
    lastRunAt : TIME;
    exercising : BOOL;
    exAt : TIME;
    exDone : BOOL;
    runCmd : BOOL;
    runCmdAt : TIME;
    stopAt : TIME;
    runCmdPrev : BOOL;
    runningPrevSr : BOOL;
    runEnded : BOOL;
    selfStop : BOOL; (* the pump itself dropped its command this scan *)
    stopWhy : UT_STOP;
    hold : BOOL;
    reqSpeed : REAL;
    waitNow : BOOL;
    trippedPrev : BOOL;
    stCode : UT_STATUS;
    stF : UT_FAULT;
    tLeft : TIME;
    shownSt : UT_STATUS;
    shownF : UT_FAULT;
    zero : REAL;
    nan : REAL;
    linkCalls : INT;
    linkLapse : INT := 2;
    linkRun : BOOL;
    linkHold : BOOL;
    linkUrgent : BOOL; (* the owner's call is an overflow: the starts limit does not hold it *)
    linkSpeedIn : REAL;
    linkOwner : STRING(12);
    twoOwners : BOOL;
    qReady : BOOL;
    qAvail : BOOL;
    qWaiting : BOOL;
    qStartsHeld : BOOL;
    qExercising : BOOL;
    qAuto : BOOL;
    qHand : BOOL;
    qVsd : BOOL;
    qSpeed : REAL;
    qHours : LREAL;
    qCapacity : REAL;
    qRole : UT_PUMP_ROLE;
    qPriming : BOOL;
    qRestartIn : TIME;
    qStatus : UT_STATUS;
    qFault : UT_FAULT;
    qStop : UT_STOP;
    qLocked : BOOL;
    qNe : UT_NE107;
  END_VAR


METHOD PUBLIC Request : BOOL
  VAR_INPUT
    ReqRun : BOOL;
    Hold : BOOL;
    ReqSpeed : REAL;
    Owner : STRING(12);
    Urgent : BOOL;                 // an overflow call: the start does not wait for the starts limit
  END_VAR
  linkCalls := linkCalls + 1;
  linkUrgent := Urgent;
  linkRun := ReqRun;
  linkHold := Hold;
  linkSpeedIn := ReqSpeed;
  linkOwner := Owner;
  Request := NOT cfgOn AND linkCalls <= 1;
END_METHOD
METHOD PUBLIC IsRunning : BOOL
  IsRunning := Running;
END_METHOD
METHOD PUBLIC IsReady : BOOL
  IsReady := qReady;
END_METHOD
METHOD PUBLIC IsAvailable : BOOL
  IsAvailable := qAvail;
END_METHOD
METHOD PUBLIC IsWaiting : BOOL
  IsWaiting := qWaiting;
END_METHOD
METHOD PUBLIC StartsHeld : BOOL
  StartsHeld := qStartsHeld;
END_METHOD
METHOD PUBLIC IsExercising : BOOL
  IsExercising := qExercising;
END_METHOD
METHOD PUBLIC IsAuto : BOOL
  IsAuto := qAuto;
END_METHOD
METHOD PUBLIC IsHand : BOOL
  IsHand := qHand;
END_METHOD
METHOD PUBLIC IsVsd : BOOL
  IsVsd := qVsd;
END_METHOD
METHOD PUBLIC GetSpeed : REAL
  GetSpeed := qSpeed;
END_METHOD
METHOD PUBLIC RunHours : LREAL
  RunHours := qHours;
END_METHOD
METHOD PUBLIC Capacity : REAL
  Capacity := qCapacity;
END_METHOD
METHOD PUBLIC Role : UT_PUMP_ROLE
  Role := qRole;
END_METHOD
METHOD PUBLIC IsPriming : BOOL
  IsPriming := qPriming;
END_METHOD
METHOD PUBLIC RestartIn : TIME
  RestartIn := qRestartIn;
END_METHOD
METHOD PUBLIC StatusCode : UT_STATUS
  StatusCode := qStatus;
END_METHOD
METHOD PUBLIC FaultId : UT_FAULT
  FaultId := qFault;
END_METHOD
METHOD PUBLIC StopReason : UT_STOP
  StopReason := qStop;
END_METHOD
METHOD PUBLIC HasFault : BOOL
  HasFault := Fault;
END_METHOD
METHOD PUBLIC HasWarning : BOOL
  HasWarning := Warning;
END_METHOD
METHOD PUBLIC IsLocked : BOOL
  IsLocked := qLocked;
END_METHOD
METHOD PUBLIC IsFitted : BOOL
  IsFitted := TRUE;
END_METHOD
METHOD PUBLIC Ne107 : UT_NE107
  Ne107 := qNe;
END_METHOD

tCur := TIME();
keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
IF NOT started THEN
  started := TRUE;
  stopAt := tCur;
  runCmdAt := tCur;
  lastRunAt := tCur;
  nan := zero / zero;
END_IF;
ok := UT_PUMP_CHECK(S := Data.set, Fault => cfgF, Warn => cfgW);
IF NOT ok AND keptGood AND NOT keep.FirstBoot THEN
  IF cfgF <> UT_F_NONE THEN Data.sts.refused := cfgF; ELSE Data.sts.refused := cfgW; END_IF;
  Data.sts.refusedWhy := UT_F_SETTING;
  Data.set := keptSet;
  ok := UT_PUMP_CHECK(S := Data.set, Fault => cfgF, Warn => cfgW);
END_IF;
IF keep.SaveSet AND (ok OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := ok;
END_IF;

(* the link *)
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
  linkSpeedIn := nan;
END_IF;

(* the motor *)
motorOk := Motor <> NULL;
IF motorOk THEN
  mAutoNow := Motor.IsAuto();
  mHandNow := Motor.IsHand();
  mReady := Motor.IsReady();
  mRunning := Motor.IsRunning();
  mRestartIn := Motor.RestartIn();
  qVsd := Motor.IsVsd();
  qSpeed := Motor.GetSpeed();
  qHours := Motor.RunHours();
ELSE
  mAutoNow := FALSE;
  mHandNow := FALSE;
  mReady := FALSE;
  mRunning := FALSE;
  mRestartIn := T#0s;
  qVsd := FALSE;
  qSpeed := 0.0;
  qHours := 0.0;
END_IF;
Running := mRunning;

(* the mode, commands *)
modeSel(SwAuto := SwAuto, SwHand := SwHand, ForceOff := FALSE, HandOn := FALSE, HandToOff := FALSE,
        AllowOOS := FALSE, Source := Data.set.modeSource, ModeReq := Mode, PowerUp := Data.set.powerUp,
        HandPowerUp := UT_HPU_KEEP, HandMax := T#0s, CmdMode := Data.cmdMode, Choice := Data.set.mode);
handNow := modeSel.Mode = UT_MODE_HAND;
autoNow := modeSel.Mode = UT_MODE_AUTO;
resetReq := Reset OR (Data.cmdReset AND NOT hReset) OR (Data.set.resetByOff AND modeSel.EnteredOff);
hReset := Data.cmdReset;
Data.cmdReset := FALSE;
cStart := Data.cmdStart AND NOT hStart;
hStart := Data.cmdStart;
Data.cmdStart := FALSE;
cStop := Data.cmdStop AND NOT hStop;
hStop := Data.cmdStop;
Data.cmdStop := FALSE;
exReq := Exercise OR (Data.cmdExercise AND NOT hEx);
hEx := Data.cmdExercise;
Data.cmdExercise := FALSE;
IF PrimeNext OR (Data.cmdPrimeNext AND NOT hPrime) THEN
  Data.sts.primeNext := TRUE;
END_IF;
hPrime := Data.cmdPrimeNext;
Data.cmdPrimeNext := FALSE;
IF PrimeCancel OR (Data.cmdPrimeCancel AND NOT hPrimeCancel) THEN
  Data.sts.primeNext := FALSE;   (* the request withdrawn; a prime already running carries on *)
END_IF;
hPrimeCancel := Data.cmdPrimeCancel;
Data.cmdPrimeCancel := FALSE;

(* prime and the start mask, from the moment the motor is seen running *)
IF Running AND NOT runningPrev THEN
  runAt := tCur;
  primeAt := tCur;
  primed := FALSE;
  primeCondPrev := FALSE;
  primeThis := Data.set.prime.enable OR Data.sts.primeNext;
END_IF;
runningPrev := Running;
IF primeThis AND Running AND NOT primed THEN
  CASE Data.set.prime.doneBy OF
  UT_PRIME_FLOW:
    primeCond := Data.sts.flow.good AND NOT (mF.l.trip OR mF.l.warn OR mF.ll.trip OR mF.ll.warn)
                 AND (Flow <> NULL OR FlowSwitch);
  UT_PRIME_INPUT:
    primeCond := PrimeDone;
  UT_PRIME_TIME:
    primeCond := tCur - primeAt >= Data.set.prime.runTime;
  ELSE
    primeCond := Data.sts.pressure.good AND (Pressure <> NULL OR NOT PressureLow)
                 AND NOT (Pressure <> NULL AND Data.sts.pressure.value <= Data.set.pressure.lo.sp);
  END_CASE;
  IF primeCond AND NOT primeCondPrev THEN
    primeCondAt := tCur;
  END_IF;
  primeCondPrev := primeCond;
  IF primeCond AND (tCur - primeCondAt >= Data.set.prime.holdTime OR Data.set.prime.doneBy = UT_PRIME_TIME) THEN
    primed := TRUE;
    Data.sts.primeNext := FALSE;
  END_IF;
  IF Data.set.prime.doneBy <> UT_PRIME_TIME AND tCur - primeAt >= Data.set.prime.timeout THEN
    primed := TRUE;              (* priming always ends at the timeout; primeTimeout acts per its response *)
    Data.sts.primeNext := FALSE;
  END_IF;
END_IF;
Priming := primeThis AND Running AND NOT primed;
masked := Priming OR (Running AND tCur - runAt < Data.set.startMask) OR PowerUpHold;

(* the measurements *)
x := UT_MEAS_READ(Sensor := Pressure, In := nan, InGood := TRUE, V => v, G => g, HasValue => hasV, Fitted => fit,
                  BandHH => bHH, BandH => bH, BandL => bL, BandLL => bLL);
lnkP := Pressure <> NULL;
missP := UT_MEAS_MISSING(Linked := lnkP, Fitted := fit, M := Data.set.pressure);
IF NOT lnkP THEN hasV := FALSE; END_IF;
x := UT_MEAS_RUN(TNow := tCur, In := v, Good := g, HasValue := hasV, Fitted := fit, Linked := lnkP,
                 HighSwitch := PressureHigh, LowSwitch := PressureLow, BandHH := bHH, BandH := bH, BandL := bL, BandLL := bLL,
                 Running := Running, Masked := masked, ResetReq := resetReq, RetryWindow := Data.set.retryWindow,
                 Meas := Data.set.pressure, Sts := Data.sts.pressure, St := mP);
x := UT_MEAS_READ(Sensor := Flow, In := nan, InGood := TRUE, V => v, G => g, HasValue => hasV, Fitted => fit,
                  BandHH => bHH, BandH => bH, BandL => bL, BandLL => bLL);
lnkF := Flow <> NULL;
missF := UT_MEAS_MISSING(Linked := lnkF, Fitted := fit, M := Data.set.flow);
IF NOT lnkF THEN hasV := FALSE; END_IF;
x := UT_MEAS_RUN(TNow := tCur, In := v, Good := g, HasValue := hasV, Fitted := fit, Linked := lnkF,
                 HighSwitch := FALSE, LowSwitch := NOT FlowSwitch, BandHH := bHH, BandH := bH, BandL := bL, BandLL := bLL,
                 Running := Running, Masked := masked, ResetReq := resetReq, RetryWindow := Data.set.retryWindow,
                 Meas := Data.set.flow, Sts := Data.sts.flow, St := mF);
x := UT_MEAS_READ(Sensor := Suction, In := nan, InGood := TRUE, V => v, G => g, HasValue => hasV, Fitted => fit,
                  BandHH => bHH, BandH => bH, BandL => bL, BandLL => bLL);
lnkS := Suction <> NULL;
missS := UT_MEAS_MISSING(Linked := lnkS, Fitted := fit, M := Data.set.suction);
IF NOT lnkS THEN hasV := FALSE; END_IF;
x := UT_MEAS_RUN(TNow := tCur, In := v, Good := g, HasValue := hasV, Fitted := fit, Linked := lnkS,
                 HighSwitch := FALSE, LowSwitch := DryRun AND NOT PowerUpHold, BandHH := bHH, BandH := bH, BandL := bL,
                 BandLL := bLL AND NOT PowerUpHold, Running := Running, Masked := masked, ResetReq := resetReq,
                 RetryWindow := Data.set.retryWindow, Meas := Data.set.suction, Sts := Data.sts.suction, St := mS);

(* the pump's other protections *)
x := UT_PROT_RUN(TNow := tCur, Cause := SealLeak, ResetReq := resetReq, RetryWindow := Data.set.retryWindow,
                 Prot := Data.set.sealLeak, Sts := Data.sts.sealLeak, St := pSeal);
x := UT_PROT_RUN(TNow := tCur, Cause := ExtFault, ResetReq := resetReq, RetryWindow := Data.set.retryWindow,
                 Prot := Data.set.extFault, Sts := Data.sts.extFault, St := pExt);
x := UT_PROT_RUN(TNow := tCur, Cause := primeThis AND Running AND Data.set.prime.doneBy <> UT_PRIME_TIME
                                        AND NOT primeCond AND tCur - primeAt >= Data.set.prime.timeout
                                        AND Data.sts.primeNext = FALSE AND NOT (primed AND primeCond),
                 ResetReq := resetReq, RetryWindow := Data.set.retryWindow, Prot := Data.set.primeTimeout,
                 Sts := Data.sts.primeTimeout, St := pPrime);
x := UT_PROT_RUN(TNow := tCur, Cause := Running AND runCmd, ResetReq := resetReq, RetryWindow := Data.set.retryWindow,
                 Prot := Data.set.maxRun, Sts := Data.sts.maxRun, St := pMaxRun);
x := UT_PROT_RUN(TNow := tCur, Cause := runCmd AND mAutoNow AND NOT mRunning AND mRestartIn = T#0s
                                        AND NOT (motorOk AND Motor.HasFault()),
                 ResetReq := resetReq, RetryWindow := Data.set.retryWindow, Prot := Data.set.startFail,
                 Sts := Data.sts.startFail, St := pStartFail);
x := UT_PROT_RUN(TNow := tCur, Cause := runningPrevSr AND NOT Running AND runCmdPrev AND runCmd AND mAutoNow,
                 ResetReq := resetReq, RetryWindow := Data.set.retryWindow, Prot := Data.set.dropped,
                 Sts := Data.sts.dropped, St := pDropped);

(* config *)
cfgOn := cfgF <> UT_F_NONE OR NOT motorOk OR twoOwners OR missP OR missF OR missS;
IF twoOwners THEN
  cfgWhich := UT_F_TWO_OWNERS;
ELSIF NOT motorOk THEN
  cfgWhich := UT_F_NO_LINK;
ELSIF cfgF = UT_F_NONE AND missP THEN
  cfgWhich := UT_F_PRESSURE_SENSOR;
ELSIF cfgF = UT_F_NONE AND missF THEN
  cfgWhich := UT_F_FLOW_SENSOR;
ELSIF cfgF = UT_F_NONE AND missS THEN
  cfgWhich := UT_F_SUCTION_SENSOR;
ELSE
  cfgWhich := cfgF;
END_IF;

(* every protection in priority order (bit i); dropped only warns *)
tripMask := 0;
warnMask := 0;
firstTrip := -1;
firstWarn := -1;
FOR i := 0 TO 22 DO
  x := FALSE;
  g := FALSE;
  CASE i OF
  0: x := mS.ll.trip; g := mS.ll.warn;
  1: x := mP.hh.trip; g := mP.hh.warn;
  2: x := mP.ll.trip; g := mP.ll.warn;
  3: x := mF.ll.trip; g := mF.ll.warn;
  4: x := mF.hh.trip; g := mF.hh.warn;
  5: x := mS.hh.trip; g := mS.hh.warn;
  6: x := pPrime.trip; g := pPrime.warn;
  7: x := pExt.trip; g := pExt.warn;
  8: x := pMaxRun.trip; g := pMaxRun.warn;
  9: x := pSeal.trip; g := pSeal.warn;
  10: x := mP.h.trip; g := mP.h.warn;
  11: x := mP.l.trip; g := mP.l.warn;
  12: x := mF.h.trip; g := mF.h.warn;
  13: x := mF.l.trip; g := mF.l.warn;
  14: x := mS.h.trip; g := mS.h.warn;
  15: x := mS.l.trip; g := mS.l.warn;
  18: x := cfgOn; g := cfgW <> UT_F_NONE OR mP.badSetting OR mF.badSetting OR mS.badSetting;
  19: x := mP.sb.trip OR mF.sb.trip OR mS.sb.trip;
      g := mP.sb.warn OR mF.sb.warn OR mS.sb.warn OR mP.goodHeld OR mF.goodHeld OR mS.goodHeld;
  20: x := pStartFail.trip; g := pStartFail.warn;
  21: g := pDropped.trip OR pDropped.warn OR Data.sts.dropped.tripped;
  22: g := ExpectAuto AND NOT (autoNow AND mAutoNow);
  END_CASE;
  IF x THEN
    tripMask := tripMask OR SHL(DWORD#1, i);
    IF firstTrip < 0 THEN firstTrip := i; END_IF;
  ELSIF g THEN
    warnMask := warnMask OR SHL(DWORD#1, i);
    IF firstWarn < 0 THEN firstWarn := i; END_IF;
  END_IF;
END_FOR;
tripped := tripMask <> 0;
warned := warnMask <> 0;

(* diagnosis *)
IF (mP.hiHi OR mP.hi) AND (mF.loLo OR mF.lo) THEN
  Data.sts.diagnosis := UT_DIAG_BLOCKED;
ELSIF (mP.loLo OR mP.lo) AND (mF.hiHi OR mF.hi) THEN
  Data.sts.diagnosis := UT_DIAG_BURST;
ELSIF mS.lo OR mS.loLo THEN
  Data.sts.diagnosis := UT_DIAG_SUCTION;
ELSIF (mP.loLo OR mP.lo) AND (mF.loLo OR mF.lo) THEN
  Data.sts.diagnosis := UT_DIAG_NO_LIFT;
ELSE
  Data.sts.diagnosis := UT_DIAG_NORMAL;
END_IF;

(* the request, per mode *)
runIn(Run := Run, Start := Start, Stop := Stop, CmdStart := cStart, CmdStop := cStop,
      Drop := NOT autoNow OR NOT Interlock OR tripped OR Inhibit, Linked := Linked, TargetDone := FALSE,
      HasTarget := FALSE, Set := Data.set.run);
ignored := FALSE;
hold := FALSE;
IF handNow THEN
  IF Stop OR cStop OR NOT Interlock OR tripped OR Inhibit THEN
    handLatch := FALSE;
  ELSIF (Start OR cStart) AND NOT modeSel.Changed THEN
    handLatch := TRUE;
  END_IF;
  want := handLatch;
  stopHold := FALSE;
ELSIF autoNow AND Linked THEN
  handLatch := FALSE;
  ignored := Run OR Start OR exReq;
  IF Stop OR cStop THEN
    stopHold := TRUE;
  END_IF;
  IF NOT linkRun THEN
    stopHold := FALSE;
  END_IF;
  hold := linkHold;
  want := linkRun AND NOT linkHold AND NOT stopHold;
ELSIF autoNow THEN
  handLatch := FALSE;
  stopHold := FALSE;
  want := runIn.Request AND NOT runIn.BadSetting;
ELSE
  handLatch := FALSE;
  stopHold := FALSE;
  want := FALSE;
END_IF;

(* start and stop delays (Auto) *)
IF want <> wantPrev THEN
  wantAt := tCur;
END_IF;
wantPrev := want;
IF handNow THEN
  demandOn := want;
ELSIF want AND tCur - wantAt >= Data.set.startDelay THEN
  demandOn := TRUE;
ELSIF NOT want AND tCur - wantAt >= Data.set.stopDelay THEN
  demandOn := FALSE;
END_IF;

(* the starts limit *)
lim(Running := Running, Failed := pStartFail.event, Reset := resetReq, Set := Data.set.starts);

(* available: the pump and its motor in Auto, no trip, interlock / permissive made, not inhibited *)
Available := autoNow AND mAutoNow AND NOT tripped AND NOT Inhibit AND Interlock AND (Permissive OR Running)
             AND motorOk AND NOT cfgOn AND (mReady OR Running OR (Motor.IsAvailable()));

(* exercise: idle, Auto, not linked *)
IF Running THEN
  lastRunAt := tCur;
END_IF;
IF NOT exercising THEN
  IF Available AND NOT Linked AND NOT demandOn AND NOT Running
     AND (exReq OR (Data.set.exerciseInterval > T#0s AND tCur - lastRunAt >= Data.set.exerciseInterval)) THEN
    exercising := TRUE;
    exAt := tCur;
  END_IF;
ELSIF demandOn OR NOT Available OR Linked OR tCur - exAt >= Data.set.exerciseTime THEN
  exDone := NOT demandOn AND Available AND NOT Linked AND tCur - exAt >= Data.set.exerciseTime;
  exercising := FALSE;
  lastRunAt := tCur;
END_IF;

(* the run command *)
selfStop := FALSE;
IF runCmd THEN
  IF tripped OR Inhibit OR NOT Interlock OR hold OR (handNow AND NOT demandOn)
     OR (NOT demandOn AND NOT exercising AND tCur - runCmdAt >= Data.set.minRunTime)
     OR NOT (autoNow OR handNow) THEN
    runCmd := FALSE;
    stopAt := tCur;
    selfStop := TRUE;
  END_IF;
ELSIF (demandOn OR exercising) AND NOT tripped AND NOT Inhibit AND Interlock AND Permissive AND NOT StartHold
      AND NOT PowerUpHold AND (lim.Permit OR handNow OR (Linked AND linkUrgent)) AND (tCur - stopAt >= Data.set.minOffTime OR handNow) THEN
  runCmd := TRUE;
  runCmdAt := tCur;
  exDone := FALSE;
END_IF;
waitNow := (demandOn OR exercising OR want) AND NOT runCmd AND NOT tripped AND NOT Inhibit;

(* the motor follows only while it is in Auto (decision 55) *)
IF motorOk THEN
  IF qVsd AND linkSpeedIn = linkSpeedIn AND Linked THEN
    reqSpeed := linkSpeedIn;
  ELSIF Speed >= 0.0 THEN
    reqSpeed := Speed;
  ELSE
    reqSpeed := nan;
  END_IF;
  x := Motor.Request(ReqRun := runCmd, Hold := tripped OR Inhibit OR NOT Interlock OR hold, ReqSpeed := reqSpeed,
                     Owner := Data.set.tag);
END_IF;

(* why the last run ended *)
stopWhy := UT_STOP_NONE;
IF (runCmd AND NOT runCmdPrev) OR (Running AND NOT runningPrevSr) THEN
  runEnded := FALSE;
END_IF;
IF runCmdPrev AND NOT runCmd AND NOT runEnded AND (mAutoNow OR NOT Running) THEN
  IF tripped AND firstTrip = 8 THEN
    stopWhy := UT_STOP_MAX_RUN;
  ELSIF tripped THEN
    stopWhy := UT_STOP_FAULT;
  ELSIF Inhibit THEN
    stopWhy := UT_STOP_INHIBITED;
  ELSIF NOT Interlock THEN
    stopWhy := UT_STOP_INTERLOCK;
  ELSIF hold THEN
    stopWhy := UT_STOP_HELD_BY_LINK;
  ELSIF exDone THEN
    stopWhy := UT_STOP_EXERCISE_DONE;
  ELSIF handNow OR stopHold THEN
    stopWhy := UT_STOP_OPERATOR;
  ELSIF NOT (autoNow OR handNow) THEN
    stopWhy := UT_STOP_SWITCHED_OFF;
  ELSE
    stopWhy := UT_STOP_DEMAND_ENDED;
  END_IF;
ELSIF runningPrevSr AND NOT Running AND NOT runEnded THEN
  IF NOT mAutoNow THEN
    stopWhy := UT_STOP_OPERATOR;
  ELSE
    stopWhy := UT_STOP_BY_MOTOR;
  END_IF;
END_IF;
runCmdPrev := runCmd;
runningPrevSr := Running;
IF stopWhy <> UT_STOP_NONE THEN
  runEnded := TRUE;
  Data.sts.stopReason := stopWhy;
END_IF;

(* outputs *)
Fault := tripped;
Warning := warned OR ignored;
Auto := autoNow AND mAutoNow;
Hand := handNow OR mHandNow;
Ready := (autoNow OR handNow) AND motorOk AND mReady AND NOT tripped AND NOT Inhibit AND Interlock AND Permissive
         AND NOT StartHold AND NOT PowerUpHold AND (lim.Permit OR (Linked AND linkUrgent)) AND (tCur - stopAt >= Data.set.minOffTime OR Running);
FlowProven := Running AND NOT masked AND NOT Priming AND NOT (mF.l.trip OR mF.l.warn OR mF.ll.trip OR mF.ll.warn)
              AND (lnkF OR Data.set.flow.installed);
IF Running THEN
  Data.det.runTime := tCur - runAt;
  Data.det.idleTime := T#0s;
  Data.det.phaseTime := Data.det.runTime;
ELSE
  Data.det.idleTime := tCur - lastRunAt;
  Data.det.phaseTime := Data.det.idleTime;
END_IF;
IF Data.set.exerciseInterval > T#0s AND NOT Running AND NOT exercising AND Data.set.exerciseInterval > tCur - lastRunAt THEN
  Data.det.nextExerciseIn := Data.set.exerciseInterval - (tCur - lastRunAt);
ELSE
  Data.det.nextExerciseIn := T#0s;
END_IF;
(* the prime's time left: done by TIME it ends at its run time (no timeout); otherwise at the latest at its timeout *)
IF Data.set.prime.doneBy = UT_PRIME_TIME THEN
  primeEnd := Data.set.prime.runTime;
ELSE
  primeEnd := Data.set.prime.timeout;
END_IF;
IF Priming AND primeEnd > tCur - primeAt THEN
  Data.det.primeLeft := primeEnd - (tCur - primeAt);
ELSE
  Data.det.primeLeft := T#0s;
END_IF;
IF Data.set.maxRun.response <> UT_RESP_OFF AND Running AND NOT pMaxRun.trip AND Data.set.maxRun.delay > tCur - runAt THEN
  Data.det.maxRunLeft := Data.set.maxRun.delay - (tCur - runAt);
ELSE
  Data.det.maxRunLeft := T#0s;
END_IF;
Data.det.permitIn := lim.PermitIn;
IF tripped THEN
  State := UT_STATE_FAULT;
ELSIF runCmd AND NOT Running THEN
  State := UT_STATE_STARTING;
ELSIF Running AND warned THEN
  State := UT_STATE_WARNING;
ELSIF Running AND (runCmd OR NOT mAutoNow) THEN
  State := UT_STATE_ON;
ELSIF Running THEN
  State := UT_STATE_STOPPING;
ELSIF (Inhibit OR NOT Permissive OR NOT Interlock) AND want THEN
  State := UT_STATE_INTERLOCKED;
ELSE
  State := UT_STATE_OFF;
END_IF;

(* fault code and names *)
Data.sts.faultCode := tripMask OR warnMask;
IF firstTrip < 0 THEN
  firstTrip := firstWarn;
END_IF;
CASE firstTrip OF
0: stF := UT_F_DRY_RUN;
1: stF := UT_F_PRESSURE_HH;
2: stF := UT_F_PRESSURE_LL;
3: stF := UT_F_NO_FLOW;
4: stF := UT_F_FLOW_HH;
5: stF := UT_F_SUCTION_HH;
6: stF := UT_F_PRIME;
7: stF := UT_F_EXTERNAL;
8: stF := UT_F_MAX_RUN;
9: stF := UT_F_SEAL_LEAK;
10: stF := UT_F_PRESSURE_H;
11: stF := UT_F_PRESSURE_L;
12: stF := UT_F_FLOW_H;
13: stF := UT_F_FLOW_L;
14: stF := UT_F_SUCTION_H;
15: stF := UT_F_SUCTION_L;
18: IF cfgOn THEN stF := cfgWhich; ELSIF cfgW <> UT_F_NONE THEN stF := cfgW; ELSE stF := UT_F_LEVEL_SETTING; END_IF;
19: stF := UT_F_SENSOR_BAD;
20: stF := UT_F_START_FAILED;
21: stF := UT_F_DROPPED;
22: stF := UT_F_NOT_AUTO;
ELSE
  stF := UT_F_NONE;
END_CASE;
IF ignored AND stF = UT_F_NONE THEN
  stF := UT_F_RUN_IGNORED;
END_IF;
IF tripped THEN
  IF NOT trippedPrev THEN
    Data.sts.trips := Data.sts.trips + 1;
  END_IF;
  Data.sts.lastFaultCode := tripMask;
  Data.sts.lastFault := stF;
END_IF;
trippedPrev := tripped;

(* status: config, fault, held, warning, normal, idle *)
tLeft := T#0s;
IF cfgOn THEN
  stCode := UT_ST_CONFIG;
ELSIF tripped THEN
  CASE firstTrip OF
  0: stCode := UT_PROT_STATUS(Reset := Data.set.suction.loLo.reset, Sts := Data.sts.suction.loLo); tLeft := Data.sts.suction.loLo.timeLeft;
  1: stCode := UT_PROT_STATUS(Reset := Data.set.pressure.hiHi.reset, Sts := Data.sts.pressure.hiHi); tLeft := Data.sts.pressure.hiHi.timeLeft;
  2: stCode := UT_PROT_STATUS(Reset := Data.set.pressure.loLo.reset, Sts := Data.sts.pressure.loLo); tLeft := Data.sts.pressure.loLo.timeLeft;
  3: stCode := UT_PROT_STATUS(Reset := Data.set.flow.loLo.reset, Sts := Data.sts.flow.loLo); tLeft := Data.sts.flow.loLo.timeLeft;
  4: stCode := UT_PROT_STATUS(Reset := Data.set.flow.hiHi.reset, Sts := Data.sts.flow.hiHi); tLeft := Data.sts.flow.hiHi.timeLeft;
  5: stCode := UT_PROT_STATUS(Reset := Data.set.suction.hiHi.reset, Sts := Data.sts.suction.hiHi); tLeft := Data.sts.suction.hiHi.timeLeft;
  6: stCode := UT_PROT_STATUS(Reset := Data.set.primeTimeout.reset, Sts := Data.sts.primeTimeout); tLeft := Data.sts.primeTimeout.timeLeft;
  7: stCode := UT_PROT_STATUS(Reset := Data.set.extFault.reset, Sts := Data.sts.extFault); tLeft := Data.sts.extFault.timeLeft;
  8: stCode := UT_PROT_STATUS(Reset := Data.set.maxRun.reset, Sts := Data.sts.maxRun); tLeft := Data.sts.maxRun.timeLeft;
  9: stCode := UT_PROT_STATUS(Reset := Data.set.sealLeak.reset, Sts := Data.sts.sealLeak); tLeft := Data.sts.sealLeak.timeLeft;
  20: stCode := UT_PROT_STATUS(Reset := Data.set.startFail.reset, Sts := Data.sts.startFail); tLeft := Data.sts.startFail.timeLeft;
  ELSE
    stCode := UT_ST_FAULT;
  END_CASE;
ELSIF mHandNow THEN
  stCode := UT_ST_MOTOR_IN_HAND;   (* the motor's own Hand bypasses all pump control *)
ELSIF (want OR Run) AND Inhibit AND NOT Running THEN
  stCode := UT_ST_INHIBITED;
ELSIF NOT Interlock AND (want OR runCmd) THEN
  stCode := UT_ST_INTERLOCK;
ELSIF autoNow AND hold THEN
  stCode := UT_ST_HELD_BY_LINK;
ELSIF (want OR demandOn OR exercising OR runCmd) AND NOT Running THEN
  IF mHandNow THEN
    stCode := UT_ST_MOTOR_IN_HAND;
  ELSIF NOT mAutoNow THEN
    stCode := UT_ST_MOTOR_NOT_AUTO;
  ELSIF runCmd AND NOT mReady AND mRestartIn > T#0s THEN
    stCode := UT_ST_RESTART_DELAY;
    tLeft := mRestartIn;
  ELSIF runCmd THEN
    stCode := UT_ST_STARTING;
  ELSIF NOT demandOn AND NOT exercising THEN
    stCode := UT_ST_START_DELAY;
    tLeft := Data.set.startDelay - (tCur - wantAt);
  ELSIF NOT Permissive THEN
    stCode := UT_ST_NOT_PERMITTED;
  ELSIF PowerUpHold THEN
    stCode := UT_ST_POWER_ON_DELAY;
  ELSIF StartHold THEN
    stCode := UT_ST_START_HOLD;
  ELSIF NOT lim.Permit THEN
    stCode := UT_ST_WAIT_STARTS;
    tLeft := lim.PermitIn;
  ELSIF tCur - stopAt < Data.set.minOffTime THEN
    stCode := UT_ST_MIN_OFF;
    tLeft := Data.set.minOffTime - (tCur - stopAt);
  ELSIF NOT mReady THEN
    stCode := UT_ST_MOTOR_NOT_READY;
  ELSE
    stCode := UT_ST_STARTING;
  END_IF;
ELSIF warned OR ignored THEN
  IF firstWarn = 18 THEN
    stCode := UT_ST_WARN_SETTING;
  ELSE
    stCode := UT_ST_WARNING;
  END_IF;
ELSIF Running THEN
  IF NOT mAutoNow THEN
    stCode := UT_ST_RUN_HAND;
  ELSIF NOT runCmd THEN
    stCode := UT_ST_STOPPING;
  ELSIF Priming THEN
    stCode := UT_ST_PRIMING;
    tLeft := Data.det.primeLeft;
  ELSIF exercising THEN
    stCode := UT_ST_EXERCISING;
    tLeft := Data.set.exerciseTime - (tCur - exAt);
  ELSIF NOT demandOn AND autoNow THEN
    stCode := UT_ST_MIN_RUN;
    tLeft := Data.set.minRunTime - (tCur - runCmdAt);
  ELSIF NOT want AND autoNow THEN
    stCode := UT_ST_STOP_DELAY;
    tLeft := Data.set.stopDelay - (tCur - wantAt);
  ELSIF Linked THEN
    stCode := UT_ST_RUN_LINKED;
  ELSIF handNow THEN
    stCode := UT_ST_RUN_HAND;
  ELSE
    stCode := UT_ST_RUN_AUTO;
  END_IF;
ELSIF mHandNow THEN
  stCode := UT_ST_MOTOR_IN_HAND;
ELSIF Linked AND autoNow THEN
  stCode := UT_ST_IDLE_GROUP;
ELSIF autoNow AND NOT mAutoNow THEN
  stCode := UT_ST_OFF_NOT_AUTO;
ELSIF handNow THEN
  stCode := UT_ST_HAND_PRESS_START;
ELSIF autoNow THEN
  stCode := UT_ST_IDLE;
ELSE
  stCode := UT_ST_OFF;
END_IF;
IF tLeft < T#0s THEN
  tLeft := T#0s;
END_IF;
Data.det.timeLeft := tLeft;
IF stCode <> shownSt OR stF <> shownF OR LEN(Data.sts.statusText) = 0 THEN
  shownSt := stCode;
  shownF := stF;
  Data.sts.statusText := UT_STATUS_TEXT(stCode, stF);
END_IF;
Data.sts.statusCode := stCode;
Data.sts.faultId := stF;
Data.sts.ne107 := UT_NE107_RUN(Fault := tripped,
                               Check := NOT autoNow OR NOT mAutoNow OR mHandNow OR Inhibit OR exercising,
                               OutOfSpec := warned AND NOT pDropped.warn,
                               Maint := NOT lim.Permit OR pSeal.warn OR pDropped.warn OR Data.sts.dropped.tripped);
Data.sts.mode := modeSel.Mode;
Data.sts.state := State;
Data.sts.request := demandOn;
Data.sts.runCmd := runCmd;
Data.sts.running := Running;
Data.sts.healthy := NOT tripped;
Data.sts.available := Available;
Data.sts.ready := Ready;
Data.sts.waiting := waitNow;
Data.sts.startsHeld := NOT lim.Permit AND (demandOn OR want);
Data.sts.notAuto := ExpectAuto AND NOT (autoNow AND mAutoNow);
Data.sts.startsLeft := lim.StartsLeft;
Data.sts.priming := Priming;
Data.sts.masked := masked;
Data.sts.exercising := exercising;
Data.sts.configBad := cfgOn;
Data.sts.fault := Fault;
Data.sts.warning := Warning;
Data.sts.inhibited := Inhibit;
Data.sts.startHold := StartHold AND NOT runCmd;
Data.sts.powerUpHold := PowerUpHold;
Data.sts.flowProven := FlowProven;
Data.sts.motorInHand := mHandNow;
Data.sts.linked := Linked;
Data.sts.held := hold;
IF Linked THEN
  Data.sts.owner := linkOwner;
ELSE
  Data.sts.owner := '';
END_IF;

(* the methods' answers *)
qReady := Ready AND Auto;
qAvail := Available;
qWaiting := waitNow;
qStartsHeld := NOT lim.Permit;  (* for an owner: a start now would wait, asked or not *)
qExercising := exercising;
qAuto := Auto;
qHand := Hand;
qCapacity := Data.set.capacity;
qRole := Data.set.role;
qPriming := Priming;
IF tCur - stopAt < Data.set.minOffTime AND NOT runCmd THEN
  qRestartIn := MAX(Data.set.minOffTime - (tCur - stopAt), MAX(mRestartIn, lim.PermitIn));
ELSE
  qRestartIn := MAX(mRestartIn, lim.PermitIn);
END_IF;
qStatus := stCode;
qFault := stF;
qStop := Data.sts.stopReason;
qLocked := Data.sts.sealLeak.locked OR Data.sts.extFault.locked OR Data.sts.primeTimeout.locked
           OR Data.sts.maxRun.locked OR Data.sts.startFail.locked OR Data.sts.dropped.locked
           OR Data.sts.pressure.hiHi.locked OR Data.sts.pressure.loLo.locked OR Data.sts.flow.loLo.locked
           OR Data.sts.suction.loLo.locked;
qNe := Data.sts.ne107;

END_FUNCTION_BLOCK