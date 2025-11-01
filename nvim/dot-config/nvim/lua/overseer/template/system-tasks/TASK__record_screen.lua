local task_name = "record-screen"

---@type overseer.TemplateDefinition
return {
  name = task_name,
  desc = "Record the screen",
  params = {
    output = {
      desc = "Output type (gif, mov, mp4)",
      type = "enum",
      choices = { "gif", "mov", "mp4" },
      default = "mp4",
      order = 1,
    },
    path = {
      desc = "Path to save the files",
      type = "string",
      optional = true,
      default = "~/external/Videos",
      order = 2,
    },
  },
  builder = function(params)
    local datefmt = os.date("%Y-%m-%d_%H-%M-%S")
    local ffmpeg_cmd = "ffmpeg -hide_banner -f x11grab -framerate 30 -video_size 1920x1080"
      .. " -i :0.0+0,0 -f pulse -i record-chrome-audio-sink.monitor -vf 'setpts=N/FR/TB'"
      .. " -c:v libx264 -preset veryfast -crf 23 -c:a aac -b:a 192k -pix_fmt yuv420p"
      .. string.format(" %s/screencast_%s.mp4", params.path, datefmt)
    local convert_to = "ffmpeg -i"
      .. string.format(" %s/screencast_%s.mp4", params.path, datefmt)
      .. string.format(" %s/screencast_%s.%s", params.path, datefmt, params.output)
    local tasks = {
      {
        "shell",
        cmd = "sleep 2", -- give time before starting to record
      },
      {
        "shell",
        cmd = ffmpeg_cmd,
      },
    }
    if params.output and params.output ~= "mp4" then table.insert(tasks, { "shell", cmd = convert_to }) end
    return {
      name = task_name,
      strategy = {
        "orchestrator",
        tasks = tasks,
      },
      components = {
        { "system-components/COMPONENT__start_insert_mode" },
        { "timeout", timeout = 60 * 60 * 2 },
        "unique",
        "default",
      },
    }
  end,
}
