# PintBroker 🍺

[![CircleCI](https://circleci.com/gh/jjcarstens/pint_broker.svg?style=svg)](https://circleci.com/gh/jjcarstens/pint_broker)
[![Hex version](https://img.shields.io/hexpm/v/pint_broker.svg "Hex version")](https://hex.pm/packages/pint_broker)

A simple, pint-sized MQTT broker that can be used for testing and development

> **Warning**
>
> This is not indended for production use and makes no attempts for large
> connection scaling and handling. It is also not considered feature complete,
> but handles most simple use cases.

**Supported:**

* Simple, unencrypted TCP connections
* [MQTT v3.1.1](http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.pdf)
  * QoS 0
  * Connect, publish, subscribe, and unsubscribe
  * Ping requests
* [Rule forwarding](#rule-forwarding)
* [Lifecycle events](#lifecycle-events)

**Unsupported:**

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

## Lifecycle events

Many broker setups have mechanism to subscribe to connect/disconnect events,
such as the [AWS IoT Lifecycle events](https://docs.aws.amazon.com/iot/latest/developerguide/life-cycle-events.html)
which are typically configured in the infrastructure to be forwarded to
a central handler or SQS queue.

PintBroker also supports this behavior by starting with `:on_connect` and
`:on_disconnect` options to register a callback function that receives
the `:client_id` of the connection.

An example for replicating the AWS IoT Lifecyle events:

```elixir
on_connect = fn client_id ->
  payload = %{clientId: client_id, eventType: :connected}
  Broadway.test_message(:my_broadway, Jason.encode!(payload))
end

on_disconnect = fn client_id ->
  payload = %{clientId: client_id, eventType: :disconnected, disconnectReason: "CONNECTION_LOST"}
  Broadway.test_message(:my_broadway, Jason.encode!(payload))
end

PintBroker.start_link(on_connect: on_connect, on_disconnect: on_disconnect)
```

The callback returns are ignored.

## Why _another_ broker?

There are many full-featured MQTT brokers out there, but they require a lot of
setup and configuration, maybe some dependencies, and tend to be overkill for
testing of MQTT interactions between client and servers. I wanted the simplest
possible broker which did not require a full ops team to implement a test
environment that clients could connect to and publish/subscribe to topics for
improved MQTT unit testing and local development of the whole system.
