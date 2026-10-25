(* UT_TRAVEL_RUN — one move of a valve or actuator to a target position.
Private shared piece (UT_VALVE, UT_VALVE_3POS).

With the target's switch fitted (UseSw) the move ends when the switch makes;
Travel is then a timeout (Timeout, or NoMove when the switch of the position
left is still made). Without a switch the position is taken after Travel.
A switch that drops right after arriving (within Travel of the start) is a
flicker: the move carries on; later it is Lost. Both the target's switch and
another one made at once: BothSw. A completed move gives StrokeDone once;
StrokeTime is the last confirmed stroke. Go FALSE stops the move where it is
(position unknown). Assume >= 1 takes that position as reached; Forget makes
the position unknown; PowerUp takes the position from the switch only. *)

FUNCTION_BLOCK UT_TRAVEL_RUN
  VAR_INPUT
    Target : INT; (* position wanted (0 = none: stop where it is) *)
    Go : BOOL; (* the drive for this move is on *)
    AtSw : BOOL; (* the target's switch made *)
    UseSw : BOOL; (* the target's switch is fitted *)
    LeftSw : BOOL; (* the switch of the position left is still made *)
    OtherSw : BOOL; (* a switch that must not be made at the target is made *)
    Travel : TIME; (* this move's time: timeout with a switch, arrival without *)
    Assume : INT := -1; (* >= 1: take this position as reached *)
    Forget : BOOL; (* position unknown now *)
    PowerUp : BOOL; (* position from the switch only *)
  END_VAR
  VAR_OUTPUT
    Pos : INT := -1; (* position reached (-1 unknown / moving) *)
    Confirmed : BOOL; (* Pos from a switch *)
    Moving : BOOL;
    Elapsed : TIME;
    TimeLeft : TIME;
    Timeout : BOOL;
    Lost : BOOL;
    NoMove : BOOL;
    BothSw : BOOL;
    StrokeDone : BOOL;
    StrokeTime : TIME;
  END_VAR
  VAR
    now : TIME;
    moveStart : TIME;
    lastTarget : INT;
    counted : BOOL;
    goPrev : BOOL;
    arrivedAt : TIME;
    flickerOk : BOOL;
  END_VAR


now := TIME();
StrokeDone := FALSE;
IF PowerUp THEN
  Moving := FALSE;
  Timeout := FALSE;
  Lost := FALSE;
  NoMove := FALSE;
  IF UseSw AND AtSw AND Target >= 1 THEN
    Pos := Target;
    Confirmed := TRUE;
  ELSE
    Pos := -1;
    Confirmed := FALSE;
  END_IF;
  lastTarget := Target;
  goPrev := Go;
END_IF;
IF Forget THEN
  Pos := -1;
  Confirmed := FALSE;
  Moving := FALSE;
END_IF;
IF Assume >= 1 THEN
  Pos := Assume;
  Confirmed := FALSE;
  Moving := FALSE;
  Timeout := FALSE;
  Lost := FALSE;
  NoMove := FALSE;
END_IF;
IF Target <> lastTarget THEN
  lastTarget := Target;
  Moving := FALSE;
  Timeout := FALSE;
  NoMove := FALSE;
  Lost := FALSE;
  counted := FALSE;
  flickerOk := FALSE;
  IF Target <> Pos THEN Pos := -1; Confirmed := FALSE; END_IF;
END_IF;
(* a move starts when the drive comes on for a target not reached *)
IF Go AND Target >= 1 AND NOT Moving AND Pos <> Target AND NOT Timeout AND NOT NoMove THEN
  Moving := TRUE;
  moveStart := now;
  counted := FALSE;
END_IF;
IF NOT Go AND Moving THEN
  Moving := FALSE;                 (* stopped where it is *)
  Pos := -1;
  Confirmed := FALSE;
END_IF;
goPrev := Go;
Elapsed := T#0s;
TimeLeft := T#0s;
IF Moving THEN
  Elapsed := now - moveStart;
  TimeLeft := Travel - Elapsed;
  IF TimeLeft < T#0s THEN TimeLeft := T#0s; END_IF;
  IF (UseSw AND AtSw) OR (NOT UseSw AND Elapsed >= Travel) THEN
    Moving := FALSE;
    Pos := Target;
    Confirmed := UseSw;
    arrivedAt := now;
    flickerOk := UseSw;
    IF UseSw THEN StrokeTime := Elapsed; END_IF;
    IF NOT counted THEN
      StrokeDone := TRUE;
      counted := TRUE;
    END_IF;
  ELSIF UseSw AND Elapsed >= Travel THEN
    Moving := FALSE;
    Pos := -1;
    IF LeftSw THEN NoMove := TRUE; ELSE Timeout := TRUE; END_IF;
  END_IF;
ELSIF UseSw AND Pos = Target AND Target >= 1 AND NOT AtSw THEN
  IF flickerOk AND now - moveStart < Travel THEN
    Moving := TRUE;                (* the switch only flickered: still travelling *)
    Pos := -1;
    Confirmed := FALSE;
  ELSE
    Lost := TRUE;
    Pos := -1;
    Confirmed := FALSE;
  END_IF;
  flickerOk := FALSE;
END_IF;
IF flickerOk AND now - moveStart >= Travel THEN flickerOk := FALSE; END_IF;
BothSw := AtSw AND OtherSw;

END_FUNCTION_BLOCK