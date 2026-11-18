(* FB_AlarmBeacon — flash alarm numbers on a single lamp, for sites with one fault lamp and no HMI.
aAlarms (the project's array of BOOL, one per alarm; alarm number = index - lower bound + 1; write it with coils).
The block steps through every active alarm in turn (from the lowest after an idle spell, then round again) and
flashes its number: Count (that many short flashes) or Binary (set.nBits flashes, most significant bit first:
long = 1, short = 0; a number too big for nBits uses as many bits as it needs, up to 15). Flashes are separated by
tGap, numbers by tPause. A number that has started is always finished, even if its alarm clears meanwhile; each
time lasts at least one scan. set.bSteadyWhenNone: the lamp on steady while no alarm is active.
Pins: bEnable, refData, aAlarms -> bLamp, nCode (the number being shown, 0 = none), bActive (any alarm), plus
FB_Object's outputs. Settings are kept (a retained last-good copy, a bad write put back). *)

FUNCTION_BLOCK FB_AlarmBeacon EXTENDS FB_Object
  VAR_INPUT
    bEnable : BOOL := TRUE;
    refData : REFERENCE TO ST_BeaconData;
  END_VAR
  VAR_IN_OUT
    aAlarms : ARRAY [*] OF BOOL;
  END_VAR
  VAR_OUTPUT
    bLamp : BOOL;
    nCode : INT; (* the alarm number being shown (0 = none) *)
    bActive : BOOL; (* any alarm *)
  END_VAR
  VAR RETAIN
    stKept : ST_BeaconSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    nPhase : INT; (* 0 choose, 1 flash, 2 gap, 3 pause *)
    tPhaseStart : TIME;
    nCur : DINT; (* the index being shown *)
    nShown : INT;
    nPulses : INT;
    nPulse : INT;
    nWeight : DINT; (* Binary: the value of the bit now *)
    nRest : DINT; (* Binary: what is left to show *)
    tOnLen : TIME;
    bBinary : BOOL;
  END_VAR
  VAR_TEMP
    bOk : BOOL;
    nI : DINT;
    nJ : DINT;
    nLo : DINT;
    nHi : DINT;
    nN : INT;
    bFound : BOOL;
    bStartPulse : BOOL;
    nBitsNow : INT;
  END_VAR


METHOD PRIVATE SetWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_BeaconSet;
  END_VAR
  SetWhy := E_UtError.None;
  IF NOT (stS.eStyle = E_BeaconStyle.Count OR stS.eStyle = E_BeaconStyle.Binary) THEN
    SetWhy := E_UtError.ChoiceBad;
  ELSIF NOT (stS.nBits >= 1) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.nBits <= 15) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.tShort > T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tLong > T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tGap > T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tPause > T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_BeaconSet;
  END_VAR
  SetOk := SetWhy(stS := stS) = E_UtError.None;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bLamp := FALSE;
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();
nLo := LOWER_BOUND(aAlarms, 1);
nHi := UPPER_BOUND(aAlarms, 1);
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
  ELSE
    stKept := refData.set;
    nKeptLayout := cLayout;
  END_IF;
  nCur := nLo - 1;
END_IF;
bOk := SetOk(stS := refData.set);
IF bOk THEN
  stKept := refData.set;
ELSIF SetOk(stS := stKept) THEN
  refData.eRefusedWhy := SetWhy(stS := refData.set);
  refData.set := stKept;
  refData.bRefused := TRUE;
  bOk := TRUE;
END_IF;
IF SystemReset() THEN
  refData.bRefused := FALSE;
  refData.eRefusedWhy := E_UtError.None;
END_IF;
nN := 0;
FOR nI := nLo TO nHi DO
  IF aAlarms[nI] THEN
    nN := nN + 1;
  END_IF;
END_FOR;
bActive := nN > 0;
refData.nActive := nN;
bError := NOT bOk;
bWarning := NOT bError AND refData.bRefused;
IF NOT bOk THEN eErrorId := E_UtError.BadSetting;
ELSIF refData.bRefused THEN eErrorId := E_UtError.SettingRefused;
ELSE eErrorId := E_UtError.None;
END_IF;
IF NOT bEnable OR NOT bOk THEN
  nPhase := 0;
  nCur := nLo - 1;
  nShown := 0;
  bLamp := FALSE;
  nCode := 0;
  refData.nCode := 0;
  IF bError THEN eState := E_State.Fault; ELSE eState := E_State.Off; END_IF;
  bFirstScan := FALSE;
  RETURN;
END_IF;

bStartPulse := FALSE;
IF nPhase = 3 AND tNow - tPhaseStart >= refData.set.tPause THEN
  nPhase := 0;
END_IF;
IF nPhase = 0 THEN
  (* the next active alarm after the one just shown, round the array *)
  bFound := FALSE;
  nJ := nCur;
  FOR nI := nLo TO nHi DO
    nJ := nJ + 1;
    IF nJ > nHi OR nJ < nLo THEN
      nJ := nLo;
    END_IF;
    IF aAlarms[nJ] THEN
      bFound := TRUE;
      EXIT;
    END_IF;
  END_FOR;
  IF bFound THEN
    IF nShown = 0 AND refData.set.bSteadyWhenNone THEN
      nPhase := 2;                (* lamp off first, so the first flash shows *)
      tPhaseStart := tNow;
    ELSE
      bStartPulse := TRUE;
    END_IF;
    nCur := nJ;
    nShown := DINT_TO_INT(nJ - nLo + 1);
    nPulse := 0;
    bBinary := refData.set.eStyle = E_BeaconStyle.Binary;
    IF bBinary THEN
      nBitsNow := LIMIT(1, refData.set.nBits, 15);
      nWeight := 1;
      FOR nI := 2 TO INT_TO_DINT(nBitsNow) DO
        nWeight := nWeight * 2;
      END_FOR;
      FOR nI := 1 TO 14 DO        (* more bits while the number needs them (at most 15 in all) *)
        IF nBitsNow >= 15 OR INT_TO_DINT(nShown) < nWeight * 2 THEN
          EXIT;
        END_IF;
        nBitsNow := nBitsNow + 1;
        nWeight := nWeight * 2;
      END_FOR;
      nPulses := nBitsNow;
      nRest := INT_TO_DINT(nShown);
    ELSE
      nPulses := nShown;
    END_IF;
  ELSE
    nShown := 0;
    nCur := nLo - 1;              (* idle: start from the lowest next time *)
  END_IF;
ELSIF nPhase = 2 AND tNow - tPhaseStart >= refData.set.tGap THEN
  bStartPulse := TRUE;
ELSIF nPhase = 1 AND tNow - tPhaseStart >= tOnLen THEN
  IF nPulse >= nPulses THEN
    nPhase := 3;
  ELSE
    nPhase := 2;
  END_IF;
  tPhaseStart := tNow;
END_IF;
IF bStartPulse THEN
  nPulse := nPulse + 1;
  tOnLen := refData.set.tShort;
  IF bBinary THEN
    IF nRest >= nWeight THEN
      tOnLen := refData.set.tLong;
      nRest := nRest - nWeight;
    END_IF;
    nWeight := nWeight / 2;
  END_IF;
  nPhase := 1;
  tPhaseStart := tNow;
END_IF;
bLamp := nPhase = 1 OR (nPhase = 0 AND refData.set.bSteadyWhenNone);
nCode := nShown;
refData.nCode := nShown;
IF nShown > 0 THEN eState := E_State.Running; ELSE eState := E_State.Idle; END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK