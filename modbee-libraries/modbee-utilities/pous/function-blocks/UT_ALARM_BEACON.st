(* UT_ALARM_BEACON — flash alarm numbers on a single lamp.

For sites with one fault lamp and no HMI. Alarms is an array of BOOL, one
per alarm; alarm number = index - lower bound + 1. The block steps through
every active alarm in turn (from the lowest number after an idle spell,
then round again) and
flashes its number:

  UT_BEACON_COUNT   the number as that many short flashes
  UT_BEACON_BINARY  `bits` flashes, most significant bit first: long = 1,
                    short = 0. A number too big for `bits` uses as many
                    bits as it needs (up to 15).

Flashes are separated by gapTime, numbers by pauseTime. A number that has
started is always finished, even if its alarm clears meanwhile. Each time
lasts at least one PLC scan. *)

FUNCTION_BLOCK UT_ALARM_BEACON
  VAR_INPUT
    Enable : BOOL := TRUE;
  END_VAR
  VAR_OUTPUT
    Lamp : BOOL;
    Code : INT; (* alarm number being shown (0 = none) *)
    Active : BOOL; (* any alarm *)
    BadSetting : BOOL; (* a bad setting at first boot (a safe value is used) *)
  END_VAR
  VAR_IN_OUT
    Alarms : ARRAY [*] OF BOOL; (* alarm n = element n (write with coils) *)
    Data : UT_BEACON_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_BEACON_SET;
    keptGood : BOOL;
  END_VAR
  VAR
    keep : UT_KEEP;
    okSet : BOOL;
    tCur : TIME;
    i : DINT;
    j : DINT;
    lo : DINT;
    hi : DINT;
    n : INT;
    found : BOOL;
    started : BOOL;
    phase : INT; (* 0 choose, 1 flash, 2 gap, 3 pause *)
    phaseStart : TIME;
    cur : DINT; (* index being shown *)
    shown : INT; (* number being shown *)
    pulses : INT; (* flashes in this number *)
    pulse : INT; (* flash now *)
    nbits : INT;
    weight : DINT; (* binary: value of the bit now *)
    rest : DINT; (* binary: what is left to show *)
    onLen : TIME;
    startPulse : BOOL;
    binary : BOOL; (* style of the number being shown *)
  END_VAR


keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
okSet := (Data.set.style = UT_BEACON_COUNT OR Data.set.style = UT_BEACON_BINARY) AND Data.set.bits >= 1 AND Data.set.bits <= 15
         AND Data.set.shortTime > T#0s AND Data.set.longTime > T#0s AND Data.set.gapTime > T#0s AND Data.set.pauseTime > T#0s;
IF NOT okSet AND keptGood AND NOT keep.FirstBoot THEN
  Data.sts.refused := UT_F_SETTING;
  Data.sts.refusedWhy := UT_F_SETTING;
  Data.set := keptSet;
  okSet := TRUE;
END_IF;
IF keep.SaveSet AND (okSet OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := okSet;
END_IF;
BadSetting := NOT okSet;
Data.sts.badSetting := BadSetting;

tCur := TIME();
lo := LOWER_BOUND(Alarms, 1);
hi := UPPER_BOUND(Alarms, 1);
IF NOT started THEN
  started := TRUE;
  cur := lo - 1;
END_IF;
n := 0;
FOR i := lo TO hi DO
  IF Alarms[i] THEN
    n := n + 1;
  END_IF;
END_FOR;
Active := n > 0;
Data.sts.activeCount := n;

IF NOT Enable THEN
  phase := 0;
  cur := lo - 1;
  shown := 0;
  Lamp := FALSE;
  Code := 0;
  Data.det.code := 0;
  RETURN;
END_IF;

startPulse := FALSE;
IF phase = 3 AND tCur - phaseStart >= Data.set.pauseTime THEN
  phase := 0;
END_IF;
IF phase = 0 THEN
  (* the next active alarm after the one just shown, round the array *)
  found := FALSE;
  j := cur;
  FOR i := lo TO hi DO
    j := j + 1;
    IF j > hi OR j < lo THEN
      j := lo;
    END_IF;
    IF Alarms[j] THEN
      found := TRUE;
      EXIT;
    END_IF;
  END_FOR;
  IF found THEN
    IF shown = 0 AND Data.set.steadyWhenNone THEN
      phase := 2;                  (* lamp off first, so the first flash shows *)
      phaseStart := tCur;
    ELSE
      startPulse := TRUE;
    END_IF;
    cur := j;
    shown := DINT_TO_INT(j - lo + 1);
    pulse := 0;
    binary := Data.set.style = UT_BEACON_BINARY;
    IF binary THEN
      nbits := LIMIT(1, Data.set.bits, 15);
      weight := 1;
      FOR i := 2 TO INT_TO_DINT(nbits) DO
        weight := weight * 2;
      END_FOR;
      (* more bits while the number needs them (at most 15 in all) *)
      FOR i := 1 TO 14 DO
        IF nbits >= 15 OR INT_TO_DINT(shown) < weight * 2 THEN
          EXIT;
        END_IF;
        nbits := nbits + 1;
        weight := weight * 2;
      END_FOR;
      pulses := nbits;
      rest := INT_TO_DINT(shown);
    ELSE
      pulses := shown;
    END_IF;
  ELSE
    shown := 0;
    cur := lo - 1;                 (* idle: start from the lowest next time *)
  END_IF;
ELSIF phase = 2 AND tCur - phaseStart >= Data.set.gapTime THEN
  startPulse := TRUE;
ELSIF phase = 1 AND tCur - phaseStart >= onLen THEN
  IF pulse >= pulses THEN
    phase := 3;
  ELSE
    phase := 2;
  END_IF;
  phaseStart := tCur;
END_IF;

IF startPulse THEN
  pulse := pulse + 1;
  onLen := Data.set.shortTime;
  IF binary THEN
    IF rest >= weight THEN
      onLen := Data.set.longTime;
      rest := rest - weight;
    END_IF;
    weight := weight / 2;
  END_IF;
  phase := 1;
  phaseStart := tCur;
END_IF;

Lamp := phase = 1 OR (phase = 0 AND Data.set.steadyWhenNone);
Code := shown;
Data.det.code := shown;

END_FUNCTION_BLOCK