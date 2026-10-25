(* UT_REPORT — report by exception: decides when one value is worth sending
to SCADA / IoT. Report pulses for one scan when:
  FIRST      the block starts, or Enable comes back (link up), with
             reportOnStart
  CHANGE     In moved more than the deadband from the last value sent, or
             Quality changed
  HEARTBEAT  heartbeat passed since the last report (T#0s = off, default)
  FORCED     Force / cmdForce
minInterval (T#0s = none, the default: no rate cap, decision 68) keeps two
reports apart; a change or Force during it is sent when it ends, with the
value then. In that is not a number is sent as BAD with the last good
value. The deadband is in the value's units (ABS), a % of the last value
sent (PCT_VALUE), or a % of span (PCT_SPAN); resolution rounds the value
first. The decision is UT_REPORT_RUN (shared with UT_REPORT_ITEM).
Settings kept; a bad write is put back. *)

FUNCTION_BLOCK UT_REPORT
  VAR_INPUT
    In : REAL; (* value to watch (BOOL / INT: convert to REAL) *)
    Force : BOOL R_EDGE; (* report now *)
    Enable : BOOL := TRUE; (* link up / born: on again = report FIRST *)
    Quality : UT_QUALITY := UT_Q_GOOD;
  END_VAR
  VAR_OUTPUT
    Report : BOOL; (* one scan: send now *)
    Value : REAL; (* held from the report *)
    Reason : UT_REPORT_REASON; (* held from the report *)
    BadSetting : BOOL;
  END_VAR
  VAR_IN_OUT
    Data : UT_REPORT_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_REPORT_SET;
    keptGood : BOOL;
  END_VAR
  VAR
    keep : UT_KEEP;
    mem : UT_REPORT_MEM;
    ok : BOOL;
    tCur : TIME;
    hCmd : BOOL;
    v : REAL;
    why : UT_REPORT_REASON;
    shownSt : UT_STATUS;
  END_VAR


tCur := TIME();
keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
ok := UT_REPORT_CHECK(S := Data.set);
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
Report := UT_REPORT_RUN(TNow := tCur, In := In, Quality := Quality, ForceReq := Force OR (Data.cmdForce AND NOT hCmd),
                        Enable := Enable, Heartbeat := Data.set.heartbeat, OnStart := Data.set.reportOnStart,
                        Set := Data.set, Mem := mem, Sts := Data.sts, Value => v, Reason => why);
hCmd := Data.cmdForce;
Data.cmdForce := FALSE;
IF Report THEN
  Value := v;
  Reason := why;
END_IF;
BadSetting := NOT ok;
Data.sts.badSetting := BadSetting;
IF mem.started THEN
  Data.det.sinceLast := tCur - mem.lastAt;
END_IF;
IF BadSetting THEN
  Data.sts.statusCode := UT_ST_WARN_SETTING;
  Data.sts.faultId := UT_F_SETTING;
ELSIF NOT Enable THEN
  Data.sts.statusCode := UT_ST_OFF;
  Data.sts.faultId := UT_F_NONE;
ELSE
  Data.sts.statusCode := UT_ST_OK;
  Data.sts.faultId := UT_F_NONE;
END_IF;
IF Data.sts.statusCode <> shownSt OR LEN(Data.sts.statusText) = 0 THEN
  shownSt := Data.sts.statusCode;
  Data.sts.statusText := UT_STATUS_TEXT(Data.sts.statusCode, Data.sts.faultId);
END_IF;

END_FUNCTION_BLOCK