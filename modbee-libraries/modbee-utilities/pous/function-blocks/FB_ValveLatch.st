(* FB_ValveLatch EXTENDS FB_Valve — a latching valve: a DC latching solenoid (3-wire, or 2-wire through an
H-bridge) moved by a pulse on its open or close coil.
Everything of FB_Valve (modes, the safe position, the owner, end switches or travel time, protections, strokes,
actuator in Local, slow stroke, exercise) plus the pulses: bOpenOut / bCloseOut pulse for set.tPulse (set.tOpenPulse / tClosePulse
when above 0) when the position commanded changes. The last
commanded position is kept over a power cut (written only on a move), so nothing is sent at power-up when the
wanted position is the kept one; a valve whose kept position is unknown gets its pulse. set.eType is not used. With
the actuator in Local no pulse is sent; a change of position is sent once it is back in Remote.
Pins added: refLatch (its record). Its settings are kept by the block (a retained last-good copy): restored at
power-up, a bad write put back. *)

FUNCTION_BLOCK FB_ValveLatch EXTENDS FB_Valve
  VAR_INPUT
    refLatch : REFERENCE TO ST_ValveLatchData;
  END_VAR
  VAR CONSTANT
    cLatchLayout : UINT := 2; (* the layout of its own kept settings *)
  END_VAR
  VAR RETAIN
    stKeptLatch : ST_ValveLatchSet;
    nKeptLatchLayout : UINT;
    nLastPos : USINT; (* 0 unknown, 1 closed, 2 open (written on a move only) *)
  END_VAR
  VAR
    bPulseOpen : BOOL;
    bPulsing : BOOL;
    tPulseAt : TIME;
    bLatchFirst : BOOL := TRUE;
  END_VAR


(* the first bad setting (None: all good) *)
METHOD PRIVATE LatchWhy : E_UtError
  LatchWhy := E_UtError.None;
  IF NOT (refLatch.set.tPulse > T#0s) THEN
    LatchWhy := E_UtError.TimeBad;
  ELSIF NOT (refLatch.set.tOpenPulse >= T#0s) THEN
    LatchWhy := E_UtError.TimeBad;
  ELSIF NOT (refLatch.set.tClosePulse >= T#0s) THEN
    LatchWhy := E_UtError.TimeBad;
  END_IF;
END_METHOD

(* the position commanded as pulses on a change *)
METHOD PROTECTED OVERRIDE Drive
  VAR_INPUT
    bRun : BOOL;
  END_VAR
  VAR
    nWant : USINT;
    tLen : TIME;
  END_VAR
  SUPER^.Drive(bRun := bRun);     // the position commanded (bWantOpen), with the safe position
  IF NOT bActRemote THEN
    bPulsing := FALSE;            (* the actuator in Local: no pulse; a change is sent once it is back *)
    bOpenOut := FALSE;
    bCloseOut := FALSE;
    RETURN;
  END_IF;
  IF bWantOpen THEN nWant := 2; ELSE nWant := 1; END_IF;
  IF nWant <> nLastPos THEN
    nLastPos := nWant;
    bPulseOpen := bWantOpen;
    bPulsing := TRUE;
    tPulseAt := tNow;
  END_IF;
  IF bPulsing AND __ISVALIDREF(refLatch) THEN
    tLen := refLatch.set.tPulse;
    IF bPulseOpen AND refLatch.set.tOpenPulse > T#0s THEN
      tLen := refLatch.set.tOpenPulse;
    ELSIF NOT bPulseOpen AND refLatch.set.tClosePulse > T#0s THEN
      tLen := refLatch.set.tClosePulse;
    END_IF;
    IF tNow - tPulseAt >= tLen THEN
      bPulsing := FALSE;
    END_IF;
  END_IF;
  bOpenOut := bPulsing AND bPulseOpen;
  bCloseOut := bPulsing AND NOT bPulseOpen;
END_METHOD

IF __ISVALIDREF(refLatch) THEN
  IF bLatchFirst THEN
    IF nKeptLatchLayout = cLatchLayout THEN
      refLatch.set := stKeptLatch;
    ELSE
      stKeptLatch := refLatch.set;
      nKeptLatchLayout := cLatchLayout;
    END_IF;
    bLatchFirst := FALSE;
  ELSIF LatchWhy() = E_UtError.None THEN
    stKeptLatch := refLatch.set;
  ELSE
    refLatch.sts.eRefusedWhy := LatchWhy();
    refLatch.set := stKeptLatch;
    refLatch.sts.bRefused := TRUE;
  END_IF;
  IF bResetThisScan THEN                  // the equipment's reset clears a refused write
    refLatch.sts.bRefused := FALSE;
    refLatch.sts.eRefusedWhy := E_UtError.None;
  END_IF;
END_IF;

SUPER^();                         // the valve: modes, the position commanded, travel, protections

IF __ISVALIDREF(refLatch) THEN
  refLatch.sts.bPulsing := bPulsing;
  refLatch.sts.nLastPos := nLastPos;
END_IF;

END_FUNCTION_BLOCK