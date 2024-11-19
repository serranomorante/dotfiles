function fish_vi_mode_prompt
    switch $fish_bind_mode
        case default
            set_color --bold blue
            echo 'N → '
        case insert
            set_color --bold brgreen
            echo 'I → '
        case replace_one
            set_color --bold yellow
            echo 'R → '
        case visual
            set_color --bold brmagenta
            echo 'V → '
        case '*'
            set_color --bold red
            echo '? → '
    end
    # comment `set_color` because it adds a new line
    # set_color normal
end
