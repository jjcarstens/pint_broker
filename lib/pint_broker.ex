defmodule PintBroker do
  @moduledoc """
  A simple, pint-sized MQTT broker that can be used for testing and development

  > #### Warning {: .warning}
  >
  > This is not indended for production use and makes no attempts for
  > large connection scaling and handling. It is also not considered
  > feature complete, but handles most simple use cases.

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

  You can specify custom `:gen_tcp` options with `:overrides` key when starting
  the server.

  ## Rule forwarding

  Many production setups will have a few topics with rules that forward
  messages to a handler such as an SQS queue or central service. This allows
  for scaling of many devices to communicate with a few nodes. For testing,
  you can specify rules when starting the broker which will forward
  `Tortoise311.Package.Publish` structs to a handler function or process in
  order to mimic this rule forwarding behavior. See `add_rule/3` for more
  information.

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
  """
  use GenServer

  alias Tortoise311.Package
  alias Tortoise311.Package.Connack
  alias Tortoise311.Package.Connect
  alias Tortoise311.Package.Pingreq
  alias Tortoise311.Package.Pingresp
  alias Tortoise311.Package.Puback
  alias Tortoise311.Package.Publish
  alias Tortoise311.Package.Suback
  alias Tortoise311.Package.Subscribe
  alias Tortoise311.Package.Unsuback
  alias Tortoise311.Package.Unsubscribe

  require Logger

  @type rule() ::
          {Tortoise311.topic_filter(),
           pid()
           | (Package.Publish.t() -> any())
           | (Tortoise311.topic(), Tortoise311.payload() -> any())}

  @type opt() ::
          {:port, :inet.port_number()}
          | {:name, GenServer.name()}
          | {:overrides, :gen_tcp.option()}
          | {:rules, [rule()]}
          | {:on_connect, (client_id :: String.t() -> :ok)}
          | {:on_disconnect, (client_id :: String.t() -> :ok)}

  @default_transport_opts [mode: :binary, packet: :raw, active: true, reuseaddr: true]

  @doc false
  @spec start_link([opt()]) :: GenServer.on_start()
  def start_link(opts) do
    name = opts[:name] || __MODULE__
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Add a topic filter rule with handler

  In many broker implementations, there are a few routing rules that forward
  messages from specific topics to a handler such as an SQS queue or central
  service in a fan-in pattern for scaling many remote devices to a few nodes.

  Many times the topic runs through a full SQL query before forwarding the
  message on. However, that is unsupported in this simple server. Instead
  you can provide a simple topic filter and a handler function or process
  which will receive the Tortoise311.Package.Publish struct that can be split
  apart by your logic to formulate into the end result needed (such as mimicing
  an SQS queue message in your producer)
  """
  @spec add_rule(GenServer.server(), Tortoise311.topic_filter(), pid() | function()) :: :ok
  def add_rule(server \\ __MODULE__, topic, handler)
      when is_pid(handler) or is_function(handler, 1) or is_function(handler, 2) do
    GenServer.call(server, {:add_rule, topic, handler})
  end

  @doc """
  Publish a message to a topic.
  """
  @spec publish(GenServer.server(), Tortoise311.topic(), Tortoise311.payload()) :: :ok
  def publish(server \\ __MODULE__, topic, payload) do
    GenServer.call(server, {:publish, topic, payload})
  end

  @impl GenServer
  def init(opts) do
    opts =
      scrub_opts(opts, [])
      |> Keyword.put_new(:port, 1883)

    transport_opts = Keyword.merge(@default_transport_opts, opts[:overrides] || [])
    {:ok, listen} = :gen_tcp.listen(opts[:port], transport_opts)

    broker = self()
    acceptor = spawn(fn -> accept(listen, broker) end)

    state = %{
      acceptor: acceptor,
      on_connect: opts[:on_connect] || fn _ -> :ok end,
      on_disconnect: opts[:on_disconnect] || fn _ -> :ok end,
      sockets: %{},
      rules: opts[:rules] || [],
      transport_opts: transport_opts
    }

    {:ok, state}
  end

  defp scrub_opts([], acc), do: acc

  defp scrub_opts([{:port, p} = opt | rem], acc) when is_integer(p) do
    scrub_opts(rem, [opt | acc])
  end

  defp scrub_opts([{:overrides, o} = opt | rem], acc) when is_list(o) do
    scrub_opts(rem, [opt | acc])
  end

  defp scrub_opts([{:on_connect, fun} = opt | rem], acc) when is_function(fun, 1) do
    scrub_opts(rem, [opt | acc])
  end

  defp scrub_opts([{:on_disconnect, fun} = opt | rem], acc) when is_function(fun, 1) do
    scrub_opts(rem, [opt | acc])
  end

  defp scrub_opts([{:rules, r} | rem], acc) when is_list(r) do
    rules =
      Enum.filter(r, fn
        {topic, handler}
        when is_binary(topic) and
               (is_pid(handler) or is_function(handler, 1) or is_function(handler, 2)) ->
          {topic, handler}

        invalid ->
          Logger.warning("[PintBroker] Ignoring invalid rule: #{inspect(invalid)}")
          false
      end)

    scrub_opts(rem, [{:rules, rules} | acc])
  end

  defp scrub_opts([invalid | rem], acc) do
    Logger.warning("[PintBroker] Ignoring invalid option: #{inspect(invalid)}")
    scrub_opts(rem, acc)
  end

  @impl GenServer
  def handle_call({:add_rule, filter, handler}, _from, state) do
    {:reply, :ok, update_in(state.rules, &[{filter, handler} | &1])}
  end

  def handle_call({:publish, topic, payload}, _from, state) do
    packet = %Publish{topic: topic, payload: payload, qos: 0}
    handle_publish(packet, state)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info({:tcp, socket, data}, state) do
    packet =
      try do
        Package.decode(data)
      catch
        _, _ ->
          data
      end

    {:noreply, handle_packet(packet, socket, state)}
  end

  def handle_info({:tcp_closed, socket}, state) do
    {:noreply, handle_close(socket, state)}
  end

  def handle_info(msg, state) do
    Logger.debug("[PintBroker] Got unknown message #{inspect(msg)}")
    {:noreply, state}
  end

  defp handle_packet(%Connect{client_id: id} = conn, socket, state) do
    matching = for {s, %{conn: %{client_id: ^id}}} <- state.sockets, do: s

    if length(matching) > 0 do
      Logger.warning("[PintBroker] closing duplicate client: #{conn.client_id}")
      :gen_tcp.close(socket)

      Enum.reduce(matching, state, fn sock, acc ->
        :gen_tcp.close(sock)
        handle_close(sock, acc)
      end)
    else
      send_packet(socket, %Connack{session_present: false, status: :accepted})
      attrs = %{conn: conn, subscriptions: []}
      state.on_connect.(conn.client_id)

      put_in(state, [:sockets, socket], attrs)
    end
  end

  defp handle_packet(%_{} = packet, socket, state) when not is_map_key(state.sockets, socket) do
    Logger.debug(
      "[PintBroker] Missing MQTT Connect. Ignoring - #{inspect(packet, limit: :infinity)}"
    )

    state
  end

  defp handle_packet(%Subscribe{} = sub, socket, state) do
    acks = for {_topic, qos} <- sub.topics, do: {:ok, qos}

    send_packet(socket, %Suback{identifier: sub.identifier, acks: acks})

    # Sort lowest QoS first so that uniq_by will ensure lowest QoS is kept
    subs =
      (state.sockets[socket][:subscriptions] ++ sub.topics)
      |> Enum.sort()
      |> Enum.uniq_by(fn {t, _qos} -> t end)

    put_in(state, [:sockets, socket, :subscriptions], subs)
  end

  defp handle_packet(%Unsubscribe{} = unsub, socket, state) do
    subs =
      state.sockets[socket][:subscriptions]
      |> Enum.reject(fn {t, _qos} -> t in unsub.topics end)

    send_packet(socket, %Unsuback{identifier: unsub.identifier})

    put_in(state, [:sockets, socket, :subscriptions], subs)
  end

  defp handle_packet(%Publish{} = pub, socket, state) do
    # Handle QoS 2?
    if pub.qos == 1, do: send_packet(socket, %Puback{identifier: pub.identifier})

    handle_publish(pub, state)
    state
  end

  defp handle_packet(%Pingreq{}, socket, state) do
    send_packet(socket, %Pingresp{})
    state
  end

  defp handle_packet(%_{} = packet, socket, state) do
    id = state.sockets[socket][:conn].client_id
    Logger.debug("[PintBroker] Unhandled packet for client #{id} - #{inspect(packet)}")
    state
  end

  defp handle_packet(raw, _socket, state) do
    Logger.info("[PintBroker] Failed to parse packet - #{inspect(raw, limit: :infinity)}")
    state
  end

  defp handle_close(socket, state) do
    {deleted, sockets} = Map.pop(state.sockets, socket)
    state = %{state | sockets: sockets}

    with %{conn: %{client_id: client_id, will: last_will}} <- deleted do
      if is_struct(last_will, Publish), do: handle_publish(last_will, state)
      state.on_disconnect.(client_id)
    end

    state
  end

  defp send_packet(socket, package) do
    case :gen_tcp.send(socket, Package.encode(package)) do
      {:error, err} ->
        Logger.warning(
          "[PintBroker] Failed to send package (#{inspect(err)}): #{inspect(package)}"
        )

      ok ->
        ok
    end
  end

  defp handle_publish(packet, state) do
    device_subs =
      for {socket, %{subscriptions: subs}} <- state.sockets,
          {filter, _qos} <- subs,
          do: {filter, socket}

    _ =
      for {filter, where} <- device_subs ++ state.rules,
          topic_match?(filter, packet.topic) do
        case where do
          p when is_port(p) -> :gen_tcp.send(where, Package.encode(packet))
          f when is_function(f, 1) -> f.(packet)
          f when is_function(f, 2) -> f.(packet.topic, packet.payload)
          p when is_pid(p) -> send(p, packet)
          _ -> Logger.debug("[PintBroker] Unhandled topic #{inspect(packet.topic)}")
        end
      end

    :ok
  end

  # Everything matched between topic and filter
  defp topic_match?(filter, topic) when is_binary(filter) do
    topic_match?(String.split(filter, "/", trim: true), topic)
  end

  defp topic_match?(filter, topic) when is_binary(topic) do
    topic_match?(filter, String.split(topic, "/", trim: true))
  end

  defp topic_match?([], []), do: true
  defp topic_match?(matched, matched), do: true

  # These positions match, continue checking
  defp topic_match?([a | filter_rem], [a | topic_rem]), do: topic_match?(filter_rem, topic_rem)

  # The filter allows any single value in the topic
  defp topic_match?(["+" | filter_rem], [_ | topic_rem]),
    do: topic_match?(filter_rem, topic_rem)

  # Multi-level topic filter requires additional levels but there
  # are no more left in the topic, so it does not match
  defp topic_match?(["#" | _], []), do: false

  # If we have gotten here, all other parts have matched and this
  # indicates all other parts of the topic are allowed
  defp topic_match?(["#" | _], _), do: true

  defp topic_match?(_, _), do: false

  defp accept(listen, broker) do
    # This function is called recursively to accept new connections
    # and pass off control to the broker process
    with {:ok, socket} <- :gen_tcp.accept(listen) do
      :gen_tcp.controlling_process(socket, broker)
    end

    accept(listen, broker)
  end
end
