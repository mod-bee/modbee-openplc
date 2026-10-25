(* UT_ALIVE — is a signal still changing? A BOOL that toggles or a counter that
moves (a heartbeat, a keep-alive input) must change within Within.

Alive  changed within Within (FALSE until the first change)
Lost   one scan: it was alive and has stopped changing
Seen   it has changed at least once since start / Restart
Changed  one scan: it changed this scan
Since  time since the last change

UT_RUN_INPUT — how a running block takes its run signal: Run (held), Start /
Stop (rising edges, Stop wins), the HMI / SCADA commands, in the style the
installer picks (Set.style):

HELD         runs while Run is TRUE. A Stop while Run is held stops it and
             keeps it stopped until Run is released (no restart behind a
             Stop); so does a run that ended at its target (Drop with
             TargetDone) while Run is held. Start / Stop pulses work as well.
TOGGLE       each rising edge of Run starts, the next stops (a push-on /
             push-off button). Start / Stop pulses work as well.
KEEPALIVE    runs while Run keeps changing (pulses from a remote unit); off
             keepAlive after the last change (AliveLost: stop reason
             "run signal stopped"); a stuck input stops it too.
PULSE_TIMER  a rising edge of Run (or Start) starts a run: with the block's
             own target (HasTarget) it runs until TargetDone; without one it
             runs pulseTime. pulseTime <= 0 with no target: BadSetting, no
             start.

Drop stops it and forgets a latched run (Off, an interlock, system Off).
Linked: an owner commands the block through its plug: the local signals do
nothing (StartEdge still tells the block, for its 'local start ignored'
warning). Edges in the first scan are ignored: nothing starts at power-up.
The run signal has no comms meaning (decision 59). *)

FUNCTION_BLOCK UT_RUN_INPUT
  VAR_INPUT
    Run : BOOL; (* the run signal (held, toggled, pulsed) *)
    Start : BOOL; (* start: rising edge *)
    Stop : BOOL; (* stop: rising edge, wins *)
    CmdStart : BOOL; (* HMI / SCADA start (rising edge) *)
    CmdStop : BOOL; (* HMI / SCADA stop (rising edge) *)
    Drop : BOOL; (* stop and forget (Off, interlock, system Off) *)
    Linked : BOOL; (* an owner commands the block: local signals do nothing *)
    TargetDone : BOOL; (* the block's own target is reached (PULSE_TIMER: ends the run; HELD: no restart while Run is held) *)
    HasTarget : BOOL; (* the block has its own time / volume target *)
  END_VAR
  VAR_OUTPUT
    Request : BOOL; (* run requested *)
    StartEdge : BOOL; (* one scan: a start (Run edge, Start, CmdStart) *)
    StopEdge : BOOL; (* one scan: a stop (Stop, CmdStop) *)
    Latched : BOOL; (* a run started by a pulse is going on *)
    AliveLost : BOOL; (* one scan: KEEPALIVE pulses stopped *)
    BadSetting : BOOL; (* the style or its time is not usable *)
  END_VAR
  VAR_IN_OUT
    Set : UT_RUN_IN_SET;
  END_VAR
  VAR
    alive : UT_ALIVE;
    started : BOOL;
    runPrev : BOOL;
    startPrev : BOOL;
    stopPrev : BOOL;
    cmdStartPrev : BOOL;
    cmdStopPrev : BOOL;
    runEdge : BOOL;
    blocked : BOOL; (* HELD: a Stop (or a run done at its target) while Run is held, until Run drops *)
    timedAt : TIME;
    now : TIME;
    first : BOOL;
  END_VAR


now := TIME();
first := NOT started;
started := TRUE;
runEdge := Run AND NOT runPrev AND NOT first;
StartEdge := runEdge OR (Start AND NOT startPrev AND NOT first) OR (CmdStart AND NOT cmdStartPrev AND NOT first);
StopEdge := (Stop AND NOT stopPrev) OR (CmdStop AND NOT cmdStopPrev);
runPrev := Run;
startPrev := Start;
stopPrev := Stop;
cmdStartPrev := CmdStart;
cmdStopPrev := CmdStop;
AliveLost := FALSE;
BadSetting := FALSE;

alive(In := Run, Count := 0, Within := Set.keepAlive, Restart := Set.style <> UT_RS_KEEPALIVE OR Drop OR Linked);

IF Drop OR Linked THEN
  Latched := FALSE;
  blocked := Run AND TargetDone;   (* the run ended at its target with Run still held: no new run until Run drops *)
  Request := FALSE;
  RETURN;
END_IF;
IF StopEdge THEN
  Latched := FALSE;
  IF Run THEN blocked := TRUE; END_IF;
END_IF;
IF NOT Run THEN
  blocked := FALSE;
END_IF;

CASE Set.style OF
  UT_RS_HELD:
    IF StartEdge AND NOT StopEdge AND NOT runEdge THEN Latched := TRUE; END_IF;
    Request := (Run AND NOT blocked) OR Latched;
  UT_RS_TOGGLE:
    IF runEdge AND NOT StopEdge THEN
      Latched := NOT Latched;
    ELSIF StartEdge AND NOT StopEdge THEN
      Latched := TRUE;
    END_IF;
    Request := Latched;
  UT_RS_KEEPALIVE:
    IF alive.Lost THEN AliveLost := TRUE; END_IF;
    IF StartEdge AND NOT StopEdge AND NOT runEdge THEN Latched := TRUE; END_IF;
    Request := (alive.Alive AND NOT blocked) OR Latched;
    BadSetting := Set.keepAlive <= T#0s;
  UT_RS_PULSE_TIMER:
    IF NOT HasTarget AND Set.pulseTime <= T#0s THEN
      BadSetting := TRUE;
      Latched := FALSE;
    ELSIF StartEdge AND NOT StopEdge THEN
      Latched := TRUE;
      timedAt := now;
    END_IF;
    IF Latched THEN
      IF HasTarget THEN
        IF TargetDone THEN Latched := FALSE; END_IF;
      ELSIF now - timedAt >= Set.pulseTime THEN
        Latched := FALSE;
      END_IF;
    END_IF;
    Request := Latched;
ELSE
  BadSetting := TRUE;            // a style that is not one: no run
  Latched := FALSE;
  Request := FALSE;
END_CASE;

END_FUNCTION_BLOCK