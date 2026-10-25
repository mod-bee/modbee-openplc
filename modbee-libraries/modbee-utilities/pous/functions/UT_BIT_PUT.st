(* Word with bit Bit (0..31) set to Value; Bit outside 0..31 leaves it as is *)

FUNCTION UT_BIT_PUT : DWORD
  VAR_INPUT
    Bits : DWORD;
    Bit : SINT;
    Value : BOOL;
  END_VAR

IF Bit < 0 OR Bit > 31 THEN
  UT_BIT_PUT := Bits;
ELSIF Value THEN
  UT_BIT_PUT := Bits OR SHL(DWORD#1, Bit);
ELSE
  UT_BIT_PUT := Bits AND NOT SHL(DWORD#1, Bit);
END_IF;

END_FUNCTION