(* UT_REPORT_ARRAY — UT_REPORT for a list of values (not a link-rate gate,
decision 68). Each value is a UT_REPORT_ITEM (the project's element
instances, called before the array, each with its own In, quality and
settings, kept inside the item); the item runs the same decision as
UT_REPORT (UT_REPORT_RUN). The array passes the link state: Enable FALSE
holds every item; Enable back (link up / born) = every item reports FIRST
(with reportOnStart); Force / cmdForce = every item reports now. Its
heartbeat applies to items whose own is 0. SizeMismatch: an item was not
called this scan (UT_F_ELEMENT_IDLE). Settings kept; a bad write is put
back. *)

FUNCTION_BLOCK UT_REPORT_ARRAY
  VAR_INPUT
    Enable : BOOL := TRUE; (* link up / born: every item reports FIRST *)
    Force : BOOL R_EDGE; (* every item reports now *)
  END_VAR
  VAR_OUTPUT
    AnyReport : BOOL;
    ReportCount : INT;
    SizeMismatch : BOOL; (* an item was not called this scan *)
    BadSetting : BOOL;
  END_VAR
  VAR_IN_OUT
    Items : ARRAY [*] OF UT_REPORT_ITEM;
    Data : UT_REPORT_ARRAY_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_REPORT_ARRAY_SET;
    keptGood : BOOL;
  END_VAR
  VAR
    keep : UT_KEEP;
    ok : BOOL;
    i : DINT;
    lo : DINT;
    x : BOOL;
    hCmd : BOOL;
    forceAll : BOOL;
    enPrev : BOOL;
    started : BOOL;
    stCode : UT_STATUS;
    stF : UT_FAULT;
    shownSt : UT_STATUS;
    shownF : UT_FAULT;
  END_VAR


keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
ok := Data.set.heartbeat >= T#0s;
IF NOT ok AND keptGood AND NOT keep.FirstBoot THEN
  Data.sts.refused := UT_F_SETTING;
  Data.sts.refusedWhy := UT_F_SETTING;
  Data.set := keptSet;
  ok := TRUE;
END_IF;
IF keep.SaveSet AND (ok OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := ok;
END_IF;
forceAll := Force OR (Data.cmdForce AND NOT hCmd);
hCmd := Data.cmdForce;
Data.cmdForce := FALSE;
AnyReport := FALSE;
ReportCount := 0;
SizeMismatch := FALSE;
BadSetting := NOT ok;
Data.sts.badItem := 0;
lo := LOWER_BOUND(Items, 1);
FOR i := lo TO UPPER_BOUND(Items, 1) DO
  IF NOT Items[i].WasCalled() THEN
    SizeMismatch := TRUE;
    IF Data.sts.badItem = 0 THEN Data.sts.badItem := DINT_TO_INT(i - lo + 1); END_IF;
  END_IF;
  IF NOT Items[i].IsValid() THEN
    BadSetting := TRUE;
    IF Data.sts.badItem = 0 THEN Data.sts.badItem := DINT_TO_INT(i - lo + 1); END_IF;
  END_IF;
  IF Items[i].Report() THEN
    AnyReport := TRUE;
    ReportCount := ReportCount + 1;
    Data.sts.reports := Data.sts.reports + 1;
  END_IF;
  IF Enable AND NOT enPrev AND started THEN
    x := Items[i].Born();        (* link back: every item reports FIRST *)
  END_IF;
  IF forceAll THEN
    x := Items[i].ForceNext();
  END_IF;
  x := Items[i].Link(Enabled := Enable, Heartbeat := Data.set.heartbeat, OnStart := Data.set.reportOnStart);
END_FOR;
enPrev := Enable;
started := TRUE;
stF := UT_F_NONE;
IF SizeMismatch THEN
  stCode := UT_ST_CONFIG;
  stF := UT_F_ELEMENT_IDLE;
ELSIF BadSetting THEN
  stCode := UT_ST_WARN_SETTING;
  stF := UT_F_SETTING;
ELSIF NOT Enable THEN
  stCode := UT_ST_OFF;
ELSE
  stCode := UT_ST_OK;
END_IF;
IF stCode <> shownSt OR stF <> shownF OR LEN(Data.sts.statusText) = 0 THEN
  shownSt := stCode;
  shownF := stF;
  Data.sts.statusText := UT_STATUS_TEXT(stCode, stF);
END_IF;
Data.sts.statusCode := stCode;
Data.sts.faultId := stF;
Data.sts.badSetting := BadSetting;
Data.sts.ne107 := UT_NE107_RUN(Fault := SizeMismatch, Check := NOT Enable, OutOfSpec := BadSetting, Maint := FALSE);

END_FUNCTION_BLOCK