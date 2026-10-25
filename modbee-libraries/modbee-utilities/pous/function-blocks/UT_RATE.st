(* UT_RATE — rate of change, with rising-fast and falling-fast alarms.

Rate is the slope of the best straight line through the readings of the
last window (a least-squares trend), so noise largely cancels. To keep the
memory small at any task interval, the window is kept as ten slices of
window / 10: each slice holds the average reading and the average time of
its readings, and the line is fitted through those, using the last nine
whole slices and the one being filled. A steady ramp gives exactly its rate
at any task interval, even with only a few scans in the window.

Rate is updated every scan, and is 0 until a full window has been measured
after a start, a Reset or a change of window (ready shows when). A step of
S shows as a bump (peak about 1.7 x S / window) lasting about one window.

filterTime smooths Rate further (a low-pass, 63 % in filterTime).

RisingFast: Rate above riseLimit for alarmDelay. FallingFast: Rate below
-fallLimit for alarmDelay. A limit of 0 is off. Both clear as soon as the
rate is back within the limit.

Time is measured from TIME() differences in whole milliseconds; the part of a
millisecond left over is carried to the next scan.

A NaN or infinite In, or InGood FALSE, is ignored: Rate holds, badInput is
set and the time it lasted does not count. Good: a full window of good
readings, settings valid. Settings kept; a bad write is put back. *)

FUNCTION_BLOCK UT_RATE
  VAR_INPUT
    In : REAL; (* value *)
    InGood : BOOL := TRUE; (* its health; FALSE: Rate held *)
    Reset : BOOL; (* restart the measurement *)
  END_VAR
  VAR_OUTPUT
    Good : BOOL; (* a full window of good readings, settings valid *)
    Rate : REAL; (* change per Data.set.unit *)
    RisingFast : BOOL; (* Rate > riseLimit (after alarmDelay) *)
    FallingFast : BOOL; (* Rate < -fallLimit (after alarmDelay) *)
  END_VAR
  VAR_IN_OUT
    Data : UT_RATE_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_RATE_SET;
    keptGood : BOOL;
  END_VAR
  VAR
    keep : UT_KEEP;
    setOk : BOOL;
    stR : UT_PROT_ST;
    stF2 : UT_PROT_ST;
    stsR : UT_PROT_STS;
    stsF : UT_PROT_STS;
    xb : BOOL;
    stCode : UT_STATUS;
    stF : UT_FAULT;
    shownSt : UT_STATUS;
    shownF : UT_FAULT;
    started : BOOL;
    tPrev : TIME; (* time counted up to *)
    winPrev : TIME;
    sumX : ARRAY [0..9] OF LREAL; (* each whole slice: sum of reading x ms *)
    sumT : ARRAY [0..9] OF LREAL; (* each whole slice: sum of reading time (ms into the slice) x ms *)
    head : INT; (* slot of the oldest slice (written next) *)
    slices : INT; (* whole slices, up to 10 *)
    accX : LREAL; (* the slice being filled: sum of reading x ms *)
    accT : LREAL; (* the slice being filled: sum of reading time x ms *)
    filled : LREAL; (* ms in the slice being filled *)
    raw : LREAL; (* trend slope, per second *)
    smooth : LREAL; (* after filterTime, per second *)
    x : LREAL;
    width : LREAL; (* ms per slice *)
    fMs : LREAL;
    dMs : LINT;
    dtMs : LREAL;
    rest : LREAL; (* ms of this scan still to place *)
    part : LREAL;
    wSum : LREAL;
    cMean : LREAL;
    mMean : LREAL;
    cj : LREAL;
    num : LREAL;
    den : LREAL;
    perUnit : LREAL;
    slot : INT;
    i : INT;
    j : INT;
    bad : BOOL;
    riseLvl : UT_LEVEL := (response := UT_RESP_WARN, recover := T#0s);
    fallLvl : UT_LEVEL := (response := UT_RESP_WARN, recover := T#0s);
  END_VAR


keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
setOk := Data.set.window >= T#0s AND Data.set.filterTime >= T#0s AND Data.set.alarmDelay >= T#0s
         AND Data.set.riseLimit >= 0.0 AND Data.set.riseLimit <= 3.4E38
         AND Data.set.fallLimit >= 0.0 AND Data.set.fallLimit <= 3.4E38
         AND (Data.set.unit = UT_PER_SEC OR Data.set.unit = UT_PER_MIN OR Data.set.unit = UT_PER_HOUR
              OR Data.set.unit = UT_PER_DAY);
IF NOT setOk AND keptGood AND NOT keep.FirstBoot THEN
  Data.sts.refused := UT_F_SETTING;
  Data.sts.refusedWhy := UT_F_SETTING;
  Data.set := keptSet;
  setOk := TRUE;
END_IF;
IF keep.SaveSet AND (setOk OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := setOk;
END_IF;
bad := NOT InGood OR NOT (In = In) OR In > 3.4E38 OR In < -3.4E38;
x := REAL_TO_LREAL(In);
width := TIME_TO_LREAL(Data.set.window) / 10.0;

IF NOT started OR Reset OR Data.set.window <> winPrev THEN
  started := TRUE;
  tPrev := TIME();
  slices := 0;
  head := 0;
  accX := 0.0;
  accT := 0.0;
  filled := 0.0;
  raw := 0.0;
  smooth := 0.0;
END_IF;
winPrev := Data.set.window;

IF bad OR width <= 0.0 THEN
  tPrev := TIME();               (* bad time does not count; window 0 = off *)
  IF width <= 0.0 THEN
    slices := 0;
    raw := 0.0;
    smooth := 0.0;
  END_IF;
ELSE
  dMs := TIME_TO_LINT(TIME() - tPrev);         (* whole ms elapsed *)
  IF dMs > 0 THEN
    tPrev := tPrev + LINT_TO_TIME(dMs);        (* the part of a ms left over carries on *)
    dtMs := LINT_TO_LREAL(dMs);
    (* this reading covers the last dtMs and is timed at the end of the
       scan; a long scan spreads it over several slices *)
    rest := dtMs;
    FOR i := 0 TO 11 DO
      IF rest >= width - filled THEN
        part := width - filled;
        sumX[head] := accX + x * part;
        sumT[head] := accT + (filled + rest) * part;
        rest := rest - part;
        head := (head + 1) MOD 10;
        IF slices < 10 THEN
          slices := slices + 1;
        END_IF;
        accX := 0.0;
        accT := 0.0;
        filled := 0.0;
      ELSE
        accX := accX + x * rest;
        accT := accT + (filled + rest) * rest;
        filled := filled + rest;
        rest := 0.0;
        EXIT;
      END_IF;
    END_FOR;
    IF rest > 0.0 THEN           (* longer than the whole window: it was all this value *)
      FOR i := 0 TO 9 DO
        sumX[i] := x * width;
        sumT[i] := width * width / 2.0;
      END_FOR;
      slices := 10;
      accX := 0.0;
      accT := 0.0;
      filled := 0.0;
    END_IF;
    IF slices >= 10 THEN
      (* weighted least squares through (average time, average reading) of
         the nine newest whole slices and the slice being filled *)
      wSum := 9.0 * width + filled;
      cMean := accT + 9.0 * width * filled;
      mMean := accX;
      FOR j := 0 TO 8 DO
        slot := (head + 1 + j) MOD 10;
        cMean := cMean + sumT[slot] + INT_TO_LREAL(j) * width * width;
        mMean := mMean + sumX[slot];
      END_FOR;
      cMean := cMean / wSum;
      mMean := mMean / wSum;
      num := 0.0;
      den := 0.0;
      FOR j := 0 TO 8 DO
        slot := (head + 1 + j) MOD 10;
        cj := sumT[slot] / width + INT_TO_LREAL(j) * width - cMean;
        num := num + width * cj * (sumX[slot] / width - mMean);
        den := den + width * cj * cj;
      END_FOR;
      IF filled > 0.0 THEN
        cj := accT / filled + 9.0 * width - cMean;
        num := num + filled * cj * (accX / filled - mMean);
        den := den + filled * cj * cj;
      END_IF;
      IF den > 0.0 THEN
        raw := num / den * 1000.0;
      ELSE
        raw := 0.0;
      END_IF;
      fMs := TIME_TO_LREAL(Data.set.filterTime);
      IF fMs <= 0.0 OR NOT Data.sts.ready THEN
        smooth := raw;
      ELSE
        smooth := smooth + (raw - smooth) * (1.0 - EXP(-dtMs / fMs));
      END_IF;
    END_IF;
  END_IF;
END_IF;

Data.sts.ready := slices >= 10;
Data.sts.badInput := bad;
CASE Data.set.unit OF
  UT_PER_SEC:  perUnit := 1.0;
  UT_PER_MIN:  perUnit := 60.0;
  UT_PER_HOUR: perUnit := 3600.0;
  UT_PER_DAY:  perUnit := 86400.0;
ELSE
  perUnit := 1.0;
END_CASE;
Rate := LREAL_TO_REAL(smooth * perUnit);

riseLvl.delay := Data.set.alarmDelay;
riseLvl.sp := Data.set.riseLimit;
xb := UT_LEVEL_RUN(TNow := TIME(), In := Rate, Good := TRUE, High := TRUE, UseIn := TRUE, Switch := FALSE,
                   Enable := Data.sts.ready AND Data.set.riseLimit > 0.0, Release := FALSE, ResetReq := FALSE,
                   RetryWindow := T#1h, Level := riseLvl, Sts := stsR, St := stR);
fallLvl.delay := Data.set.alarmDelay;
fallLvl.sp := -Data.set.fallLimit;
xb := UT_LEVEL_RUN(TNow := TIME(), In := Rate, Good := TRUE, High := FALSE, UseIn := TRUE, Switch := FALSE,
                   Enable := Data.sts.ready AND Data.set.fallLimit > 0.0, Release := FALSE, ResetReq := FALSE,
                   RetryWindow := T#1h, Level := fallLvl, Sts := stsF, St := stF2);
RisingFast := stR.warn;
FallingFast := stF2.warn;
Good := Data.sts.ready AND setOk AND NOT bad;
stF := UT_F_NONE;
IF bad THEN
  stCode := UT_ST_WARNING;
  stF := UT_F_INPUT_BAD;
ELSIF RisingFast OR FallingFast THEN
  stCode := UT_ST_WARNING;
  stF := UT_F_RATE_LIMIT;
ELSIF NOT setOk THEN
  stCode := UT_ST_WARN_SETTING;
  stF := UT_F_SETTING;
ELSIF NOT Data.sts.ready THEN
  stCode := UT_ST_STARTING;
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
Data.sts.wrnConfig := NOT setOk;

Data.sts.rate := Rate;
Data.sts.risingFast := RisingFast;
Data.sts.fallingFast := FallingFast;

END_FUNCTION_BLOCK