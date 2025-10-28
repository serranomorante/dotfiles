local task_name = "record-screen"

---@type overseer.TemplateDefinition
return {
  name = task_name,
  desc = "Record the screen",
  builder = function()
    local ffmpeg_cmd = "ffmpeg -hide_banner -f x11grab -framerate 30 -video_size 1920x1080"
      .. " -i :0.0+0,0 -f pulse -i record-chrome-audio-sink.monitor -vf 'setpts=N/FR/TB'"
      .. " -c:v libx264 -preset veryfast -crf 23 -c:a aac -b:a 192k -pix_fmt yuv420p"
      .. " ~/external/Videos/screencast_$(date +\\%Y\\%m\\%d_\\%H\\%M\\%S).mp4"

    return {
      name = task_name,
      strategy = {
        "orchestrator",
        tasks = {
          {
            "shell",
            cmd = "sleep 2", -- give time before starting to record
          },
          {
            "shell",
            cmd = ffmpeg_cmd,
          },
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
