# PintBroker 🍺

A simple, pint-sized MQTT broker that can be used for testing and development

## Usage

> **Warning**
>
> This is not indended for production use and makes no attempts for large
> connection scaling and handling. It is also not considered feature complete,
> but handles most simple use cases.

Supported:

* Simple, unencrypted TCP connections
* [MQTT v3.1.1](http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.pdf)
  * QoS 0
  * Connect, publish, subscribe, and unsubscribe
  * Ping requests
  * Rule forwarding (see below)

Unsupported:

* SSL connections
* QoS 1 and 2
* [MQTT v5](https://docs.oasis-open.org/mqtt/mqtt/v5.0/mqtt-v5.0.pdf)

## Rule forwarding

Many production setups will have a few topics with rules that forward
messages to a handler such as an SQS queue or central service. This allows
for scaling of many devices to communicate with a few nodes. For testing,
you can specify rules when starting the broker which will forward
`Tortoise311.Package.Publish` structs to a handler function or process in
order to mimic this rule forwarding behavior. See `PintBroker.add_rule/3` for
more information.

**Example:**

```elixir
iex> s = self()

iex> handler1 = fn pub -> send(s, pub) end

iex> PintBroker.start_link(rules: [{"my/+/test/topic", handler1}])
{:ok, #PID<0.226.0>}

# You can publish from the broker or another client
iex> PintBroker.publish("my/first/test/topic", "hello world")

iex> flush()
%Tortoise311.Package.Publish{
  __META__: %Tortoise311.Package.Meta{opcode: 3, flags: 0},
  identifier: nil,
  topic: "my/first/test/topic",
  payload: "hello world",
  qos: 0,
  dup: false,
  retain: false
}
```
