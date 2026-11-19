(* FB_ValveLatch EXTENDS FB_Valve — a latching valve: a DC latching solenoid (3-wire, or 2-wire through an
H-bridge) moved by a pulse on its open or close coil.
Everything of FB_Valve (modes, the safe position, the owner, end switches or travel time, protections, strokes,
actuator in Local, slow stroke, exercise) plus the pulses: bOpenOutput / bCloseOutput pulse for set.tCoilPulseLength (set.tOpenPulseLength / tClosePulseLength
when above 0) when the position commanded changes. The last
commanded position is kept over a power cut (written only on a move), so nothing is sent at power-up when the
wanted position is the kept one; a valve whose kept position is unknown gets its pulse. set.eValveType is not used. With
the actuator in Local no pulse is sent; a change of position is sent once it is back in Remote.
Pins added: refLatchingData (its record). Its settings are kept by the block (a retained last-good copy): restored at
power-up, a bad write put back. *)

FUNCTION_BLOCK FB_ValveLatch EXTENDS FB_Valve
  VAR_INPUT
    refLatchingData : REFERENCE TO ST_ValveLatchData; (* the latching valve record *)
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
  IF NOT (refLatchingData.set.tCoilPulseLength > T#0s) THEN
    LatchWhy := E_UtError.TimeBad;
  ELSIF NOT (refLatchingData.set.tOpenPulseLength >= T#0s) THEN
    LatchWhy := E_UtError.TimeBad;
  ELSIF NOT (refLatchingData.set.tClosePulseLength >= T#0s) THEN
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
  IF NOT bActuatorRemote THEN
    bPulsing := FALSE;            (* the actuator in Local: no pulse; a change is sent once it is back *)
    bOpenOutput := FALSE;
    bCloseOutput := FALSE;
    RETURN;
  END_IF;
  IF bWantOpen THEN nWant := 2; ELSE nWant := 1; END_IF;
  IF nWant <> nLastPos THEN
    nLastPos := nWant;
    bPulseOpen := bWantOpen;
    bPulsing := TRUE;
    tPulseAt := tNow;
  END_IF;
  IF bPulsing AND __ISVALIDREF(refLatchingData) THEN
    tLen := refLatchingData.set.tCoilPulseLength;
    IF bPulseOpen AND refLatchingData.set.tOpenPulseLength > T#0s THEN
      tLen := refLatchingData.set.tOpenPulseLength;
    ELSIF NOT bPulseOpen AND refLatchingData.set.tClosePulseLength > T#0s THEN
      tLen := refLatchingData.set.tClosePulseLength;
    END_IF;
    IF tNow - tPulseAt >= tLen THEN
      bPulsing := FALSE;
    END_IF;
  END_IF;
  bOpenOutput := bPulsing AND bPulseOpen;
  bCloseOutput := bPulsing AND NOT bPulseOpen;
END_METHOD

IF __ISVALIDREF(refLatchingData) THEN
  IF bLatchFirst THEN
    IF nKeptLatchLayout = cLatchLayout THEN
      refLatchingData.set := stKeptLatch;
    ELSE
      stKeptLatch := refLatchingData.set;
      nKeptLatchLayout := cLatchLayout;
    END_IF;
    bLatchFirst := FALSE;
  ELSIF LatchWhy() = E_UtError.None THEN
    stKeptLatch := refLatchingData.set;
  ELSE
    refLatchingData.sts.eSettingRefusedErrorId := LatchWhy();
    refLatchingData.set := stKeptLatch;
    refLatchingData.sts.bSettingRefused := TRUE;
  END_IF;
  IF bResetThisScan THEN                  // the equipment's reset clears a refused write
    refLatchingData.sts.bSettingRefused := FALSE;
    refLatchingData.sts.eSettingRefusedErrorId := E_UtError.None;
  END_IF;
END_IF;

SUPER^();                         // the valve: modes, the position commanded, travel, protections

IF __ISVALIDREF(refLatchingData) THEN
  refLatchingData.sts.bPulsing := bPulsing;
  refLatchingData.sts.nKeptPosition := nLastPos;
END_IF;

END_FUNCTION_BLOCK