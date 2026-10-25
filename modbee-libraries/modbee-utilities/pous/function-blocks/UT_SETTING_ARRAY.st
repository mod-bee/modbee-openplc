(* UT_SETTING_ARRAY — UT_SETTING_CHECK for a list of project values; each item
(UT_SETTING, the project's element instances, called before the array)
keeps its own value and limits (kept over a power cut).

The HMI / SCADA writes an item's `request`; each time it changes (or on
cmdCheck) it is checked against the item's minValue / maxValue and against
the items it must be above / below, named by their POSITION in the array
(1 = the first element; 0 = none). Passed: the item's value := request.
Failed: the value is kept, the item shows refused / refusedWhy (until its
next accepted write), and the array's RefusedItem / RefusedWhy say which.
Items are checked in array order, so two related items changed in one scan
check the later one against the earlier one's new value. Nothing is checked
on the first scan (requests are only read). Bad: an item's value itself
fails the checks now (written past the check, or a related item moved). *)

FUNCTION_BLOCK UT_SETTING_ARRAY
  VAR_OUTPUT
    Accepted : BOOL; (* one scan: a request was taken *)
    Refused : BOOL; (* one scan: a request was refused *)
    AnyBad : BOOL;
    RefusedItem : INT; (* the last refused item (0 = none since power-up) *)
    RefusedWhy : UT_FAULT;
  END_VAR
  VAR_IN_OUT
    Items : ARRAY [*] OF UT_SETTING;
  END_VAR
  VAR
    lo : DINT;
    hi : DINT;
    n : DINT;
    i : DINT;
    ax : DINT;
    bx : DINT;
    aboveV : REAL;
    belowV : REAL;
    why : UT_FAULT;
    limitsOk : BOOL;
    pass : INT;
    x : BOOL;
  END_VAR


Accepted := FALSE;
Refused := FALSE;
AnyBad := FALSE;
lo := LOWER_BOUND(Items, 1);
hi := UPPER_BOUND(Items, 1);
n := hi - lo + 1;
(* pass 1: the requests, in order; pass 2: every value's own check *)
FOR pass := 1 TO 2 DO
  FOR i := lo TO hi DO
    ax := 0;
    bx := 0;
    aboveV := -3.4E38;
    belowV := 3.4E38;
    IF Items[i].AboveItem() >= 1 AND INT_TO_DINT(Items[i].AboveItem()) <= n THEN
      ax := lo + INT_TO_DINT(Items[i].AboveItem()) - 1;
      IF ax <> i THEN aboveV := Items[ax].GetValue(); ELSE ax := 0; END_IF;
    END_IF;
    IF Items[i].BelowItem() >= 1 AND INT_TO_DINT(Items[i].BelowItem()) <= n THEN
      bx := lo + INT_TO_DINT(Items[i].BelowItem()) - 1;
      IF bx <> i THEN belowV := Items[bx].GetValue(); ELSE bx := 0; END_IF;
    END_IF;
    limitsOk := Items[i].MinValue() = Items[i].MinValue() AND Items[i].MaxValue() = Items[i].MaxValue()
                AND aboveV = aboveV AND belowV = belowV AND Items[i].MinValue() >= -3.4E38
                AND Items[i].MaxValue() <= 3.4E38 AND aboveV >= -3.4E38 AND belowV <= 3.4E38;
    IF pass = 1 THEN
      IF Items[i].Pending() THEN
        IF NOT limitsOk THEN
          why := UT_F_LIMITS;
        ELSE
          why := UT_CHECK_REAL(Value := Items[i].Request(), MinValue := Items[i].MinValue(), MaxValue := Items[i].MaxValue(),
                               UseAbove := ax <> 0, Above := aboveV, UseBelow := bx <> 0, Below := belowV);
        END_IF;
        IF why = UT_F_NONE THEN
          x := Items[i].Accept();
          Accepted := TRUE;
        ELSE
          x := Items[i].Refuse(Reason := why);
          Refused := TRUE;
          RefusedItem := DINT_TO_INT(i - lo + 1);
          RefusedWhy := why;
        END_IF;
      END_IF;
    ELSE
      IF NOT limitsOk THEN
        why := UT_F_LIMITS;
      ELSE
        why := UT_CHECK_REAL(Value := Items[i].GetValue(), MinValue := Items[i].MinValue(), MaxValue := Items[i].MaxValue(),
                             UseAbove := ax <> 0, Above := aboveV, UseBelow := bx <> 0, Below := belowV);
      END_IF;
      x := Items[i].SetBad(IsBad := why <> UT_F_NONE);
      AnyBad := AnyBad OR why <> UT_F_NONE;
    END_IF;
  END_FOR;
END_FOR;

END_FUNCTION_BLOCK