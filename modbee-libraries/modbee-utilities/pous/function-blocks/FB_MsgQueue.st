(* FB_MsgQueue — message ticker and site-status board for an HMI (messages are codes: the source's eState and
eErrorId, the HMI shows the words).
Call it once per source per scan, all calls on the same instance, aMessages, aSources and refData (one rung each):
  fbMsgs(eSourceState := fbPump1.eState, eSourceErrorId := fbPump1.eErrorId, nSource := 1, aMessages := aMsgBuf, aSources := aMsgSrc, refData := stMsgs);
  fbMsgs(eSourceState := fbPump2.eState, eSourceErrorId := fbPump2.eErrorId, nSource := 2, ...);
aSources[nSource] keeps the last state and error seen from that source, so a message is taken only when one of them
changes. Its kind: Fault (eSourceState Fault), Warning (an eSourceErrorId, not Fault), Held (Held or Waiting), else
Normal; only kinds of set.eMinMessageKind or worse are taken (default Held; Normal: every change).
  Queue   (the default) each new or changed message is queued, shown for set.tDisplayTime, then dropped, in the order
          they came.
  Active  one slot per source holds its current message; a kind below eMinMessageKind (or Idle, Off, Running with no
          error) removes it; the display goes round the active ones every tDisplayTime ("what's wrong now").
When the buffer is full: set.eWhenFull DropOldest makes room by dropping the oldest (sts.nMessageLostCount); HoldNew keeps what
is there and new messages wait for room (their source is tried again on every call). Queue: a buffer that stays
full for set.tClearFullAfter is emptied. bCmdClearMessages: Queue empties it; Active builds it again from the sources.
bCmdNextMessage: the next message now (Queue drops the one on display).
RAM is what you declare: one ST_Msg per slot, one ST_MsgSrc per source. One instance is called many times in a
scan (TIME() is the same for the whole scan): bMessageReceived stays on for the rest of the scan in which a message arrived,
and the commands act once per scan.
Pins: eSourceState, eSourceErrorId, nSource, dtLocalTime, refData, aMessages, aSources -> nMessages, nShownSource, eShownState, eShownErrorId
(the message on display; 0 / Idle / None when none), bMessageReceived, plus FB_Object's outputs (warning BadSetting: no
slot or no source; ValueBad: a call's nSource outside aSources, ignored). Settings are kept (a retained last-good
copy, a bad write put back). *)

FUNCTION_BLOCK FB_MsgQueue EXTENDS FB_Object
  VAR_INPUT
    eSourceState : E_State; (* the source's state (e.g. fbPump1.eState) *)
    eSourceErrorId : E_UtError; (* its error (e.g. fbPump1.eErrorId) *)
    nSource : INT := 1; (* the source: the element of aSources this call uses *)
    dtLocalTime : DT; (* optional real-time clock: stamped on each message *)
    refData : REFERENCE TO ST_MsgQueueData; (* the block's record (one rung per source, all with the same record) *)
  END_VAR
  VAR_IN_OUT
    aMessages : ARRAY [*] OF ST_MSG; (* the slots: as many as declared *)
    aSources : ARRAY [*] OF ST_MSGSRC; (* last state and error seen per source, index = nSource *)
  END_VAR
  VAR_OUTPUT
    nMessages : INT; (* messages waiting (Queue) or active (Active) *)
    nShownSource : INT; (* the source of the message on display (0 when none) *)
    eShownState : E_State; (* its state (Idle when none) *)
    eShownErrorId : E_UtError; (* its error (None when none) *)
    bMessageReceived : BOOL; (* on for the scan in which a message came (or changed) *)
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
  IF NOT (stS.tDisplayTime >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tClearFullAfter >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.eQueueMode = E_MsgMode.Queue OR stS.eQueueMode = E_MsgMode.Active) THEN
    SetWhy := E_UtError.ChoiceBad;
  ELSIF NOT (stS.eWhenFull = E_MsgFull.DropOldest OR stS.eWhenFull = E_MsgFull.HoldNew) THEN
    SetWhy := E_UtError.ChoiceBad;
  ELSIF NOT (stS.eMinMessageKind = E_MsgKind.Normal OR stS.eMinMessageKind = E_MsgKind.Held OR stS.eMinMessageKind = E_MsgKind.Warning
             OR stS.eMinMessageKind = E_MsgKind.Fault) THEN
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
  bMessageReceived := FALSE;
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();
nBLo := LOWER_BOUND(aMessages, 1);
nNb := MAX(UPPER_BOUND(aMessages, 1) - nBLo + 1, 0);
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
    refData.sts.eSettingRefusedErrorId := SetWhy(stS := refData.set);
    refData.set := stKept;
    refData.sts.bSettingRefused := TRUE;
    bSetOk := TRUE;
  END_IF;
  IF SystemReset() THEN
    refData.sts.bSettingRefused := FALSE;
    refData.sts.eSettingRefusedErrorId := E_UtError.None;
  END_IF;
END_IF;
refData.sts.bBufferSizeBad := nNb < 1 OR nSHi < nSLo;
bDropOld := refData.set.eWhenFull <> E_MsgFull.HoldNew;
nMinKind := KindNo(eK := refData.set.eMinMessageKind);

IF NOT bStarted THEN
  (* the first call, also after a power cut: empty, no source seen *)
  bStarted := TRUE;
  eModePrev := refData.set.eQueueMode;
  nCnt := 0;
  nHead := 0;
  nPos := 0;
  bShowing := FALSE;
  bRefresh := TRUE;
  FOR nI := nSLo TO nSHi DO
    aSources[nI].eLastState := E_State.Idle;
    aSources[nI].eLastErrorId := E_UtError.None;
    aSources[nI].bEverHeard := TRUE;
  END_FOR;
END_IF;

(* a mode change starts afresh; Active builds from the sources *)
IF refData.set.eQueueMode <> eModePrev THEN
  eModePrev := refData.set.eQueueMode;
  nCnt := 0;
  nHead := 0;
  nPos := 0;
  bShowing := FALSE;
  bRefresh := TRUE;
  IF refData.set.eQueueMode = E_MsgMode.Active THEN
    FOR nI := nSLo TO nSHi DO
      aSources[nI].bEverHeard := FALSE;
    END_FOR;
  END_IF;
END_IF;

(* once per scan: the scan's flags, and the HMI commands (once per write) *)
bClearReq := FALSE;
bNextReq := FALSE;
IF bNewScan THEN
  bMessageReceived := FALSE;
  refData.sts.bSourceOutOfRange := FALSE;
  bClearReq := refData.bCmdClearMessages AND NOT bClearSeen;
  bClearSeen := refData.bCmdClearMessages;
  refData.bCmdClearMessages := FALSE;
  bNextReq := refData.bCmdNextMessage AND NOT bNextSeen;
  bNextSeen := refData.bCmdNextMessage;
  refData.bCmdNextMessage := FALSE;
END_IF;
IF bClearReq THEN
  nCnt := 0;
  nHead := 0;
  nPos := 0;
  bShowing := FALSE;
  bRefresh := TRUE;
  IF refData.set.eQueueMode = E_MsgMode.Active THEN
    FOR nI := nSLo TO nSHi DO
      aSources[nI].bEverHeard := FALSE;
    END_FOR;
  END_IF;
END_IF;

(* this call's source: act only on a change of its codes *)
nS := INT_TO_DINT(nSource);
IF nS < nSLo OR nS > nSHi THEN
  refData.sts.bSourceOutOfRange := TRUE;
ELSIF NOT aSources[nS].bEverHeard OR eSourceState <> aSources[nS].eLastState OR eSourceErrorId <> aSources[nS].eLastErrorId THEN
  bTaken := TRUE;
  IF eSourceState = E_State.Fault THEN
    nKind := 3;
  ELSIF eSourceErrorId <> E_UtError.None THEN
    nKind := 2;
  ELSIF eSourceState = E_State.Held OR eSourceState = E_State.Waiting THEN
    nKind := 1;
  ELSE
    nKind := 0;
  END_IF;
  (* eMinMessageKind or worse; Active never shows Idle, Off or Running with no error (nothing to say) *)
  bShow := nKind >= nMinKind
           AND (refData.set.eQueueMode = E_MsgMode.Queue OR eSourceErrorId <> E_UtError.None
                OR NOT (eSourceState = E_State.Idle OR eSourceState = E_State.Off OR eSourceState = E_State.Running));
  IF refData.set.eQueueMode = E_MsgMode.Queue THEN
    IF bShow AND nNb >= 1 THEN
      IF nCnt >= nNb THEN
        IF bDropOld THEN
          (* drop the oldest to make room *)
          nHead := (nHead + 1) MOD nNb;
          nCnt := nCnt - 1;
          refData.sts.nMessageLostCount := refData.sts.nMessageLostCount + 1;
          bShowing := FALSE;
        ELSE
          bTaken := FALSE;        (* wait for room *)
        END_IF;
      END_IF;
      IF nCnt < nNb THEN
        nP := nBLo + (nHead + nCnt) MOD nNb;
        aMessages[nP].nSource := nSource;
        aMessages[nP].eSourceState := eSourceState;
        aMessages[nP].eSourceErrorId := eSourceErrorId;
        aMessages[nP].dtTimeStamp := dtLocalTime;
        nCnt := nCnt + 1;
        bMessageReceived := TRUE;
      END_IF;
    END_IF;
  ELSE
    (* Active: this source's slot, if it has one *)
    nK := -1;
    FOR nI := 0 TO nCnt - 1 DO
      IF aMessages[nBLo + nI].nSource = nSource THEN
        nK := nI;
        EXIT;
      END_IF;
    END_FOR;
    IF bShow THEN
      IF nK < 0 AND nCnt >= nNb AND nNb >= 1 AND bDropOld THEN
        (* drop the oldest to make room *)
        FOR nI := 0 TO nCnt - 2 DO
          aMessages[nBLo + nI] := aMessages[nBLo + nI + 1];
        END_FOR;
        nCnt := nCnt - 1;
        refData.sts.nMessageLostCount := refData.sts.nMessageLostCount + 1;
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
        aMessages[nP].nSource := nSource;
        aMessages[nP].eSourceState := eSourceState;
        aMessages[nP].eSourceErrorId := eSourceErrorId;
        aMessages[nP].dtTimeStamp := dtLocalTime;
        bMessageReceived := TRUE;
        IF bShowing AND nK = nPos THEN
          bRefresh := TRUE;
        END_IF;
      ELSIF nNb >= 1 THEN
        bTaken := FALSE;          (* HoldNew and full: wait for room *)
      END_IF;
    ELSIF nK >= 0 THEN
      (* back to normal, or below eMinMessageKind: remove it, the rest move up *)
      FOR nI := nK TO nCnt - 2 DO
        aMessages[nBLo + nI] := aMessages[nBLo + nI + 1];
      END_FOR;
      nCnt := nCnt - 1;
      aMessages[nBLo + nCnt].nSource := 0;
      aMessages[nBLo + nCnt].eSourceState := E_State.Idle;
      aMessages[nBLo + nCnt].eSourceErrorId := E_UtError.None;
      IF nK < nPos THEN
        nPos := nPos - 1;
      ELSIF nK = nPos THEN
        bShowing := FALSE;        (* the next one is shown now *)
      END_IF;
    END_IF;
  END_IF;
  IF bTaken THEN
    aSources[nS].eLastState := eSourceState;
    aSources[nS].eLastErrorId := eSourceErrorId;
    aSources[nS].bEverHeard := TRUE;
  END_IF;
END_IF;

(* Queue: a buffer full too long is emptied *)
IF refData.set.eQueueMode = E_MsgMode.Queue AND nNb >= 1 AND nCnt >= nNb THEN
  IF NOT bWasFull THEN
    bWasFull := TRUE;
    tFullSince := tNow;
  ELSIF refData.set.tClearFullAfter > T#0s AND tNow - tFullSince >= refData.set.tClearFullAfter THEN
    refData.sts.nMessageLostCount := refData.sts.nMessageLostCount + DINT_TO_UDINT(nCnt);
    nCnt := 0;
    nHead := 0;
    bShowing := FALSE;
    bWasFull := FALSE;
  END_IF;
ELSE
  bWasFull := FALSE;
END_IF;

(* the display: each message for tDisplayTime (at least one scan) *)
IF bShowing AND (bNextReq OR (tNow - tShowAt >= refData.set.tDisplayTime AND tNow <> tShowAt)) THEN
  IF refData.set.eQueueMode = E_MsgMode.Queue THEN
    (* shown: drop it *)
    nP := nBLo + nHead;
    aMessages[nP].nSource := 0;
    aMessages[nP].eSourceState := E_State.Idle;
    aMessages[nP].eSourceErrorId := E_UtError.None;
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
  IF bShowing OR nShownSource <> 0 THEN
    bShowing := FALSE;
    bRefresh := TRUE;
  END_IF;
ELSIF NOT bShowing THEN
  IF refData.set.eQueueMode = E_MsgMode.Queue OR nPos >= nCnt THEN
    nPos := 0;
  END_IF;
  bShowing := TRUE;
  tShowAt := tNow;
  bRefresh := TRUE;
END_IF;
IF bRefresh THEN
  bRefresh := FALSE;
  IF bShowing THEN
    IF refData.set.eQueueMode = E_MsgMode.Queue THEN
      nP := nBLo + nHead;
    ELSE
      nP := nBLo + nPos;
    END_IF;
    nShownSource := aMessages[nP].nSource;
    eShownState := aMessages[nP].eSourceState;
    eShownErrorId := aMessages[nP].eSourceErrorId;
  ELSE
    nShownSource := 0;
    eShownState := E_State.Idle;
    eShownErrorId := E_UtError.None;
  END_IF;
END_IF;

nMessages := DINT_TO_INT(nCnt);
refData.sts.nMessages := nMessages;
refData.sts.bBufferFull := nNb >= 1 AND nCnt >= nNb;
bError := NOT bSetOk;
bWarning := NOT bError AND (refData.sts.bBufferSizeBad OR refData.sts.bSourceOutOfRange OR refData.sts.bSettingRefused);
IF bError OR refData.sts.bBufferSizeBad THEN
  eErrorId := E_UtError.BadSetting;
ELSIF refData.sts.bSourceOutOfRange THEN
  eErrorId := E_UtError.ValueBad;
ELSIF refData.sts.bSettingRefused THEN
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