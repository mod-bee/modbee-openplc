(* why the settings of one reported value are bad (None: good; private to FB_Report and FB_ReportArray) *)

FUNCTION F_ReportSetWhy : E_UtError
  VAR_IN_OUT
    stS : ST_ReportSet;
  END_VAR

F_ReportSetWhy := E_UtError.None;
IF NOT (stS.fDeadband >= 0.0) THEN
  F_ReportSetWhy := E_UtError.BelowMin;
ELSIF NOT (stS.fDeadband <= REAL#3.4E38) THEN
  F_ReportSetWhy := E_UtError.AboveMax;
ELSIF NOT (stS.fSpan >= 0.0) THEN
  F_ReportSetWhy := E_UtError.BelowMin;
ELSIF NOT (stS.fSpan <= REAL#3.4E38) THEN
  F_ReportSetWhy := E_UtError.AboveMax;
ELSIF NOT (stS.fResolution >= 0.0) THEN
  F_ReportSetWhy := E_UtError.BelowMin;
ELSIF NOT (stS.fResolution <= REAL#3.4E38) THEN
  F_ReportSetWhy := E_UtError.AboveMax;
ELSIF NOT (stS.tMinInterval >= T#0s) THEN
  F_ReportSetWhy := E_UtError.TimeBad;
ELSIF NOT (stS.tHeartbeat >= T#0s) THEN
  F_ReportSetWhy := E_UtError.TimeBad;
ELSIF NOT (stS.eDeadbandMode = E_DeadbandMode.Abs OR stS.eDeadbandMode = E_DeadbandMode.PctValue
           OR (stS.eDeadbandMode = E_DeadbandMode.PctSpan AND stS.fSpan > 0.0)) THEN
  F_ReportSetWhy := E_UtError.ChoiceBad;
END_IF;

END_FUNCTION