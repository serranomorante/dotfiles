local task_name = "record-screen"

---@type overseer.TemplateDefinition
return {
  name = task_name,
  desc = "Record the screen",
  params = {
    audio_source = {
      desc = "Audio source",
      type = "enum",
      choices = { "source_node.work_audio", "source_node.music-production-audio" },
      default = "source_node.work_audio",
      order = 1,
    },
    output = {
      desc = "Output type (gif, mov, mp4)",
      type = "enum",
      choices = { "gif", "mov", "mp4" },
      default = "mp4",
      order = 2,
    },
    path = {
      desc = "Path to save the files",
      type = "string",
      choices = { "~/Videos" },
      order = 3,
    },
  },
  builder = function(params)
    local datefmt = os.date("%Y-%m-%d_%H-%M-%S")
    local recording_id = string.format("record-screen-%s", datefmt)
    local script = vim.fn.expand("~/dotfiles/audio/dot-local/bin/record-screen-ffmpeg")
    local runtime_root = vim.env.XDG_RUNTIME_DIR or "/tmp"
    local status_path = string.format("%s/dotfiles-record-screen/%s/status", runtime_root, recording_id)

    return {
      name = task_name,
      cmd = script,
      args = {
        "start",
        "--id",
        recording_id,
        "--audio-source",
        params.audio_source,
        "--output",
        params.output,
        "--path",
        params.path,
      },
      metadata = {
        PREVENT_QUIT = true,
        record_screen = {
          id = recording_id,
          script = script,
          status_path = status_path,
        },
      },
      components = {
        { "timeout", timeout = 60 * 60 * 2 },
        "unique",
        "default",
      },
    }
  end,
}
