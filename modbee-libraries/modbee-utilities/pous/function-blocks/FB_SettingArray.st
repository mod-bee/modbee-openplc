(* FB_SettingArray — FB_SettingCheck for a list of project values.
aItems (the project's table, VAR_IN_OUT, at most 32 kept): each row holds the value in use (fValueInUse: the project
reads it), its limits fLowestAllowed / fHighestAllowed and the items it must be above / below (nMustBeAboveItem / nMustBeBelowItem: their POSITION in the
table, 1 = the first element, 0 = none), the value wanted (fRequestedValue: the HMI / SCADA writes it) and bCmdCheckNow.
Each time an item's fRequestedValue changes (or on bCmdCheckNow) it is checked against its limits and the related items:
passed, fValueInUse := fRequestedValue; failed, fValueInUse is kept, the row shows bRequestRefused / eRefusedReason (until its next accepted
write), and the block's nRefusedItem / eRefusedReason say which. Items are checked in table order, so two related
items changed in one scan check the later one against the earlier one's new value. Nothing is checked on the
first scan (requests are only read). bValueBad: an item's value itself fails the checks now (written past the check,
or a related item moved); bError BadSetting then.
Kept over a power cut by the block: each item's fValueInUse (the first 32). The limits and relations are the
project's configuration (set at the declaration), not kept. *)

FUNCTION_BLOCK FB_SettingArray EXTENDS FB_Object
  VAR_IN_OUT
    aItems : ARRAY [*] OF ST_SETTINGITEM; (* the project's table of settings (at most 32 kept) *)
  END_VAR
  VAR_OUTPUT
    bRequestAccepted : BOOL; (* one scan: a request was taken *)
    bRequestRefused : BOOL; (* one scan: a request was refused *)
    bAnyValueBad : BOOL; (* a value in use fails its checks now *)
    nRefusedItem : INT; (* the last refused item (0 = none since power-up) *)
    eRefusedReason : E_UtError; (* why the last request was refused (None after an accepted one) *)
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


bRequestAccepted := FALSE;
bRequestRefused := FALSE;
bAnyValueBad := FALSE;
nLo := LOWER_BOUND(aItems, 1);
nN := UPPER_BOUND(aItems, 1) - nLo + 1;
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    FOR nI := 1 TO MIN(nN, INT_TO_DINT(nKeptRows)) DO
      aItems[nLo + nI - 1].fValueInUse := aKeptValue[nI];
    END_FOR;
  ELSE
    nKeptLayout := cLayout;
  END_IF;
  FOR nI := 1 TO nN DO            (* requests are only read on the first scan *)
    aItems[nLo + nI - 1].fRequestLastRead := aItems[nLo + nI - 1].fRequestedValue;
    aItems[nLo + nI - 1].bCmdCheckNow := FALSE;
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
    IF aItems[nR].nMustBeAboveItem >= 1 AND INT_TO_DINT(aItems[nR].nMustBeAboveItem) <= nN AND INT_TO_DINT(aItems[nR].nMustBeAboveItem) <> nI THEN
      nAx := nLo + INT_TO_DINT(aItems[nR].nMustBeAboveItem) - 1;
      fAboveV := aItems[nAx].fValueInUse;
    END_IF;
    IF aItems[nR].nMustBeBelowItem >= 1 AND INT_TO_DINT(aItems[nR].nMustBeBelowItem) <= nN AND INT_TO_DINT(aItems[nR].nMustBeBelowItem) <> nI THEN
      nBx := nLo + INT_TO_DINT(aItems[nR].nMustBeBelowItem) - 1;
      fBelowV := aItems[nBx].fValueInUse;
    END_IF;
    bLimitsOk := aItems[nR].fLowestAllowed = aItems[nR].fLowestAllowed AND aItems[nR].fHighestAllowed = aItems[nR].fHighestAllowed AND fAboveV = fAboveV
                 AND fBelowV = fBelowV AND aItems[nR].fLowestAllowed >= REAL#-3.4E38 AND aItems[nR].fHighestAllowed <= REAL#3.4E38
                 AND fAboveV >= REAL#-3.4E38 AND fBelowV <= REAL#3.4E38;
    IF nPass = 1 THEN
      (* NaN never equals itself: NaN to NaN is no change *)
      bPending := NOT bFirstScan
                  AND (NOT (aItems[nR].fRequestedValue = aItems[nR].fRequestLastRead
                            OR (NOT (aItems[nR].fRequestedValue = aItems[nR].fRequestedValue) AND NOT (aItems[nR].fRequestLastRead = aItems[nR].fRequestLastRead)))
                       OR aItems[nR].bCmdCheckNow);
      aItems[nR].fRequestLastRead := aItems[nR].fRequestedValue;
      aItems[nR].bCmdCheckNow := FALSE;
      IF bPending THEN
        IF NOT bLimitsOk THEN
          eWhy := E_UtError.LimitsBad;
        ELSE
          eWhy := F_CheckReal(fValue := aItems[nR].fRequestedValue, fLowestAllowed := aItems[nR].fLowestAllowed, fHighestAllowed := aItems[nR].fHighestAllowed,
                              bCheckAbove := nAx <> 0, fMustBeAbove := fAboveV, bCheckBelow := nBx <> 0, fMustBeBelow := fBelowV);
        END_IF;
        IF eWhy = E_UtError.None THEN
          aItems[nR].fValueInUse := aItems[nR].fRequestedValue;
          aItems[nR].bRequestRefused := FALSE;
          aItems[nR].eRefusedReason := E_UtError.None;
          bRequestAccepted := TRUE;
        ELSE
          aItems[nR].bRequestRefused := TRUE;
          aItems[nR].eRefusedReason := eWhy;
          bRequestRefused := TRUE;
          nRefusedItem := DINT_TO_INT(nI);
          eRefusedReason := eWhy;
        END_IF;
      END_IF;
    ELSE
      IF NOT bLimitsOk THEN
        eWhy := E_UtError.LimitsBad;
      ELSE
        eWhy := F_CheckReal(fValue := aItems[nR].fValueInUse, fLowestAllowed := aItems[nR].fLowestAllowed, fHighestAllowed := aItems[nR].fHighestAllowed,
                            bCheckAbove := nAx <> 0, fMustBeAbove := fAboveV, bCheckBelow := nBx <> 0, fMustBeBelow := fBelowV);
      END_IF;
      aItems[nR].bValueBad := eWhy <> E_UtError.None;
      bAnyValueBad := bAnyValueBad OR aItems[nR].bValueBad;
    END_IF;
  END_FOR;
END_FOR;

(* keep the values (a value written past the check is kept too: bValueBad shows it) *)
FOR nI := 1 TO MIN(nN, cMaxKept) DO
  IF aKeptValue[nI] <> aItems[nLo + nI - 1].fValueInUse THEN
    aKeptValue[nI] := aItems[nLo + nI - 1].fValueInUse;
  END_IF;
END_FOR;
IF MIN(nN, cMaxKept) > INT_TO_DINT(nKeptRows) THEN
  nKeptRows := DINT_TO_INT(MIN(nN, cMaxKept));
END_IF;
bError := bAnyValueBad;
bWarning := FALSE;
IF bAnyValueBad THEN eErrorId := E_UtError.BadSetting; ELSE eErrorId := E_UtError.None; END_IF;
IF bAnyValueBad THEN eState := E_State.Fault; ELSE eState := E_State.Running; END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK