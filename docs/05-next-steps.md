# 5. Next steps

## The libraries' own documentation

Each library has its own guide, with a getting-started page, a reference for
every block and pin, worked examples and troubleshooting.

| Library | Start with |
| --- | --- |
| ModBee Node UIO | [node-uio docs](../modbee-hardware/modbee-hardware-arduino/modbee-node-uio/node-uio/docs/README.md): analog inputs and outputs, calibration, retained variables, pulse counting, sleep |
| ModBee Node UIO Web UI | [node-webUI docs](../modbee-hardware/modbee-hardware-arduino/modbee-node-uio/node-webUI/docs/README.md) |
| BeeBus | [modbee-beebus docs](../modbee-communication/modbee-beebus/docs/README.md) |
| Modbus | [modbee-modbus docs](../modbee-communication/modbee-modbus/docs/README.md) |
| MQTT and Sparkplug B | [modbee-mqtt docs](../modbee-communication/modbee-mqtt/docs/README.md) |
| GSM | [modbee-gsm docs](../modbee-communication/modbee-gsm/docs/README.md) |
| OTA | [modbee-ota docs](../modbee-communication/modbee-ota/docs/README.md) |
| ModBee Utilities | [modbee-utilities docs](../modbee-libraries/modbee-utilities/docs/README.md) |
| ModBee Devices | [modbee-devices docs](../modbee-libraries/modbee-devices/docs/README.md) |

Every block also explains itself in the editor: select it in the **Library**
panel and its description appears in the box below the library tree.

## The Node UIO hardware

Wiring, terminals, power, the analog inputs' voltage or current setting
(a solder bridge on the board), and HATs are in the
[modbee-node-uio repository](https://github.com/mod-bee/modbee-node-uio).

## The OpenPLC Editor

The ModBee editor works like the OpenPLC Editor, so OpenPLC's own
documentation applies: the languages, the editor's screens and debugging.
See the [OpenPLC Editor documentation](https://edge.autonomylogic.com/docs/openplc-editor/overview).
Remember that ModBee boards and libraries need the
[ModBee editor](01-overview.md#why-the-modbee-openplc-editor).

## Things to try next

- **Read an analog sensor:** add an `ANALOG_IN` block after `DIGITAL_IN`, and
  see [node-uio analog](../modbee-hardware/modbee-hardware-arduino/modbee-node-uio/node-uio/docs/03-analog.md).
- **Keep a value through a power cut:** declare it `RETAIN`. See
  [retained variables](../modbee-hardware/modbee-hardware-arduino/modbee-node-uio/node-uio/docs/05-retained-variables.md).
- **Run a pump properly:** the `modbee-utilities` pump blocks add run
  feedback, faults, alarms, run hours and HMI messages.
- **Talk to other devices:** a Modbus sensor on RS485 with `modbee-modbus`,
  or report to SCADA with `modbee-mqtt`.
