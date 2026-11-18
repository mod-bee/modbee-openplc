(* FB_MsgQueue — message ticker and site-status board for an HMI (messages are codes: the source's eState and
eErrorId, the HMI shows the words).
Call it once per source per scan, all calls on the same instance, aBuffer, aSources and refData (one rung each):
  fbMsgs(eSrcState := fbPump1.eState, eSrcError := fbPump1.eErrorId, nSrc := 1, aBuffer := aMsgBuf, aSources := aMsgSrc, refData := stMsgs);
  fbMsgs(eSrcState := fbPump2.eState, eSrcError := fbPump2.eErrorId, nSrc := 2, ...);
aSources[nSrc] keeps the last state and error seen from that source, so a message is taken only when one of them
changes. Its kind: Fault (eSrcState Fault), Warning (an eSrcError, not Fault), Held (Held or Waiting), else
Normal; only kinds of set.eMinKind or worse are taken (default Held; Normal: every change).
  Queue   (the default) each new or changed message is queued, shown for set.tShowTime, then dropped, in the order
          they came.
  Active  one slot per source holds its current message; a kind below eMinKind (or Idle, Off, Running with no
          error) removes it; the display goes round the active ones every tShowTime ("what's wrong now").
When the buffer is full: set.eWhenFull DropOldest makes room by dropping the oldest (sts.nLost); HoldNew keeps what
is there and new messages wait for room (their source is tried again on every call). Queue: a buffer that stays
full for set.tClearFullAfter is emptied. bCmdClear: Queue empties it; Active builds it again from the sources.
bCmdNext: the next message now (Queue drops the one on display).
RAM is what you declare: one ST_Msg per slot, one ST_MsgSrc per source. One instance is called many times in a
scan (TIME() is the same for the whole scan): bNewMsg stays on for the rest of the scan in which a message arrived,
and the commands act once per scan.
Pins: eSrcState, eSrcError, nSrc, dtClock, refData, aBuffer, aSources -> nCount, nMsgSrc, eMsgState, eMsgError
(the message on display; 0 / Idle / None when none), bNewMsg, plus FB_Object's outputs (warning BadSetting: no
slot or no source; ValueBad: a call's nSrc outside aSources, ignored). Settings are kept (a retained last-good
copy, a bad write put back). *)

FUNCTION_BLOCK FB_MsgQueue EXTENDS FB_Object
  VAR_INPUT
    eSrcState : E_State; (* the source's state (e.g. fbPump1.eState) *)
    eSrcError : E_UtError; (* its error (e.g. fbPump1.eErrorId) *)
    nSrc : INT := 1; (* the source: the element of aSources this call uses *)
    dtClock : DT; (* optional real-time clock: stamped on each message *)
    refData : REFERENCE TO ST_MsgQueueData;
  END_VAR
  VAR_IN_OUT
    aBuffer : ARRAY [*] OF ST_MSG; (* the slots: as many as declared *)
    aSources : ARRAY [*] OF ST_MSGSRC; (* last state and error seen per source, index = nSrc *)
  END_VAR
  VAR_OUTPUT
    nCount : INT; (* messages waiting (Queue) or active (Active) *)
    nMsgSrc : INT; (* the source of the message on display (0 when none) *)
    eMsgState : E_State; (* its state (Idle when none) *)
    eMsgError : E_UtError; (* its error (None when none) *)
    bNewMsg : BOOL; (* on for the scan in which a message came (or changed) *)
  END_VAR
  VAR RETAIN
    stKept : ST_MsgQueueSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    bStarted : BOOL;
    tLast : TIME;
    bSetOk : BOOL := TRUE;
    eModePrev : E_MsgMode;
    nHead : DINT; (* Queue: offset of the oldest *)
    nCnt : DINT; (* messages held *)
    nPos : DINT; (* offset of the one on display (Queue: 0, the oldest) *)
    bShowing : BOOL;
    tShowAt : TIME;
    bRefresh : BOOL; (* the outputs need the message on display again *)
    tFullSince : TIME;
    bWasFull : BOOL;
    bClearSeen : BOOL;
    bNextSeen : BOOL;
  END_VAR
  VAR_TEMP
    bNewScan : BOOL;
    nBLo : DINT;
    nNb : DINT;
    nSLo : DINT;
    nSHi : DINT;
    nS : DINT;
    bDropOld : BOOL;
    nKind : INT;
    nMinKind : INT;
    bShow : BOOL;
    bTaken : BOOL;
    bClearReq : BOOL;
    bNextReq : BOOL;
    nI : DINT;
    nK : DINT;
    nP : DINT;
  END_VAR


METHOD PRIVATE SetWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_MsgQueueSet;
  END_VAR
  SetWhy := E_UtError.None;
  IF NOT (stS.tShowTime >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tClearFullAfter >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.eMode = E_MsgMode.Queue OR stS.eMode = E_MsgMode.Active) THEN
    SetWhy := E_UtError.ChoiceBad;
  ELSIF NOT (stS.eWhenFull = E_MsgFull.DropOldest OR stS.eWhenFull = E_MsgFull.HoldNew) THEN
    SetWhy := E_UtError.ChoiceBad;
  ELSIF NOT (stS.eMinKind = E_MsgKind.Normal OR stS.eMinKind = E_MsgKind.Held OR stS.eMinKind = E_MsgKind.Warning
             OR stS.eMinKind = E_MsgKind.Fault) THEN
    SetWhy := E_UtError.ChoiceBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_MsgQueueSet;
  END_VAR
  SetOk := SetWhy(stS := stS) = E_UtError.None;
END_METHOD

METHOD PRIVATE KindNo : INT
  VAR_INPUT
    eK : E_MsgKind;
  END_VAR
  CASE eK OF
  E_MsgKind.Held: KindNo := 1;
  E_MsgKind.Warning: KindNo := 2;
  E_MsgKind.Fault: KindNo := 3;
  ELSE
    KindNo := 0;
  END_CASE;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bNewMsg := FALSE;
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();
nBLo := LOWER_BOUND(aBuffer, 1);
nNb := MAX(UPPER_BOUND(aBuffer, 1) - nBLo + 1, 0);
nSLo := LOWER_BOUND(aSources, 1);
nSHi := UPPER_BOUND(aSources, 1);
bNewScan := NOT bStarted OR tNow <> tLast;
tLast := tNow;
IF bNewScan THEN
  IF bFirstScan THEN
    IF nKeptLayout = cLayout THEN
      refData.set := stKept;
    ELSE
      stKept := refData.set;
      nKeptLayout := cLayout;
    END_IF;
  END_IF;
  bSetOk := SetOk(stS := refData.set);
  IF bSetOk THEN
    stKept := refData.set;
  ELSIF SetOk(stS := stKept) THEN
    refData.sts.eRefusedWhy := SetWhy(stS := refData.set);
    refData.set := stKept;
    refData.sts.bRefused := TRUE;
    bSetOk := TRUE;
  END_IF;
  IF SystemReset() THEN
    refData.sts.bRefused := FALSE;
    refData.sts.eRefusedWhy := E_UtError.None;
  END_IF;
END_IF;
refData.sts.bWrnConfig := nNb < 1 OR nSHi < nSLo;
bDropOld := refData.set.eWhenFull <> E_MsgFull.HoldNew;
nMinKind := KindNo(eK := refData.set.eMinKind);

IF NOT bStarted THEN
  (* the first call, also after a power cut: empty, no source seen *)
  bStarted := TRUE;
  eModePrev := refData.set.eMode;
  nCnt := 0;
  nHead := 0;
  nPos := 0;
  bShowing := FALSE;
  bRefresh := TRUE;
  FOR nI := nSLo TO nSHi DO
    aSources[nI].eState := E_State.Idle;
    aSources[nI].eError := E_UtError.None;
    aSources[nI].bKnown := TRUE;
  END_FOR;
END_IF;

(* a mode change starts afresh; Active builds from the sources *)
IF refData.set.eMode <> eModePrev THEN
  eModePrev := refData.set.eMode;
  nCnt := 0;
  nHead := 0;
  nPos := 0;
  bShowing := FALSE;
  bRefresh := TRUE;
  IF refData.set.eMode = E_MsgMode.Active THEN
    FOR nI := nSLo TO nSHi DO
      aSources[nI].bKnown := FALSE;
    END_FOR;
  END_IF;
END_IF;

(* once per scan: the scan's flags, and the HMI commands (once per write) *)
bClearReq := FALSE;
bNextReq := FALSE;
IF bNewScan THEN
  bNewMsg := FALSE;
  refData.sts.bWrnSrc := FALSE;
  bClearReq := refData.bCmdClear AND NOT bClearSeen;
  bClearSeen := refData.bCmdClear;
  refData.bCmdClear := FALSE;
  bNextReq := refData.bCmdNext AND NOT bNextSeen;
  bNextSeen := refData.bCmdNext;
  refData.bCmdNext := FALSE;
END_IF;
IF bClearReq THEN
  nCnt := 0;
  nHead := 0;
  nPos := 0;
  bShowing := FALSE;
  bRefresh := TRUE;
  IF refData.set.eMode = E_MsgMode.Active THEN
    FOR nI := nSLo TO nSHi DO
      aSources[nI].bKnown := FALSE;
    END_FOR;
  END_IF;
END_IF;

(* this call's source: act only on a change of its codes *)
nS := INT_TO_DINT(nSrc);
IF nS < nSLo OR nS > nSHi THEN
  refData.sts.bWrnSrc := TRUE;
ELSIF NOT aSources[nS].bKnown OR eSrcState <> aSources[nS].eState OR eSrcError <> aSources[nS].eError THEN
  bTaken := TRUE;
  IF eSrcState = E_State.Fault THEN
    nKind := 3;
  ELSIF eSrcError <> E_UtError.None THEN
    nKind := 2;
  ELSIF eSrcState = E_State.Held OR eSrcState = E_State.Waiting THEN
    nKind := 1;
  ELSE
    nKind := 0;
  END_IF;
  (* eMinKind or worse; Active never shows Idle, Off or Running with no error (nothing to say) *)
  bShow := nKind >= nMinKind
           AND (refData.set.eMode = E_MsgMode.Queue OR eSrcError <> E_UtError.None
                OR NOT (eSrcState = E_State.Idle OR eSrcState = E_State.Off OR eSrcState = E_State.Running));
  IF refData.set.eMode = E_MsgMode.Queue THEN
    IF bShow AND nNb >= 1 THEN
      IF nCnt >= nNb THEN
        IF bDropOld THEN
          (* drop the oldest to make room *)
          nHead := (nHead + 1) MOD nNb;
          nCnt := nCnt - 1;
          refData.sts.nLost := refData.sts.nLost + 1;
          bShowing := FALSE;
        ELSE
          bTaken := FALSE;        (* wait for room *)
        END_IF;
      END_IF;
      IF nCnt < nNb THEN
        nP := nBLo + (nHead + nCnt) MOD nNb;
        aBuffer[nP].nSrc := nSrc;
        aBuffer[nP].eState := eSrcState;
        aBuffer[nP].eError := eSrcError;
        aBuffer[nP].dtStamp := dtClock;
        nCnt := nCnt + 1;
        bNewMsg := TRUE;
      END_IF;
    END_IF;
  ELSE
    (* Active: this source's slot, if it has one *)
    nK := -1;
    FOR nI := 0 TO nCnt - 1 DO
      IF aBuffer[nBLo + nI].nSrc = nSrc THEN
        nK := nI;
        EXIT;
      END_IF;
    END_FOR;
    IF bShow THEN
      IF nK < 0 AND nCnt >= nNb AND nNb >= 1 AND bDropOld THEN
        (* drop the oldest to make room *)
        FOR nI := 0 TO nCnt - 2 DO
          aBuffer[nBLo + nI] := aBuffer[nBLo + nI + 1];
        END_FOR;
        nCnt := nCnt - 1;
        refData.sts.nLost := refData.sts.nLost + 1;
        IF nPos > 0 THEN
          nPos := nPos - 1;
        ELSE
          bShowing := FALSE;
        END_IF;
      END_IF;
      IF nK < 0 AND nCnt < nNb THEN
        nK := nCnt;
        nCnt := nCnt + 1;
      END_IF;
      IF nK >= 0 THEN
        nP := nBLo + nK;
        aBuffer[nP].nSrc := nSrc;
        aBuffer[nP].eState := eSrcState;
        aBuffer[nP].eError := eSrcError;
        aBuffer[nP].dtStamp := dtClock;
        bNewMsg := TRUE;
        IF bShowing AND nK = nPos THEN
          bRefresh := TRUE;
        END_IF;
      ELSIF nNb >= 1 THEN
        bTaken := FALSE;          (* HoldNew and full: wait for room *)
      END_IF;
    ELSIF nK >= 0 THEN
      (* back to normal, or below eMinKind: remove it, the rest move up *)
      FOR nI := nK TO nCnt - 2 DO
        aBuffer[nBLo + nI] := aBuffer[nBLo + nI + 1];
      END_FOR;
      nCnt := nCnt - 1;
      aBuffer[nBLo + nCnt].nSrc := 0;
      aBuffer[nBLo + nCnt].eState := E_State.Idle;
      aBuffer[nBLo + nCnt].eError := E_UtError.None;
      IF nK < nPos THEN
        nPos := nPos - 1;
      ELSIF nK = nPos THEN
        bShowing := FALSE;        (* the next one is shown now *)
      END_IF;
    END_IF;
  END_IF;
  IF bTaken THEN
    aSources[nS].eState := eSrcState;
    aSources[nS].eError := eSrcError;
    aSources[nS].bKnown := TRUE;
  END_IF;
END_IF;

(* Queue: a buffer full too long is emptied *)
IF refData.set.eMode = E_MsgMode.Queue AND nNb >= 1 AND nCnt >= nNb THEN
  IF NOT bWasFull THEN
    bWasFull := TRUE;
    tFullSince := tNow;
  ELSIF refData.set.tClearFullAfter > T#0s AND tNow - tFullSince >= refData.set.tClearFullAfter THEN
    refData.sts.nLost := refData.sts.nLost + DINT_TO_UDINT(nCnt);
    nCnt := 0;
    nHead := 0;
    bShowing := FALSE;
    bWasFull := FALSE;
  END_IF;
ELSE
  bWasFull := FALSE;
END_IF;

(* the display: each message for tShowTime (at least one scan) *)
IF bShowing AND (bNextReq OR (tNow - tShowAt >= refData.set.tShowTime AND tNow <> tShowAt)) THEN
  IF refData.set.eMode = E_MsgMode.Queue THEN
    (* shown: drop it *)
    nP := nBLo + nHead;
    aBuffer[nP].nSrc := 0;
    aBuffer[nP].eState := E_State.Idle;
    aBuffer[nP].eError := E_UtError.None;
    nHead := (nHead + 1) MOD nNb;
    nCnt := nCnt - 1;
    bShowing := FALSE;
  ELSIF nCnt > 1 THEN
    nPos := (nPos + 1) MOD nCnt;
    tShowAt := tNow;
    bRefresh := TRUE;
  ELSE
    tShowAt := tNow;              (* only one: it stays *)
  END_IF;
END_IF;
IF nCnt <= 0 THEN
  nCnt := 0;
  nHead := 0;
  nPos := 0;
  IF bShowing OR nMsgSrc <> 0 THEN
    bShowing := FALSE;
    bRefresh := TRUE;
  END_IF;
ELSIF NOT bShowing THEN
  IF refData.set.eMode = E_MsgMode.Queue OR nPos >= nCnt THEN
    nPos := 0;
  END_IF;
  bShowing := TRUE;
  tShowAt := tNow;
  bRefresh := TRUE;
END_IF;
IF bRefresh THEN
  bRefresh := FALSE;
  IF bShowing THEN
    IF refData.set.eMode = E_MsgMode.Queue THEN
      nP := nBLo + nHead;
    ELSE
      nP := nBLo + nPos;
    END_IF;
    nMsgSrc := aBuffer[nP].nSrc;
    eMsgState := aBuffer[nP].eState;
    eMsgError := aBuffer[nP].eError;
  ELSE
    nMsgSrc := 0;
    eMsgState := E_State.Idle;
    eMsgError := E_UtError.None;
  END_IF;
END_IF;

nCount := DINT_TO_INT(nCnt);
refData.sts.nCount := nCount;
refData.sts.bFull := nNb >= 1 AND nCnt >= nNb;
bError := NOT bSetOk;
bWarning := NOT bError AND (refData.sts.bWrnConfig OR refData.sts.bWrnSrc OR refData.sts.bRefused);
IF bError OR refData.sts.bWrnConfig THEN
  eErrorId := E_UtError.BadSetting;
ELSIF refData.sts.bWrnSrc THEN
  eErrorId := E_UtError.ValueBad;
ELSIF refData.sts.bRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN
  eState := E_State.Fault;
ELSE
  eState := E_State.Running;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK