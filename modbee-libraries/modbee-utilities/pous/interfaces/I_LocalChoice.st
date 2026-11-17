INTERFACE I_LocalChoice EXTENDS __SYSTEM


.IQueryInterface
  METHOD Choose : BOOL             // TRUE: the block has this choice
    VAR_INPUT
      eChoice : E_LocalChoice;
    END_VAR
  END_METHOD

END_INTERFACE