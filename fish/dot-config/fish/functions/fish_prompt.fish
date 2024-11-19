# Write shell commands on new line
# https://stackoverflow.com/a/43881171
function fish_prompt
    functions -q fish_prompt_original; and fish_prompt_original; or echo $PWD '>'
    echo
    fish_vi_mode_prompt
end
