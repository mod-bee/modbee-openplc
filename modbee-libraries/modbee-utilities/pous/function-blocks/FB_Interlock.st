(* FB_Interlock — the conditions that must all be healthy before a device may run, as one bOk signal (-> the
device's bInterlock or bPermissive), with first-out and maintenance bypasses.
Pins: bBypassEnable (key switch / HMI permission for bypasses), bReset (clear the first-out and the held
conditions), refData (set, sts), and the tables the project declares (VAR_IN_OUT, the same size, at most 16 rows):
aCondSet (each condition's settings) and aCond (each condition's live row: the project writes aCond[i].bOk on the
condition's own rung, the HMI aCond[i].bBypass) -> bOk (all healthy or bypassed), nFirstOut (the first condition
to stop the device since the last reset, 1-based; 0 = none), nNotOk, bBypassed (a bypass in effect: show it),
plus FB_Object's bError / bWarning / eErrorId / eState.
Each condition: tDelay (must be not OK this long to count); eReset Auto (OK again as soon as healthy), Manual
(held until a reset while healthy: pull cords, e-stops) or Retry (by itself while healthy, at most
set.nMaxRetries times in set.tRetryWindow, then held); a bypass (its bBypass, only when bBypassAllowed, while
bBypassEnable, for at most set.tBypassTimeout, 0 = never drops out; once timed out it stays off until the request
or bBypassEnable goes). nFirstOut: the condition that went out first (same scan: the lowest); after a reset with
conditions still out, the lowest of those. A reset acts in the same scan.
Errors: bError for no rows, tables of different sizes or more than 16 rows, or settings that were never good
(BadSetting); bWarning for a bypass (Bypassed) or a refused write (SettingRefused). Not OK is the block's job, not
an error: eState Held, eErrorId ConditionOut.
Kept settings (a retained last-good copy, restored at power-up, a bad write put back, sts.bRefused): set, and
each condition row packed into one DWORD: bits 0..1 eReset, 2 bBypassAllowed, 3..31 tDelay in 10 ms steps
(0 .. about 62 days; kept rounded down to 10 ms). *)

FUNCTION_BLOCK FB_Interlock EXTENDS FB_Object
  VAR_INPUT
    bBypassEnable : BOOL := FALSE; (* key switch / HMI permission for bypasses *)
    bReset : BOOL R_EDGE; (* clear the first-out and the held conditions *)
    refData : REFERENCE TO ST_IntlkData;
  END_VAR
  VAR_IN_OUT
    aCondSet : ARRAY [*] OF ST_INTLKCONDSET;
    aCond : ARRAY [*] OF ST_INTLKCOND;
  END_VAR
  VAR_OUTPUT
    bOk : BOOL; (* all OK or bypassed -> the device's bInterlock / bPermissive *)
    nFirstOut : INT; (* the first condition out since the reset (1-based; 0 = none) *)
    nNotOk : INT;
    bBypassed : BOOL; (* a bypass in effect (show it!) *)
  END_VAR
  VAR RETAIN
    stKept : ST_IntlkSet;
    aKeptCond : ARRAY [1..16] OF DWORD;
    nKeptRows : INT;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
    cMaxRows : INT := 16;
  END_VAR
  VAR
    bOkPrev : BOOL := TRUE;
    bResetSeen : BOOL;
  END_VAR
  VAR_TEMP
    bOkSet : BOOL;
    bRowsOk : BOOL;
    bCfgBad : BOOL;
    bResetReq : BOOL;
    bActive : BOOL;
    bBadSet : BOOL;
    nLb : DINT;
    nRows : INT;
    nI : INT;
    nR : DINT;
    nS : DINT;
    nFirst : INT;
    nWentFirst : INT;
    nPacked : DWORD;
  END_VAR


(* the block's settings are usable *)
METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_IntlkSet;
  END_VAR
  SetOk := stS.tBypassTimeout >= T#0s AND stS.nMaxRetries >= 0 AND stS.tRetryWindow >= T#0s;
END_METHOD

(* one condition's settings are usable (and fit the kept form) *)
METHOD PRIVATE CondOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_IntlkCondSet;
  END_VAR
  CondOk := stS.tDelay >= T#0s AND TIME_TO_LINT(stS.tDelay) / 10 <= 16#1FFFFFFF
            AND (stS.eReset = E_ResetMode.Auto OR stS.eReset = E_ResetMode.Retry
                 OR stS.eReset = E_ResetMode.Manual);
END_METHOD

(* one condition's settings as its kept DWORD, and back *)
METHOD PRIVATE Pack : DWORD
  VAR_INPUT
    stS : REFERENCE TO ST_IntlkCondSet;
  END_VAR
  Pack := SHL(LINT_TO_DWORD(TIME_TO_LINT(stS.tDelay) / 10), 3) OR USINT_TO_DWORD(TO_USINT(stS.eReset));
  IF stS.bBypassAllowed THEN
    Pack := Pack OR DWORD#16#4;
  END_IF;
END_METHOD

METHOD PRIVATE Unpack : BOOL
  VAR_INPUT
    nW : DWORD;
    stS : REFERENCE TO ST_IntlkCondSet;
  END_VAR
  stS.tDelay := LINT_TO_TIME(DWORD_TO_LINT(SHR(nW, 3)) * 10);
  CASE DWORD_TO_USINT(nW AND DWORD#16#3) OF
    0: stS.eReset := E_ResetMode.Manual;
    1: stS.eReset := E_ResetMode.Retry;
  ELSE
    stS.eReset := E_ResetMode.Auto;
  END_CASE;
  stS.bBypassAllowed := (nW AND DWORD#16#4) <> DWORD#0;
  Unpack := TRUE;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bOk := FALSE;
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();
nLb := LOWER_BOUND(aCond, 1);
nRows := DINT_TO_INT(UPPER_BOUND(aCond, 1) - nLb + 1);
bCfgBad := nRows < 1 OR nRows > cMaxRows
           OR UPPER_BOUND(aCondSet, 1) - LOWER_BOUND(aCondSet, 1) + 1 <> INT_TO_DINT(nRows);
IF bCfgBad THEN
  nRows := 0;
END_IF;

(* kept settings; a bad write is put back *)
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
    FOR nI := 1 TO MIN(nRows, nKeptRows) DO
      nS := LOWER_BOUND(aCondSet, 1) + nI - 1;
      Unpack(nW := aKeptCond[nI], stS := aCondSet[nS]);
    END_FOR;
  ELSE
    stKept := refData.set;
    nKeptLayout := cLayout;
  END_IF;
END_IF;
bOkSet := SetOk(stS := refData.set);
IF bOkSet THEN
  stKept := refData.set;
ELSIF SetOk(stS := stKept) THEN
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
  bOkSet := TRUE;
END_IF;
bRowsOk := TRUE;
FOR nI := 1 TO nRows DO
  nS := LOWER_BOUND(aCondSet, 1) + nI - 1;
  IF CondOk(stS := aCondSet[nS]) THEN
    aKeptCond[nI] := Pack(stS := aCondSet[nS]);
  ELSIF nI <= nKeptRows THEN
    Unpack(nW := aKeptCond[nI], stS := aCondSet[nS]);
    refData.sts.bRefused := TRUE;
  ELSE
    bRowsOk := FALSE;             (* never good: no copy to put back *)
  END_IF;
END_FOR;
IF nRows > nKeptRows AND bRowsOk THEN
  nKeptRows := nRows;
END_IF;

(* the reset: the pin, the system, the HMI once per write *)
bResetReq := bReset OR SystemReset() OR (refData.bCmdReset AND NOT bResetSeen);
bResetSeen := refData.bCmdReset;
refData.bCmdReset := FALSE;
IF bResetReq THEN
  nFirstOut := 0;
  refData.sts.bRefused := FALSE;
END_IF;

(* each condition *)
bOk := nRows > 0;
bBypassed := FALSE;
nNotOk := 0;
nFirst := 0;
nWentFirst := 0;
FOR nI := 1 TO nRows DO
  nR := nLb + nI - 1;
  nS := LOWER_BOUND(aCondSet, 1) + nI - 1;
  bBadSet := NOT CondOk(stS := aCondSet[nS]);
  (* not OK this long *)
  IF NOT aCond[nR].bOk AND NOT aCond[nR].bBad THEN
    aCond[nR].tBadSince := tNow;
  END_IF;
  aCond[nR].bBad := NOT aCond[nR].bOk;
  bActive := aCond[nR].bBad AND (aCondSet[nS].tDelay <= T#0s
                                 OR tNow - aCond[nR].tBadSince >= aCondSet[nS].tDelay);
  IF aCondSet[nS].eReset = E_ResetMode.Auto AND NOT bBadSet THEN
    aCond[nR].bLatched := FALSE;
  ELSIF bActive THEN
    aCond[nR].bLatched := TRUE;
  ELSIF aCond[nR].bLatched AND aCond[nR].bOk THEN
    IF bResetReq THEN
      aCond[nR].bLatched := FALSE;
    ELSIF aCondSet[nS].eReset = E_ResetMode.Retry AND NOT bBadSet THEN
      IF aCond[nR].nRetries > 0 AND tNow - aCond[nR].tWindowAt >= refData.set.tRetryWindow THEN
        aCond[nR].nRetries := 0;  (* a new window *)
      END_IF;
      IF aCond[nR].nRetries < refData.set.nMaxRetries THEN
        IF aCond[nR].nRetries = 0 THEN
          aCond[nR].tWindowAt := tNow;
        END_IF;
        aCond[nR].nRetries := aCond[nR].nRetries + 1;
        aCond[nR].bLatched := FALSE;   (* by itself, a few times *)
      END_IF;
    END_IF;
  END_IF;
  IF bResetReq AND aCond[nR].bOk THEN
    aCond[nR].nRetries := 0;
  END_IF;
  aCond[nR].bWentBad := (bActive OR aCond[nR].bLatched) AND NOT aCond[nR].bTripped;
  aCond[nR].bTripped := bActive OR aCond[nR].bLatched;
  (* the bypass: allowed, asked, permitted, within the timeout *)
  IF NOT (aCond[nR].bBypass AND aCondSet[nS].bBypassAllowed
          AND bBypassEnable AND bOkSet) THEN
    aCond[nR].bBypassOn := FALSE;
    aCond[nR].bBypassed := FALSE;
  ELSE
    IF NOT aCond[nR].bBypassOn THEN
      aCond[nR].bBypassOn := TRUE;
      aCond[nR].tBypassAt := tNow;
    END_IF;
    aCond[nR].bBypassed := refData.set.tBypassTimeout <= T#0s
                           OR tNow - aCond[nR].tBypassAt < refData.set.tBypassTimeout;
  END_IF;
  (* into the whole *)
  IF aCond[nR].bBypassed THEN
    bBypassed := TRUE;
  ELSIF aCond[nR].bTripped THEN
    bOk := FALSE;
    nNotOk := nNotOk + 1;
    IF nFirst = 0 THEN
      nFirst := nI;
    END_IF;
    IF aCond[nR].bWentBad AND nWentFirst = 0 THEN
      nWentFirst := nI;
    END_IF;
  END_IF;
END_FOR;

(* first-out: kept until a reset; the one that went out first (same scan: the lowest) *)
IF nFirstOut = 0 THEN
  IF nWentFirst > 0 THEN
    nFirstOut := nWentFirst;
  ELSE
    nFirstOut := nFirst;          (* after a reset (or power-up) with conditions still out *)
  END_IF;
END_IF;
IF bOkPrev AND NOT bOk THEN
  refData.sts.nTrips := refData.sts.nTrips + 1;
END_IF;
bOkPrev := bOk;

(* errors *)
bError := bCfgBad OR NOT bRowsOk OR NOT bOkSet;
bWarning := NOT bError AND (bBypassed OR refData.sts.bRefused);
IF bError THEN
  eErrorId := E_UtError.BadSetting;
ELSIF NOT bOk THEN
  eErrorId := E_UtError.ConditionOut;
ELSIF bBypassed THEN
  eErrorId := E_UtError.Bypassed;
ELSIF refData.sts.bRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN
  eState := E_State.Fault;
ELSIF NOT bOk THEN
  eState := E_State.Held;
ELSE
  eState := E_State.Running;
END_IF;
refData.sts.bOk := bOk;
refData.sts.nFirstOut := nFirstOut;
refData.sts.bBypassed := bBypassed;
refData.sts.nNotOk := nNotOk;
bFirstScan := FALSE;

END_FUNCTION_BLOCK