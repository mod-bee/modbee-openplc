(* why the settings of one reported value are bad (None: good; private to FB_Report and FB_ReportArray) *)

FUNCTION F_ReportSetWhy : E_UtError
  VAR_IN_OUT
    stSettings : ST_ReportSet; (* the settings to check *)
  END_VAR

F_ReportSetWhy := E_UtError.None;
IF NOT (stSettings.fDeadband >= 0.0) THEN
  F_ReportSetWhy := E_UtError.BelowMin;
ELSIF NOT (stSettings.fDeadband <= REAL#3.4E38) THEN
  F_ReportSetWhy := E_UtError.AboveMax;
ELSIF NOT (stSettings.fSpan >= 0.0) THEN
  F_ReportSetWhy := E_UtError.BelowMin;
ELSIF NOT (stSettings.fSpan <= REAL#3.4E38) THEN
  F_ReportSetWhy := E_UtError.AboveMax;
ELSIF NOT (stSettings.fRoundToStep >= 0.0) THEN
  F_ReportSetWhy := E_UtError.BelowMin;
ELSIF NOT (stSettings.fRoundToStep <= REAL#3.4E38) THEN
  F_ReportSetWhy := E_UtError.AboveMax;
ELSIF NOT (stSettings.tMinInterval >= T#0s) THEN
  F_ReportSetWhy := E_UtError.TimeBad;
ELSIF NOT (stSettings.tHeartbeatInterval >= T#0s) THEN
  F_ReportSetWhy := E_UtError.TimeBad;
ELSIF NOT (stSettings.eDeadbandMode = E_DeadbandMode.Abs OR stSettings.eDeadbandMode = E_DeadbandMode.PctValue
           OR (stSettings.eDeadbandMode = E_DeadbandMode.PctSpan AND stSettings.fSpan > 0.0)) THEN
  F_ReportSetWhy := E_UtError.ChoiceBad;
END_IF;

END_FUNCTION