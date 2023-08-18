defmodule OtpCrashWeb.EchoSocket do
  require Logger
  @behaviour Phoenix.Socket.Transport

  def child_spec(opts) do
    # We won't spawn any process, so let's ignore the child spec
    :ignore
  end

  def connect(state) do
    # Callback to retrieve relevant data from the connection.
    # The map contains options, params, transport and endpoint keys.
    {:ok, state}
  end

  def init(state) do
    # Now we are effectively inside the process that maintains the socket.
    {:ok, state}
  end

  def handle_in({binary, _opts}, state) do
    Logger.info("Received and echoing back")

    if String.valid?(binary) do
      {:reply, :ok, {:text, binary}, state}
    else
      {:reply, :ok, {:binary, binary}, state}
    end
  end

  def handle_info(_, state) do
    {:ok, state}
  end

  def terminate(_reason, _state) do
    :ok
  end
end
