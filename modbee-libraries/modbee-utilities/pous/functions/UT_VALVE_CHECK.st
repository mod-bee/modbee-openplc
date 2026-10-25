(* UT_VALVE — a two-position valve, cylinder or damper (every kind of decision
4); the base of UT_VALVE_FLOAT and UT_VALVE_MOD (81b). Offers the UT_I_VALVE
plug: an owner (a zone, a route, a station) wires the instance to its Valve
pin and calls Request every scan. No Run pin (a valve opens).

Who moves it: OOS = every output off (spring kinds go to their spring side);
Off = the safe position; Hand = LocalOpen / LocalClose / LocalStop, cmdOpen /
cmdClose / cmdStop, OpenCmd / CloseCmd (bumpless entry; Interlock / a trip
set the Hand target safe); Auto linked = the owner's ReqOpen (own Open
ignored; CloseCmd / cmdClose hold it closed until the owner's open drops);
Auto = Open per set.input (HELD / TOGGLE / KEEPALIVE / PULSE_TIMER), OpenCmd
latch, CloseCmd. Every mode: Interlock FALSE / a trip -> safe; a config
fault -> outputs off; Permissive FALSE holds back a move away from safe.

Kinds (set.valveType): SPRING (NC solenoid / spring-return motor: OpenOut
held), SPRING_NO (NO solenoid: CloseOut held to close), DOUBLE_HELD (5/2:
OpenOut / CloseOut held), DOUBLE_PULSE (latching 3-wire or 2-wire H-bridge:
OpenOut / CloseOut pulses), MOTOR (OpenOut / CloseOut drive with a reversal
pause; driveHold keeps the drive on at the end). Open / closed: by the end
switch when fitted (useOpenLs / useClosedLs), else after openTime /
closeTime from the drive (UT_TRAVEL_RUN). Latching: no automatic re-pulse,
nothing sent at power-up (the last commanded position is kept, tot.lastPos),
a fresh command re-sends its pulse, Reset takes the requested position as
true and sends nothing.

Exercise (exerciseEnable): one open-hold-close cycle when resting in Auto
for exerciseEvery, or on the Exercise pin / cmdExercise; a request wins.
Settings kept; a bad write is put back (decision 62).

Variants (EXTENDS) set vOwnTravel and the hooks before SUPER(); the base
then runs the core and the common outputs and skips its two-position travel. *)

FUNCTION UT_VALVE_CHECK : BOOL
  VAR_INPUT
    TwoPos : BOOL; (* the two-position settings are in use (UT_VALVE itself) *)
  END_VAR
  VAR_IN_OUT
    S : UT_VALVE_SET;
  END_VAR
  VAR_OUTPUT
    Fault : UT_FAULT;
    Warn : UT_FAULT;
  END_VAR
  VAR
    latching : BOOL;
  END_VAR


Fault := UT_F_NONE;
Warn := UT_F_NONE;
latching := S.valveType = UT_VT_DOUBLE_PULSE;
IF NOT (S.modeSource = UT_SRC_HMI OR S.modeSource = UT_SRC_SWITCH OR S.modeSource = UT_SRC_REMOTE) THEN
  Fault := UT_F_MODE_SOURCE;
ELSIF TwoPos AND NOT (S.valveType = UT_VT_SPRING OR S.valveType = UT_VT_SPRING_NO OR S.valveType = UT_VT_DOUBLE_HELD
                      OR S.valveType = UT_VT_DOUBLE_PULSE OR S.valveType = UT_VT_MOTOR) THEN
  Fault := UT_F_VALVE_TYPE;
ELSIF TwoPos AND (S.openTime <= T#0s OR S.closeTime <= T#0s) THEN
  Fault := UT_F_TRAVEL_TIME;
ELSIF TwoPos AND latching AND NOT (S.openPulse >= T#10ms AND S.openPulse <= T#2s AND S.closePulse >= T#10ms
                                   AND S.closePulse <= T#2s) THEN
  Fault := UT_F_PULSE_TIME;
ELSIF TwoPos AND latching AND (S.openTime < S.openPulse OR S.closeTime < S.closePulse) THEN
  Fault := UT_F_TRAVEL_TIME;
ELSIF S.reversalDelay < T#0s AND S.valveType = UT_VT_MOTOR THEN
  Fault := UT_F_REVERSAL_DELAY;
ELSIF TwoPos AND NOT (S.safePosition = UT_SAFE_CLOSED OR S.safePosition = UT_SAFE_OPEN OR S.safePosition = UT_SAFE_HOLD) THEN
  Fault := UT_F_SAFE_POSITION;
END_IF;
IF NOT (S.input.style = UT_RS_HELD OR S.input.style = UT_RS_TOGGLE
        OR (S.input.style = UT_RS_KEEPALIVE AND S.input.keepAlive > T#0s)
        OR (S.input.style = UT_RS_PULSE_TIMER AND S.input.pulseTime > T#0s)) THEN
  Warn := UT_F_RUN_STYLE;
ELSIF S.retryWindow < T#0s THEN
  Warn := UT_F_RETRY_WINDOW;
ELSIF S.exerciseEvery < T#0s OR S.exerciseTime < T#0s THEN
  Warn := UT_F_EXERCISE;
ELSIF S.strokeWarn < T#0s THEN
  Warn := UT_F_STROKE_WARN;
ELSIF TwoPos AND NOT latching AND NOT (S.openPulse >= T#10ms AND S.openPulse <= T#2s AND S.closePulse >= T#10ms
                                       AND S.closePulse <= T#2s) THEN
  Warn := UT_F_PULSE_TIME;
ELSIF S.reversalDelay < T#0s THEN
  Warn := UT_F_REVERSAL_DELAY;
ELSIF NOT (UT_PROT_OK(P := S.openTimeout) AND UT_PROT_OK(P := S.closeTimeout) AND UT_PROT_OK(P := S.bothLimits)
           AND UT_PROT_OK(P := S.positionLost) AND UT_PROT_OK(P := S.noMovement) AND UT_PROT_OK(P := S.drive)
           AND UT_PROT_OK(P := S.torque) AND UT_PROT_OK(P := S.actLocal) AND UT_PROT_OK(P := S.slowStroke)) THEN
  Warn := UT_F_SETTING;
END_IF;
UT_VALVE_CHECK := Fault = UT_F_NONE AND Warn = UT_F_NONE;

END_FUNCTION