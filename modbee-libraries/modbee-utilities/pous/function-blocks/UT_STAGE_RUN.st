(* UT_STAGE_RUN — the level stages of a pump station as one lean piece (private,
UT_PUMP_STATION). Stage n is on from its start point until its stop point:
EMPTY starts above and stops below (start > stop), FILL starts below and
stops above (start < stop); a stage the wrong way round or not a number is
not used. Stages 1..3 call one pump each; stage 4 calls every remaining pump
of a 5+ pump station. Stage 1's start can be moved (Start1, e.g. a random
variation). Run FALSE (level not trusted, disabled, inhibited, low float)
drops every stage. Stage 1 the wrong way round: StageBad (the station's
config fault; EMPTY keeps its float backup). *)

FUNCTION_BLOCK UT_STAGE_RUN
  VAR_INPUT
    Level : REAL;
    Empty : BOOL; (* TRUE: EMPTY (sump), FALSE: FILL (tank) *)
    Run : BOOL; (* the stages may act *)
    Members : INT; (* pumps in the station *)
    Start1 : REAL; (* stage 1's start in use (its setting, or moved by a variation) *)
  END_VAR
  VAR_OUTPUT
    Need : INT; (* pumps the level asks for *)
    LevelCall : BOOL; (* stage 1 is on: the level asks for pumping *)
    AtStop : BOOL; (* the level is at or past stage 1's stop point (a run's end) *)
    StageBad : BOOL; (* stage 1 the wrong way round or not a number *)
  END_VAR
  VAR_IN_OUT
    Stages : ARRAY [1..4] OF UT_STAGE;
  END_VAR
  VAR
    latch : ARRAY [1..4] OF BOOL;
    s : INT;
    st : REAL;
    sp : REAL;
    usable : BOOL;
  END_VAR


StageBad := NOT ((Empty AND Stages[1].start > Stages[1].stop) OR (NOT Empty AND Stages[1].start < Stages[1].stop))
            OR ABS(Stages[1].start) > 3.4E38 OR ABS(Stages[1].stop) > 3.4E38;
FOR s := 1 TO 4 DO
  st := Stages[s].start;
  IF s = 1 THEN st := Start1; END_IF;
  sp := Stages[s].stop;
  usable := ((Empty AND Stages[s].start > sp) OR (NOT Empty AND Stages[s].start < sp))
            AND ABS(Stages[s].start) <= 3.4E38 AND ABS(sp) <= 3.4E38;
  IF NOT Run OR NOT usable OR NOT (Level = Level) THEN
    latch[s] := FALSE;
  ELSIF Empty THEN
    IF Level >= st THEN
      latch[s] := TRUE;
    ELSIF Level <= sp THEN
      latch[s] := FALSE;
    END_IF;
  ELSIF Level <= st THEN
    latch[s] := TRUE;
  ELSIF Level >= sp THEN
    latch[s] := FALSE;
  END_IF;
END_FOR;
Need := 0;
FOR s := 1 TO 3 DO
  IF latch[s] THEN Need := Need + 1; END_IF;
END_FOR;
IF latch[4] AND Members > 3 THEN
  Need := Need + Members - 3;
END_IF;
IF Need > Members THEN Need := Members; END_IF;
IF Need < 0 THEN Need := 0; END_IF;
LevelCall := latch[1];
IF Empty THEN
  AtStop := Level <= Stages[1].stop;
ELSE
  AtStop := Level >= Stages[1].stop;
END_IF;

END_FUNCTION_BLOCK