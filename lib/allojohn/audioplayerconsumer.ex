defmodule AlloJohn.AudioPlayerConsumer do
  use Nostrum.Consumer

  alias AlloJohn.SongQueue
  alias Nostrum.Api
  alias Nostrum.Cache.GuildCache
  alias Nostrum.Voice

  require Logger

  # Compile-time helper for defining Discord Application Command options
  opt = fn type, name, desc, opts ->
    %{type: type, name: name, description: desc}
    |> Map.merge(Enum.into(opts, %{}))
  end

  @play_opts [
    opt.(1, "file", "Play a file", options: [opt.(3, "url", "File URL to play", required: true)]),
    opt.(1, "url", "Play a URL from a common service",
      options: [opt.(3, "url", "URL to play", required: true)]
    )
  ]

  @commands [
    {"allo", "Summon bot to your voice channel", []},
    {"nikalbc", "Tell bot to leave your voice channel", []},
    {"play", "Play a sound", @play_opts},
    {"stop", "Stop the playing sound", []},
    {"pause", "Pause the playing sound", []},
    {"resume", "Resume the paused sound", []},
    {"queue", "Queue the next song", @play_opts},
    {"show-queue", "shows the current queue", []}
  ]

  def get_voice_channel_of_interaction(%{guild_id: guild_id, user: %{id: user_id}} = _interaction) do
    guild_id
    |> GuildCache.get!()
    |> Map.get(:voice_states)
    |> Enum.find(%{}, fn v -> v.user_id == user_id end)
    |> Map.get(:channel_id)
  end

  # If you are running this example in an iex session where you manually call
  # AudioPlayerSupervisor.start_link, you will have to call this function
  # with your guild_id as the argument
  def create_guild_commands(guild_id) do
    Enum.each(@commands, fn {name, description, options} ->
      Api.create_guild_application_command(guild_id, %{
        name: name,
        description: description,
        options: options
      })
    end)
  end

  def handle_event({:READY, %{guilds: guilds} = _event, _ws_state}) do
    guilds
    |> Enum.map(fn guild -> guild.id end)
    |> Enum.each(fn guild_id ->
      create_guild_commands(guild_id)
    end)
  end

  def handle_event({:INTERACTION_CREATE, interaction, _ws_state}) do
    # Run the command, and check for a response message, or default to a checkmark emoji
    message =
      case do_command(interaction) do
        {:msg, msg} -> msg
        _ -> ":white_check_mark:"
      end

    Api.create_interaction_response(interaction, %{type: 4, data: %{content: message}})
  end

  def handle_event({:VOICE_SPEAKING_UPDATE, payload, _ws_state}) do
    Logger.debug("VOICE SPEAKING UPDATE #{inspect(payload)}")
  end

  # Default event handler, if you don't include this, your consumer WILL crash if
  # you don't have a method definition for each event type.
  def handle_event(_event) do
    :noop
  end

  def do_command(%{guild_id: guild_id, data: %{name: "allo"}} = interaction) do
    case get_voice_channel_of_interaction(interaction) do
      nil ->
        {:msg, "You must be in a voice channel to summon me"}

      voice_channel_id ->
        Voice.join_channel(guild_id, voice_channel_id)

        # Registering a separate song queue genserver with guild id as the name
        # into the registry
        name = {:via, Registry, {AlloJohn.SongQueueRegistry, guild_id}}
        AlloJohn.SongQueue.start_link(guild_id, name: name)
        Logger.debug("Started a SongQueue Genserver for Guild: #{guild_id}")
    end
  end

  def do_command(%{guild_id: guild_id, data: %{name: "nikalbc"}}) do
    Voice.leave_channel(guild_id)

    # stop the corresponding genserver with this guild id
    [{pid, _}] = Registry.lookup(AlloJohn.SongQueueRegistry, guild_id)
    AlloJohn.SongQueue.stop(pid)
    Logger.debug("Stopped a SongQueue Genserver for Guild: #{guild_id}")
    {:msg, ":wave:"}
  end

  def do_command(%{guild_id: guild_id, data: %{name: "show-queue"}}) do
    [{pid, _}] = Registry.lookup(AlloJohn.SongQueueRegistry, guild_id)
    queue = AlloJohn.SongQueue.get_queue(pid)
    Logger.debug(queue)
    queue_str = Enum.join(queue, "\n")
    {:msg, "Queue:\n#{queue_str}"}
  end

  def do_command(%{guild_id: guild_id, data: %{name: "pause"}}), do: Voice.pause(guild_id)

  def do_command(%{guild_id: guild_id, data: %{name: "resume"}}), do: Voice.resume(guild_id)

  def do_command(%{guild_id: guild_id, data: %{name: "stop"}}) do
    [{pid, _}] = Registry.lookup(AlloJohn.SongQueueRegistry, guild_id)
    SongQueue.clear_queue(pid)
    Voice.stop(guild_id)
  end

  def do_command(%{guild_id: guild_id, data: %{name: "play", options: options}}) do
    if Voice.ready?(guild_id) do
      # Adding a new behaviour, whenever we send a play command, it will first
      # stop the current song and play the new one instead
      Voice.stop(guild_id)

      [%{name: "url", options: [%{value: url}]}] = options
      [{pid, _}] = Registry.lookup(AlloJohn.SongQueueRegistry, guild_id)
      SongQueue.clear_queue(pid)
      SongQueue.add_song(pid, url)
      # case options do
      #   [%{name: "file", options: [%{value: url}]}] -> Voice.play(guild_id, url, :url)
      #   [%{name: "url", options: [%{value: url}]}] -> Voice.play(guild_id, url, :ytdl)
      # end
    else
      {:msg, "I must be in a voice channel before playing audio"}
    end
  end

  def do_command(%{guild_id: guild_id, data: %{name: "queue", options: options}}) do
    [%{name: "url", options: [%{value: url}]}] = options
    [{pid, _}] = Registry.lookup(AlloJohn.SongQueueRegistry, guild_id)
    SongQueue.add_song(pid, url)
  end
end
