defmodule AlloJohn.Application do
  use Application

  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: AlloJohn.SongQueueRegistry},
      AlloJohn.AudioPlayerConsumer
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
