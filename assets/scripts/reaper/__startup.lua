local resource_path = reaper.GetResourcePath()
local startup_scripts = {
    resource_path .. "/Scripts/custom/yabridge_focus_repair.lua",
}

for _, script in ipairs(startup_scripts) do
    local chunk, err = loadfile(script)
    if chunk then
        local ok, runtime_err = pcall(chunk)
        if not ok then
            reaper.ShowConsoleMsg(("Startup script failed: %s\n%s\n"):format(script, runtime_err))
        end
    else
        reaper.ShowConsoleMsg(("Startup script missing or invalid: %s\n%s\n"):format(script, err))
    end
end
