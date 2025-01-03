import Config

config :nostrum,
  token: System.get_env("ALLO_JOHN_TOKEN"),
  ffmpeg: "/usr/bin/ffmpeg",
  youtubedl: "/usr/local/bin/youtube-dl",
  streamlink: "/home/tempest/.local/bin/streamlink"

config :allojohn,
  use_cookies: System.get_env("USE_YT_COOKIES", "false"),
  cookies: System.get_env("YT_COOKIES_PATH", "~/cookies.txt")
