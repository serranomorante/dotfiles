# Use fzf to search history
function reverse_history_search
    history | fzf -q "$(commandline -b)" | read -l command
    if test $command
        commandline -rb $command
    end
end
