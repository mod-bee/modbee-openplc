(* FB_SettingArray — FB_SettingCheck for a list of project values (src-v2 UT_SETTING_ARRAY + UT_SETTING, rows instead
of element blocks, DESIGN-0.2.md section 5.6; the same rules).
aItem (the project's table, VAR_IN_OUT, at most 32 kept): each row holds the value in use (fValue: the project
reads it), its limits fMin / fMax and the items it must be above / below (nAbove / nBelow: their POSITION in the
table, 1 = the first element, 0 = none), the value wanted (fRequest: the HMI / SCADA writes it) and bCmdCheck.
Each time an item's fRequest changes (or on bCmdCheck) it is checked against its limits and the related items:
passed, fValue := fRequest; failed, fValue is kept, the row shows bRefused / eRefusedId (until its next accepted
write), and the block's nRefusedItem / eRefusedId say which. Items are checked in table order, so two related
items changed in one scan check the later one against the earlier one's new value. Nothing is checked on the
first scan (requests are only read). bBad: an item's value itself fails the checks now (written past the check,
or a related item moved); bError BadSetting then.
Kept over a power cut by the block: each item's fValue (the first 32). The limits and relations are the
project's configuration (set at the declaration), not kept. *)

FUNCTION_BLOCK FB_SettingArray EXTENDS FB_Object
  VAR_IN_OUT
    aItem : ARRAY [*] OF ST_SETTINGITEM;
  END_VAR
  VAR_OUTPUT
    bAccepted : BOOL; (* one scan: a request was taken *)
    bRefused : BOOL; (* one scan: a request was refused *)
    bAnyBad : BOOL;
    nRefusedItem : INT; (* the last refused item (0 = none since power-up) *)
    eRefusedId : E_UtError;
  END_VAR
  VAR RETAIN
    aKeptValue : ARRAY [1..32] OF REAL;
    nKeptRows : INT;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
    cMaxKept : DINT := 32;
  END_VAR
  VAR_TEMP
    nLo : DINT;
    nN : DINT;
    nI : DINT;
    nR : DINT;
    nAx : DINT;
    nBx : DINT;
    fAboveV : REAL;
    fBelowV : REAL;
    eWhy : E_UtError;
    bLimitsOk : BOOL;
    nPass : INT;
    bPending : BOOL;
  END_VAR


bAccepted := FALSE;
bRefused := FALSE;
bAnyBad := FALSE;
nLo := LOWER_BOUND(aItem, 1);
nN := UPPER_BOUND(aItem, 1) - nLo + 1;
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    FOR nI := 1 TO MIN(nN, INT_TO_DINT(nKeptRows)) DO
      aItem[nLo + nI - 1].fValue := aKeptValue[nI];
    END_FOR;
  ELSE
    nKeptLayout := cLayout;
  END_IF;
  FOR nI := 1 TO nN DO            (* requests are only read on the first scan *)
    aItem[nLo + nI - 1].fSeen := aItem[nLo + nI - 1].fRequest;
    aItem[nLo + nI - 1].bCmdCheck := FALSE;
  END_FOR;
END_IF;

(* pass 1: the requests, in order; pass 2: every value's own check *)
FOR nPass := 1 TO 2 DO
  FOR nI := 1 TO nN DO
    nR := nLo + nI - 1;
    nAx := 0;
    nBx := 0;
    fAboveV := REAL#-3.4E38;
    fBelowV := REAL#3.4E38;
    IF aItem[nR].nAbove >= 1 AND INT_TO_DINT(aItem[nR].nAbove) <= nN AND INT_TO_DINT(aItem[nR].nAbove) <> nI THEN
      nAx := nLo + INT_TO_DINT(aItem[nR].nAbove) - 1;
      fAboveV := aItem[nAx].fValue;
    END_IF;
    IF aItem[nR].nBelow >= 1 AND INT_TO_DINT(aItem[nR].nBelow) <= nN AND INT_TO_DINT(aItem[nR].nBelow) <> nI THEN
      nBx := nLo + INT_TO_DINT(aItem[nR].nBelow) - 1;
      fBelowV := aItem[nBx].fValue;
    END_IF;
    bLimitsOk := aItem[nR].fMin = aItem[nR].fMin AND aItem[nR].fMax = aItem[nR].fMax AND fAboveV = fAboveV
                 AND fBelowV = fBelowV AND aItem[nR].fMin >= REAL#-3.4E38 AND aItem[nR].fMax <= REAL#3.4E38
                 AND fAboveV >= REAL#-3.4E38 AND fBelowV <= REAL#3.4E38;
    IF nPass = 1 THEN
      (* NaN never equals itself: NaN to NaN is no change *)
      bPending := NOT bFirstScan
                  AND (NOT (aItem[nR].fRequest = aItem[nR].fSeen
                            OR (NOT (aItem[nR].fRequest = aItem[nR].fRequest) AND NOT (aItem[nR].fSeen = aItem[nR].fSeen)))
                       OR aItem[nR].bCmdCheck);
      aItem[nR].fSeen := aItem[nR].fRequest;
      aItem[nR].bCmdCheck := FALSE;
      IF bPending THEN
        IF NOT bLimitsOk THEN
          eWhy := E_UtError.LimitsBad;
        ELSE
          eWhy := F_CheckReal(fValue := aItem[nR].fRequest, fMin := aItem[nR].fMin, fMax := aItem[nR].fMax,
                              bUseAbove := nAx <> 0, fAbove := fAboveV, bUseBelow := nBx <> 0, fBelow := fBelowV);
        END_IF;
        IF eWhy = E_UtError.None THEN
          aItem[nR].fValue := aItem[nR].fRequest;
          aItem[nR].bRefused := FALSE;
          aItem[nR].eRefusedId := E_UtError.None;
          bAccepted := TRUE;
        ELSE
          aItem[nR].bRefused := TRUE;
          aItem[nR].eRefusedId := eWhy;
          bRefused := TRUE;
          nRefusedItem := DINT_TO_INT(nI);
          eRefusedId := eWhy;
        END_IF;
      END_IF;
    ELSE
      IF NOT bLimitsOk THEN
        eWhy := E_UtError.LimitsBad;
      ELSE
        eWhy := F_CheckReal(fValue := aItem[nR].fValue, fMin := aItem[nR].fMin, fMax := aItem[nR].fMax,
                            bUseAbove := nAx <> 0, fAbove := fAboveV, bUseBelow := nBx <> 0, fBelow := fBelowV);
      END_IF;
      aItem[nR].bBad := eWhy <> E_UtError.None;
      bAnyBad := bAnyBad OR aItem[nR].bBad;
    END_IF;
  END_FOR;
END_FOR;

(* keep the values (a value written past the check is kept too: bBad shows it) *)
FOR nI := 1 TO MIN(nN, cMaxKept) DO
  IF aKeptValue[nI] <> aItem[nLo + nI - 1].fValue THEN
    aKeptValue[nI] := aItem[nLo + nI - 1].fValue;
  END_IF;
END_FOR;
IF MIN(nN, cMaxKept) > INT_TO_DINT(nKeptRows) THEN
  nKeptRows := DINT_TO_INT(MIN(nN, cMaxKept));
END_IF;
bError := bAnyBad;
bWarning := FALSE;
IF bAnyBad THEN eErrorId := E_UtError.BadSetting; ELSE eErrorId := E_UtError.None; END_IF;
IF bAnyBad THEN eState := E_State.Fault; ELSE eState := E_State.Running; END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK