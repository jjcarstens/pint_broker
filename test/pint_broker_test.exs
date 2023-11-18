defmodule PintBrokerTest do
  use ExUnit.Case, async: true

  alias Tortoise311.Package

  setup do
    ok = fn _ -> :ok end
    state = %{sockets: %{}, rules: [], on_connect: ok, on_disconnect: ok}
    %{state: state}
  end

  @tag :integration
  test "handles MQTT packets", %{test: test} do
    test_pid = self()
    port = 1883

    opts = [
      port: port,
      on_connect: fn c -> send(test_pid, {:on_connect, c}) end,
      on_disconnect: fn c -> send(test_pid, {:on_disconnect, c}) end,
      name: test
    ]

    server = start_supervised!({PintBroker, opts})

    # Can connect to server
    assert {:ok, socket} = :gen_tcp.connect(~c"localhost", port, active: true, mode: :binary)

    # connect acks
    :gen_tcp.send(socket, encode(%Package.Connect{client_id: "howdy"}))
    assert_receive({:tcp, ^socket, data}, 1000)
    assert %Package.Connack{status: :accepted} = Package.decode(data)
    # on_connect callback is called with successful connection
    assert_receive({:on_connect, "howdy"})

    # subscribe to topic
    subscribe = encode(%Package.Subscribe{identifier: 1234, topics: [{"hello", 1}]})
    :gen_tcp.send(socket, subscribe)
    assert_receive({:tcp, ^socket, data}, 1000)
    assert %Package.Suback{identifier: 1234} = Package.decode(data)

    # Can publish from broker to client
    PintBroker.publish(server, "hello", "world")
    assert_receive({:tcp, ^socket, data}, 1000)
    assert %Package.Publish{topic: "hello", payload: "world"} = Package.decode(data)

    # publish qos 1 sends puback
    subscribe = encode(%Package.Publish{identifier: 1235, topic: "howdy", qos: 1, payload: <<>>})
    :gen_tcp.send(socket, subscribe)
    assert_receive({:tcp, ^socket, data}, 1000)
    assert %Package.Puback{identifier: 1235} = Package.decode(data)

    # pingreq sends pingresp
    :gen_tcp.send(socket, encode(%Package.Pingreq{}))
    assert_receive({:tcp, ^socket, data}, 1000)
    assert %Package.Pingresp{} = Package.decode(data)

    # Unsubscribe to topic
    unsubscribe = encode(%Package.Unsubscribe{identifier: 1234, topics: ["hello"]})
    :gen_tcp.send(socket, unsubscribe)
    assert_receive({:tcp, ^socket, data}, 1000)
    assert %Package.Unsuback{identifier: 1234} = Package.decode(data)

    # Ignores other packets
    :gen_tcp.send(socket, encode(%Package.Pubcomp{identifier: 3295}))
    refute_receive({:tcp, ^socket, _})

    # Handles bad data received
    :gen_tcp.send(socket, <<1, 2, 3, 4>>)
    refute_receive({:tcp, ^socket, _})

    # Duplicate connect acks closes connection
    :gen_tcp.send(socket, encode(%Package.Connect{client_id: "howdy"}))
    assert_receive({:tcp_closed, ^socket})
    # on_disconnect called with socket close
    assert_receive({:on_disconnect, "howdy"})
  end

  test "connect packet tracks socket", %{state: state} do
    socket = fake_socket()
    connect = encode(%Package.Connect{client_id: "howdy"})

    assert {:noreply, updated} = PintBroker.handle_info({:tcp, socket, connect}, state)
    assert %{conn: %Package.Connect{client_id: "howdy"}} = updated.sockets[socket]

    # Duplicate connect closes connection
    assert {:noreply, updated2} = PintBroker.handle_info({:tcp, socket, connect}, updated)
    refute updated2.sockets[socket]
  end

  test "tracks subscriptions", %{state: state} do
    socket = fake_socket()
    subscribe = encode(%Package.Subscribe{identifier: 1234, topics: [{"hello", 0}]})
    state = put_in(state.sockets[socket], %{subscriptions: []})

    assert {:noreply, updated} = PintBroker.handle_info({:tcp, socket, subscribe}, state)
    assert %{subscriptions: [{"hello", 0}]} = updated.sockets[socket]

    # Duplicate topic subscription uses lowest QoS
    subscribe2 = encode(%Package.Subscribe{identifier: 1234, topics: [{"hello", 1}]})
    assert {:noreply, updated2} = PintBroker.handle_info({:tcp, socket, subscribe2}, updated)
    assert %{subscriptions: [{"hello", 0}]} = updated2.sockets[socket]
  end

  test "unsubscribe topics", %{state: state} do
    socket = fake_socket()
    subscribe = encode(%Package.Unsubscribe{identifier: 1234, topics: ["hello"]})
    state = put_in(state.sockets[socket], %{subscriptions: [{"hello", 0}]})

    assert {:noreply, updated} = PintBroker.handle_info({:tcp, socket, subscribe}, state)
    assert %{subscriptions: []} = updated.sockets[socket]
  end

  test "publishes messages to rules", %{state: state} do
    socket = fake_socket()
    pub = %Package.Publish{topic: "hello", payload: "world"}

    test_pid = self()

    state = %{
      state
      | sockets: %{socket => %{}},
        rules: [
          {"hello", fn packet -> send(test_pid, {:fn1, packet}) end},
          {"hello", fn topic, payload -> send(test_pid, {:fn2, topic, payload}) end},
          {"hello", test_pid}
        ]
    }

    assert {:noreply, ^state} =
             PintBroker.handle_info({:tcp, socket, Package.encode(pub)}, state)

    assert_receive({:fn1, ^pub}, 1000)
    assert_receive({:fn2, "hello", "world"}, 1000)
    assert_receive(^pub, 1000)
  end

  test "Requires initial MQTT connect before using parsable packets", %{state: state} do
    # # Ignores other packets
    unhandled_packet_log =
      ExUnit.CaptureLog.capture_log(fn ->
        unhandled = encode(%Package.Pubcomp{identifier: 3295})

        assert {:noreply, ^state} =
                 PintBroker.handle_info({:tcp, fake_socket(), unhandled}, state)
      end)

    assert unhandled_packet_log =~ ~r/Missing MQTT Connect/
  end

  test "ignores unhandled packets", %{state: state} do
    # # Ignores other packets
    unhandled_packet_log =
      ExUnit.CaptureLog.capture_log(fn ->
        unhandled = encode(%Package.Pubcomp{identifier: 3295})
        socket = fake_socket()
        state = put_in(state.sockets[socket], %{conn: %{client_id: "howdy"}})

        assert {:noreply, ^state} =
                 PintBroker.handle_info({:tcp, socket, unhandled}, state)
      end)

    assert unhandled_packet_log =~ ~r/Unhandled packet for client howdy/
  end

  test "ignores unparsable packets", %{state: state} do
    bad_data_log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:noreply, ^state} =
                 PintBroker.handle_info({:tcp, fake_socket(), <<1, 2, 3, 4>>}, state)
      end)

    assert bad_data_log =~ ~r/Failed to parse packet/
  end

  test "cleans up closed sockets", %{state: state} do
    socket = fake_socket()

    with_socket = put_in(state.sockets[socket], %{howdy: :partner})

    assert {:noreply, ^state} = PintBroker.handle_info({:tcp_closed, socket}, with_socket)
  end

  defp encode(package) do
    case Package.encode(package) do
      # Sometimes it is just iodata returned. This is safe when
      # used with :gen_tcp, but we need binary to actually decode
      # during functional testing since that is how it would be
      # received over the wire.
      iodata when is_list(iodata) ->
        :erlang.list_to_binary(iodata)

      bin ->
        bin
    end
  end

  def fake_socket do
    i = System.unique_integer([:positive])
    :erlang.list_to_port(~c"#Port<0.#{i}>")
  end
end
