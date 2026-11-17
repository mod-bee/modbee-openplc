(* FB_RunStyle — how a run takes its signal: a front end for FB_Run (or any block with a held run pin), in the style
the installer picks (set.eStyle):
  Held       bRun follows bIn
  Toggle     each rising edge of bIn flips bRun (a push-on / push-off button)
  KeepAlive  bRun while bIn keeps changing (pulses from a remote unit); off set.tKeepAlive after the last change
             (bLost for one scan)
  Pulse      a rising edge of bIn: with set.tPulse = 0 a one-scan bStart (the run's own target ends it: wire bStart
             to FB_Run.bStart); with set.tPulse > 0, bRun for tPulse
bStop (rising edge) ends a Toggle / Pulse run and forgets it. Edges in the first scan are ignored: nothing starts
at power-up. Its settings are kept by the block (a retained last-good copy): restored at power-up, a bad write
put back. *)

FUNCTION_BLOCK FB_RunStyle EXTENDS FB_Object
  VAR_INPUT
    bIn : BOOL; (* the run signal (held, toggled, pulsed, kept alive) *)
    bStop : BOOL; (* rising edge: ends a latched run *)
    refData : REFERENCE TO ST_RunStyleData;
  END_VAR
  VAR_OUTPUT
    bRun : BOOL; (* -> FB_Run.bRun (held) *)
    bStart : BOOL; (* one scan -> FB_Run.bStart (Pulse with the run's own target) *)
    bLost : BOOL; (* one scan: KeepAlive pulses stopped *)
  END_VAR
  VAR RETAIN
    stKept : ST_RunStyleSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    bInPrev : BOOL;
    bStopPrev : BOOL;
    bLatched : BOOL;
    tAt : TIME; (* the last change (KeepAlive), the pulse start (Pulse) *)
    bAlive : BOOL;
  END_VAR
  VAR_TEMP
    bOk : BOOL;
    bEdge : BOOL;
    bStopEdge : BOOL;
  END_VAR


METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_RunStyleSet;
  END_VAR
  SetOk := (stS.eStyle = E_RunStyle.Held OR stS.eStyle = E_RunStyle.Toggle OR stS.eStyle = E_RunStyle.Pulse
            OR (stS.eStyle = E_RunStyle.KeepAlive AND stS.tKeepAlive > T#0s))
           AND stS.tKeepAlive >= T#0s AND stS.tPulse >= T#0s;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bRun := FALSE;
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();
bStart := FALSE;
bLost := FALSE;
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
  ELSE
    stKept := refData.set;
    nKeptLayout := cLayout;
  END_IF;
  bInPrev := bIn;                 (* no edge at power-up *)
  bStopPrev := bStop;
  tAt := tNow;
END_IF;
bOk := SetOk(stS := refData.set);
IF bOk THEN
  stKept := refData.set;
ELSIF SetOk(stS := stKept) THEN
  refData.set := stKept;
  refData.bRefused := TRUE;
  bOk := TRUE;
END_IF;
bEdge := bIn AND NOT bInPrev;
bStopEdge := bStop AND NOT bStopPrev;
IF bStopEdge THEN
  bLatched := FALSE;
END_IF;

CASE refData.set.eStyle OF
  E_RunStyle.Toggle:
    IF bEdge AND NOT bStopEdge THEN
      bLatched := NOT bLatched;
    END_IF;
    bRun := bLatched;
  E_RunStyle.KeepAlive:
    IF bIn <> bInPrev THEN
      tAt := tNow;
      bAlive := TRUE;
    ELSIF bAlive AND tNow - tAt >= refData.set.tKeepAlive THEN
      bAlive := FALSE;
      bLost := TRUE;
    END_IF;
    bRun := bAlive AND bOk;
  E_RunStyle.Pulse:
    IF bEdge AND NOT bStopEdge THEN
      IF refData.set.tPulse > T#0s THEN
        bLatched := TRUE;
        tAt := tNow;
      ELSE
        bStart := TRUE;
      END_IF;
    END_IF;
    IF bLatched AND tNow - tAt >= refData.set.tPulse THEN
      bLatched := FALSE;
    END_IF;
    bRun := bLatched;
ELSE
  bRun := bIn;
END_CASE;
bInPrev := bIn;
bStopPrev := bStop;
refData.bRun := bRun;
bError := NOT bOk;
bWarning := NOT bError AND (bLost OR refData.bRefused);
IF NOT bOk THEN
  eErrorId := E_UtError.BadSetting;
ELSIF bLost THEN
  eErrorId := E_UtError.LinkLost;
ELSIF refData.bRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bRun THEN eState := E_State.Running; ELSE eState := E_State.Idle; END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK