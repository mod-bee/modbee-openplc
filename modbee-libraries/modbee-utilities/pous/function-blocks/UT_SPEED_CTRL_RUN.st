(* UT_SPEED_CTRL_RUN — the speed loop of UT_SPEED_CTRL and UT_PUMP_CASCADE
(private). The loop is today's field-proven one; this version keeps the
settings, status and detail apart, holds the loop's state in LREAL (spd,
iPart, flowCap, the output rate limit) and ramps the setpoint and the pipe
fill with UT_RAMP, so slow rates (per hour, per day) and a long ti are exact
at any task interval.

UT_SPEED_CTRL_CHECK checks the settings and the pins in use and works out
the values the loop uses (U). The block that owns the settings calls it
first: a bad setting written by an HMI / SCADA is put back from the kept
copy before the loop runs (decision 62). The loop then runs on U.

What the speed follows (control): PV, the PID on Pv (pressure or level);
FLOW, the PID on Flow; FIXED, a fixed speed (no PID; a bad sensor does not
stop it). Presets NORMAL / LOW / HIGH (a LOW or HIGH setpoint of 0 uses the
NORMAL one). Manual speed wins over all of them. highPv always watches Pv.

    Speed = kp * (e + 1/ti * integral(e dt) + td * de/dt)      (% speed)

e = sp - Pv (reverseActing: Pv - sp). Anti-windup: the integral stays inside
the output limits and stops while the output is held by a limit or the rate
limit. Bumpless: whenever the loop takes the output back, the integral is
loaded from the speed it is given.

Phases: IDLE -> FILLING (optional) -> CONTROL -> BOOST -> SLEEP -> CONTROL;
FALLBACK at a fixed speed after a hunting trip or with a failed sensor;
MANUAL at the manual (or FIXED control's) speed, protections still acting. *)

FUNCTION_BLOCK UT_SPEED_CTRL_RUN
  VAR_INPUT
    Enable : BOOL; (* control wanted *)
    Pv : REAL; (* controlled value (pressure / level) *)
    PvGood : BOOL; (* Pv usable (linked, Good) *)
    Flow : REAL; (* flow *)
    FlowGood : BOOL; (* Flow usable (linked, Good) *)
    Sp : REAL; (* setpoint when spSource = PIN *)
    Running : BOOL := TRUE; (* the pump runs *)
    ExtSpeed : REAL := -1.0; (* speed from an external PID, % *)
    ResetReq : BOOL; (* reset request this scan (edge already taken) *)
    MoreAvailable : BOOL; (* a group can still add a pump: lowPvAtMax waits until it cannot *)
  END_VAR
  VAR_OUTPUT
    Run : BOOL; (* pump wanted *)
    Filled : BOOL; (* the pipe fill is done this run *)
    AtSetpoint : BOOL;
    MoreNeeded : BOOL;
    LessNeeded : BOOL;
    Fault : BOOL;
    Warning : BOOL;
    Speed : REAL; (* speed request, % *)
    Phase : UT_SC_PHASE;
  END_VAR
  VAR_IN_OUT
    Set : UT_SPEED_CTRL_SET;
    U : UT_SC_USE; (* from UT_SPEED_CTRL_CHECK, this scan *)
    Sts : UT_SPEED_CTRL_STS;
    Det : UT_SPEED_CTRL_DET;
  END_VAR
  VAR
    started : BOOL;
    tCur : TIME;
    tPrev : TIME;
    dMs : LINT;
    dts : LREAL; (* seconds counted this scan (whole ms, the rest carried) *)
    mustCycle : BOOL;
    reqRun : BOOL;
    lowLvl : UT_LEVEL; (* lowPvAtMax as used (sp 0: half the setpoint) *)
    lowUse : BOOL;
    cv : REAL; (* the value under control *)
    cvGood : BOOL;
    pressOk : BOOL; (* Pv usable, for highPv *)
    pvNow : BOOL;
    pvBad : BOOL;
    pvGoodSince : TIME;
    pvAlarm : BOOL;
    flowOk : BOOL;
    ph : UT_SC_PHASE;
    prevPhase : UT_SC_PHASE;
    phLast : UT_SC_PHASE;
    phaseAt : TIME;
    spAct : REAL;
    spBoost : REAL;
    fillTarget : REAL;
    filledRun : BOOL; (* this run's line is full *)
    dir : REAL;
    e : LREAL;
    eT : REAL; (* error against the target setpoint (acting direction) *)
    ePrev : LREAL;
    pPart : LREAL;
    iPart : LREAL;
    dPart : LREAL;
    di : LREAL;
    tiS : LREAL;
    tdS : LREAL;
    preload : BOOL;
    spd : LREAL; (* speed now *)
    want : LREAL;
    cand : LREAL;
    stepMax : LREAL;
    lo : LREAL;
    hi : LREAL;
    minS : LREAL;
    maxS : LREAL;
    flowCap : LREAL;
    capRate : LREAL;
    rateS : LREAL; (* rateLimit in %/s *)
    holdSpeed : LREAL;
    extHeld : LREAL;
    driveOn : BOOL;
    overridden : BOOL;
    atHi : BOOL;
    atLo : BOOL;
    satisfied : BOOL;
    sleepSince : TIME;
    boostStart : TIME;
    sleepStart : TIME;
    wakeSince : TIME;
    moreSince : TIME;
    lessSince : TIME;
    tripStop : BOOL;
    huntTrip : BOOL;
    resetDone : BOOL;
    huntSide : INT;
    huntMax : INT;
    hb : REAL;
    huntCur : INT;
    huntPrev : INT;
    huntAt : TIME;
    huntLast : TIME;
    sk : INT;
    tRst : UT_RESET_MODE;
    tLocked : BOOL;
    tTl : TIME;
    tLeft : TIME;
    sleepCounting : BOOL;
    runPrev : BOOL;
    tripMask : DWORD;
    tripMaskPrev : DWORD;
    stCode : UT_STATUS;
    stF : UT_FAULT;
    shownSt : UT_STATUS;
    shownF : UT_FAULT;
    sFill : UT_PROT_ST;
    sHigh : UT_PROT_ST;
    sLowAtMax : UT_PROT_ST;
    sNotReach : UT_PROT_ST;
    sHunt : UT_PROT_ST;
    spRampFb : UT_RAMP; (* the setpoint ramp *)
    fillRampFb : UT_RAMP; (* the pipe fill ramp *)
    x : BOOL;
  END_VAR


tCur := TIME();
IF NOT started THEN
  started := TRUE;
  tPrev := tCur;
  pvGoodSince := tCur;
  phaseAt := tCur;
END_IF;
dMs := TIME_TO_LINT(tCur - tPrev);         (* whole ms; the rest carries on *)
IF dMs < 0 THEN
  dMs := 0;
  tPrev := tCur;
END_IF;
tPrev := tPrev + LINT_TO_TIME(dMs);
dts := LINT_TO_LREAL(dMs) / 1000.0;

(* the value under control *)
IF Set.control = UT_SC_CTRL_FLOW THEN
  cv := Flow;
  cvGood := FlowGood;
ELSE
  cv := Pv;
  cvGood := PvGood OR Set.control = UT_SC_CTRL_FIXED;
END_IF;
pressOk := PvGood AND Pv = Pv AND ABS(Pv) <= 3.4E38;
minS := U.minS;
maxS := U.maxS;
IF U.perS > 0.0 THEN
  rateS := U.rateUse / U.perS;
ELSE
  rateS := 0.0;
END_IF;
IF Set.reverseActing THEN
  dir := -1.0;
ELSE
  dir := 1.0;
END_IF;

(* sensor: bad at once, good again after pvRecover *)
pvNow := cvGood AND (Set.control = UT_SC_CTRL_FIXED OR (cv = cv AND ABS(cv) <= 3.4E38));
IF NOT pvNow THEN
  pvBad := TRUE;
  pvGoodSince := tCur;
ELSIF pvBad AND tCur - pvGoodSince >= Set.pvRecover THEN
  pvBad := FALSE;
END_IF;
pvAlarm := pvBad AND Enable AND NOT U.cfgBad;
flowOk := FlowGood AND Flow = Flow AND ABS(Flow) <= 3.4E38;

IF pvNow THEN
  eT := dir * (U.spTarget - cv);
ELSE
  eT := 0.0;
END_IF;
satisfied := pvNow AND eT <= U.band;
driveOn := Run AND Running;

(* protections (from last scan's phase and speed) *)
x := UT_LEVEL_RUN(TNow := tCur, In := Pv, Good := TRUE, High := TRUE, UseIn := TRUE, Switch := FALSE,
      Enable := Enable AND NOT U.cfgBad AND pressOk AND Set.highPv.sp <> 0.0, Release := FALSE,
      ResetReq := ResetReq, RetryWindow := Set.retryWindow, Level := Set.highPv, Sts := Sts.highPv, St := sHigh);
(* low at max speed: sp 0 = below half the setpoint (direct acting) *)
lowLvl := Set.lowPvAtMax;
lowUse := TRUE;
IF lowLvl.sp = 0.0 THEN
  lowLvl.sp := spAct - 0.5 * ABS(spAct);
  lowUse := NOT Set.reverseActing;
END_IF;
x := UT_LEVEL_RUN(TNow := tCur, In := cv, Good := TRUE, High := FALSE, UseIn := TRUE, Switch := FALSE,
      Enable := Enable AND NOT U.cfgBad AND pvNow AND driveOn AND atHi AND lowUse
                AND (ph = UT_SC_CONTROL OR ph = UT_SC_BOOST OR ph = UT_SC_MANUAL) AND NOT MoreAvailable,
      Release := FALSE, ResetReq := ResetReq, RetryWindow := Set.retryWindow, Level := lowLvl,
      Sts := Sts.lowPvAtMax, St := sLowAtMax);
x := UT_PROT_RUN(TNow := tCur, Cause := ph = UT_SC_FILLING AND driveOn, ResetReq := ResetReq,
      RetryWindow := Set.retryWindow, Prot := Set.pipeFill.timeout, Sts := Sts.pipeFill, St := sFill);
x := UT_PROT_RUN(TNow := tCur, Cause := ph = UT_SC_CONTROL AND driveOn AND pvNow AND NOT overridden
                  AND ABS(cv - spAct) > U.band AND NOT atHi AND NOT atLo,
      ResetReq := ResetReq, RetryWindow := Set.retryWindow, Prot := Set.notReaching, Sts := Sts.notReaching,
      St := sNotReach);
huntMax := LIMIT(1, Set.huntCycles, 15);
x := UT_PROT_RUN(TNow := tCur, Cause := Set.huntWindow > T#0s AND Sts.huntCount > huntMax, ResetReq := ResetReq,
      RetryWindow := Set.retryWindow, Prot := Set.hunting, Sts := Sts.hunting, St := sHunt);

tripStop := sFill.trip OR sHigh.trip OR sLowAtMax.trip OR sNotReach.trip OR (pvAlarm AND U.pvf = UT_PVFAIL_STOP);
huntTrip := sHunt.trip;
IF sFill.badSetting OR sHigh.badSetting OR sLowAtMax.badSetting OR sNotReach.badSetting OR sHunt.badSetting THEN
  U.cfgWarn := TRUE;
  U.warnId := UT_F_SETTING;
END_IF;
(* only a reset that was needed (MANUAL, or RETRY locked out) asks for Enable to cycle *)
resetDone := sFill.reset OR sHigh.reset OR sLowAtMax.reset OR sNotReach.reset OR sHunt.reset;
IF resetDone AND ph = UT_SC_IDLE AND NOT Set.restartAfterReset THEN
  mustCycle := TRUE;
END_IF;
IF NOT Enable THEN
  mustCycle := FALSE;
END_IF;
reqRun := Enable AND NOT U.cfgBad AND NOT mustCycle;

(* ---------------------------------------------------------------- phase *)
prevPhase := ph;
IF NOT reqRun OR tripStop THEN
  ph := UT_SC_IDLE;
  filledRun := FALSE;
ELSIF Set.manual OR U.fixedOn THEN
  IF ph = UT_SC_IDLE OR ph = UT_SC_SLEEP THEN
    spd := LIMIT(minS, Set.startSpeed, maxS);
    flowCap := maxS;
  END_IF;
  ph := UT_SC_MANUAL;              (* the operator's / fixed speed; the protections still act *)
ELSIF pvAlarm AND U.pvf = UT_PVFAIL_HOLD AND ph = UT_SC_SLEEP THEN
  ph := UT_SC_SLEEP;               (* holding: a sleeping pump stays asleep *)
ELSIF pvAlarm OR huntTrip THEN
  IF ph <> UT_SC_FALLBACK THEN
    IF pvAlarm AND U.pvf = UT_PVFAIL_HOLD AND ph <> UT_SC_IDLE THEN
      holdSpeed := spd;
    ELSIF pvAlarm AND U.pvf = UT_PVFAIL_HOLD THEN
      holdSpeed := Set.startSpeed;
    ELSE
      holdSpeed := Set.fallbackSpeed;
    END_IF;
    IF ph = UT_SC_IDLE OR ph = UT_SC_SLEEP THEN
      spd := LIMIT(minS, Set.startSpeed, maxS);
    END_IF;
    ph := UT_SC_FALLBACK;
  ELSIF pvAlarm AND U.pvf = UT_PVFAIL_FALLBACK THEN
    holdSpeed := Set.fallbackSpeed;
  ELSIF NOT pvAlarm THEN
    holdSpeed := Set.fallbackSpeed; (* a hunting trip: always the fallback speed *)
  END_IF;
ELSE
  CASE ph OF
  UT_SC_IDLE:
    spd := LIMIT(minS, Set.startSpeed, maxS);
    preload := TRUE;
    flowCap := maxS;
    spAct := U.spTarget;
    IF Set.pipeFill.mode <> UT_FILL_OFF AND NOT Set.reverseActing THEN
      ph := UT_SC_FILLING;
      IF Set.pipeFill.mode = UT_FILL_RAMP AND pvNow THEN
        spAct := MIN(cv, U.spTarget);
      END_IF;
    ELSE
      ph := UT_SC_CONTROL;
    END_IF;

  UT_SC_FALLBACK, UT_SC_MANUAL:
    IF Set.pipeFill.mode <> UT_FILL_OFF AND NOT Set.reverseActing AND NOT filledRun THEN
      ph := UT_SC_FILLING;         (* the line is not full yet: the fill first *)
      IF Set.pipeFill.mode = UT_FILL_RAMP AND pvNow THEN
        spAct := MIN(cv, U.spTarget);
      END_IF;
    ELSE
      ph := UT_SC_CONTROL;
      preload := TRUE;             (* bumpless: the loop carries on from the speed now *)
    END_IF;

  UT_SC_BOOST:
    IF eT > U.wake OR NOT Set.sleep.enable THEN
      ph := UT_SC_CONTROL;         (* demand came back during the boost *)
    ELSIF tCur - boostStart >= Set.sleep.boostTime THEN
      ph := UT_SC_SLEEP;
      sleepStart := tCur;
      wakeSince := tCur;
    END_IF;

  UT_SC_SLEEP:
    IF NOT (pvNow AND eT > U.wake) THEN
      wakeSince := tCur;
    END_IF;
    IF NOT Set.sleep.enable
       OR (tCur - wakeSince >= Set.sleep.wakeDelay AND tCur - sleepStart >= Set.sleep.minSleep
           AND pvNow AND eT > U.wake) THEN
      ph := UT_SC_CONTROL;
      spd := LIMIT(minS, Set.startSpeed, maxS);
      preload := TRUE;
      flowCap := maxS;
    END_IF;
  END_CASE;
END_IF;

(* fill completion and the sleep check *)
IF Set.pipeFill.target > 0.0 THEN
  fillTarget := Set.pipeFill.target;
ELSE
  fillTarget := 0.9 * U.spTarget;
END_IF;
IF ph = UT_SC_FILLING AND prevPhase = UT_SC_FILLING AND pvNow AND cv >= fillTarget
   AND (Set.pipeFill.mode = UT_FILL_FIXED OR spAct >= U.spTarget) THEN
  ph := UT_SC_CONTROL;
  preload := TRUE;
  filledRun := TRUE;
END_IF;
IF ph <> UT_SC_IDLE AND pvNow AND cv >= fillTarget THEN
  filledRun := TRUE;               (* Pv at the fill target: the line is full whatever the phase *)
END_IF;
sleepCounting := ph = UT_SC_CONTROL AND prevPhase = UT_SC_CONTROL AND Set.sleep.enable AND driveOn AND satisfied
   AND (spd <= Set.sleep.speed OR (Set.sleep.flow > 0.0 AND flowOk AND Flow < Set.sleep.flow));
IF sleepCounting THEN
  IF tCur - sleepSince >= Set.sleep.delay THEN
    spBoost := U.spTarget + dir * ABS(U.spTarget) * U.boostV / 100.0;
    IF U.boostV > 0.0 AND Set.sleep.boostTime > T#0s THEN
      ph := UT_SC_BOOST;
      boostStart := tCur;
    ELSE
      ph := UT_SC_SLEEP;
      sleepStart := tCur;
      wakeSince := tCur;
    END_IF;
  END_IF;
ELSE
  sleepSince := tCur;
END_IF;

(* ------------------------------------------------------------- setpoint *)
IF ph = UT_SC_FILLING AND Set.pipeFill.mode = UT_FILL_RAMP THEN
  IF prevPhase <> UT_SC_FILLING THEN
    fillRampFb(In := spAct, Track := TRUE);   (* the fill starts from Pv *)
  ELSE
    fillRampFb(In := U.spTarget, RateUp := U.fillUse, RateDown := 0.0, RateUnit := Set.rateUnit, Track := FALSE);
  END_IF;
  spAct := fillRampFb.Out;
  spRampFb(In := spAct, Track := TRUE);
ELSIF ph = UT_SC_BOOST THEN
  spAct := spBoost;
  spRampFb(In := spAct, Track := TRUE);
ELSIF ph = UT_SC_IDLE OR ph = UT_SC_SLEEP OR ph = UT_SC_MANUAL OR U.rampUse <= 0.0 OR U.cfgBad THEN
  spRampFb(In := U.spTarget, Track := TRUE);
  spAct := spRampFb.Out;
ELSE
  spRampFb(In := U.spTarget, RateUp := U.rampUse, RateDown := U.rampUse, RateUnit := Set.rateUnit, Track := FALSE);
  spAct := spRampFb.Out;
END_IF;

(* --------------------------------------------------------------- limits *)
lo := minS;
hi := maxS;
IF rateS > 0.0 THEN
  capRate := rateS;
ELSE
  capRate := 5.0;
END_IF;
IF Set.flowLimit > 0.0 AND flowOk AND driveOn THEN
  IF Flow > Set.flowLimit THEN
    IF flowCap > spd THEN
      flowCap := spd;              (* start bringing it down from where it is *)
    END_IF;
    flowCap := flowCap - capRate * MIN(1.0, (Flow - Set.flowLimit) / (0.2 * Set.flowLimit)) * dts;
  ELSE
    flowCap := flowCap + capRate * MIN(1.0, (Set.flowLimit - Flow) / (0.2 * Set.flowLimit)) * dts;
  END_IF;
  flowCap := LIMIT(minS, flowCap, maxS);
  hi := flowCap;
ELSE
  flowCap := maxS;
END_IF;
overridden := sHigh.warn AND (ph = UT_SC_FILLING OR ph = UT_SC_CONTROL OR ph = UT_SC_BOOST
                              OR ph = UT_SC_FALLBACK OR ph = UT_SC_MANUAL);
IF rateS > 0.0 THEN
  stepMax := rateS * dts;
ELSE
  stepMax := 1.0E30;
END_IF;

(* --------------------------------------------------------------- output *)
IF Set.ti > T#0s THEN
  tiS := LINT_TO_LREAL(TIME_TO_LINT(Set.ti)) / 1000.0;
ELSE
  tiS := 0.0;
END_IF;
IF Set.td > T#0s THEN
  tdS := LINT_TO_LREAL(TIME_TO_LINT(Set.td)) / 1000.0;
ELSE
  tdS := 0.0;
END_IF;
IF pvNow THEN
  e := dir * (spAct - cv);
  IF ABS(e) <= U.db THEN
    e := 0.0;
  END_IF;
ELSE
  e := 0.0;
END_IF;
pPart := 0.0;
dPart := 0.0;

IF ph = UT_SC_IDLE OR ph = UT_SC_SLEEP THEN
  spd := 0.0;
  preload := TRUE;
  iPart := 0.0;
ELSIF overridden THEN
  spd := lo;                       (* overpressure: straight to minimum *)
  preload := TRUE;
ELSIF NOT Running THEN
  preload := TRUE;                 (* the drive has not started: hold the speed *)
ELSIF ph = UT_SC_MANUAL THEN
  want := LIMIT(lo, U.speedUse, hi);
  spd := spd + LIMIT(-stepMax, want - spd, stepMax);
  preload := TRUE;
ELSIF ph = UT_SC_FALLBACK THEN
  want := LIMIT(lo, holdSpeed, hi);
  spd := spd + LIMIT(-stepMax, want - spd, stepMax);
  preload := TRUE;
ELSIF ph = UT_SC_FILLING AND Set.pipeFill.mode = UT_FILL_FIXED THEN
  want := LIMIT(lo, Set.pipeFill.speed, hi);
  spd := spd + LIMIT(-stepMax, want - spd, stepMax);
  preload := TRUE;
ELSIF Set.loop = UT_LOOP_EXTERNAL THEN
  IF ExtSpeed >= 0.0 AND ExtSpeed <= 3.4E38 THEN
    extHeld := ExtSpeed;
  ELSIF preload THEN
    extHeld := spd;
  END_IF;
  preload := FALSE;
  want := LIMIT(lo, extHeld, hi);
  spd := spd + LIMIT(-stepMax, want - spd, stepMax);
  iPart := 0.0;
ELSE
  (* the PID *)
  pPart := Set.kp * e;
  di := 0.0;
  IF preload THEN
    iPart := spd - pPart;          (* bumpless: carry on from the speed now *)
    ePrev := e;
    preload := FALSE;
  ELSE
    IF tdS > 0.0 AND dts > 0.0 THEN
      dPart := Set.kp * tdS * (e - ePrev) / dts;
    END_IF;
    IF tiS > 0.0 THEN
      di := Set.kp * e * dts / tiS;
    END_IF;
  END_IF;
  IF dts > 0.0 THEN
    ePrev := e;
  END_IF;
  IF NOT (iPart = iPart) THEN
    iPart := spd;
  END_IF;
  cand := pPart + iPart + di + dPart;
  IF NOT (cand = cand) THEN
    cand := spd;                   (* infinities of opposite sign: hold *)
  END_IF;
  want := LIMIT(lo, cand, hi);
  want := spd + LIMIT(-stepMax, want - spd, stepMax);
  (* anti-windup *)
  IF (di > 0.0 AND want >= cand) OR (di < 0.0 AND want <= cand) THEN
    IF di > 0.0 THEN
      iPart := MAX(iPart, MIN(iPart + di, hi));
    ELSE
      iPart := MIN(iPart, MAX(iPart + di, lo));
    END_IF;
  END_IF;
  IF hi < maxS THEN
    iPart := MIN(iPart, hi);       (* the flow limit takes the integral down with it *)
  END_IF;
  spd := want;
END_IF;
IF ph <> UT_SC_IDLE AND ph <> UT_SC_SLEEP THEN
  IF NOT (spd = spd) THEN
    spd := lo;
  END_IF;
  spd := LIMIT(lo, spd, hi);
END_IF;

Run := ph = UT_SC_FILLING OR ph = UT_SC_CONTROL OR ph = UT_SC_BOOST OR ph = UT_SC_FALLBACK OR ph = UT_SC_MANUAL;
IF Run THEN
  Speed := LREAL_TO_REAL(spd);
ELSE
  Speed := 0.0;
END_IF;
atHi := Run AND spd >= hi - 0.01;
Sts.flowLimiting := Run AND hi < maxS AND atHi;
atLo := Run AND spd <= lo + 0.01;
Filled := ph <> UT_SC_IDLE
          AND (filledRun OR Set.pipeFill.mode = UT_FILL_OFF OR Set.reverseActing
               OR ph = UT_SC_CONTROL OR ph = UT_SC_BOOST OR ph = UT_SC_SLEEP);

(* -------------------------------------------------------------- hunting *)
hb := Set.huntBand / 2.0;
IF (ph = UT_SC_CONTROL OR ph = UT_SC_BOOST) AND Run AND Running AND pvNow THEN
  IF (cv - spAct > hb AND huntSide < 0) OR (spAct - cv > hb AND huntSide > 0) THEN
    IF huntCur < 32767 THEN
      huntCur := huntCur + 1;
    END_IF;
    huntLast := tCur;
  END_IF;
  IF cv - spAct > hb THEN
    huntSide := 1;
  ELSIF spAct - cv > hb THEN
    huntSide := -1;
  END_IF;
ELSE
  huntSide := 0;
END_IF;
IF Set.huntWindow > T#0s AND tCur - huntLast > Set.huntWindow THEN
  huntCur := 0;                    (* no crossing for a whole window: none left *)
  huntPrev := 0;
END_IF;
IF Set.huntWindow > T#0s THEN
  IF tCur - huntAt >= Set.huntWindow THEN
    IF tCur - huntAt >= Set.huntWindow + Set.huntWindow THEN
      huntPrev := 0;               (* a whole window without a scan of it *)
    ELSE
      huntPrev := huntCur;
    END_IF;
    huntCur := 0;
    huntAt := tCur;
  END_IF;
  Sts.huntCount := huntCur + REAL_TO_INT(INT_TO_REAL(huntPrev)
                   * (1.0 - LINT_TO_REAL(TIME_TO_LINT(tCur - huntAt)) / LINT_TO_REAL(TIME_TO_LINT(Set.huntWindow))));
ELSE
  huntCur := 0;
  huntPrev := 0;
  huntAt := tCur;
  Sts.huntCount := 0;
END_IF;

(* -------------------------------------------------------------- staging *)
IF NOT (ph = UT_SC_CONTROL AND driveOn AND atHi AND NOT overridden AND eT > U.band) THEN
  moreSince := tCur;
END_IF;
IF NOT (ph = UT_SC_CONTROL AND driveOn AND atLo AND NOT overridden) THEN
  lessSince := tCur;
END_IF;
MoreNeeded := tCur - moreSince >= Set.stageDelay AND ph = UT_SC_CONTROL AND atHi;
LessNeeded := tCur - lessSince >= Set.stageDelay AND ph = UT_SC_CONTROL AND atLo;
AtSetpoint := (ph = UT_SC_CONTROL OR ph = UT_SC_BOOST OR ph = UT_SC_SLEEP) AND pvNow AND ABS(cv - spAct) <= U.band;

(* --------------------------------------------------------------- status *)
Fault := sFill.trip OR sHigh.trip OR sLowAtMax.trip OR sNotReach.trip OR sHunt.trip
         OR (pvAlarm AND U.pvf = UT_PVFAIL_STOP) OR (U.cfgBad AND Enable);
Warning := sFill.warn OR sHigh.warn OR sLowAtMax.warn OR sNotReach.warn OR sHunt.warn
           OR (pvAlarm AND U.pvf <> UT_PVFAIL_STOP) OR U.cfgWarn;

Sts.faultCode := 0;
Sts.faultId := UT_F_NONE;
IF U.cfgWarn THEN Sts.faultCode := Sts.faultCode OR 16#80; Sts.faultId := U.warnId; END_IF;
IF U.cfgBad AND Enable THEN Sts.faultCode := Sts.faultCode OR 16#1; Sts.faultId := U.cfgId; END_IF;
IF Sts.notReaching.tripped THEN Sts.faultCode := Sts.faultCode OR 16#20; Sts.faultId := UT_F_NOT_REACHING; END_IF;
IF Sts.hunting.tripped THEN Sts.faultCode := Sts.faultCode OR 16#40; Sts.faultId := UT_F_HUNTING; END_IF;
IF Sts.pipeFill.tripped THEN Sts.faultCode := Sts.faultCode OR 16#10; Sts.faultId := UT_F_PIPE_FILL; END_IF;
IF Sts.lowPvAtMax.tripped THEN Sts.faultCode := Sts.faultCode OR 16#8; Sts.faultId := UT_F_LOW_AT_MAX; END_IF;
IF pvAlarm THEN Sts.faultCode := Sts.faultCode OR 16#2; Sts.faultId := UT_F_SENSOR_BAD; END_IF;
IF Sts.highPv.tripped THEN Sts.faultCode := Sts.faultCode OR 16#4; Sts.faultId := UT_F_OVERPRESSURE; END_IF;

(* the last trip, kept after it clears; trips since power-up *)
tripMask := 0;
IF sHunt.trip THEN tripMask := tripMask OR 16#40; Sts.lastFault := UT_F_HUNTING; END_IF;
IF sNotReach.trip THEN tripMask := tripMask OR 16#20; Sts.lastFault := UT_F_NOT_REACHING; END_IF;
IF sFill.trip THEN tripMask := tripMask OR 16#10; Sts.lastFault := UT_F_PIPE_FILL; END_IF;
IF sLowAtMax.trip THEN tripMask := tripMask OR 16#8; Sts.lastFault := UT_F_LOW_AT_MAX; END_IF;
IF pvAlarm AND U.pvf = UT_PVFAIL_STOP THEN tripMask := tripMask OR 16#2; Sts.lastFault := UT_F_SENSOR_BAD; END_IF;
IF sHigh.trip THEN tripMask := tripMask OR 16#4; Sts.lastFault := UT_F_OVERPRESSURE; END_IF;
IF tripMask <> 0 THEN
  IF tripMaskPrev = 0 THEN
    Sts.trips := Sts.trips + 1;
  END_IF;
  Sts.lastFaultCode := tripMask;
END_IF;
tripMaskPrev := tripMask;

(* why it stopped: set when Run drops *)
IF runPrev AND NOT Run THEN
  IF tripStop THEN
    Sts.stopReason := UT_STOP_FAULT;
  ELSIF U.cfgBad THEN
    Sts.stopReason := UT_STOP_SETTING;
  ELSIF NOT Enable THEN
    Sts.stopReason := UT_STOP_DEMAND_ENDED;
  ELSIF ph = UT_SC_SLEEP THEN
    Sts.stopReason := UT_STOP_ASLEEP;
  ELSE
    Sts.stopReason := UT_STOP_DEMAND_ENDED;
  END_IF;
END_IF;
runPrev := Run;

IF ph <> phLast THEN
  phaseAt := tCur;
END_IF;
phLast := ph;
Det.phaseTime := tCur - phaseAt;

(* status: config, fault, held, warning, normal, idle *)
sk := 0;
stF := UT_F_NONE;
IF sHigh.trip THEN sk := 1;
ELSIF sLowAtMax.trip THEN sk := 2;
ELSIF sFill.trip THEN sk := 3;
ELSIF sNotReach.trip THEN sk := 4;
ELSIF sHunt.trip THEN sk := 5;
ELSIF sHigh.warn THEN sk := 11;
ELSIF sLowAtMax.warn THEN sk := 12;
ELSIF sFill.warn THEN sk := 13;
ELSIF sNotReach.warn THEN sk := 14;
ELSIF sHunt.warn THEN sk := 15;
END_IF;
tTl := T#0s;
tLeft := T#0s;
tLocked := FALSE;
CASE sk MOD 10 OF
1: tRst := Set.highPv.reset; tLocked := Sts.highPv.locked; tTl := Sts.highPv.timeLeft;
2: tRst := Set.lowPvAtMax.reset; tLocked := Sts.lowPvAtMax.locked; tTl := Sts.lowPvAtMax.timeLeft;
3: tRst := Set.pipeFill.timeout.reset; tLocked := Sts.pipeFill.locked; tTl := Sts.pipeFill.timeLeft;
4: tRst := Set.notReaching.reset; tLocked := Sts.notReaching.locked; tTl := Sts.notReaching.timeLeft;
5: tRst := Set.hunting.reset; tLocked := Sts.hunting.locked; tTl := Sts.hunting.timeLeft;
END_CASE;
IF U.cfgBad THEN
  stCode := UT_ST_CONFIG;
  stF := U.cfgId;
ELSIF sk = 1 OR (sk > 1 AND sk < 10 AND NOT (pvAlarm AND U.pvf = UT_PVFAIL_STOP)) THEN
  CASE sk OF
  1: stF := UT_F_OVERPRESSURE;
  2: stF := UT_F_LOW_AT_MAX;
  3: stF := UT_F_PIPE_FILL;
  4: stF := UT_F_NOT_REACHING;
  ELSE
    stF := UT_F_HUNTING;
  END_CASE;
  IF tRst = UT_RST_MANUAL THEN
    stCode := UT_ST_FAULT_RESET;
  ELSIF tLocked THEN
    stCode := UT_ST_FAULT_LOCKED;
  ELSIF tRst = UT_RST_RETRY THEN
    stCode := UT_ST_FAULT_RETRY;
    tLeft := tTl;
  ELSE
    stCode := UT_ST_FAULT;
    tLeft := tTl;
  END_IF;
ELSIF pvAlarm AND U.pvf = UT_PVFAIL_STOP THEN
  stCode := UT_ST_FAULT;
  stF := UT_F_SENSOR_BAD;
ELSIF mustCycle AND Enable THEN
  stCode := UT_ST_ENABLE_CYCLE;
ELSIF Run AND NOT Running THEN
  stCode := UT_ST_DRIVE_NOT_RUNNING;
ELSIF ph = UT_SC_SLEEP THEN
  stCode := UT_ST_SLEEPING;
  IF tCur - sleepStart < Set.sleep.minSleep THEN
    tLeft := Set.sleep.minSleep - (tCur - sleepStart);
  ELSIF tCur - wakeSince > T#0s THEN
    tLeft := Set.sleep.wakeDelay - (tCur - wakeSince);   (* waking: the wake delay *)
  END_IF;
ELSIF pvAlarm THEN
  stCode := UT_ST_WARNING;            (* running on the fallback / held / manual speed *)
  stF := UT_F_SENSOR_BAD;
ELSIF sk > 10 THEN
  stCode := UT_ST_WARNING;
  CASE sk - 10 OF
  1: stF := UT_F_OVERPRESSURE;
  2: stF := UT_F_LOW_AT_MAX;
  3: stF := UT_F_PIPE_FILL;
  4: stF := UT_F_NOT_REACHING;
  ELSE
    stF := UT_F_HUNTING;
  END_CASE;
ELSIF U.cfgWarn THEN
  stCode := UT_ST_WARN_SETTING;
  stF := U.warnId;
ELSIF ph = UT_SC_MANUAL AND U.fixedOn THEN
  stCode := UT_ST_FIXED_SPEED;
ELSIF ph = UT_SC_MANUAL THEN
  stCode := UT_ST_MANUAL_SPEED;
ELSIF ph = UT_SC_FILLING THEN
  stCode := UT_ST_PIPE_FILL;
  tLeft := Sts.pipeFill.timeLeft;
ELSIF ph = UT_SC_BOOST THEN
  stCode := UT_ST_BOOST;
  tLeft := Set.sleep.boostTime - (tCur - boostStart);
ELSIF ph = UT_SC_FALLBACK THEN
  stCode := UT_ST_FALLBACK;
ELSIF Sts.flowLimiting THEN
  stCode := UT_ST_FLOW_LIMIT;
ELSIF ph = UT_SC_CONTROL AND atHi AND eT > U.band THEN
  stCode := UT_ST_MAX_SPEED;
ELSIF Run THEN
  stCode := UT_ST_HOLDING;
ELSE
  stCode := UT_ST_IDLE_NOT_ENABLED;
END_IF;
IF stCode = UT_ST_HOLDING OR stCode = UT_ST_MAX_SPEED OR stCode = UT_ST_FLOW_LIMIT THEN
  IF sleepCounting THEN
    tLeft := Set.sleep.delay - (tCur - sleepSince);
  ELSIF tCur - moreSince > T#0s THEN
    tLeft := Set.stageDelay - (tCur - moreSince);
  ELSIF tCur - lessSince > T#0s THEN
    tLeft := Set.stageDelay - (tCur - lessSince);
  END_IF;
END_IF;
IF tLeft < T#0s THEN
  tLeft := T#0s;
END_IF;
Det.timeLeft := tLeft;
IF stCode <> shownSt OR stF <> shownF OR LEN(Sts.statusText) = 0 THEN
  shownSt := stCode;
  shownF := stF;
  Sts.statusText := UT_STATUS_TEXT(stCode, stF);
END_IF;
Sts.statusCode := stCode;
(* NE107: trip / config / sensor stop = FAILURE; manual speed = CHECK; warnings = OUT_OF_SPEC *)
Sts.ne107 := UT_NE107_RUN(Fault := Fault, Check := ph = UT_SC_MANUAL AND NOT U.fixedOn,
                          OutOfSpec := Warning, Maint := FALSE);

Phase := ph;
Sts.phase := ph;
Sts.spActive := spAct;
Sts.pv := cv;
Det.error := LREAL_TO_REAL(e);
Det.pTerm := LREAL_TO_REAL(pPart);
Det.iTerm := LREAL_TO_REAL(iPart);
Det.dTerm := LREAL_TO_REAL(dPart);
Sts.speed := Speed;
Sts.sleeping := ph = UT_SC_SLEEP;
Sts.manual := ph = UT_SC_MANUAL AND NOT U.fixedOn;
Sts.pvBad := pvBad;
Sts.configBad := U.cfgBad;
Sts.fault := Fault;
Sts.warning := Warning;
Sts.filled := Filled;
Sts.presetUsed := U.preset;
Sts.manualSpeedUsed := U.manSpd;

END_FUNCTION_BLOCK