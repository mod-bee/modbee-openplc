(* I_Measurement — the measurement plug: a value in its unit, whether it can be trusted (bIsGood), has a value
at all and is fitted, and Band for its switch bands. Offered by FB_AnalogIn, FB_SwitchSet, FB_Vessel, the meters,
FB_SignalSelect and the decorators; read by pumps, level checks, level control and speed loops. *)

INTERFACE I_Measurement


PROPERTY fActValue : REAL         // the value in its unit (held at the last good one while bad, when so set)
  GET
  END_GET
END_PROPERTY
PROPERTY bIsGood : BOOL           // the value can be trusted now
  GET
  END_GET
END_PROPERTY
PROPERTY bHasValue : BOOL         // a continuous value (FALSE: switches only)
  GET
  END_GET
END_PROPERTY
PROPERTY bIsFitted : BOOL         // the sensor is on this site (FALSE: no value, no bands, no fault)
  GET
  END_GET
END_PROPERTY
PROPERTY eUnit : E_Unit           // the unit of fActValue (None: not set, or switches only)
  GET
  END_GET
END_PROPERTY

METHOD Band : BOOL                // a switch level is made (FALSE for a plain analog value)
  VAR_INPUT
    eBand : E_Band;    // the band asked about (LowLow, Low, High, HighHigh); returns TRUE while the value is in it
  END_VAR
END_METHOD

END_INTERFACE