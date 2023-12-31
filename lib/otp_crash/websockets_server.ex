defmodule OtpCrash.WebsocketsServer do
  use GenServer
  require Logger
  require Mint.HTTP

  defstruct [:conn, :websocket, :request_ref, :caller, :status, :resp_headers, :closing?]

  # def connect(url) do
  #   with {:ok, socket} <- GenServer.start_link(__MODULE__, []),
  #        {:ok, :connected} <- GenServer.call(socket, {:connect, url}) do
  #     {:ok, socket}
  #   end
  # end

  def start_link(init_args) do
    GenServer.start_link(__MODULE__, [init_args], name: __MODULE__)
  end

  def send_message(pid \\ __MODULE__, text) do
    GenServer.call(pid, {:send_text, text})
  end

  def send_binary_message(pid \\ __MODULE__, binary) do
    binary = binary || File.read!("black_hd.png")
    GenServer.call(pid, {:send_binary, binary})
  end

  def send_binary_message() do
    binary = File.read!("black_hd.png")
    Process.send(self(), {:send_binary, binary}, [])
  end

  def send_text_message() do
    Process.send(self(), {:send_text, "Testing"}, [])
  end

  @impl GenServer
  @spec init(any) ::
          {:ok,
           %{
             :conn => Mint.HTTP.t() | Mint.HTTP2.t(),
             :request_ref => reference,
             optional(any) => any
           }, {:continue, :send}}
  def init(_args) do
    initial_state = %__MODULE__{}
    {:ok, state} = connect("ws://localhost:4000/ws/websocket", initial_state)

    {:ok, state, {:continue, :send}}
  end

  @impl GenServer
  def handle_continue(:send, state) do
    Process.sleep(2000)

    for _ <- 1..11 do
      send_binary_message()
      send_text_message()
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_call({:send_text, text}, _from, state) do
    {:ok, state} = send_frame(state, {:text, text})
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:send_binary, binary}, _from, state) do
    Logger.info("Sending binary message")
    {:ok, state} = send_frame(state, {:binary, binary})
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info({:send_binary, binary}, state) do
    {:ok, state} = send_frame(state, {:binary, binary})
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(message, state) do
    case Mint.WebSocket.stream(state.conn, message) do
      {:ok, conn, responses} ->
        state = put_in(state.conn, conn) |> handle_responses(responses)
        if state.closing?, do: do_close(state), else: {:noreply, state}

      {:error, conn, reason, _responses} ->
        state = put_in(state.conn, conn) |> reply({:error, reason})
        {:noreply, state}

      :unknown ->
        {:noreply, state}
    end
  end

  def connect(url, state) do
    uri = URI.parse(url)

    http_scheme =
      case uri.scheme do
        "ws" -> :http
        "wss" -> :https
      end

    ws_scheme =
      case uri.scheme do
        "ws" -> :ws
        "wss" -> :wss
      end

    path =
      case uri.query do
        nil -> uri.path
        query -> uri.path <> "?" <> query
      end

    with {:ok, conn} <-
           Mint.HTTP.connect(http_scheme, uri.host, uri.port),
         {:ok, conn, ref} <- Mint.WebSocket.upgrade(ws_scheme, conn, path, []) do
      Logger.info("Websocket connected")

      state = %{state | conn: conn, request_ref: ref}

      {:ok, state}
    else
      {:error, reason} ->
        Logger.error({:error, reason})
        {:error, state}

      {:error, conn, reason} ->
        Logger.error({:error, reason})

        {:error, put_in(state.conn, conn)}
    end
  end

  defp handle_responses(state, responses)

  defp handle_responses(%{request_ref: ref} = state, [{:status, ref, status} | rest]) do
    put_in(state.status, status)
    |> handle_responses(rest)
  end

  defp handle_responses(%{request_ref: ref} = state, [{:headers, ref, resp_headers} | rest]) do
    put_in(state.resp_headers, resp_headers)
    |> handle_responses(rest)
  end

  defp handle_responses(%{request_ref: ref} = state, [{:done, ref} | rest]) do
    case Mint.WebSocket.new(state.conn, ref, state.status, state.resp_headers) do
      {:ok, conn, websocket} ->
        %{state | conn: conn, websocket: websocket, status: nil, resp_headers: nil}
        |> reply({:ok, :connected})
        |> handle_responses(rest)

      {:error, conn, reason} ->
        put_in(state.conn, conn)
        |> reply({:error, reason})
    end
  end

  defp handle_responses(%{request_ref: ref, websocket: websocket} = state, [
         {:data, ref, data} | rest
       ])
       when websocket != nil do
    case Mint.WebSocket.decode(websocket, data) do
      {:ok, websocket, frames} ->
        put_in(state.websocket, websocket)
        |> handle_frames(frames)
        |> handle_responses(rest)

      {:error, websocket, reason} ->
        put_in(state.websocket, websocket)
        |> reply({:error, reason})
    end
  end

  defp handle_responses(state, [_response | rest]) do
    handle_responses(state, rest)
  end

  defp handle_responses(state, []), do: state

  defp send_frame(state, frame) do
    with {:ok, websocket, data} <- Mint.WebSocket.encode(state.websocket, frame),
         state = put_in(state.websocket, websocket),
         {:ok, conn} <- Mint.WebSocket.stream_request_body(state.conn, state.request_ref, data) do
      {:ok, put_in(state.conn, conn)}
    else
      {:error, %Mint.WebSocket{} = websocket, reason} ->
        {:error, put_in(state.websocket, websocket), reason}

      {:error, conn, reason} ->
        {:error, put_in(state.conn, conn), reason}
    end
  end

  def handle_frames(state, frames) do
    Enum.reduce(frames, state, fn
      # reply to pings with pongs
      {:ping, data}, state ->
        {:ok, state} = send_frame(state, {:pong, data})
        state

      {:close, _code, reason}, state ->
        Logger.debug("Closing connection: #{inspect(reason)}")
        %{state | closing?: true}

      {:text, text}, state ->
        Logger.debug("Received: #{inspect(text)}, sending back the reverse")
        {:ok, state} = send_frame(state, {:text, String.reverse(text)})
        state

      {:binary, binary}, state ->
        Logger.debug("Received: #{inspect(binary)}, echoing back")
        {:ok, state} = send_frame(state, {:binary, binary})
        state

      frame, state ->
        Logger.debug("Unexpected frame received: #{inspect(frame)}")
        state
    end)
  end

  defp do_close(state) do
    # Streaming a close frame may fail if the server has already closed
    # for writing.
    _ = send_frame(state, :close)
    Mint.HTTP.close(state.conn)
    {:stop, :normal, state}
  end

  defp reply(state, response) do
    if state.caller, do: GenServer.reply(state.caller, response)
    put_in(state.caller, nil)
  end
end
