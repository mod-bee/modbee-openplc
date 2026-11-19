# FB_Route — Outlet selector

The outlet selector for up to four outlet valves: which outlet the pumps deliver to, valve first, the wet-weather divert to storage, a blocked irrigator.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bLevelPumping` | `BOOL` | `FALSE` | level pumping chooses the route |
| in | `nRunOutlet` | `INT` |  | the outlet of a run or the zone watering, 1..4; above 0 also asks for it |
| in | `bWaterRequested` | `BOOL` |  | water wanted: a pump is asked or in Hand |
| in | `bPumpRunning` | `BOOL` |  | a pump runs: never close under it; the close delay starts when it drops |
| in | `bSendToStorage` | `BOOL` |  | wet weather (FB_IrrDefer.bSendToStorage) |
| in | `bStorageFull` | `BOOL` |  | the storage is full: no divert to it |
| in | `bIrrigatorTripped` | `BOOL` |  | the irrigator's fail-safe tripped |
| in | `ipValve1` | `I_Equipment` |  | outlet 1's valve |
| in | `ipValve2` | `I_Equipment` |  | outlet 2's valve |
| in | `ipValve3` | `I_Equipment` |  | outlet 3's valve |
| in | `ipValve4` | `I_Equipment` |  | outlet 4's valve |
| in | `refData` | `REFERENCE TO ST_RouteData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `nOutletInUse` | `INT` |  | the outlet in use (0 = none) |
| out | `bRouteProven` | `BOOL` |  | the route is proven open: to the pumps' start hold |
| out | `bRouteLost` | `BOOL` |  | to the pumps' interlock |
| out | `bIrrigationOutletInUse` | `BOOL` |  | the outlet in use is an irrigation outlet |
| out | `bStorageOutletInUse` | `BOOL` |  | the outlet in use is the storage |
| out | `nSpeedPreset` | `INT` | `-1` | the outlet's speed preset; -1 = the speed control's own |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_RouteData` (pin `refData`)

**Settings `set`** (`ST_RouteSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `aOutlets` | `ARRAY[1..4] OF ST_Outlet` |  | outlets 1..4: kind and speed preset; fields below |
| `nLevelPumpingOutlet` | `USINT` |  | 0 = no valve |
| `nRunOutlet` | `USINT` |  | the outlet of a run or the zone watering, 1..4; above 0 also asks for it |
| `nStorageOutlet` | `USINT` |  | 0 = no storage |
| `tValveCloseDelay` | `TIME` | `T#5s` | 0 .. 10 min |

**`aOutlets`** (`ST_Outlet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eOutletKind` | `E_OutletKind` |  | None, Irrigation, Storage or Other |
| `nSpeedPreset` | `SINT` | `-1` | -1 none, 0 normal, 1 low, 2 high (the speed control's presets) |

**Status `sts`** (`ST_RouteSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nOutletInUse` | `USINT` |  | the outlet in use (0 = none) |
| `nOpenRequestedBits` | `BYTE` |  | bit n-1: requested open |
| `nProvenOpenBits` | `BYTE` |  | bit n-1: open |
| `nFaultedOutlet` | `USINT` |  | the outlet whose valve has a fault (0 = none) |
| `eOutletKindInUse` | `E_OutletKind` |  | the kind of the outlet in use |
| `bRouteProven` | `BOOL` |  | the route is proven open: to the pumps' start hold |
| `bRouteLost` | `BOOL` |  | a pump runs and no outlet is open, or the outlet in use is blocked: to the pumps' interlock |
| `bOpening` | `BOOL` |  | a valve is opening |
| `bClosing` | `BOOL` |  | a valve is closing |
| `bDivertedToStorage` | `BOOL` |  | level pumping is sent to the storage (wet weather or the irrigator blocked) |
| `bNoStorageAvailable` | `BOOL` |  | wet weather asks for storage but none is fitted or it is full (warning NoStorage) |
| `bRouteBlocked` | `BOOL` |  | the irrigator is blocked and there is no storage: nothing opens (RouteBlocked) |
| `tTimeLeft` | `TIME` |  | time left in the close delay or travel now counting |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

## Lists

- `E_OutletKind`: `None`, `Irrigation`, `Storage`, `Other` (default `None`)

## How it works

The outlet selector (up to 4 outlet valves): which outlet the pumps deliver to, valve first, the wet-weather divert to storage, an irrigator blocked.

The outlet in use: `nRunOutlet` 1..4 (never diverted; outside 0..4 refused, a warning) -> else `bLevelPumping` -> `set.nLevelPumpingOutlet` (an Irrigation outlet: with `bSendToStorage` or `bIrrigatorTripped` -> `set.nStorageOutlet` while it is set, fitted and not full ("diverted"); with `bSendToStorage` and no storage it stays, warning NoStorage; with `bIrrigatorTripped` and no storage nothing opens: RouteBlocked) -> else `set.nRunOutlet` (Hand, manual runs, zones that own their valves).

While `bWaterRequested` OR `bPumpRunning` OR `nRunOutlet` > 0 the outlet in use gets Request(open) and every other outlet with a kind Request(closed), every scan (one owner); kind None is never requested. Valve first: `bRouteProven` once the outlet in use is open (its `bIsRunning`). An outlet change: the old outlet is released `set.tValveCloseDelay` after the new one is proven; the last proven outlet is never released under a running pump; the request gone: released `tValveCloseDelay` after the pumps stop. `bRouteLost`: a pump runs and no held outlet is open, or the outlet in use is blocked. Valves move only in their own Auto (else warning NotAuto); proof in any mode. Every kind None = routing not used, `bRouteProven` TRUE. Settings are kept (a retained last-good copy, a bad write put back).

## Example

Two outlets: irrigation (1) and storage (2).

| Pin | Wire |
| --- | --- |
| `bLevelPumping` | `fbLevelCtl.bLevelCalls` |
| `bWaterRequested` | `fbLevelCtl.bLevelCalls` |
| `bPumpRunning` | `DI_P1_Running` |
| `bSendToStorage` | `fbDefer.bSendToStorage` |
| `ipValve1` | `fbValveIrr` |
| `ipValve2` | `fbValveStore` |
| `refData` | `stRoute` |
| `bRouteProven` | the pump's permissive |
| `bRouteLost` | NOT on the pump's interlock |

In `stRoute.set`: outlet 1 kind `Irrigation`, outlet 2 kind `Storage`, `nLevelPumpingOutlet := 1`, `nStorageOutlet := 2`.

**Back to** [the index](../README.md).
