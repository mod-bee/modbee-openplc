(* A transmitter chosen in the settings (installed, analog or both) whose plug
says it is not on this site (the IO map row not set): a configuration fault
for the owner, the way a missing setting is. *)

FUNCTION UT_MEAS_MISSING : BOOL
  VAR_INPUT
    Linked : BOOL; (* a measurement plug is wired *)
    Fitted : BOOL := TRUE; (* the plug's IsFitted() *)
  END_VAR
  VAR_IN_OUT
    M : UT_MEAS;
  END_VAR


UT_MEAS_MISSING := Linked AND NOT Fitted AND M.installed
                   AND (M.sensor = UT_SENSOR_ANALOG OR M.sensor = UT_SENSOR_BOTH);

END_FUNCTION