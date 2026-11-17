# FB_Route — Outlet selector

The outlet selector for up to four outlet valves: which outlet the pumps deliver to, valve first, the wet-weather divert to storage, a blocked irrigator.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bLevelRun` | `BOOL` | `FALSE` | level pumping chooses the route |
| in | `nRunOutlet` | `INT` |  | the outlet of a run / the zone watering, 1..4; > 0 also asks for it |
| in | `bWanted` | `BOOL` |  | water wanted: a pump is asked or in Hand |
| in | `bPumpRunning` | `BOOL` |  | never close under it; the close delay starts when it drops |
| in | `bToStorage` | `BOOL` |  | wet weather: FB_IrrDefer |
| in | `bStorageFull` | `BOOL` |  | The storage is full: no divert to it |
| in | `bIrrBlocked` | `BOOL` |  | the irrigator's fail-safe tripped |
| in | `ipValve1` | `I_Equipment` |  | The instance it drives (a motor, pump, valve or FB_Group) |
| in | `ipValve2` | `I_Equipment` |  | The instance it drives (a motor, pump, valve or FB_Group) |
| in | `ipValve3` | `I_Equipment` |  | The instance it drives (a motor, pump, valve or FB_Group) |
| in | `ipValve4` | `I_Equipment` |  | The instance it drives (a motor, pump, valve or FB_Group) |
| in | `refData` | `REFERENCE TO ST_RouteData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `nOutlet` | `INT` |  | in use, 0 none |
| out | `bRouteOk` | `BOOL` |  | proven: -> the pumps' start hold |
| out | `bRouteLost` | `BOOL` |  | -> the pumps' interlock |
| out | `bIsIrrigation` | `BOOL` |  | The outlet in use is an irrigation outlet |
| out | `bIsStorage` | `BOOL` |  | The outlet in use is the storage |
| out | `nPreset` | `INT` | `-1` | the outlet's speed preset; -1 = the speed control's own |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_RouteData` (pin `refData`)

**Settings `set`** (`ST_RouteSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `aOutlet` | `ARRAY[1..4] OF ST_Outlet` |  | fields below |
| `nLevelOutlet` | `USINT` |  | 0 = no valve |
| `nRunOutlet` | `USINT` |  | the outlet of a run / the zone watering, 1..4; > 0 also asks for it |
| `nStorageOutlet` | `USINT` |  | 0 = no storage |
| `tCloseDelay` | `TIME` | `T#5s` | 0 .. 10 min |

**`aOutlet`** (`ST_Outlet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eKind` | `E_OutletKind` |  | The kind |
| `nPreset` | `SINT` | `-1` | -1 none, 0 normal, 1 low, 2 high (the speed control's presets) |

**Status `sts`** (`ST_RouteSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nOutlet` | `USINT` |  | in use, 0 none |
| `nOpenMask` | `BYTE` |  | bit n-1: requested open |
| `nProvenMask` | `BYTE` |  | bit n-1: open |
| `nFaultOutlet` | `USINT` |  |  |
| `eKind` | `E_OutletKind` |  | The kind |
| `bRouteOk` | `BOOL` |  | proven: -> the pumps' start hold |
| `bRouteLost` | `BOOL` |  | -> the pumps' interlock |
| `bOpening` | `BOOL` |  |  |
| `bClosing` | `BOOL` |  |  |
| `bDiverted` | `BOOL` |  |  |
| `bNoStorage` | `BOOL` |  |  |
| `bBlocked` | `BOOL` |  |  |
| `tTimeLeft` | `TIME` |  | Time left in the delay or phase running now |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |

## Lists

- `E_OutletKind`: `None`, `Irrigation`, `Storage`, `Other` (default `None`)

## How it works

The outlet selector (up to 4 outlet valves): which outlet the pumps deliver to, valve first, the wet-weather divert to storage, an irrigator blocked.

The outlet in use: `nRunOutlet` 1..4 (never diverted; outside 0..4 refused, a warning) -> else `bLevelRun` -> `set.nLevelOutlet` (an Irrigation outlet: with `bToStorage` or `bIrrBlocked` -> `set.nStorageOutlet` while it is set, fitted and not full ("diverted"); with `bToStorage` and no storage it stays, warning NoStorage; with `bIrrBlocked` and no storage nothing opens: RouteBlocked) -> else `set.nRunOutlet` (Hand, manual runs, zones that own their valves).

While `bWanted` OR `bPumpRunning` OR `nRunOutlet` > 0 the outlet in use gets Request(open) and every other outlet with a kind Request(closed), every scan (one owner); kind None is never requested. Valve first: `bRouteOk` once the outlet in use is open (its `bIsRunning`). An outlet change: the old outlet is released `set.tCloseDelay` after the new one is proven; the last proven outlet is never released under a running pump; the request gone: released `tCloseDelay` after the pumps stop. `bRouteLost`: a pump runs and no held outlet is open, or the outlet in use is blocked. Valves move only in their own Auto (else warning NotAuto); proof in any mode. Every kind None = routing not used, `bRouteOk` TRUE. Settings are kept (a retained last-good copy, a bad write put back).

## Example

Two outlets: irrigation (1) and storage (2).

| Pin | Wire |
| --- | --- |
| `bLevelRun` | `fbLevelCtl.bCall` |
| `bWanted` | `fbLevelCtl.bCall` |
| `bPumpRunning` | `DI_P1_Running` |
| `bToStorage` | `fbDefer.bToStorage` |
| `ipValve1` | `fbValveIrr` |
| `ipValve2` | `fbValveStore` |
| `refData` | `stRoute` |
| `bRouteOk` | the pump's permissive |
| `bRouteLost` | NOT on the pump's interlock |

In `stRoute.set`: outlet 1 kind `Irrigation`, outlet 2 kind `Storage`, `nLevelOutlet := 1`, `nStorageOutlet := 2`.

**Back to** [the index](../README.md).
