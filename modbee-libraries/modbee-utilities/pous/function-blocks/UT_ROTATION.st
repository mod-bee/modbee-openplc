(* UT_ROTATION — shaft / belt speed monitor from a proximity sensor.

Watches a proximity sensor on a shaft, pulley or target wheel. Measures the
speed, and detects a stall (no pulse for stallTime while running: the sensor
stuck on or stuck off), underspeed (belt slip, overload), overspeed, and
pulses while the machine is stopped (a faulty sensor, or something else
turning it). Wire Healthy to the motor's Interlock to stop on a stall.

Speed, in speedUnit, from the pulse rate f (pulses per second):
  UT_SPD_RPM    rpm   = 60 x f / pulsesPerRev  (the default)
  UT_SPD_RPS    rev/s = f / pulsesPerRev       (Hz of the shaft)
  UT_SPD_M_MIN  m/min = 60 x f x distPerPulse  (belt / chain line speed)
  UT_SPD_M_S    m/s   = f x distPerPulse
minSpeed, maxSpeed and the speed are all in speedUnit. f is measured from
the first to the last pulse of a window at least filterTime long (one pulse
period when the shaft is slower). Between pulses f falls as 1 / (time since
the last pulse) once that is longer than the last period, so a stopping
shaft is seen slowing down; after stallTime with no pulse it is 0.
A pulse is seen once per scan: the fastest measurable rate is
1 / (2 x scan time) pulses per second; wrnTooFast is raised for 5 s whenever
pulses arrive at that limit.

An unknown speedUnit, or a line speed with distPerPulse not above 0 (or not
a number), sets wrnConfig and warning (fault bit 4): the speed reads 0 and
the under / over speed checks are off until it is fixed. The stall and
sensor checks do not need the unit and still act.

Protections (UT_PROTECTION, see conventions), fault bits:
  b0 stall       TRIP, MANUAL  running, past startDelay, no pulse for stallTime
  b1 underspeed  WARN, AUTO    running, past startDelay, below minSpeed for speedDelay
  b2 overspeed   OFF           above maxSpeed for speedDelay
  b3 sensor      WARN, AUTO    pulses while stopped, coastDown after the stop
  b4 config      warning       speedUnit / distPerPulse invalid (wrnConfig)
Reset: the Reset pin (rising edge) or cmdReset (rising edge).

The protections run as UT_PROT_RUN (state in one UT_PROT_ST each).
statusCode / faultId / statusText: a trip > a warning > starting (the start
delay, timeLeft counting) > running / coasting / stopped (codes in the doc). *)

FUNCTION_BLOCK UT_ROTATION
  VAR_INPUT
    Running : BOOL; (* machine running (UT_MOTOR.Running) *)
    Sensor : BOOL; (* proximity sensor *)
    Reset : BOOL R_EDGE; (* reset a latched fault *)
  END_VAR
  VAR_OUTPUT
    Healthy : BOOL; (* no fault -> motor Interlock *)
    Rotating : BOOL; (* pulses being seen *)
    Speed : REAL; (* in Data.set.speedUnit (default rpm) *)
    Fault : BOOL;
  END_VAR
  VAR_IN_OUT
    Data : UT_ROTATION_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_ROTATION_SET;
    keptGood : BOOL;
  END_VAR
  VAR
    keep : UT_KEEP;
    setOk : BOOL;
    started : BOOL;
    tCur : TIME;
    tPrev : TIME;
    elapsed : TIME;
    sensorPrev : BOOL;
    runPrev : BOOL;
    cmdPrev : BOOL;
    cmd : BOOL;
    resetReq : BOOL;
    edgeSeen : BOOL;
    lastEdge : TIME;
    winStart : TIME;
    winEdges : INT;
    runStart : TIME;
    stopTime : TIME;
    fastUntil : TIME;
    belowSince : TIME;
    aboveSince : TIME;
    below : BOOL;
    above : BOOL;
    ppr : INT;
    measured : REAL; (* pulse rate from the last window, pulses/s *)
    kSpd : REAL; (* speed units per (pulse/s) *)
    cfgBad : BOOL; (* speedUnit / distPerPulse invalid *)
    since : TIME;
    shown : REAL;
    decay : REAL;
    pastStart : BOOL;
    pStall : UT_PROT_ST; (* the protections' engine state (UT_PROT_RUN) *)
    pUnder : UT_PROT_ST;
    pOver : UT_PROT_ST;
    pSensor : UT_PROT_ST;
    x1 : BOOL;
    x2 : BOOL;
    x3 : BOOL;
    x4 : BOOL;
    k : INT; (* status: the protection shown, 1 stall .. 4 sensor *)
    pRst : UT_RESET_MODE;
    pRet : INT;
    pMax : INT;
    st : UT_STATUS;
    stF : UT_FAULT;
    stTime : TIME;
    shownSt : UT_STATUS;
    shownF : UT_FAULT;
    shown1 : BOOL; (* statusText has been set *)
  END_VAR


keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
setOk := Data.set.pulsesPerRev >= 1 AND Data.set.startDelay >= T#0s AND Data.set.stallTime > T#0s
         AND Data.set.minSpeed >= 0.0 AND Data.set.maxSpeed >= 0.0 AND Data.set.speedDelay >= T#0s
         AND Data.set.filterTime >= T#0s AND Data.set.coastDown >= T#0s AND Data.set.retryWindow >= T#0s
         AND UT_PROT_OK(P := Data.set.stall) AND UT_PROT_OK(P := Data.set.underspeed)
         AND UT_PROT_OK(P := Data.set.overspeed) AND UT_PROT_OK(P := Data.set.sensor);
IF NOT setOk AND keptGood AND NOT keep.FirstBoot THEN
  Data.sts.refused := UT_F_SETTING;
  Data.sts.refusedWhy := UT_F_SETTING;
  Data.set := keptSet;
  setOk := TRUE;
END_IF;
IF keep.SaveSet AND (setOk OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := setOk;
END_IF;
tCur := TIME();
IF NOT started THEN
  started := TRUE;
  tPrev := tCur;
  runStart := tCur;
  stopTime := tCur;
  fastUntil := tCur;
  sensorPrev := Sensor;
  runPrev := Running;
END_IF;
elapsed := tCur - tPrev;
tPrev := tCur;
ppr := MAX(Data.set.pulsesPerRev, 1);
CASE Data.set.speedUnit OF
UT_SPD_RPM: kSpd := 60.0 / INT_TO_REAL(ppr);
UT_SPD_RPS: kSpd := 1.0 / INT_TO_REAL(ppr);
UT_SPD_M_MIN: kSpd := 60.0 * Data.set.distPerPulse;
UT_SPD_M_S: kSpd := Data.set.distPerPulse;
ELSE
  kSpd := 0.0;
END_CASE;
cfgBad := NOT (kSpd > 0.0 AND kSpd <= 3.4E38);   (* NaN fails too *)
Data.sts.wrnConfig := cfgBad;
Data.sts.configBad := cfgBad;

IF Running AND NOT runPrev THEN
  runStart := tCur;
ELSIF runPrev AND NOT Running THEN
  stopTime := tCur;
END_IF;
runPrev := Running;

(* a pulse *)
IF Sensor AND NOT sensorPrev THEN
  IF edgeSeen AND tCur - lastEdge <= elapsed + elapsed + elapsed / 2 AND elapsed > T#0s THEN
    fastUntil := tCur + T#5s;    (* at the limit: one pulse every two scans *)
  END_IF;
  IF NOT edgeSeen OR tCur - lastEdge >= Data.set.stallTime THEN
    winStart := tCur;            (* first pulse after a stop: start measuring *)
    winEdges := 0;
    measured := 0.0;
  ELSE
    Data.period := tCur - lastEdge;
    winEdges := winEdges + 1;
    IF tCur - winStart >= Data.set.filterTime THEN
      measured := 1000.0 * INT_TO_REAL(winEdges) / LINT_TO_REAL(TIME_TO_LINT(tCur - winStart));
      winStart := tCur;
      winEdges := 0;
    END_IF;
  END_IF;
  edgeSeen := TRUE;
  lastEdge := tCur;
END_IF;
sensorPrev := Sensor;
Data.sts.wrnTooFast := tCur < fastUntil;

(* the speed shown: falls while no pulse comes, 0 after stallTime *)
shown := measured;
IF edgeSeen THEN
  since := tCur - lastEdge;
  IF since >= Data.set.stallTime THEN
    shown := 0.0;
    measured := 0.0;
  ELSIF since > Data.period AND since > T#0s THEN
    decay := 1000.0 / LINT_TO_REAL(TIME_TO_LINT(since));
    IF decay < shown THEN
      shown := decay;
    END_IF;
  END_IF;
END_IF;
IF cfgBad THEN
  shown := 0.0;
ELSE
  shown := shown * kSpd;         (* pulses/s -> speedUnit *)
END_IF;
Rotating := edgeSeen AND tCur - lastEdge < Data.set.stallTime;

(* conditions *)
pastStart := Running AND tCur - runStart >= Data.set.startDelay;
below := pastStart AND NOT cfgBad AND Data.set.minSpeed > 0.0 AND shown < Data.set.minSpeed;
IF NOT below THEN
  belowSince := tCur;
END_IF;
above := NOT cfgBad AND Data.set.maxSpeed > 0.0 AND shown > Data.set.maxSpeed;
IF NOT above THEN
  aboveSince := tCur;
END_IF;

cmd := Data.cmdReset;
Data.cmdReset := FALSE;
resetReq := (cmd AND NOT cmdPrev) OR Reset;   (* the HMI once per request *)
cmdPrev := cmd;

x1 := UT_PROT_RUN(TNow := tCur, Cause := pastStart AND (NOT edgeSeen OR tCur - lastEdge >= Data.set.stallTime)
                                         AND tCur - runStart >= Data.set.stallTime,
                 ResetReq := resetReq, RetryWindow := Data.set.retryWindow, Prot := Data.set.stall, Sts := Data.sts.stall, St := pStall);
x2 := UT_PROT_RUN(TNow := tCur, Cause := below AND tCur - belowSince >= Data.set.speedDelay,
                 ResetReq := resetReq, RetryWindow := Data.set.retryWindow, Prot := Data.set.underspeed, Sts := Data.sts.underspeed, St := pUnder);
x3 := UT_PROT_RUN(TNow := tCur, Cause := above AND tCur - aboveSince >= Data.set.speedDelay,
                 ResetReq := resetReq, RetryWindow := Data.set.retryWindow, Prot := Data.set.overspeed, Sts := Data.sts.overspeed, St := pOver);
x4 := UT_PROT_RUN(TNow := tCur, Cause := NOT Running AND Rotating AND tCur - stopTime >= Data.set.coastDown
                                         AND lastEdge - stopTime >= Data.set.coastDown,
                 ResetReq := resetReq, RetryWindow := Data.set.retryWindow, Prot := Data.set.sensor, Sts := Data.sts.sensor, St := pSensor);

Fault := pStall.trip OR pUnder.trip OR pOver.trip OR pSensor.trip;
Healthy := NOT Fault;
Data.sts.fault := Fault;
Data.sts.warning := pStall.warn OR pUnder.warn OR pOver.warn OR pSensor.warn OR cfgBad;
Data.sts.faultCode := 0;
IF Data.sts.stall.tripped THEN
  Data.sts.faultCode := Data.sts.faultCode OR 16#1;
END_IF;
IF Data.sts.underspeed.tripped THEN
  Data.sts.faultCode := Data.sts.faultCode OR 16#2;
END_IF;
IF Data.sts.overspeed.tripped THEN
  Data.sts.faultCode := Data.sts.faultCode OR 16#4;
END_IF;
IF Data.sts.sensor.tripped THEN
  Data.sts.faultCode := Data.sts.faultCode OR 16#8;
END_IF;
IF cfgBad THEN
  Data.sts.faultCode := Data.sts.faultCode OR 16#10;
END_IF;
Speed := shown;
Data.sts.speed := shown;
Data.sts.rotating := Rotating;

(* status: a trip > a warning > starting > running / coasting / stopped *)
k := 0;
stTime := T#0s;
stF := UT_F_NONE;
IF Fault THEN
  IF pStall.trip THEN k := 1; pRst := Data.set.stall.reset; pRet := Data.sts.stall.retries; pMax := Data.set.stall.maxRetries; stTime := Data.sts.stall.timeLeft;
  ELSIF pOver.trip THEN k := 3; pRst := Data.set.overspeed.reset; pRet := Data.sts.overspeed.retries; pMax := Data.set.overspeed.maxRetries; stTime := Data.sts.overspeed.timeLeft;
  ELSIF pUnder.trip THEN k := 2; pRst := Data.set.underspeed.reset; pRet := Data.sts.underspeed.retries; pMax := Data.set.underspeed.maxRetries; stTime := Data.sts.underspeed.timeLeft;
  ELSE k := 4; pRst := Data.set.sensor.reset; pRet := Data.sts.sensor.retries; pMax := Data.set.sensor.maxRetries; stTime := Data.sts.sensor.timeLeft;
  END_IF;
  IF pRst = UT_RST_MANUAL THEN
    st := UT_ST_FAULT_RESET;
  ELSIF pRst = UT_RST_RETRY AND pRet >= pMax THEN
    st := UT_ST_FAULT_LOCKED;
  ELSIF pRst = UT_RST_RETRY THEN
    st := UT_ST_FAULT_RETRY;
  ELSE
    st := UT_ST_FAULT;
  END_IF;
ELSIF pStall.warn OR pUnder.warn OR pOver.warn OR pSensor.warn THEN
  IF pStall.warn THEN k := 1;
  ELSIF pOver.warn THEN k := 3;
  ELSIF pUnder.warn THEN k := 2;
  ELSE k := 4;
  END_IF;
  st := UT_ST_WARNING;
ELSIF cfgBad THEN
  st := UT_ST_WARN_SETTING;
  IF Data.set.speedUnit = UT_SPD_M_MIN OR Data.set.speedUnit = UT_SPD_M_S THEN
    stF := UT_F_DIST_PER_PULSE;
  ELSE
    stF := UT_F_SPEED_UNIT;
  END_IF;
ELSIF Data.sts.wrnTooFast THEN
  st := UT_ST_WARNING;
  stF := UT_F_PULSES_FAST;
ELSIF Running AND NOT pastStart THEN
  st := UT_ST_CHECKS_DELAY;
  stTime := Data.set.startDelay - (tCur - runStart);
ELSIF Running THEN
  st := UT_ST_RUNNING;
ELSIF Rotating THEN
  st := UT_ST_STILL_TURNING;
ELSE
  st := UT_ST_STOPPED;
END_IF;
CASE k OF
1: stF := UT_F_STALLED;
2: stF := UT_F_UNDERSPEED;
3: stF := UT_F_OVERSPEED;
4: stF := UT_F_PULSES_STOPPED;
END_CASE;
IF stTime < T#0s THEN
  stTime := T#0s;
END_IF;
Data.timeLeft := stTime;
IF NOT shown1 OR st <> shownSt OR stF <> shownF THEN
  shown1 := TRUE;
  shownSt := st;
  shownF := stF;
  Data.sts.statusText := UT_STATUS_TEXT(st, stF);
END_IF;
Data.sts.statusCode := st;
Data.sts.faultId := stF;
Data.sts.ne107 := UT_NE107_RUN(Fault := Fault, Check := FALSE, OutOfSpec := Data.sts.warning, Maint := FALSE);

END_FUNCTION_BLOCK