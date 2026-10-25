(* UT_MSG_QUEUE — message ticker and site-status board for an HMI.

Call it once per source per scan, all calls on the same instance, Buffer,
Sources and Data:
  Msgs(Status := Pump1.statusCode, Fault := Pump1.faultId, Src := 1,
       Buffer := MsgBuf, Sources := MsgSrc, Data := MsgCfg);
  Msgs(Status := Pump2.statusCode, Fault := Pump2.faultId, Src := 2, ...);
A message is codes, not words: the source's status (UT_STATUS) and fault
(UT_FAULT). Sources[Src] keeps the last status and fault seen from that
source, so a message is taken only when one of them changes. Only statuses
of minKind or worse are taken (UT_STATUS_KIND; default UT_KIND_HELD:
held / waiting, warnings, faults, config; UT_KIND_NORMAL: every change). Message is the one on display
in words (UT_STATUS_TEXT); an HMI can show its own words from MsgStatus /
MsgFault.

QUEUE   (the default) each new or changed message is queued, shown for
        showTime, then dropped, in the order they came.
ACTIVE  one slot per source holds its current message; a status below
        minKind (or Idle, Off, OK) removes it; the display goes round the
        active ones every showTime ("what's wrong now").

When the buffer is full: whenFull DROP_OLDEST makes room by dropping the
oldest (counted in `lost`); HOLD_NEW keeps what is there and new messages
wait for room (their source is tried again on every call). QUEUE: a
buffer that stays full for clearFullAfter is emptied.

RAM is what you declare: one UT_MSG per slot, one UT_MSG_SRC per source. Every
loop is bounded by the array sizes. Positions do not depend on the
arrays' lower bounds. The display is timed from TIME() differences, and
one instance is called many times in a scan (TIME() is the same for the
whole scan): NewMsg stays on for the rest of the scan in which a message
arrived, and the commands act once per scan. *)

FUNCTION_BLOCK UT_MSG_QUEUE
  VAR_INPUT
    Status : UT_STATUS; (* the source's status (e.g. Pump1.statusCode) *)
    Fault : UT_FAULT; (* its fault (e.g. Pump1.faultId) *)
    Src : INT := 1; (* source number: the element of Sources this call uses *)
    Clock : DT; (* optional real-time clock: stamped on each message *)
  END_VAR
  VAR_OUTPUT
    Message : STRING(30); (* the message on display in words ('' = none) *)
    Count : INT; (* messages waiting (QUEUE) or active (ACTIVE) *)
    MsgSrc : INT; (* source of the message on display (0 when none) *)
    MsgStatus : UT_STATUS; (* its status (UT_ST_IDLE when none) *)
    MsgFault : UT_FAULT; (* its fault (UT_F_NONE when none) *)
    NewMsg : BOOL; (* on for the scan in which a message came (or changed) *)
    BadSetting : BOOL;
  END_VAR
  VAR RETAIN
    keptSet : UT_MSG_SET;
    keptGood : BOOL;
  END_VAR
  VAR_IN_OUT
    Buffer : ARRAY [*] OF UT_MSG; (* the slots: as many as you declare *)
    Sources : ARRAY [*] OF UT_MSG_SRC; (* last status and fault seen per source, index = Src (the block writes it) *)
    Data : UT_MSG_DATA;
  END_VAR
  VAR
    started : BOOL;
    tCur : TIME;
    tLast : TIME;
    newScan : BOOL;
    kp : UT_KEEP;
    setOk : BOOL := TRUE;
    blo : DINT;
    nb : DINT; (* slots *)
    slo : DINT;
    shi : DINT;
    m : UT_MQ_MODE; (* mode in use *)
    modePrev : UT_MQ_MODE;
    sh : TIME; (* showTime in use *)
    mk : UT_KIND; (* minKind in use *)
    kind : UT_KIND; (* this call's status kind *)
    show : BOOL; (* this call's status is taken *)
    dropOld : BOOL;
    cfa : TIME; (* clearFullAfter in use *)
    cfg : BOOL;
    head : DINT; (* QUEUE: offset of the oldest *)
    cnt : DINT; (* messages held *)
    pos : DINT; (* offset of the one on display (QUEUE: 0, the oldest) *)
    showing : BOOL;
    showAt : TIME;
    refresh : BOOL; (* the outputs need the message on display again *)
    fullSince : TIME;
    wasFull : BOOL;
    clearSeen : BOOL;
    nextSeen : BOOL;
    clearReq : BOOL;
    nextReq : BOOL;
    taken : BOOL;
    i : DINT;
    k : DINT;
    p : DINT;
  END_VAR


tCur := TIME();
blo := LOWER_BOUND(Buffer, 1);
nb := UPPER_BOUND(Buffer, 1) - blo + 1;
IF nb < 0 THEN
  nb := 0;
END_IF;
slo := LOWER_BOUND(Sources, 1);
shi := UPPER_BOUND(Sources, 1);
newScan := NOT started OR tCur <> tLast;
tLast := tCur;
IF newScan THEN
  kp();
  IF kp.RestoreSet THEN
    Data.set := keptSet;
  END_IF;
  setOk := Data.set.showTime >= T#0s AND Data.set.clearFullAfter >= T#0s
           AND (Data.set.mode = UT_MQ_QUEUE OR Data.set.mode = UT_MQ_ACTIVE)
           AND (Data.set.whenFull = UT_MQ_DROP_OLDEST OR Data.set.whenFull = UT_MQ_HOLD_NEW);
  IF NOT setOk AND keptGood AND NOT kp.FirstBoot THEN
    Data.sts.refused := UT_F_SETTING;
    Data.sts.refusedWhy := UT_F_SETTING;
    Data.set := keptSet;
    setOk := TRUE;
  END_IF;
  IF kp.SaveSet AND (setOk OR NOT keptGood) THEN
    keptSet := Data.set;
    keptGood := setOk;
  END_IF;
END_IF;

(* settings: a safe value and a warning *)
cfg := nb < 1 OR shi < slo;
IF Data.set.mode = UT_MQ_QUEUE OR Data.set.mode = UT_MQ_ACTIVE THEN
  m := Data.set.mode;
ELSE
  m := UT_MQ_QUEUE;
  cfg := TRUE;
END_IF;
sh := Data.set.showTime;
IF sh < T#0s THEN
  sh := T#3s;
  cfg := TRUE;
END_IF;
mk := Data.set.minKind;
IF NOT (mk = UT_KIND_NORMAL OR mk = UT_KIND_HELD OR mk = UT_KIND_WARNING OR mk = UT_KIND_FAULT
        OR mk = UT_KIND_CONFIG) THEN
  mk := UT_KIND_HELD;
  cfg := TRUE;
END_IF;
dropOld := Data.set.whenFull <> UT_MQ_HOLD_NEW;
IF NOT (Data.set.whenFull = UT_MQ_DROP_OLDEST OR Data.set.whenFull = UT_MQ_HOLD_NEW) THEN
  cfg := TRUE;                   (* unknown: drop the oldest *)
END_IF;
cfa := Data.set.clearFullAfter;
IF cfa < T#0s THEN
  cfa := T#0s;
  cfg := TRUE;
END_IF;
Data.sts.wrnConfig := cfg;

IF NOT started THEN
  (* first call, also after a power cut: empty, no source seen *)
  started := TRUE;
  modePrev := m;
  cnt := 0;
  head := 0;
  pos := 0;
  showing := FALSE;
  refresh := TRUE;
  FOR i := slo TO shi DO
    Sources[i].status := UT_ST_IDLE;
    Sources[i].fault := UT_F_NONE;
    Sources[i].known := TRUE;
  END_FOR;
END_IF;

(* a mode change starts afresh; ACTIVE builds from the sources' codes *)
IF m <> modePrev THEN
  modePrev := m;
  cnt := 0;
  head := 0;
  pos := 0;
  showing := FALSE;
  refresh := TRUE;
  IF m = UT_MQ_ACTIVE THEN
    FOR i := slo TO shi DO
      Sources[i].known := FALSE;
    END_FOR;
  END_IF;
END_IF;

(* once per scan: the scan's flags, and the HMI commands (once per request) *)
clearReq := FALSE;
nextReq := FALSE;
IF newScan THEN
  NewMsg := FALSE;
  Data.sts.wrnSrc := FALSE;
  clearReq := Data.cmdClear AND NOT clearSeen;
  clearSeen := Data.cmdClear;
  Data.cmdClear := FALSE;
  nextReq := Data.cmdNext AND NOT nextSeen;
  nextSeen := Data.cmdNext;
  Data.cmdNext := FALSE;
END_IF;
IF clearReq THEN
  cnt := 0;
  head := 0;
  pos := 0;
  showing := FALSE;
  refresh := TRUE;
  IF m = UT_MQ_ACTIVE THEN
    FOR i := slo TO shi DO
      Sources[i].known := FALSE;
    END_FOR;
  END_IF;
END_IF;

(* this call's source: act only on a change of its code *)
IF Src < slo OR Src > shi THEN
  Data.sts.wrnSrc := TRUE;
ELSIF NOT Sources[Src].known OR Status <> Sources[Src].status OR Fault <> Sources[Src].fault THEN
  taken := TRUE;
  (* minKind or worse; ACTIVE never shows Idle, Off or OK (nothing to say) *)
  kind := UT_STATUS_KIND(Status);
  show := (m = UT_MQ_QUEUE OR NOT (Status = UT_ST_IDLE OR Status = UT_ST_OFF OR Status = UT_ST_OK))
          AND (kind = mk OR kind = UT_KIND_CONFIG
               OR (kind = UT_KIND_FAULT AND mk <> UT_KIND_CONFIG)
               OR (kind = UT_KIND_WARNING AND (mk = UT_KIND_NORMAL OR mk = UT_KIND_HELD))
               OR (kind = UT_KIND_HELD AND mk = UT_KIND_NORMAL));
  IF m = UT_MQ_QUEUE THEN
    IF show AND nb >= 1 THEN
      IF cnt >= nb THEN
        IF dropOld THEN
          (* drop the oldest to make room *)
          head := (head + 1) MOD nb;
          cnt := cnt - 1;
          Data.sts.lost := Data.sts.lost + 1;
          showing := FALSE;
        ELSE
          taken := FALSE;        (* wait for room *)
        END_IF;
      END_IF;
      IF cnt < nb THEN
        p := blo + (head + cnt) MOD nb;
        Buffer[p].src := Src;
        Buffer[p].status := Status;
        Buffer[p].fault := Fault;
        Buffer[p].stamp := Clock;
        cnt := cnt + 1;
        NewMsg := TRUE;
      END_IF;
    END_IF;
  ELSE
    (* ACTIVE: this source's slot, if it has one *)
    k := -1;
    FOR i := 0 TO cnt - 1 DO
      IF Buffer[blo + i].src = Src THEN
        k := i;
        EXIT;
      END_IF;
    END_FOR;
    IF show THEN
      IF k < 0 AND cnt >= nb AND nb >= 1 AND dropOld THEN
        (* drop the oldest to make room *)
        FOR i := 0 TO cnt - 2 DO
          Buffer[blo + i] := Buffer[blo + i + 1];
        END_FOR;
        cnt := cnt - 1;
        Data.sts.lost := Data.sts.lost + 1;
        IF pos > 0 THEN
          pos := pos - 1;
        ELSE
          showing := FALSE;
        END_IF;
      END_IF;
      IF k < 0 AND cnt < nb THEN
        k := cnt;
        cnt := cnt + 1;
      END_IF;
      IF k >= 0 THEN
        p := blo + k;
        Buffer[p].src := Src;
        Buffer[p].status := Status;
        Buffer[p].fault := Fault;
        Buffer[p].stamp := Clock;
        NewMsg := TRUE;
        IF showing AND k = pos THEN
          refresh := TRUE;
        END_IF;
      ELSIF nb >= 1 THEN
        taken := FALSE;          (* HOLD_NEW and full: wait for room *)
      END_IF;
    ELSIF k >= 0 THEN
      (* back to normal, or below minKind: remove it, the rest move up *)
      FOR i := k TO cnt - 2 DO
        Buffer[blo + i] := Buffer[blo + i + 1];
      END_FOR;
      cnt := cnt - 1;
      Buffer[blo + cnt].src := 0;
      Buffer[blo + cnt].status := UT_ST_IDLE;
      Buffer[blo + cnt].fault := UT_F_NONE;
      IF k < pos THEN
        pos := pos - 1;
      ELSIF k = pos THEN
        showing := FALSE;        (* the next one is shown now *)
      END_IF;
    END_IF;
  END_IF;
  IF taken THEN
    Sources[Src].status := Status;
    Sources[Src].fault := Fault;
    Sources[Src].known := TRUE;
  END_IF;
END_IF;

(* QUEUE: a buffer full too long is emptied *)
IF m = UT_MQ_QUEUE AND nb >= 1 AND cnt >= nb THEN
  IF NOT wasFull THEN
    wasFull := TRUE;
    fullSince := tCur;
  ELSIF cfa > T#0s AND tCur - fullSince >= cfa THEN
    Data.sts.lost := Data.sts.lost + DINT_TO_UDINT(cnt);
    cnt := 0;
    head := 0;
    showing := FALSE;
    wasFull := FALSE;
  END_IF;
ELSE
  wasFull := FALSE;
END_IF;

(* the display: each message for showTime (at least one scan) *)
IF showing AND (nextReq OR (tCur - showAt >= sh AND tCur <> showAt)) THEN
  IF m = UT_MQ_QUEUE THEN
    (* shown: drop it *)
    p := blo + head;
    Buffer[p].src := 0;
    Buffer[p].status := UT_ST_IDLE;
    Buffer[p].fault := UT_F_NONE;
    head := (head + 1) MOD nb;
    cnt := cnt - 1;
    showing := FALSE;
  ELSIF cnt > 1 THEN
    pos := (pos + 1) MOD cnt;
    showAt := tCur;
    refresh := TRUE;
  ELSE
    showAt := tCur;              (* only one: it stays *)
  END_IF;
END_IF;
IF cnt <= 0 THEN
  cnt := 0;
  head := 0;
  pos := 0;
  IF showing OR MsgSrc <> 0 OR LEN(Message) > 0 THEN
    showing := FALSE;
    refresh := TRUE;
  END_IF;
ELSIF NOT showing THEN
  IF m = UT_MQ_QUEUE OR pos >= cnt THEN
    pos := 0;
  END_IF;
  showing := TRUE;
  showAt := tCur;
  refresh := TRUE;
END_IF;
IF refresh THEN
  refresh := FALSE;
  IF showing THEN
    IF m = UT_MQ_QUEUE THEN
      p := blo + head;
    ELSE
      p := blo + pos;
    END_IF;
    MsgSrc := Buffer[p].src;
    MsgStatus := Buffer[p].status;
    MsgFault := Buffer[p].fault;
    Message := UT_STATUS_TEXT(MsgStatus, MsgFault);
  ELSE
    Message := '';
    MsgSrc := 0;
    MsgStatus := UT_ST_IDLE;
    MsgFault := UT_F_NONE;
  END_IF;
END_IF;

Count := DINT_TO_INT(cnt);
Data.sts.count := Count;
BadSetting := NOT setOk OR Data.sts.wrnConfig;
Data.sts.full := nb >= 1 AND cnt >= nb;

END_FUNCTION_BLOCK