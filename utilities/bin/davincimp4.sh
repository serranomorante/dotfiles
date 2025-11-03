#!/bin/bash

# Put his file in ~/.local/bin to be in the path
# Run it from directory where video file is in
# execute as: davincimp4.sh 'file name.mov'
# Inverted commas required if a space in the filename

# Check if an input file is provided
if [[ $# -eq 0 ]]; then
  echo "Usage: $0 <input_mov_file>"
  exit 1
fi

# Get the input file name (without extension)
input_file="${1%.*}"

# Get the output file name (same name as input but with .mp4 extension)
output_file="${input_file}.mp4"

# Option in Video: FFmpeg command with hardware acceleration and encoding parameters
# For a higher bitrate try changing -qp 15 to -qp 10
ffmpeg -hwaccel cuda -hwaccel_device 0 -i "$input_file.mov" -vf yadif -codec:v h264_nvenc -qp 10 -bf 2 -flags +cgop -pix_fmt yuv420p -codec:a aac -strict -2 -b:a 384k -r:a 48000 -movflags faststart "$output_file"

# Another Nvidia option
# ffmpeg -y -hwaccel cuda -hwaccel_output_format cuda -i "$input_file.mov" -c:a copy -c:v h264_nvenc -b:v 10M -fps_mode passthrough "$output_file"

# Non Nvidia option
# ffmpeg -i "$input_file.mov" -vf yadif -codec:v libx264 -crf 1 -bf 2 -flags +cgop -pix_fmt yuv420p -codec:a aac -strict -2 -b:a 384k -r:a 48000 -movflags faststart "$output_file"

echo "Conversion completed. Output file: $output_file"
