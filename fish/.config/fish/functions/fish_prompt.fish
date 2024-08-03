# Write shell commands on new line
# https://stackoverflow.com/a/43881171
function fish_prompt
    fish_prompt_original
    echo
    fish_vi_mode_prompt
end
