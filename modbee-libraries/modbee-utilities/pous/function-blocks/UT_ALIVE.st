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

FUNCTION_BLOCK UT_ALIVE
  VAR_INPUT
    In : BOOL; (* a toggling signal *)
    Count : DINT; (* or a counter that moves *)
    Within : TIME := T#30s; (* must change within this *)
    Restart : BOOL; (* forget the state (not alive, not seen) *)
  END_VAR
  VAR_OUTPUT
    Alive : BOOL;
    Lost : BOOL;
    Seen : BOOL;
    Changed : BOOL;
    Since : TIME;
  END_VAR
  VAR
    started : BOOL;
    inPrev : BOOL;
    countPrev : DINT;
    lastAt : TIME;
    now : TIME;
  END_VAR


now := TIME();
Lost := FALSE;
Changed := FALSE;
IF NOT started OR Restart THEN
  started := TRUE;
  inPrev := In;
  countPrev := Count;
  lastAt := now;
  Seen := FALSE;
  Alive := FALSE;
  Since := T#0s;
  RETURN;
END_IF;
IF In <> inPrev OR Count <> countPrev THEN
  Changed := TRUE;
  Seen := TRUE;
  lastAt := now;
END_IF;
inPrev := In;
countPrev := Count;
Since := now - lastAt;
IF Changed THEN
  Alive := TRUE;
ELSIF Alive AND (Within <= T#0s OR Since >= Within) THEN
  Alive := FALSE;
  Lost := TRUE;
END_IF;

END_FUNCTION_BLOCK