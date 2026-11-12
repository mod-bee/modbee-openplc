# 13 Provisioning: a PLC that gets its own login

On a [modbee broker](https://github.com/mod-bee/modbee-mqtt/blob/main/docs/logins.md),
every device has a login of its own. The client's `Provision` method lets a
PLC get its login by itself, so nobody types a password into it, keeps a list of them, or
drives to site when one is lost.

## What you do once, on the broker

Make a **provisioning key** for the site. It also says what each PLC may
publish and subscribe to - here, only topics under its own name:

```bash
docker compose exec modbee modbee key create site-north \
  --publish 'plant/${username}/#' --subscribe 'plant/${username}/cmd'
```

```
key site-north
  site-north.eDjPQkJQq6X9L0q9paHAxReD9KZc72PH
```

The same key goes into every PLC of the site.

## What goes in the program

Give the client a **name that is unique on the site** - `sClientId`, which
becomes the PLC's user name - and call `Provision` with the key, every scan,
before the client's own call:

```st
VAR
  mqtt : FB_MqttClient;
  sKey : STRING(127) := 'site-north.eDjPQkJQq6X9L0q9paHAxReD9KZc72PH';
  bProvisioned : BOOL;
  sSiteGroup : STRING(64);
END_VAR

mqtt.Provision(sKey := sKey, bProvisioned => bProvisioned, sGroup => sSiteGroup);
mqtt(eTransport := E_MqttTransport.RuntimeTcp, eSecurity := E_MqttSecurity.TlsVerify,
     sHost := 'mqtt.example.com', sClientId := 'pump-station-3');
```

That is all. **Leave `stSessionConfig`'s `sUserName` and `sUserPassword`
empty** - the login comes from `Provision`, and wins over them.

## What happens

1. On its first start the PLC has no login. It connects with the key, which
   lets it do exactly one thing: ask for a login.
2. The broker makes one for this PLC - its name, and a secret only it holds -
   and sends it back.
3. The client keeps it in its own **retained** memory, so it survives a
   power cut (turn on the project's persistent storage), and reconnects with
   it.
4. `bProvisioned` goes TRUE, and from then on the PLC connects as itself.

**`bConnected` on the client stays FALSE while the PLC is only connected with
the key.** Anything gated on `mqtt.bConnected` - which is how publishing should
be gated - waits for the real connection, because nothing it published with
the key would be allowed anyway.

The other methods need nothing different. Subscriptions are made again on the
PLC's own connection by themselves.

## What the key tells the PLC: sGroup and sPrefix

A key can carry values for the devices it registers (`modbee key create ...
--data group=north-plant --data prefix=acme/north`, or set by your platform).
`Provision` puts two of them on its outputs, kept in retained memory with the
login - valid from the first scan - and asks again at every connect:

| Output | Is | Wire it to |
| --- | --- | --- |
| `sGroup` | the site's Sparkplug group | `FB_SparkplugNode`'s `sGroupId` - with a `SEL` to a group of your own when it is empty (a broker whose keys carry none) |
| `sPrefix` | the start of this PLC's own topics | e.g. firmware updates: `<sPrefix>/<sClientId>/$ota` as `FB_OtaNode`'s `sBaseTopic` (modbee-ota) |

So whoever sets the PLC up types the key and its name - not the group, not a
topic path - and renaming the PLC moves everything built from its name.

## When things change

| | What happens |
| --- | --- |
| The PLC restarts | It connects with the retained login, without asking again |
| A PLC is replaced | Download the same program - same `sClientId`, same key - to the new one. Once the old PLC is offline it registers with the same key (nothing to change on the broker), and the old PLC's login stops working. While the old PLC is still connected, the new one is refused and asks again every five minutes - a copy of the key never knocks a working PLC off |
| A PLC is stolen or lost | An admin disables its login (`modbee user disable pump-station-3`): it is signed out at once and stays out. Nothing else changes - not the key, not another PLC |
| The key's devices at once are online (`--devices`) | A key may limit how many of the PLCs it let in are online at the same time - any of them. One more is refused (`bRefused`, the broker's reason in `sReason`) and asks again every five minutes, until one goes or the key is raised (`modbee key set ... --devices`) |
| The key is turned off (`modbee key set ... --devices 0`) | Every PLC it let in is signed out and refused until the key is raised again - the same key, nothing to download |
| An admin resets its login (`modbee user reset pump-station-3`) | The stored login is refused, so the PLC registers again with its key by itself. No site visit |
| Registering again is pending or refused | The old login is **kept** until the broker issues a new one, so the PLC is never left with no login at all, and it tries the old one again every five minutes - a login put back on the broker works again by itself |
| An admin disables it (`modbee user disable ...`) | It stays out. Registering again does not undo it - an admin enables it |
| The key needs approval (`--approval manual`) | `bPending` is TRUE until an admin runs `modbee user approve pump-station-3`. The PLC asks again every thirty seconds |
| The key is wrong, or removed | `bRefused` is TRUE and the method returns `NotAuthorized`, with the broker's reason in `sReason`. It asks again every five minutes |
| The site's group is changed on the broker | The broker refuses a connect whose Will (the Sparkplug NDEATH) is on the old group. The PLC connects once without its Will, asks again, and reconnects on the new `sGroup` - by itself |
| Its rights no longer cover its Will, and the group is the same (`modbee user permissions ...`) | `bRefused` is TRUE and the method returns `NotAuthorized`, `sReason` says the broker refuses its Will. It tries again every five minutes, so rights put back work again by itself |
| Its values are changed on the broker (`modbee user set ... --data`) | It has them at its next connect |

`bForget` (a rising edge) throws the stored login away and registers again.
It is rarely needed: a login that stops working is replaced by itself.

## The method

`mqtt.Provision(sKey, bForget, bProvisioned =>, bPending =>, bRefused =>,
sUserName =>, sGroup =>, sPrefix =>, sReason =>)`

| | |
| --- | --- |
| `sKey` | the provisioning key |
| `bForget` | rising edge: forget the stored login and register again. Not at program start, so one wired TRUE does not throw the login away on every reboot |
| `bProvisioned` | this PLC has its own login, and is connected with it |
| `bPending` | waiting for an admin to approve it |
| `bRefused` | the broker said no; `sReason` says why |
| `sUserName` | the login in use |
| `sGroup`, `sPrefix` | what the key hands its devices |
| `sReason` | what the broker said, in words |
| returns | `Ok`; `InvalidArgument` with no `sClientId`, or no `sKey` and no stored login; `NotAuthorized` when refused; `WrongTask` outside the client's task |

The client's `sClientId` is the PLC's name, and must be set.

## Good to know

- **Put the key in a variable**, not a literal in the rung, for the same
  reason as a password: a literal ends up in every backup of the project.
  Anyone holding the key can register a device on that site, so treat it like
  a site password - but it cannot read or publish anything by itself.
- **Use TLS** on anything that leaves the building, as for any login: the
  key and the PLC's secret are bytes in its first packet.
- **The name must be unique** on the broker. Two PLCs with the same
  `sClientId` would keep taking the name from each other.
- **It needs a modbee broker.** The provisioning exchange is modbee's; on
  another broker, use `stSessionConfig`'s `sUserName` and `sUserPassword`.

**Next:** [14 Sparkplug](14-sparkplug.md)
