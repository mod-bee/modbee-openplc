(* UT_CMD — command arbiter for two masters: the local one (panel HMI) and the
remote one (SCADA / IoT). Each gives command bits (a rising edge acts), a
mode request and a selection (each acts on a change to a value of 0 or
more). The accepted requests come out for one scan: Cmd / Cmd0..Cmd7, Mode,
Sel (else -1). Stop / off bits (stopMask) and mode 0 win over everything
else in a scan; local wins over remote. RemoteEnabled FALSE = local control:
remote requests are refused (Refused, refusedCount), except the stop bits
and mode 0 when remoteStop. localOnlyMask bits are never taken from the
remote master; remoteModes says which mode codes it may ask for; remoteSel
whether it may change the selection. Settings kept; a bad write is put back. *)

FUNCTION_BLOCK UT_CMD
  VAR_INPUT
    LocalCmd : DWORD; (* command bits (rising edge acts) *)
    RemoteCmd : DWORD;
    LocalMode : INT := -1; (* mode request (acts on a change to 0..15) *)
    RemoteMode : INT := -1;
    LocalSel : INT := -1; (* selection (auto type, preset, route ...) *)
    RemoteSel : INT := -1;
    RemoteEnabled : BOOL := TRUE; (* FALSE: local control *)
  END_VAR
  VAR_OUTPUT
    Cmd0 : BOOL;
    Cmd1 : BOOL;
    Cmd2 : BOOL;
    Cmd3 : BOOL;
    Cmd4 : BOOL;
    Cmd5 : BOOL;
    Cmd6 : BOOL;
    Cmd7 : BOOL;
    Cmd : DWORD; (* accepted bits, one scan *)
    Mode : INT; (* accepted mode request, one scan, else -1 *)
    Sel : INT; (* accepted selection, one scan, else -1 *)
    LastFrom : UT_CMD_FROM;
    LastRemote : BOOL;
    Refused : BOOL; (* one scan: a remote request was refused *)
  END_VAR
  VAR_IN_OUT
    Data : UT_CMD_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_CMD_SET;
  END_VAR
  VAR
    keep : UT_KEEP;
    started : BOOL;
    locPrev : DWORD;
    remPrev : DWORD;
    locModePrev : INT;
    remModePrev : INT;
    locSelPrev : INT;
    remSelPrev : INT;
    locEdge : DWORD;
    remEdge : DWORD;
    remMask : DWORD;
    remOk : DWORD;
    remBad : DWORD;
    locMode : INT;
    remMode : INT;
    locSel : INT;
    remSel : INT;
    modeBad : BOOL;
    selBad : BOOL;
    all : DWORD;
    locUsed : BOOL;
    remUsed : BOOL;
    remWas : BOOL;
    stCode : UT_STATUS;
    shownSt : UT_STATUS;
  END_VAR


keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;           (* every value of these settings is usable: nothing to put back *)
END_IF;
IF keep.SaveSet THEN
  keptSet := Data.set;
END_IF;
Refused := FALSE;
IF NOT started THEN
  started := TRUE;
  locPrev := LocalCmd;
  remPrev := RemoteCmd;
  locModePrev := LocalMode;
  remModePrev := RemoteMode;
  locSelPrev := LocalSel;
  remSelPrev := RemoteSel;
  remWas := RemoteEnabled;
  stCode := UT_ST_LOCAL_REMOTE;
END_IF;

(* each master's new requests *)
locEdge := LocalCmd AND NOT locPrev;
remEdge := RemoteCmd AND NOT remPrev;
locPrev := LocalCmd;
remPrev := RemoteCmd;
locMode := -1;
IF LocalMode <> locModePrev AND LocalMode >= 0 THEN
  locMode := LocalMode;
END_IF;
locModePrev := LocalMode;
remMode := -1;
IF RemoteMode <> remModePrev AND RemoteMode >= 0 THEN
  remMode := RemoteMode;
END_IF;
remModePrev := RemoteMode;
locSel := -1;
IF LocalSel <> locSelPrev AND LocalSel >= 0 THEN
  locSel := LocalSel;
END_IF;
locSelPrev := LocalSel;
remSel := -1;
IF RemoteSel <> remSelPrev AND RemoteSel >= 0 THEN
  remSel := RemoteSel;
END_IF;
remSelPrev := RemoteSel;

(* what the remote master may do now *)
IF RemoteEnabled THEN
  remMask := 16#FFFFFFFF;
ELSIF Data.set.remoteStop THEN
  remMask := Data.set.stopMask;
ELSE
  remMask := 0;
END_IF;
remMask := remMask AND NOT Data.set.localOnlyMask;
remOk := remEdge AND remMask;
remBad := remEdge AND NOT remMask;
modeBad := FALSE;
IF remMode >= 0 THEN
  IF remMode > 15 THEN
    modeBad := TRUE;
  ELSIF (SHR(Data.set.remoteModes, remMode) AND WORD#1) = WORD#0 THEN
    modeBad := TRUE;
  ELSIF NOT RemoteEnabled AND NOT (Data.set.remoteStop AND remMode = 0) THEN
    modeBad := TRUE;
  END_IF;
  IF modeBad THEN
    remMode := -1;
  END_IF;
END_IF;
IF locMode > 15 THEN
  locMode := -1;
END_IF;
selBad := remSel >= 0 AND NOT (RemoteEnabled AND Data.set.remoteSel);
IF selBad THEN
  remSel := -1;
END_IF;

(* combine: stop / off wins, then local before remote *)
all := locEdge OR remOk;
IF locMode = 0 OR remMode = 0 THEN
  Mode := 0;
ELSIF locMode >= 0 THEN
  Mode := locMode;
ELSE
  Mode := remMode;
END_IF;
IF (all AND Data.set.stopMask) <> 0 OR Mode = 0 THEN
  all := all AND Data.set.stopMask;
  IF Mode > 0 THEN
    Mode := -1;
  END_IF;
END_IF;
IF locSel >= 0 THEN
  Sel := locSel;
ELSE
  Sel := remSel;
END_IF;
Cmd := all;
Cmd0 := (Cmd AND 16#01) <> 0;
Cmd1 := (Cmd AND 16#02) <> 0;
Cmd2 := (Cmd AND 16#04) <> 0;
Cmd3 := (Cmd AND 16#08) <> 0;
Cmd4 := (Cmd AND 16#10) <> 0;
Cmd5 := (Cmd AND 16#20) <> 0;
Cmd6 := (Cmd AND 16#40) <> 0;
Cmd7 := (Cmd AND 16#80) <> 0;

(* who gave it; status *)
locUsed := (locEdge AND Cmd) <> 0 OR (Mode >= 0 AND Mode = locMode) OR (Sel >= 0 AND Sel = locSel);
remUsed := (remOk AND Cmd) <> 0 OR (Mode >= 0 AND Mode = remMode) OR (Sel >= 0 AND Sel = remSel AND locSel < 0);
IF locUsed OR remUsed THEN
  IF locUsed THEN
    Data.sts.lastSource := UT_FROM_LOCAL;
  ELSE
    Data.sts.lastSource := UT_FROM_REMOTE;
  END_IF;
  Data.sts.lastCmd := Cmd;
  Data.sts.lastMode := Mode;
  Data.sts.lastSel := Sel;
END_IF;
IF remBad <> 0 OR modeBad OR selBad THEN
  Refused := TRUE;
  Data.sts.refusedCount := Data.sts.refusedCount + 1;
  IF NOT RemoteEnabled THEN
    stCode := UT_ST_REFUSED_LOCAL;
  ELSE
    stCode := UT_ST_REFUSED_LOCAL_ONLY;
  END_IF;
ELSIF locUsed OR remUsed OR RemoteEnabled <> remWas
      OR NOT (stCode = UT_ST_REFUSED_LOCAL OR stCode = UT_ST_REFUSED_LOCAL_ONLY) THEN
  IF RemoteEnabled THEN
    stCode := UT_ST_LOCAL_REMOTE;
  ELSE
    stCode := UT_ST_LOCAL;
  END_IF;
END_IF;
remWas := RemoteEnabled;
LastFrom := Data.sts.lastSource;
LastRemote := Data.sts.lastSource = UT_FROM_REMOTE;
IF stCode <> shownSt OR LEN(Data.sts.statusText) = 0 THEN
  shownSt := stCode;
  Data.sts.statusText := UT_STATUS_TEXT(stCode, UT_F_NONE);
END_IF;
Data.sts.statusCode := stCode;
Data.sts.faultId := UT_F_NONE;
Data.sts.ne107 := UT_NE107_RUN(Fault := FALSE, Check := NOT RemoteEnabled, OutOfSpec := FALSE, Maint := FALSE);

END_FUNCTION_BLOCK