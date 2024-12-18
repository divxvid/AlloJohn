defmodule AlloJohn.SongQueue do
  alias Nostrum.Voice
  require Logger
  use GenServer
  # API functions
  def start_link(guild_id, opts \\ []) do
    {:ok, pid} = GenServer.start_link(__MODULE__, guild_id, opts)
    Process.send_after(pid, :poll_voice, 1000)
    {:ok, pid}
  end

  def get_queue(pid) do
    GenServer.call(pid, :get_queue)
  end

  def clear_queue(pid) do
    GenServer.cast(pid, :clear_queue)
  end

  def add_song(pid, song_url) do
    GenServer.cast(pid, {:push, song_url})
  end

  def stop(pid) do
    GenServer.stop(pid, :normal)
  end

  # callbacks
  @impl true
  def init(guild_id) do
    initial_state = {:queue.new(), guild_id}
    {:ok, initial_state}
  end

  @impl true
  def handle_cast({:push, song_url}, {queue, guild_id}) do
    queue = :queue.in(song_url, queue)
    {:noreply, {queue, guild_id}}
  end

  @impl true
  def handle_cast(:clear_queue, {_, guild_id}) do
    queue = :queue.new()
    {:noreply, {queue, guild_id}}
  end

  @impl true
  def handle_call(:current_song, _from, {queue, guild_id}) do
    current_song = :queue.head(queue)
    {:reply, current_song, {queue, guild_id}}
  end

  @impl true
  def handle_call(:get_queue, _from, {queue, guild_id}) do
    queue_list = :queue.to_list(queue)
    {:reply, queue_list, {queue, guild_id}}
  end

  @impl true
  def handle_call(:next_song, _from, {queue, guild_id}) do
    current_song = :queue.head(queue)

    queue = :queue.drop(queue)
    queue = :queue.in(current_song, queue)

    next_song = :queue.head(queue)
    {:reply, next_song, {queue, guild_id}}
  end

  @impl true
  def handle_info(:poll_voice, {queue, guild_id}) do
    voice = Voice.get_voice(guild_id)
    Process.send_after(self(), :poll_voice, 1000)

    cond do
      # if this is not defined, we are sure that nothing is getting played
      # So, we do play the next song from the queue if it has something
      not is_pid(voice.ffmpeg_proc) || not Process.alive?(voice.ffmpeg_proc) ->
        unless :queue.is_empty(queue) do
          current_song = :queue.head(queue)

          queue = :queue.drop(queue)
          queue = :queue.in(current_song, queue)

          next_song_url = :queue.head(queue)
          Voice.play(guild_id, next_song_url, :ytdl)
          {:noreply, {queue, guild_id}}
        else
          {:noreply, {queue, guild_id}}
        end

      # Voice.playing?(guild_id) ->
      #   Logger.debug("[POLLER #{guild_id}] Something's playing wow")
      #   {:noreply, {queue, guild_id}}
      #
      # not voice.speaking ->
      #   Logger.debug("[POLLER #{guild_id}] Song is paused I think")
      #   {:noreply, {queue, guild_id}}
      #
      true ->
        {:noreply, {queue, guild_id}}
    end
  end
end
