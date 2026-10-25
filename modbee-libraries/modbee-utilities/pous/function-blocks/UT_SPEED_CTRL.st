(* UT_SPEED_CTRL — constant pressure / flow / level with a speed drive.

Holds the value on the Pv plug (or the Flow plug) at the setpoint by varying
a drive's speed: PV / FLOW / FIXED control, each with NORMAL / LOW / HIGH
presets, manual speed, pipe fill, sleep / boost / wake, flow limit,
overpressure override, lost prime (low at max speed), hunting, sensor
failure. Link Run, Speed and Filled to the pump (pump.Run, pump.Speed,
pump.PrimeDone) and the pump's Running back to Running.

Pins: Reset, Manual and Auto act on their rising edge. Preset (0 NORMAL,
1 LOW, 2 HIGH) and ManualSpeed act while wired; unwired (-1) the kept
choices in Data.set are used. ExtSpeed is the speed of an external PID
(loop EXTERNAL); unwired (-1) with EXTERNAL is a config fault.

Every setting is kept by the block itself (decision 28): restored at power
up and after an upload, saved once a second. A bad setting written by an
HMI / SCADA is put back to the last good one and reported in sts.refused /
sts.refusedWhy (decision 62). Trips are forgotten at power-up. *)

FUNCTION_BLOCK UT_SPEED_CTRL
  VAR_INPUT
    Enable : BOOL; (* control wanted *)
    Reset : BOOL R_EDGE; (* reset trips whose cause has gone *)
    Manual : BOOL R_EDGE; (* run at the manual speed (kept choice), protections acting *)
    Auto : BOOL R_EDGE; (* back to the loop *)
    Running : BOOL := TRUE; (* the pump runs (pump.Running) *)
    MoreAvailable : BOOL; (* a group can still add a pump *)
    Preset : INT := -1; (* 0 NORMAL, 1 LOW, 2 HIGH while wired; -1 = the kept set.preset *)
    ManualSpeed : REAL := -1.0; (* manual speed % while wired; < 0 = the kept set.manualSpeed *)
    Sp : REAL; (* setpoint when spSource = PIN *)
    ExtSpeed : REAL := -1.0; (* external PID speed %; < 0 = not wired *)
    Pv : UT_I_MEAS; (* the controlled value (pressure / level) *)
    Flow : UT_I_MEAS; (* flow (FLOW control, flow limit, low-flow sleep) *)
  END_VAR
  VAR_OUTPUT
    Run : BOOL; (* pump wanted (-> pump.Run) *)
    Filled : BOOL; (* the pipe fill is done this run (-> pump.PrimeDone) *)
    AtSetpoint : BOOL;
    MoreNeeded : BOOL; (* at max speed and short for stageDelay *)
    LessNeeded : BOOL; (* at min speed for stageDelay *)
    Fault : BOOL;
    Warning : BOOL;
    Speed : REAL; (* speed request % (-> pump.Speed) *)
    Phase : UT_SC_PHASE;
  END_VAR
  VAR_IN_OUT
    Data : UT_SPEED_CTRL_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_SPEED_CTRL_SET; (* the kept settings *)
    keptGood : BOOL; (* the kept settings passed the check *)
  END_VAR
  VAR
    hReset : BOOL;
    hManual : BOOL;
    hAuto : BOOL;
    keep : UT_KEEP;
    ctl : UT_SPEED_CTRL_RUN;
    use : UT_SC_USE;
    ok : BOOL;
    resetReq : BOOL;
    manReq : BOOL;
    autoReq : BOOL;
    pvFitted : BOOL;
    pvVal : REAL;
    pvGood : BOOL;
    flowFitted : BOOL;
    flowVal : REAL;
    flowGood : BOOL;
  END_VAR


keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
(* HMI commands act once per request, even when held on *)
resetReq := Reset OR (Data.cmdReset AND NOT hReset);
hReset := Data.cmdReset;
Data.cmdReset := FALSE;
manReq := Manual OR (Data.cmdManual AND NOT hManual);
hManual := Data.cmdManual;
Data.cmdManual := FALSE;
autoReq := Auto OR (Data.cmdAuto AND NOT hAuto);
hAuto := Data.cmdAuto;
Data.cmdAuto := FALSE;

(* the plugs *)
pvFitted := FALSE;
pvGood := FALSE;
pvVal := 0.0;
IF Pv <> NULL THEN
  pvFitted := Pv.IsFitted();
  pvGood := pvFitted AND Pv.GoodNow();
  pvVal := Pv.GetValue();
END_IF;
flowFitted := FALSE;
flowGood := FALSE;
flowVal := 0.0;
IF Flow <> NULL THEN
  flowFitted := Flow.IsFitted();
  flowGood := flowFitted AND Flow.GoodNow();
  flowVal := Flow.GetValue();
END_IF;

(* settings: a bad write is put back to the last good one *)
ok := UT_SPEED_CTRL_CHECK(Preset := Preset, ManualSpeed := ManualSpeed, Sp := Sp, PvFitted := pvFitted,
                          FlowFitted := flowFitted, ExtSpeed := ExtSpeed, ManualReq := manReq, AutoReq := autoReq,
                          Set := Data.set, U := use);
IF NOT ok AND keptGood AND NOT keep.FirstBoot THEN
  Data.sts.refused := use.setId;
  Data.sts.refusedWhy := UT_F_SETTING;
  Data.set := keptSet;
  ok := UT_SPEED_CTRL_CHECK(Preset := Preset, ManualSpeed := ManualSpeed, Sp := Sp, PvFitted := pvFitted,
                            FlowFitted := flowFitted, ExtSpeed := ExtSpeed, ManualReq := manReq, AutoReq := autoReq,
                            Set := Data.set, U := use);
END_IF;

ctl(Enable := Enable, Pv := pvVal, PvGood := pvGood, Flow := flowVal, FlowGood := flowGood, Sp := Sp,
    Running := Running, ExtSpeed := ExtSpeed, ResetReq := resetReq, MoreAvailable := MoreAvailable,
    Set := Data.set, U := use, Sts := Data.sts, Det := Data.det);

IF keep.SaveSet AND (ok OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := ok;
END_IF;

Run := ctl.Run;
Filled := ctl.Filled;
AtSetpoint := ctl.AtSetpoint;
MoreNeeded := ctl.MoreNeeded;
LessNeeded := ctl.LessNeeded;
Fault := ctl.Fault;
Warning := ctl.Warning;
Speed := ctl.Speed;
Phase := ctl.Phase;

END_FUNCTION_BLOCK