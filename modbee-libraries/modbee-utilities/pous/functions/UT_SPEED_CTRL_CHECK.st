(* The settings and pins in use: TRUE when every setting is usable *)

FUNCTION UT_SPEED_CTRL_CHECK : BOOL
  VAR_INPUT
    Preset : INT := -1; (* the pin: 0..2 while wired, -1 = the kept one *)
    ManualSpeed : REAL := -1.0; (* the pin: < 0 = the kept one *)
    Sp : REAL; (* the pin, spSource = PIN *)
    PvFitted : BOOL; (* a Pv measurement is linked *)
    FlowFitted : BOOL; (* a Flow measurement is linked *)
    ExtSpeed : REAL := -1.0; (* < 0: not wired *)
    ManualReq : BOOL; (* manual speed requested this scan (kept in set.manual) *)
    AutoReq : BOOL; (* back to the loop this scan (wins) *)
  END_VAR
  VAR_IN_OUT
    Set : UT_SPEED_CTRL_SET;
    U : UT_SC_USE;
  END_VAR
  VAR
    bad : BOOL;
  END_VAR


IF AutoReq THEN
  Set.manual := FALSE;
ELSIF ManualReq THEN
  Set.manual := TRUE;
END_IF;
U.cfgWarn := FALSE;
U.warnId := UT_F_NONE;
U.setOk := TRUE;
U.setId := UT_F_NONE;
(* the preset and the manual speed in use *)
IF Preset < 0 THEN
  U.preset := Set.preset;
ELSIF Preset = 0 THEN
  U.preset := UT_PRESET_NORMAL;
ELSIF Preset = 1 THEN
  U.preset := UT_PRESET_LOW;
ELSIF Preset = 2 THEN
  U.preset := UT_PRESET_HIGH;
ELSE
  U.preset := Set.preset;
  U.cfgWarn := TRUE;
  U.warnId := UT_F_PRESET;
END_IF;
IF ManualSpeed >= 0.0 THEN
  U.manSpd := ManualSpeed;
ELSE
  U.manSpd := Set.manualSpeed;
END_IF;
U.fixedOn := Set.control = UT_SC_CTRL_FIXED AND NOT Set.manual;
(* the setpoint *)
IF Set.control = UT_SC_CTRL_FLOW THEN
  U.spTarget := Set.flowSp;
  IF U.preset = UT_PRESET_LOW AND Set.flowSpLow <> 0.0 THEN
    U.spTarget := Set.flowSpLow;
  ELSIF U.preset = UT_PRESET_HIGH AND Set.flowSpHigh <> 0.0 THEN
    U.spTarget := Set.flowSpHigh;
  END_IF;
ELSIF Set.spSource = UT_SP_PIN THEN
  U.spTarget := Sp;
ELSIF U.preset = UT_PRESET_LOW AND Set.spLow <> 0.0 THEN
  U.spTarget := Set.spLow;
ELSIF U.preset = UT_PRESET_HIGH AND Set.spHigh <> 0.0 THEN
  U.spTarget := Set.spHigh;
ELSE
  U.spTarget := Set.sp;
END_IF;
CASE Set.rateUnit OF
UT_PER_SEC: U.perS := 1.0;
UT_PER_MIN: U.perS := 60.0;
UT_PER_HOUR: U.perS := 3600.0;
UT_PER_DAY: U.perS := 86400.0;
ELSE
  U.perS := 0.0;
END_CASE;
(* settings that stop the loop (the first one found is shown) *)
U.cfgId := UT_F_NONE;
IF NOT (Set.control = UT_SC_CTRL_PV OR Set.control = UT_SC_CTRL_FLOW OR Set.control = UT_SC_CTRL_FIXED) THEN
  U.cfgId := UT_F_SETTING;
ELSIF Set.control <> UT_SC_CTRL_FIXED AND Set.spSource = UT_SP_RECORD
      AND (NOT (U.spTarget = U.spTarget) OR ABS(U.spTarget) > 3.4E38 OR U.spTarget = 0.0) THEN
  U.cfgId := UT_F_SETPOINT;
ELSIF NOT (Set.kp >= 0.0 AND Set.kp <= 3.4E38) THEN
  U.cfgId := UT_F_KP;
ELSIF NOT (Set.rateLimit >= 0.0 AND Set.rateLimit <= 3.4E38) THEN
  U.cfgId := UT_F_RATE_LIMIT;
ELSIF U.perS = 0.0 THEN
  U.cfgId := UT_F_RATE_UNIT;
ELSIF NOT (Set.startSpeed = Set.startSpeed) OR NOT (Set.fallbackSpeed = Set.fallbackSpeed) THEN
  U.cfgId := UT_F_START_SPEED;
ELSIF NOT (Set.minSpeed >= 0.0 AND Set.maxSpeed > 0.0 AND Set.minSpeed <= Set.maxSpeed AND Set.maxSpeed <= 3.4E38) THEN
  U.cfgId := UT_F_MIN_MAX_SPEED;
END_IF;
IF U.cfgId <> UT_F_NONE THEN
  U.setOk := FALSE;
  U.setId := U.cfgId;
END_IF;
(* settings with a safe value (the loop runs on it, with a warning) *)
bad := NOT (Set.spSource = UT_SP_RECORD OR Set.spSource = UT_SP_PIN)
   OR NOT (Set.loop = UT_LOOP_INTERNAL OR Set.loop = UT_LOOP_EXTERNAL)
   OR NOT (Set.pipeFill.mode = UT_FILL_OFF OR Set.pipeFill.mode = UT_FILL_FIXED OR Set.pipeFill.mode = UT_FILL_RAMP)
   OR NOT (Set.pvFail = UT_PVFAIL_STOP OR Set.pvFail = UT_PVFAIL_FALLBACK OR Set.pvFail = UT_PVFAIL_HOLD)
   OR NOT (Set.preset = UT_PRESET_NORMAL OR Set.preset = UT_PRESET_LOW OR Set.preset = UT_PRESET_HIGH)
   OR Set.ti < T#0s OR Set.td < T#0s
   OR (U.cfgId = UT_F_NONE AND NOT (Set.startSpeed >= Set.minSpeed AND Set.startSpeed <= Set.maxSpeed))
   OR (U.cfgId = UT_F_NONE AND NOT (Set.fallbackSpeed >= Set.minSpeed AND Set.fallbackSpeed <= Set.maxSpeed))
   OR NOT (Set.pipeFill.speed >= 0.0 AND Set.pipeFill.speed <= 100.0)
   OR NOT (Set.pipeFill.target >= 0.0 AND Set.pipeFill.target <= 3.4E38)
   OR NOT (Set.pipeFill.rate >= 0.0 AND Set.pipeFill.rate <= 3.4E38)
   OR NOT (Set.sleep.speed >= 0.0 AND Set.sleep.speed <= 100.0)
   OR NOT (Set.sleep.flow >= 0.0 AND Set.sleep.flow <= 3.4E38)
   OR NOT (Set.sleep.wakeDrop >= 0.0 AND Set.sleep.wakeDrop <= 3.4E38)
   OR NOT (Set.sleep.boost >= 0.0 AND Set.sleep.boost <= 100.0)
   OR Set.sleep.delay < T#0s OR Set.sleep.boostTime < T#0s OR Set.sleep.wakeDelay < T#0s
   OR Set.sleep.minSleep < T#0s
   OR NOT (Set.atSpBand >= 0.0 AND Set.atSpBand <= 3.4E38)
   OR NOT (Set.deadband >= 0.0 AND Set.deadband <= 3.4E38)
   OR NOT (Set.spRamp >= 0.0 AND Set.spRamp <= 3.4E38)
   OR NOT (Set.flowLimit >= 0.0 AND Set.flowLimit <= 3.4E38)
   OR Set.huntCycles < 1 OR Set.huntCycles > 15 OR Set.huntWindow < T#0s
   OR NOT (Set.huntBand >= 0.0 AND Set.huntBand <= 3.4E38)
   OR Set.pvRecover < T#0s OR Set.stageDelay < T#0s OR Set.retryWindow < T#0s
   OR NOT (Set.manualSpeed >= 0.0 AND Set.manualSpeed <= 100.0)
   OR NOT (ABS(Set.spLow) <= 3.4E38 AND ABS(Set.spHigh) <= 3.4E38 AND ABS(Set.flowSp) <= 3.4E38
           AND ABS(Set.flowSpLow) <= 3.4E38 AND ABS(Set.flowSpHigh) <= 3.4E38 AND ABS(Set.sp) <= 3.4E38)
   OR NOT (Set.fixedSpeed >= 0.0 AND Set.fixedSpeed <= 100.0 AND Set.fixedSpeedLow >= 0.0 AND Set.fixedSpeedLow <= 100.0
           AND Set.fixedSpeedHigh >= 0.0 AND Set.fixedSpeedHigh <= 100.0);
IF bad THEN
  U.cfgWarn := TRUE;
  U.warnId := UT_F_SETTING;
  IF U.setOk THEN
    U.setOk := FALSE;
    U.setId := UT_F_SETTING;
  END_IF;
END_IF;
(* pins: no run without what the control needs; never put back *)
U.cfgBad := U.cfgId <> UT_F_NONE;
IF NOT U.cfgBad THEN
  IF Set.control = UT_SC_CTRL_FLOW AND NOT FlowFitted THEN
    U.cfgId := UT_F_NO_METER;
  ELSIF Set.control = UT_SC_CTRL_PV AND NOT PvFitted THEN
    U.cfgId := UT_F_NO_LINK;
  ELSIF Set.control = UT_SC_CTRL_PV AND Set.spSource = UT_SP_PIN
        AND (NOT (U.spTarget = U.spTarget) OR ABS(U.spTarget) > 3.4E38 OR U.spTarget = 0.0) THEN
    U.cfgId := UT_F_SETPOINT;
  ELSIF Set.loop = UT_LOOP_EXTERNAL AND Set.control <> UT_SC_CTRL_FIXED AND NOT (ExtSpeed >= 0.0) THEN
    U.cfgId := UT_F_EXT_SPEED;
  END_IF;
  U.cfgBad := U.cfgId <> UT_F_NONE;
END_IF;
(* the values in use *)
IF U.cfgBad THEN
  U.minS := 0.0;
  U.maxS := 0.0;
ELSE
  U.minS := Set.minSpeed;
  U.maxS := Set.maxSpeed;
END_IF;
IF U.perS > 0.0 THEN
  U.rateUse := Set.rateLimit;
  U.fillUse := Set.pipeFill.rate;
ELSE
  U.rateUse := 0.0;
  U.fillUse := 0.0;
END_IF;
IF NOT (U.fillUse >= 0.0 AND U.fillUse <= 3.4E38) THEN U.fillUse := 0.0; END_IF;
U.wake := Set.sleep.wakeDrop;
IF NOT (U.wake >= 0.0 AND U.wake <= 3.4E38) THEN U.wake := 0.0; END_IF;     (* NaN would never wake *)
U.band := Set.atSpBand;
IF NOT (U.band >= 0.0 AND U.band <= 3.4E38) THEN U.band := 0.0; END_IF;
U.db := Set.deadband;
IF NOT (U.db >= 0.0 AND U.db <= 3.4E38) THEN U.db := 0.0; END_IF;
U.rampUse := Set.spRamp;
IF NOT (U.rampUse >= 0.0 AND U.rampUse <= 3.4E38) OR U.perS = 0.0 THEN U.rampUse := 0.0; END_IF;
U.boostV := Set.sleep.boost;
IF NOT (U.boostV >= 0.0 AND U.boostV <= 100.0) THEN U.boostV := 0.0; END_IF;
IF U.fixedOn THEN
  CASE U.preset OF
  UT_PRESET_LOW: U.speedUse := Set.fixedSpeedLow;
  UT_PRESET_HIGH: U.speedUse := Set.fixedSpeedHigh;
  ELSE
    U.speedUse := Set.fixedSpeed;
  END_CASE;
ELSE
  U.speedUse := U.manSpd;
END_IF;
IF NOT (U.speedUse >= 0.0 AND U.speedUse <= 100.0) THEN
  U.speedUse := U.minS;          (* the safe side: the minimum speed *)
  U.cfgWarn := TRUE;
  U.warnId := UT_F_HAND_SPEED;
END_IF;
U.pvf := Set.pvFail;
IF NOT (U.pvf = UT_PVFAIL_STOP OR U.pvf = UT_PVFAIL_FALLBACK OR U.pvf = UT_PVFAIL_HOLD) THEN
  U.pvf := UT_PVFAIL_STOP;       (* unknown: the safe side *)
END_IF;
UT_SPEED_CTRL_CHECK := U.setOk;

END_FUNCTION