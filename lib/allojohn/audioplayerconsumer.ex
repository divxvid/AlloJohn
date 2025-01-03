defmodule AlloJohn.AudioPlayerConsumer do
  use Nostrum.Consumer

  alias Nostrum.Struct.Component.ActionRow
  alias Nostrum.Struct.Component.Button
  alias AlloJohn.SongQueue
  alias Nostrum.Api
  alias Nostrum.Cache.GuildCache
  alias Nostrum.Voice

  require Logger

  @pause_emoji "⏸️"
  @resume_emoji "▶️"
  @stop_emoji "⏹️"
  @next_emoji "➡️"

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
        _ -> ""
      end

    Api.create_interaction_response!(
      interaction,
      create_response(message)
    )
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
        AlloJohn.SongQueue.start_link(guild_id, name: via(guild_id))
        Logger.debug("Started a SongQueue Genserver for Guild: #{guild_id}")
    end
  end

  def do_command(%{guild_id: guild_id, data: %{name: "nikalbc"}}) do
    Voice.leave_channel(guild_id)

    # stop the corresponding genserver with this guild id
    AlloJohn.SongQueue.stop(via(guild_id))
    Logger.debug("Stopped a SongQueue Genserver for Guild: #{guild_id}")
    {:msg, ":wave:"}
  end

  def do_command(%{guild_id: guild_id, data: %{name: "show-queue"}}) do
    queue = AlloJohn.SongQueue.get_queue(via(guild_id))
    queue_str = Enum.join(queue, "\n- ")
    {:msg, "Queue:\n- #{queue_str}"}
  end

  def do_command(%{guild_id: guild_id, data: %{name: "pause"}}), do: Voice.pause(guild_id)

  def do_command(%{guild_id: guild_id, data: %{name: "resume"}}), do: Voice.resume(guild_id)

  def do_command(%{guild_id: guild_id, data: %{name: "stop"}}) do
    SongQueue.clear_queue(via(guild_id))
    Voice.stop(guild_id)
  end

  def do_command(%{guild_id: guild_id, data: %{name: "play", options: options}}) do
    if Voice.ready?(guild_id) do
      # Adding a new behaviour, whenever we send a play command, it will first
      # stop the current song and play the new one instead
      Voice.stop(guild_id)

      [%{name: "url", options: [%{value: url}]}] = options
      SongQueue.clear_queue(via(guild_id))
      SongQueue.add_song(via(guild_id), url)
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
    SongQueue.add_song(via(guild_id), url)
  end

  def do_command(%{guild_id: guild_id, data: %{custom_id: "pause-clicked"}}) do
    Voice.pause(guild_id)
  end

  def do_command(%{guild_id: guild_id, data: %{custom_id: "resume-clicked"}}) do
    Voice.resume(guild_id)
  end

  def do_command(%{guild_id: guild_id, data: %{custom_id: "stop-clicked"}}) do
    SongQueue.clear_queue(via(guild_id))
    Voice.stop(guild_id)
  end

  def do_command(%{guild_id: guild_id, data: %{custom_id: "next-clicked"}}) do
    Voice.stop(guild_id)
  end

  defp create_response(message) do
    buttons = [
      Button.interaction_button(@pause_emoji, "pause-clicked"),
      Button.interaction_button(@resume_emoji, "resume-clicked"),
      Button.interaction_button(@stop_emoji, "stop-clicked"),
      Button.interaction_button(@next_emoji, "next-clicked")
    ]

    action_row = ActionRow.action_row(buttons)

    %{
      type: 4,
      data: %{
        content: message,
        components: [action_row]
      }
    }
  end

  defp via(guild_id) do
    {:via, Registry, {AlloJohn.SongQueueRegistry, guild_id}}
  end
end
