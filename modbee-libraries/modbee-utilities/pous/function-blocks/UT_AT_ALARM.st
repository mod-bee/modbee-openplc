(* One alarm of a UT_ALARM_TABLE (an element block: one box per alarm, called before the table) *)

FUNCTION_BLOCK UT_AT_ALARM
  VAR_INPUT
    In : BOOL; (* the live condition *)
  END_VAR
  VAR_IN_OUT
    Data : UT_AT_ALARM_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_AT_SET;
    keptGood : BOOL;
  END_VAR
  VAR
    keep : UT_KEEP;
    mem : UT_AT_MEM;
    okSet : BOOL;
    tCur : TIME;
    ackAsk : BOOL;
    silAsk : BOOL;
    qRaised : BOOL;
    qSound : BOOL;
    qState : UT_AT_STATE;
    qOn : BOOL;
    qUnacked : BOOL;
    qTrip : BOOL;
    qCode : UT_FAULT;
  END_VAR


METHOD PUBLIC State : UT_AT_STATE
  State := qState;
END_METHOD
METHOD PUBLIC IsOn : BOOL
  IsOn := qOn;
END_METHOD
METHOD PUBLIC IsTrip : BOOL      // a TRIP alarm
  IsTrip := qTrip;
END_METHOD
METHOD PUBLIC IsUnacked : BOOL
  IsUnacked := qUnacked;
END_METHOD
METHOD PUBLIC Code : UT_FAULT
  Code := qCode;
END_METHOD
METHOD PUBLIC Raised : BOOL      // raised this scan
  Raised := qRaised;
END_METHOD
METHOD PUBLIC Sounding : BOOL
  Sounding := qSound;
END_METHOD
METHOD PUBLIC IsValid : BOOL
  IsValid := okSet;
END_METHOD
METHOD PUBLIC Ack : BOOL         // acknowledge; a latched / locked alarm whose condition has gone clears
  ackAsk := TRUE;
  Ack := TRUE;
END_METHOD
METHOD PUBLIC Silence : BOOL
  silAsk := TRUE;
  Silence := TRUE;
END_METHOD

tCur := TIME();
keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
okSet := UT_PROT_OK(P := Data.set.prot) AND Data.set.retryWindow >= T#0s AND Data.set.rearm >= T#0s;
IF NOT okSet AND keptGood AND NOT keep.FirstBoot THEN
  Data.sts.code := Data.set.code;
  Data.set := keptSet;
  okSet := TRUE;
END_IF;
IF keep.SaveSet AND (okSet OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := okSet;
END_IF;
qRaised := UT_ALARM_RUN(TNow := tCur, In := In, AckReq := ackAsk, ResetReq := ackAsk, SilenceReq := silAsk,
                        Set := Data.set, Mem := mem, Sts := Data.sts, Sounding => qSound);
ackAsk := FALSE;
silAsk := FALSE;
qState := Data.sts.state;
qOn := Data.sts.q;
qUnacked := Data.sts.unacked;
qTrip := Data.set.prot.response = UT_RESP_TRIP;
qCode := Data.set.code;

END_FUNCTION_BLOCK