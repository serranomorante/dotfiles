# To save custom key bindings, put the bind statements into config.fish. Alternatively, fish also automatically executes a function called fish_user_key_bindings if it exists.
function fish_user_key_bindings
    bind -M default / reverse_history_search
    bind -M insert \cn down-line 
    bind -M insert \cp up-line 
    bind -M insert \cy accept-autosuggestion 
end
