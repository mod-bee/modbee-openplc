(* One condition of a UT_INTERLOCK (an element block: one box per condition, called before the interlock) *)

FUNCTION_BLOCK UT_INTLK_COND
  VAR_INPUT
    Ok : BOOL := TRUE; (* the live condition *)
  END_VAR
  VAR_IN_OUT
    Data : UT_INTLK_COND_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_INTLK_COND_SET;
    keptGood : BOOL;
  END_VAR
  VAR
    keep : UT_KEEP;
    okSet : BOOL;
    cur : UT_INTLK_COND_SET;
    tCur : TIME;
    tPrev : TIME;
    started : BOOL;
    badNow : BOOL;
    badSince : TIME;
    active : BOOL;
    latched : BOOL;
    tripped : BOOL;
    trippedPrev : BOOL;
    wentBadNow : BOOL;
    resetAsk : BOOL;
    permBypass : BOOL; (* from the interlock's last Permit *)
    permTimeout : TIME;
    permRetries : INT := 3;
    permWindow : TIME := T#1h;
    bypassed : BOOL;
    bypassAt : TIME;
    bypassOn : BOOL;
    retries : INT;
    windowAt : TIME;
  END_VAR


METHOD PUBLIC IsOk : BOOL        // healthy, or bypassed
  IsOk := NOT tripped OR bypassed;
END_METHOD
METHOD PUBLIC IsBad : BOOL       // counts against Ok
  IsBad := tripped AND NOT bypassed;
END_METHOD
METHOD PUBLIC IsBypassed : BOOL
  IsBypassed := bypassed;
END_METHOD
METHOD PUBLIC IsWaiting : BOOL   // not OK, still within its delay
  IsWaiting := badNow AND NOT tripped;
END_METHOD
METHOD PUBLIC IsHealthyHeld : BOOL   // held, healthy again: waits for a reset
  IsHealthyHeld := tripped AND NOT badNow;
END_METHOD
METHOD PUBLIC WentBad : BOOL     // this scan
  WentBad := wentBadNow;
END_METHOD
METHOD PUBLIC IsValid : BOOL
  IsValid := okSet;
END_METHOD
METHOD PUBLIC Reset : BOOL       // a reset: a held condition that is healthy clears
  resetAsk := TRUE;
  Reset := TRUE;
END_METHOD
METHOD PUBLIC Permit : BOOL      // the interlock's permission and settings, every scan
  VAR_INPUT
    Bypass : BOOL;               // BypassEnable
    Timeout : TIME;              // bypassTimeout
    MaxRetries : INT;
    Window : TIME;
  END_VAR
  permBypass := Bypass;
  permTimeout := Timeout;
  permRetries := MaxRetries;
  permWindow := Window;
  Permit := TRUE;
END_METHOD

tCur := TIME();
IF NOT started THEN
  started := TRUE;
  tPrev := tCur;
END_IF;
keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
okSet := Data.set.delay >= T#0s
         AND (Data.set.reset = UT_RST_AUTO OR Data.set.reset = UT_RST_RETRY OR Data.set.reset = UT_RST_MANUAL);
IF NOT okSet AND keptGood AND NOT keep.FirstBoot THEN
  Data.sts.refused := UT_F_CONDITION;
  Data.sts.refusedWhy := UT_F_SETTING;
  Data.set := keptSet;
  okSet := TRUE;
END_IF;
IF keep.SaveSet AND (okSet OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := okSet;
END_IF;
cur := Data.set;

(* not OK this long *)
IF NOT Ok AND NOT badNow THEN
  badSince := tCur;
END_IF;
badNow := NOT Ok;
active := badNow AND (cur.delay <= T#0s OR tCur - badSince >= cur.delay);
IF cur.reset = UT_RST_AUTO AND okSet THEN
  latched := FALSE;
ELSIF active THEN
  latched := TRUE;
ELSIF latched AND Ok THEN
  IF resetAsk THEN
    latched := FALSE;
  ELSIF cur.reset = UT_RST_RETRY AND okSet THEN
    IF retries > 0 AND tCur - windowAt >= permWindow THEN
      retries := 0;              (* a new window *)
    END_IF;
    IF retries < permRetries THEN
      IF retries = 0 THEN windowAt := tCur; END_IF;
      retries := retries + 1;
      latched := FALSE;          (* by itself, a few times *)
    END_IF;
  END_IF;
END_IF;
IF resetAsk AND Ok THEN
  retries := 0;
END_IF;
resetAsk := FALSE;
tripped := active OR latched;
wentBadNow := tripped AND NOT trippedPrev;
trippedPrev := tripped;

(* the bypass: allowed, asked, permitted, within the timeout *)
IF NOT (Data.bypass AND cur.bypassAllowed AND permBypass AND permTimeout >= T#0s) THEN
  bypassOn := FALSE;
  bypassed := FALSE;
ELSE
  IF NOT bypassOn THEN
    bypassOn := TRUE;
    bypassAt := tCur;
  END_IF;
  bypassed := permTimeout <= T#0s OR tCur - bypassAt < permTimeout;
END_IF;

(* status *)
Data.sts.bad := badNow;
Data.sts.tripped := tripped;
Data.sts.latched := latched;
Data.sts.bypassed := bypassed;
Data.sts.retries := retries;
IF badNow THEN Data.det.badFor := tCur - badSince; ELSE Data.det.badFor := T#0s; END_IF;
IF bypassOn THEN Data.det.bypassFor := tCur - bypassAt; ELSE Data.det.bypassFor := T#0s; END_IF;
IF badNow AND NOT active AND cur.delay > tCur - badSince THEN
  Data.det.delayLeft := cur.delay - (tCur - badSince);
ELSE
  Data.det.delayLeft := T#0s;
END_IF;
IF bypassed AND permTimeout > T#0s THEN
  Data.det.bypassLeft := permTimeout - (tCur - bypassAt);
ELSE
  Data.det.bypassLeft := T#0s;
END_IF;
Data.sts.faultId := UT_F_NONE;
IF NOT okSet THEN
  Data.sts.statusCode := UT_ST_CONFIG;
  Data.sts.faultId := UT_F_CONDITION;
ELSIF bypassed THEN
  Data.sts.statusCode := UT_ST_BYPASSED;
ELSIF tripped AND Ok THEN
  Data.sts.statusCode := UT_ST_RESET_NEEDED;
ELSIF tripped THEN
  Data.sts.statusCode := UT_ST_INTERLOCK;
ELSE
  Data.sts.statusCode := UT_ST_OK;
END_IF;

END_FUNCTION_BLOCK