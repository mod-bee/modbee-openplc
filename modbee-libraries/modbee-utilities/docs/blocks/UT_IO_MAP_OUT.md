# UT_IO_MAP_OUT — Output IO map: functions to terminals

The output side of the IO map. Your logic writes **functions** ("pump 1 run",
"inlet valve open"), and the map puts each one on the output channel its settings
name: a board relay, an I2C relay module, a field-bus device or a remote value. It
tells your logic whether each output reached the field, turns every spare output
off, and lets a commissioning engineer force an output for a set time, only while
the system is Off.

The input side, the module table, the force slots and the IO types (`UT_IO_…`) are
on [UT_IO_MAP_IN](UT_IO_MAP_IN.md). Both maps use the same module table and force
slots.

**Call it last in the scan**, after all your logic, and before your IO code copies
the output image to the hardware.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ForcePermit` | BOOL | FALSE | Outputs may be forced only while TRUE. Wire the system Off state. Dropping it ends every output force. Unwired: outputs can never be forced |
| in | `ForceTime` | TIME | T#5s | How long a commissioning force lasts. At most 10 min. `T#0s`, negative or over 10 min: 5 s or 10 min is used (`Setting: force time`) |
| in | `ReleaseAll` | BOOL | FALSE | TRUE ends every output force now and refuses new ones. Wire the HMI link-lost signal, or a "release all forces" key |
| out | `AllOk` | BOOL | | Every output function with an address is on a good channel, and every fitted output module answers |
| out | `AnyForced` | BOOL | | An output force slot is forcing |
| out | `ConfigBad` | BOOL | | A wrong address, a function on a module not fitted, or two functions on one output |
| inout | `Dig` | ARRAY[*] OF UT_IO_DO | | The digital output functions. Your logic writes `q` and `block` |
| inout | `Ana` | ARRAY[*] OF UT_IO_AO | | The analog output functions. Your logic writes `v` |
| inout | `DigImg` | ARRAY[*] OF UT_IO_DCH | | The digital output terminals. Your IO code reads `q` (and may write `bad`) |
| inout | `AnaImg` | ARRAY[*] OF UT_IO_ACH | | The analog output terminals. Your IO code reads `v` (and may write `bad`) |
| inout | `Mods` | ARRAY[*] OF UT_IO_MOD | | The module table, shared with UT_IO_MAP_IN |
| inout | `Force` | ARRAY[*] OF UT_IO_FORCE | | The force slots, shared with UT_IO_MAP_IN. Never `RETAIN` |
| inout | `Data` | UT_IO_MAP_DATA | | Status: code, text and counts |

Number every array from 1 (`ARRAY[1..n]`). The image's `fn` uses 0 for "spare", so a
function in row 0 would not be seen, and a second function on its channel would not
be caught.

## Using it
```iecst
VAR
  IoOut   : UT_IO_MAP_OUT;
  DoFn    : ARRAY[1..8] OF UT_IO_DO;     (* 1 = pump 1 run, 2 = inlet valve open, ... *)
  AoFn    : ARRAY[1..2] OF UT_IO_AO;     (* 1 = pump 1 speed reference *)
  DoImg   : ARRAY[1..8] OF UT_IO_DCH;
  AoImg   : ARRAY[1..2] OF UT_IO_ACH;
  IoOutSt : UT_IO_MAP_DATA;
END_VAR

(* 3. your logic writes functions *)
DoFn[1].q := M1.Run;
DoFn[1].block := DiFn[2].q;            (* pump 1 overload: a force can never run it *)
AoFn[1].v := Vsd1.SpeedRefRaw;

(* 4. the IO map, last *)
IoMods[2].ok := TRUE;                  (* the board DO module always answers *)
IoOut(ForcePermit := SystemOff, ReleaseAll := NOT HmiLinkOk, Dig := DoFn, Ana := AoFn,
      DigImg := DoImg, AnaImg := AoImg, Mods := IoMods, Force := IoForce, Data := IoOutSt);

(* 5. your IO code: the image to the terminals *)
%QX0.0 := DoImg[1].q;
%QW0 := REAL_TO_INT(AoImg[1].v);
```

`IoMods` and `IoForce` are the same arrays as on [UT_IO_MAP_IN](UT_IO_MAP_IN.md#using-it).
The board relays are a module row such as `kind := UT_IOK_DO`, `src := UT_IOS_BOARD`,
`module := 1`, `first := 1`, `count := 8`.

## Digital output function `UT_IO_DO`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `src`, `module`, `ch` | | NONE, 0, 0 | Setting: where it is wired (see [Addresses](UT_IO_MAP_IN.md#addresses)). `UT_IOS_NONE` = not fitted on this site |
| `q` | BOOL | FALSE | Your logic: the output wanted |
| `block` | BOOL | FALSE | Your logic: TRUE holds the output off, forced or not. Wire the hard trips here |
| `out` | BOOL | | Status: what went to the channel, after a force and the `block` bit. FALSE when nothing was written |
| `ok` | BOOL | | Status: the channel is fitted, answering and good, so the output reached the field. A force does not change it |
| `why` | UT_IO_Q | | Status: the quality and why ([UT_IO_Q](UT_IO_MAP_IN.md#quality-ut_io_q)) |

## Analog output function `UT_IO_AO`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `src`, `module`, `ch` | | NONE, 0, 0 | Setting: where it is wired |
| `v` | REAL | 0.0 | Your logic: the raw value wanted (e.g. UT_ANALOG_OUT's `OutRaw`, UT_MOTOR_VSD's `SpeedRefRaw`) |
| `out` | REAL | | Status: what went to the channel, after a force. 0.0 when nothing was written |
| `ok` | BOOL | | Status: the channel is fitted, answering and good |
| `why` | UT_IO_Q | | Status: the quality and why |

Analog outputs have no `block` bit.

## Record `UT_IO_MAP_DATA`
As on [UT_IO_MAP_IN](UT_IO_MAP_IN.md#record-ut_io_map_data), for the outputs:
`statusCode`, `faultId`, `statusText`; `forcedCount` (output force slots forcing),
`forceLeft` (the longest time left), `badCount` (functions with an address whose
channel is not good: wrong address, used twice, module not fitted, missing or bad;
a force does not change it) and `missingCount` (fitted output modules not answering).

## Status
The most important problem, in the order below. The text is rebuilt only when the
code or the fault changes.

| `statusCode` | `faultId` | `statusText` | When |
| --- | --- | --- | --- |
| `UT_ST_CONFIG` | `UT_F_IO_ADDRESS` | `Config: IO address` | A function's module is not in the table, or its channel is not on the module or outside the image |
| `UT_ST_CONFIG` | `UT_F_IO_SHARED` | `Config: output used twice` | Two functions are on one output channel |
| `UT_ST_CONFIG` | `UT_F_IO_NOT_FITTED` | `Config: IO not fitted` | A function is on a module with `fitted` FALSE |
| `UT_ST_WARNING` | `UT_F_IO_FORCED` | `Warning: IO forced` | An output is forced (`forceLeft`: the time left) |
| `UT_ST_WARNING` | `UT_F_IO_MISSING` | `Warning: IO module missing` | A fitted output module is not answering |
| `UT_ST_WARNING` | `UT_F_IO_BAD` | `Warning: IO channel bad` | A function's channel has `bad` set |
| `UT_ST_WARN_SETTING` | `UT_F_FORCE_TIME` | `Setting: force time` | `ForceTime` is 0, negative or over 10 min |
| `UT_ST_OK` | | `OK` | Everything good |

## How it works
1. **The block owns the output image.** Each scan it first turns every output
   channel off (analog 0.0). Then each output force puts its value on its channel.
   Then each function, in row order, writes its `q` / `v` to its channel, unless the
   channel is forced. Last, a function's `block` bit turns its channel off, forced
   or not.
2. So a channel with no function is off, and a function moved to another channel
   leaves nothing behind. Anything else that writes into the output image is
   overwritten.
3. **One channel, one function.** A function on a channel that an earlier row
   already uses is not written: `why` SHARED, `out` off, `ConfigBad`, and
   `Config: output used twice`. The earlier row keeps the channel.
4. **ok** is TRUE when the channel's module is fitted and answering and the channel's
   `bad` is not set: the output reached the field (a remote valve over the radio, an
   I2C relay module). The channel is still written when the module is missing or not
   fitted; `out` shows the value.
5. **why** gives the channel's quality. While the channel is forced it shows FORCED,
   or BLOCKED when the `block` bit holds it off, in place of NOT_FITTED, MISSING or
   BAD; `ok` and the status still show the real quality.
6. **block**: wire the hard trips into it (the motor's overload for its run output,
   dry run for the pump), so a commissioning force can never run a tripped motor.
   Not forced, `block` simply holds the output off.

### Forcing an output (commissioning)
- Only while `ForcePermit` is TRUE (system Off). A `cmdForce` without it is refused
  (slot `state` NOT_PERMITTED). When `ForcePermit` drops, every output force ends
  (NOT_PERMITTED).
- Fill a slot with `kind` (DO or AO), the address and the value (`q` or `v`), then
  set `cmdForce`. A slot names a channel, so spare outputs can be tested too.
- The forced value takes the place of the function's value: a forced off beats your
  logic. Only `block` beats a force.
- Each force ends by itself after `ForceTime` (5 s by default, at most 10 min).
  `cmdForce` again starts the time again. `cmdRelease`, or `ReleaseAll`, ends it at
  once. A shorter `ForceTime` cuts a running force's time at once.
- A slot whose address does not exist is refused (NO_MODULE or NO_CHANNEL).
  Changing the address of a slot that is forcing moves the force to the new channel
  (if it exists and `ForcePermit` is on). Release it first.
- How a slot runs is on [UT_IO_FORCE_RUN](UT_IO_FORCE_RUN.md).

### Invalid settings
- A wrong address, two functions on one channel, or a module not fitted: `ConfigBad`
  and a `Config:` status. A wrong address or a second function writes nothing; a
  function on a module not fitted is still written. The rest of the map carries on.
- `ForceTime` 0 or negative: 5 s is used; over 10 min: 10 min. `Setting: force time`.

### Power cut
Nothing is kept: every force ends at a power cut, a PLC stop or a program download,
and the outputs follow your logic from the first scan. Keep the function settings
and the module table by writing them from your program or declaring those arrays
`RETAIN`. Never declare the force slots `RETAIN`.
