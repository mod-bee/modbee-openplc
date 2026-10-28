# 13 Provisioning: a PLC that gets its own login

On a [modbee broker](https://github.com/mod-bee/modbee-mqtt/blob/main/docs/logins.md),
every device has a login of its own. `MQTT_PROVISION` lets a PLC get its
login by itself, so nobody types a password into it, keeps a list of them, or
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

Give the client a **name that is unique on the site** - it becomes the PLC's
user name - and put `MQTT_PROVISION` beside it with the key:

```
VAR
  net  : MQTT_CLIENT;
  prov : MQTT_PROVISION;
  sKey : STRING(127) := 'site-north.eDjPQkJQq6X9L0q9paHAxReD9KZc72PH';
END_VAR

prov ( CLIENT := net, KEY := sKey );
net  ( TRANSPORT := MQTT_RUNTIME_TCP, SECURITY := MQTT_TLS_VERIFY,
       HOST := 'mqtt.example.com', CLIENT_ID := 'pump-station-3' );
```

That is all. **Leave `USERNAME` and `PASSWORD` on `MQTT_CONFIG` empty** - the
login comes from `MQTT_PROVISION`. Like the other helpers it can sit above or
below the client.

## What happens

1. On its first start the PLC has no login. It connects with the key, which
   lets it do exactly one thing: ask for a login.
2. The broker makes one for this PLC - its name, and a secret only it holds -
   and sends it back.
3. `MQTT_PROVISION` keeps it in its own **retained** memory, so it survives a
   power cut, and the client reconnects with it.
4. `PROVISIONED` goes TRUE, and from then on the PLC connects as itself.

**`CONNECTED` on the client stays FALSE while the PLC is only connected with
the key.** Anything gated on `net.CONNECTED` - which is how publishing should
be gated - waits for the real connection, because nothing it published with
the key would be allowed anyway.

The other blocks need nothing different. Subscriptions are made again on the
PLC's own connection by themselves.

## What the key tells the PLC: GROUP and PREFIX

A key can carry values for the devices it registers (`modbee key create ...
--data group=north-plant --data prefix=acme/north`, or set by your platform).
`MQTT_PROVISION` puts two of them on its outputs, kept in its retained memory
with the login, and asks again at every connect:

| Output | Is | Wire it to |
| --- | --- | --- |
| `GROUP` | the site's Sparkplug group | `SPARKPLUG_NODE`'s `GROUP` - with a `SEL` to a group of your own when it is empty (a broker whose keys carry none) |
| `PREFIX` | the start of this PLC's own topics | e.g. firmware updates: `PREFIX/<CLIENT_ID>/$ota` as `OTA_NODE`'s `BASE` |

So whoever sets the PLC up types the key and its name - not the group, not a
topic path - and renaming the PLC moves everything built from its name.

## When things change

| | What happens |
| --- | --- |
| The PLC restarts | It connects with the retained login, without asking again |
| A PLC is replaced | Download the same program - same `CLIENT_ID`, same key - to the new one. It registers, takes the name over, and the old PLC's login stops working |
| An admin resets its login (`modbee user reset pump-station-3`) | The stored login is refused, so the PLC registers again with its key by itself. No site visit |
| Registering again is pending or refused | The old login is **kept** until the broker issues a new one, so the PLC is never left with no login at all, and it tries the old one again every five minutes - a login put back on the broker works again by itself |
| An admin disables it (`modbee user disable ...`) | It stays out. Registering again does not undo it - an admin enables it |
| The key needs approval (`--approval manual`) | `PENDING` is TRUE until an admin runs `modbee user approve pump-station-3`. The PLC asks again every thirty seconds |
| The key is wrong, or removed | `REFUSED` and `ERROR` are TRUE, with the broker's reason in `REASON`. It asks again every five minutes |
| The site's group is changed on the broker | The broker refuses a connect whose Will (the Sparkplug NDEATH) is on the old group. The PLC connects once without its Will, asks again, and reconnects on the new `GROUP` - by itself |
| Its rights no longer cover its Will, and the group is the same (`modbee user permissions ...`) | `REFUSED` and `ERROR` are TRUE, `REASON` says the broker refuses its Will. It tries again every five minutes, so rights put back work again by itself |
| Its values are changed on the broker (`modbee user set ... --data`) | It has them at its next connect |

`FORGET` (a rising edge) throws the stored login away and registers again.
It is rarely needed: a login that stops working is replaced by itself.

## The pins

| Pin | |
| --- | --- |
| `CLIENT` | the client. Its `CLIENT_ID` is the PLC's name, and must be set |
| `KEY` | the provisioning key |
| `FORGET` | rising edge: forget the stored login and register again |
| `PROVISIONED` | this PLC has its own login, and is connected with it |
| `PENDING` | waiting for an admin to approve it |
| `REFUSED` | the broker said no; `REASON` says why |
| `USERNAME` | the login in use |
| `REASON` | what the broker said, in words |
| `ERROR`, `STATUS` | as on every block |

## Good to know

- **Put the key in a variable**, not a literal in the rung, for the same
  reason as a password: a literal ends up in every backup of the project.
  Anyone holding the key can register a device on that site, so treat it like
  a site password - but it cannot read or publish anything by itself.
- **Use TLS** on anything that leaves the building, as for any login: the
  key and the PLC's secret are bytes in its first packet.
- **The name must be unique** on the broker. Two PLCs with the same
  `CLIENT_ID` would keep taking the name from each other.
- **It needs a modbee broker.** The provisioning exchange is modbee's; on
  another broker, use `MQTT_CONFIG`'s `USERNAME` and `PASSWORD` as before.
