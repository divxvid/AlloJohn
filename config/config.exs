import Config

config :nostrum,
  token: System.get_env("ALLO_JOHN_TOKEN"),
  ffmpeg: "/usr/bin/ffmpeg",
  youtubedl: "/usr/local/bin/youtube-dl",
  streamlink: "/home/tempest/.local/bin/streamlink"
