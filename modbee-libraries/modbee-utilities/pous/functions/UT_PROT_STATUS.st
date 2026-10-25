(* The status line of a tripped protection: needs a reset, locked out,
waiting to retry, or waiting for the cause to clear *)

FUNCTION UT_PROT_STATUS : UT_STATUS
  VAR_INPUT
    Reset : UT_RESET_MODE; (* the protection's reset mode *)
  END_VAR
  VAR_IN_OUT
    Sts : UT_PROT_STS;
  END_VAR


IF Reset = UT_RST_MANUAL THEN
  UT_PROT_STATUS := UT_ST_FAULT_RESET;
ELSIF Sts.locked THEN
  UT_PROT_STATUS := UT_ST_FAULT_LOCKED;
ELSIF Reset = UT_RST_RETRY THEN
  UT_PROT_STATUS := UT_ST_FAULT_RETRY;
ELSE
  UT_PROT_STATUS := UT_ST_FAULT;
END_IF;

END_FUNCTION