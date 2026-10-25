(* UT_TOGGLE — push-on / push-off.
Each press of the pushbutton (a rising edge on In) flips Q. Holding the
button does nothing more. Reset forces Q off and wins over everything;
ForceOn forces Q on; both act while held, and a press meanwhile is ignored.
Q is not kept over a power cut: it starts off. A button already held at the
first scan counts as a press only with EdgeAtStart (a stuck or held button
never switches a machine on by itself at power-up). *)

FUNCTION_BLOCK UT_TOGGLE
  VAR_INPUT
    In : BOOL R_EDGE; (* pushbutton: each press flips Q *)
    Reset : BOOL; (* forces Q off (wins) *)
    ForceOn : BOOL; (* forces Q on *)
    EdgeAtStart : BOOL; (* a button held at the first scan counts as a press *)
  END_VAR
  VAR_OUTPUT
    Q : BOOL;
  END_VAR
  VAR
    state : BOOL;
    started : BOOL;
    firstScan : BOOL;
  END_VAR


firstScan := NOT started;
started := TRUE;
IF Reset THEN
  state := FALSE;
ELSIF ForceOn THEN
  state := TRUE;
ELSIF In AND (NOT firstScan OR EdgeAtStart) THEN
  state := NOT state;
END_IF;
Q := state;

END_FUNCTION_BLOCK