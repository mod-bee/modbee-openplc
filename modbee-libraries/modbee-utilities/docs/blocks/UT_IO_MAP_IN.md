# UT_IO_MAP_IN — Input IO map: terminals to functions

Your plant logic reads **functions** ("well float HH", "pump 1 overload"), never a
terminal. The IO map connects each function to a channel from its settings, so
re-wiring a site, or moving a signal to an I2C module or a remote device, is a
setting, not a program change. It also tells your logic whether each value can be
trusted, gives a fail-safe value when it can't, and lets a commissioning engineer
force an input for a set time.

UT_IO_MAP_IN does the inputs; [UT_IO_MAP_OUT](UT_IO_MAP_OUT.md) does the outputs.
The two share the module table and the force slots. The IO types (`UT_IO_…`) are
described on this page.

**Call order in the scan:**
1. Your IO code copies the hardware into the input image (`DigImg[n].q`,
   `AnaImg[n].v`) and sets each module's `ok`.
2. **UT_IO_MAP_IN.**
3. Your logic, which reads `Dig[n].q`, `Dig[n].ok`, `Ana[n].v`.
4. [UT_IO_MAP_OUT](UT_IO_MAP_OUT.md).
5. Your IO code copies the output image to the hardware.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ForceTime` | TIME | T#5s | How long a commissioning force lasts. At most 10 min. `T#0s`, negative or over 10 min: 5 s or 10 min is used (`Setting: force time`) |
| in | `ReleaseAll` | BOOL | FALSE | TRUE ends every input force now and refuses new ones. Wire the HMI link-lost signal, or a "release all forces" key |
| in | `UnusedOff` | BOOL | FALSE | TRUE: a function that is not fitted on this site (`src` NONE) reads FALSE (analog 0.0) instead of its `failSafe`. A fitted function that is lost still reads its `failSafe` |
| out | `AllOk` | BOOL | | Every function with an address reads a good (or forced) channel, and every fitted input module answers |
| out | `AnyForced` | BOOL | | An input force slot is forcing |
| out | `ConfigBad` | BOOL | | A function's address is wrong (no such module or channel), or its module is not fitted |
| inout | `Dig` | ARRAY[*] OF UT_IO_DI | | The digital input functions, one row each |
| inout | `Ana` | ARRAY[*] OF UT_IO_AI | | The analog input functions (raw values), one row each |
| inout | `DigImg` | ARRAY[*] OF UT_IO_DCH | | The digital input terminals. Your IO code writes `q` (and `bad`) |
| inout | `AnaImg` | ARRAY[*] OF UT_IO_ACH | | The analog input terminals. Your IO code writes `v` (and `bad`) |
| inout | `Mods` | ARRAY[*] OF UT_IO_MOD | | The module table, shared with UT_IO_MAP_OUT |
| inout | `Force` | ARRAY[*] OF UT_IO_FORCE | | The force slots, shared with UT_IO_MAP_OUT. Never `RETAIN` |
| inout | `Data` | UT_IO_MAP_DATA | | Status: code, text and counts |

Number every array from 1 (`ARRAY[1..n]`). The row number of a function is its
number on the IO page, and 0 means "none" in the image's `fn`.

## Using it
```iecst
VAR
  IoIn    : UT_IO_MAP_IN;
  DiFn    : ARRAY[1..16] OF UT_IO_DI;    (* 1 = well float HH, 2 = pump 1 overload, ... *)
  AiFn    : ARRAY[1..4] OF UT_IO_AI;     (* 1 = sump level, ... *)
  DiImg   : ARRAY[1..16] OF UT_IO_DCH;   (* board DI 1..8, I2C module DI 9..16 *)
  AiImg   : ARRAY[1..4] OF UT_IO_ACH;
  IoMods  : ARRAY[1..6] OF UT_IO_MOD;
  IoForce : ARRAY[1..4] OF UT_IO_FORCE;
  IoInSt  : UT_IO_MAP_DATA;
END_VAR

(* 1. your IO code: terminals into the image *)
DiImg[1].q := %IX0.0;
DiImg[2].q := %IX0.1;
AiImg[1].v := INT_TO_REAL(%IW0);
IoMods[1].ok := TRUE;                  (* the board always answers *)
IoMods[3].ok := I2cDiModuleOk;         (* from the I2C driver *)

(* 2. the IO map *)
IoIn(ReleaseAll := NOT HmiLinkOk, Dig := DiFn, Ana := AiFn, DigImg := DiImg, AnaImg := AiImg,
     Mods := IoMods, Force := IoForce, Data := IoInSt);

(* 3. your logic reads functions *)
Pump1(Demand := DiFn[1].q, ...);
Level(In := AiFn[1].v, Data := LevelData);
```

The settings, for example: `IoMods[1]` is `kind := UT_IOK_DI`, `src := UT_IOS_BOARD`,
`module := 1`, `first := 1`, `count := 8`. `DiFn[2]` (the pump 1 overload, an NC aux
on board input 2) is `src := UT_IOS_BOARD`, `module := 1`, `ch := 2`, `nc := TRUE`,
`failSafe := TRUE`.

## Addresses
A channel's address is three numbers:

| Setting | Type | Meaning |
| --- | --- | --- |
| `src` | UT_IO_SRC | Where it is (below). `UT_IOS_NONE` = the function is not fitted on this site |
| `module` | USINT | Which module of that source, from 1. The board's DI, DO, AI and AO are each a module: board DI module 1, board DO module 1 … |
| `ch` | USINT | The channel on that module, from 1 |

**`UT_IO_SRC`: where a channel is**
| No. | Value | Meaning |
| --- | --- | --- |
| 0 | `UT_IOS_NONE` | Not fitted: the function reads its `failSafe` (or FALSE / 0.0 with `UnusedOff`) |
| 1 | `UT_IOS_BOARD` | The controller's own terminals |
| 2 | `UT_IOS_I2C` | An I2C expansion module |
| 3 | `UT_IOS_FIELD` | A field-bus device: Modbus over RS485, or the LoRa mesh |
| 4 | `UT_IOS_REMOTE` | A remote value (MQTT / SCADA) |

**`UT_IO_KIND`: what a module's channels are**
| No. | Value | Meaning |
| --- | --- | --- |
| 0 | `UT_IOK_NONE` | An empty row of the module table, or a force slot not used |
| 1 | `UT_IOK_DI` | Digital inputs |
| 2 | `UT_IOK_DO` | Digital outputs |
| 3 | `UT_IOK_AI` | Analog inputs |
| 4 | `UT_IOK_AO` | Analog outputs |

## The module table `UT_IO_MOD`
One row per module. UT_IO_MAP_IN looks after the DI and AI rows, UT_IO_MAP_OUT the
DO and AO rows.

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `kind` | UT_IO_KIND | UT_IOK_NONE | DI, DO, AI or AO |
| `src` | UT_IO_SRC | UT_IOS_NONE | Board, I2C, field or remote |
| `module` | USINT | 0 | Its number within that source, from 1 |
| `first` | INT | 0 | The image row of its channel 1 (an index of `DigImg` or `AnaImg`) |
| `count` | USINT | 0 | How many channels it has |
| `fitted` | BOOL | TRUE | Setting: installed on this site |
| `ok` | BOOL | FALSE | Present and answering. **Your IO code or the driver sets it every scan**; for the board, set it TRUE. Left FALSE, the module reads as missing |
| `state` | UT_IO_Q | | Status: `UT_IOQ_OK`, `UT_IOQ_NOT_FITTED` or `UT_IOQ_MISSING` |
| `used` | USINT | | Status: how many functions are mapped to it |

A function's module is the first row with the same `kind`, `src` and `module`.
Channel `ch` is image row `first + ch - 1`.

## The image `UT_IO_DCH`, `UT_IO_ACH`
One row per terminal. The input image (`DigImg`, `AnaImg` here) and the output
image (on UT_IO_MAP_OUT) are separate arrays.

| Field | Type | Meaning |
| --- | --- | --- |
| `q` (digital) | BOOL | The terminal: input contact made, output energised |
| `v` (analog) | REAL | The raw value (inputs: before scaling) |
| `bad` | BOOL | Written by its driver: this channel can't be trusted (a stale point, a failed write) |
| `forced` | BOOL | Status: a force slot holds it |
| `fn` | INT | Status: the row of the function on it (inputs: the first one); 0 = spare |

The input image always keeps the real terminal value, also while it is forced: the
IO page can show both.

## Digital input function `UT_IO_DI`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `src`, `module`, `ch` | | NONE, 0, 0 | Setting: where it is wired (see [Addresses](#addresses)) |
| `nc` | BOOL | FALSE | Setting: a normally-closed contact. The block inverts it, so `q` is TRUE = active |
| `debounce` | TIME | T#0s | Setting: a new state must hold this long before `q` follows (both ways). `T#0s` = none |
| `failSafe` | BOOL | FALSE | Setting: what `q` reads when the channel is not fitted, missing, bad or wrongly addressed |
| `q` | BOOL | | Status: the value for your logic, TRUE = active |
| `ok` | BOOL | | Status: `q` comes from a good channel, or from a force |
| `why` | UT_IO_Q | | Status: the quality, and why it is not good (below) |
| `raw`, `since` | BOOL, TIME | | Kept by the block for the debounce. Don't write them |

## Analog input function `UT_IO_AI`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `src`, `module`, `ch` | | NONE, 0, 0 | Setting: where it is wired |
| `failSafe` | REAL | 0.0 | Setting: what `v` reads when the channel is not good. 0.0 looks like a broken 4–20 mA loop to [UT_ANALOG_IN](UT_ANALOG_IN.md) |
| `v` | REAL | | Status: the raw value for your logic. Feed it to UT_ANALOG_IN's `In` |
| `ok` | BOOL | | Status: `v` comes from a good channel, or from a force |
| `why` | UT_IO_Q | | Status: the quality and why |

## Quality `UT_IO_Q`
The `why` of a function, the `state` of a module or of a force slot. A function's
`ok` is TRUE only for OK and FORCED.

| No. | Value | Function | Module | Force slot |
| --- | --- | --- | --- | --- |
| 0 | `UT_IOQ_UNUSED` | Not fitted on this site (`src` NONE) | Empty row | Free, released or timed out |
| 1 | `UT_IOQ_OK` | Good | Fitted and answering | |
| 2 | `UT_IOQ_FORCED` | Its channel is forced | | Forcing |
| 3 | `UT_IOQ_NOT_FITTED` | Its module is not fitted on this site | `fitted` FALSE | |
| 4 | `UT_IOQ_MISSING` | Its module is fitted but not answering | `ok` FALSE | |
| 5 | `UT_IOQ_BAD` | The channel's `bad` is set | | |
| 6 | `UT_IOQ_NO_MODULE` | No module of that kind, source and number in the table | | Refused: no such module |
| 7 | `UT_IOQ_NO_CHANNEL` | The module has no such channel, or the image is too short | | Refused: no such channel |
| 8 | `UT_IOQ_SHARED` | Outputs: another function already drives this channel | | |
| 9 | `UT_IOQ_BLOCKED` | Outputs: forced, but held off by its `block` bit | | |
| 10 | `UT_IOQ_NOT_PERMITTED` | | | Outputs: refused or ended, `ForcePermit` is FALSE |

## Force slot `UT_IO_FORCE`
One row per force. A slot names a channel, not a function, so a spare terminal can
be forced too. Declare the slots without `RETAIN`.

| Field | Type | Meaning |
| --- | --- | --- |
| `kind` | UT_IO_KIND | The channel to force: DI or AI here (DO or AO on UT_IO_MAP_OUT). `UT_IOK_NONE` = slot not used |
| `src`, `module`, `ch` | | The channel's address |
| `q` | BOOL | Digital: the state. Inputs: the terminal, as if the contact were made |
| `v` | REAL | Analog: the raw value (inputs: before scaling) |
| `cmdForce` | BOOL | HMI: force now, or start the time again |
| `cmdRelease` | BOOL | HMI: release now |
| `active` | BOOL | Status: forcing now |
| `timeLeft` | TIME | Status: time until it releases by itself |
| `state` | UT_IO_Q | Status: `UT_IOQ_FORCED`, or why not (`UT_IOQ_NO_MODULE`, `UT_IOQ_NO_CHANNEL`, `UT_IOQ_NOT_PERMITTED`), `UT_IOQ_UNUSED` when free |
| `row`, `forceSeen`, `releaseSeen` | | Kept by the block. Don't write them |

The commands act once, on their rising edge, and the block clears them. A command
held on (a Modbus coil, a debugger force) acts once. How a slot runs is on
[UT_IO_FORCE_RUN](UT_IO_FORCE_RUN.md).

## Record `UT_IO_MAP_DATA`
One per map (one for inputs, one for outputs). Status only.

| Field | Type | Meaning |
| --- | --- | --- |
| `statusCode` | UT_STATUS | OK, a warning, or a configuration problem (below) |
| `faultId` | UT_FAULT | Which: IO forced, IO module missing, IO address … |
| `statusText` | STRING(30) | The two in words |
| `forcedCount` | INT | Input force slots forcing now |
| `forceLeft` | TIME | The longest time left of the active forces |
| `badCount` | INT | Functions with an address (`src` not NONE) that are not good: wrong address, module not fitted, missing or bad. A forced function counts as good |
| `missingCount` | INT | Fitted input modules not answering (used by a function or not) |

## Status
`statusCode`, `faultId` and `statusText` give the most important problem, in the
order below. The text is rebuilt only when the code or the fault changes. The
numbers are in [conventions](../conventions.md#the-numbers).

| `statusCode` | `faultId` | `statusText` | When |
| --- | --- | --- | --- |
| `UT_ST_CONFIG` | `UT_F_IO_ADDRESS` | `Config: IO address` | A function's module is not in the table, or its channel is not on the module or outside the image |
| `UT_ST_CONFIG` | `UT_F_IO_NOT_FITTED` | `Config: IO not fitted` | A function is on a module with `fitted` FALSE |
| `UT_ST_WARNING` | `UT_F_IO_FORCED` | `Warning: IO forced` | An input is forced (`forceLeft`: the time left) |
| `UT_ST_WARNING` | `UT_F_IO_MISSING` | `Warning: IO module missing` | A fitted input module is not answering |
| `UT_ST_WARNING` | `UT_F_IO_BAD` | `Warning: IO channel bad` | A function's channel has `bad` set |
| `UT_ST_WARN_SETTING` | `UT_F_FORCE_TIME` | `Setting: force time` | `ForceTime` is 0, negative or over 10 min |
| `UT_ST_OK` | | `OK` | Everything good |

A `Config:` status here does not stop the block: the other functions carry on, and
the function with the wrong address reads its `failSafe`.

## How it works
1. Each scan, for each function row, the block finds its module in the table and its
   row in the image, and checks in this order: not fitted (`src` NONE), no module,
   no channel, forced, module not fitted, module missing, channel bad, else OK.
2. **Good or forced:** `q` / `v` is the terminal (or the forced value), `ok` TRUE.
   Digital: inverted when `nc` is set, then debounced.
3. **Not good:** `q` / `v` reads the function's `failSafe`, never a plain "off", and
   `ok` is FALSE. Your logic decides what a lost signal means: a high-level float
   with `failSafe := TRUE` reads "high" when its module drops off the bus.
4. **Not fitted** (`src` NONE): reads `failSafe`, or FALSE / 0.0 with `UnusedOff`.
   `ok` stays FALSE and `why` UNUSED. Use `UnusedOff` when an option that is not
   installed must read "not active", while a fitted signal that is lost still reads
   its `failSafe`. A function on a module that is not fitted (`fitted` FALSE) always
   reads its `failSafe`.
5. **A channel that comes back** (good again after not fitted, missing, bad or a wrong
   address, and on the first scan): `q` follows it at once, with no debounce. When a
   force ends, the real value comes back through the debounce.
6. **Debounce:** a new state must hold `debounce` before `q` changes, on and off. A
   shorter pulse is ignored.
7. One input channel can feed several functions (no warning). The image's `fn` shows
   the first one.
8. The status and counts are worked out last. Modules of kind DO and AO, and force
   slots of kind DO and AO, are left to UT_IO_MAP_OUT.

### Forcing an input (commissioning)
- Fill a slot with `kind` (DI or AI), the address and the value (`q` or `v`), then
  set `cmdForce`. Inputs can be forced at any time (no permit).
- The force goes on the **terminal**, before the NC setting and before scaling, as a
  test wire would. An NC function sees a forced `q` TRUE as "contact made", which is
  inactive. A forced analog raw value goes through UT_ANALOG_IN's checks: force
  2.0 mA to test its wire-break alarm.
- The debounce is skipped while forced. A forced channel on a missing or not-fitted
  module reads as good (`why` FORCED) while forced; the module still shows its state.
- Each force ends by itself after `ForceTime` (5 s by default, at most 10 min).
  `cmdForce` again starts the time again. `cmdRelease`, or `ReleaseAll`, ends it at
  once. A shorter `ForceTime` cuts a running force's time at once.
- A slot whose address does not exist is refused (`state` NO_MODULE or NO_CHANNEL).
  Setting a slot's `kind` to NONE ends its force.
- Changing the address of a slot that is forcing moves the force to the new channel
  (if it exists). Release it first.
- These slots are separate from the debugger's force.

### Invalid settings
- A wrong address or a module not fitted: that function reads its `failSafe`,
  `ConfigBad` and a `Config:` status. The rest of the map carries on.
- `ForceTime` 0 or negative: 5 s is used; over 10 min: 10 min. `Setting: force time`.

### Power cut
Nothing is kept: every force ends at a power cut, a PLC stop or a program download.
The functions start again on the first scan, with no debounce. To keep the settings
(`src`, `module`, `ch`, `nc`, `debounce`, `failSafe`, the module table), write them
from your program or declare those arrays `RETAIN`. Never declare the force slots
`RETAIN`.
