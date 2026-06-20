#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: utilities
# dotfiles-test-tags: utilities system-health performance go shell
# dotfiles-test-case: dotfiles-spikes-generates-xorg-suspect-report
# dotfiles-test-case: dotfiles-spikes-prefers-dominant-unit-over-monitor
# dotfiles-test-case: dotfiles-spikes-prefers-active-victim-unit-over-concurrent-top
# dotfiles-test-case: dotfiles-spikes-groups-recent-incidents
# dotfiles-test-case: dotfiles-spikes-skips-sddm-xorg-suspect
# dotfiles-test-case: dotfiles-spikes-renders-specific-browser-candidates
# dotfiles-test-case: dotfiles-spikes-prioritizes-victim-kitty-context
# dotfiles-test-case: dotfiles-spikes-renders-enriched-context
# dotfiles-test-case: dotfiles-spikes-check
# dotfiles-test-case: dotfiles-health-links-spike-count
# dotfiles-test-case: system-spike-watch-compile-cache
# dotfiles-test-case: system-spike-watch-check

# Purpose: Verify lightweight system spike events are reported into Foam with suspect attribution.

spikes_script="${DOTFILES_TEST_ROOT}/utilities/bin/dotfiles-spikes"
watch_script="${DOTFILES_TEST_ROOT}/utilities/bin/system-spike-watch"
health_script="${DOTFILES_TEST_ROOT}/utilities/bin/dotfiles-health"

write_fake_xorg_event() {
    local state_dir=$1
    local today offset started ended

    today=$(date '+%Y-%m-%d')
    offset=$(date '+%z')
    started="${today}T12:00:00${offset}"
    ended="${today}T12:00:03${offset}"
    mkdir -p "${state_dir}/events"
    cat >"${state_dir}/events/${today}.jsonl" <<JSON
{"schema_version":1,"event_id":"test-xorg-timer","started_at":"${started}","ended_at":"${ended}","duration_s":3.0,"trigger_process":{"pid":1320,"comm":"Xorg"},"trigger_cpu_pct":71.0,"victim":{"pid":1320,"comm":"Xorg"},"victim_kind":"xorg","top_processes":[{"pid":1320,"comm":"Xorg","cmdline":"/usr/lib/Xorg -nolisten tcp","unit":"sddm.service","cpu_pct":71.0,"first_seen":0.0,"last_seen":3.0},{"pid":171621,"comm":"xrandr","cmdline":"xrandr --query","unit":"display-health-check.service","cpu_pct":45.0,"first_seen":0.1,"last_seen":2.9}],"top_units":[{"unit":"sddm.service","cpu_pct":71.0},{"unit":"display-health-check.service","cpu_pct":45.0}],"suspects":[{"pid":171621,"comm":"xrandr","cmdline":"xrandr --query","unit":"display-health-check.service","cpu_pct":45.0,"first_seen":0.1,"last_seen":2.9,"reason":"same burst cgroup/unit display-health-check.service; process appeared during burst; command xrandr consumed CPU during victim spike"}],"confidence":"high","classification":"interactive-path critical","notes":"Xorg spiked; likely related to display-health-check.service"}
JSON
}

write_fake_generic_monitor_event() {
    local state_dir=$1
    local today offset started ended

    today=$(date '+%Y-%m-%d')
    offset=$(date '+%z')
    started="${today}T12:05:00${offset}"
    ended="${today}T12:05:03${offset}"
    mkdir -p "${state_dir}/events"
    cat >"${state_dir}/events/${today}.jsonl" <<JSON
{"schema_version":1,"event_id":"test-gulp-monitor","started_at":"${started}","ended_at":"${ended}","duration_s":3.0,"trigger_process":{"pid":4782,"comm":"gulp watch"},"trigger_cpu_pct":188.0,"victim":{"pid":4782,"comm":"gulp watch"},"victim_kind":"generic","top_processes":[{"pid":4782,"comm":"gulp watch","cmdline":"gulp watch","unit":"hypothesis-self-hosted.service","cpu_pct":183.1,"first_seen":0.0,"last_seen":3.0},{"pid":4182,"comm":"python3","cmdline":"/usr/bin/python3 /home/aaaa/bin/system-spike-watch run","unit":"system-spike-watch.service","cpu_pct":20.9,"first_seen":0.0,"last_seen":3.0},{"pid":3947,"comm":"gpg-agent","cmdline":"/usr/bin/gpg-agent --supervised","unit":"gpg-agent.service","cpu_pct":3.9,"first_seen":0.0,"last_seen":3.0}],"top_units":[{"unit":"hypothesis-self-hosted.service","cpu_pct":187.0},{"unit":"system-spike-watch.service","cpu_pct":20.9},{"unit":"gpg-agent.service","cpu_pct":3.9}],"suspects":[{"pid":4182,"comm":"python3","cmdline":"/usr/bin/python3 /home/aaaa/bin/system-spike-watch run","unit":"system-spike-watch.service","cpu_pct":20.9,"first_seen":0.0,"last_seen":3.0,"reason":"same burst cgroup/unit system-spike-watch.service; command python3 consumed CPU during victim spike"},{"pid":3947,"comm":"gpg-agent","cmdline":"/usr/bin/gpg-agent --supervised","unit":"gpg-agent.service","cpu_pct":3.9,"first_seen":0.0,"last_seen":3.0,"reason":"same burst cgroup/unit gpg-agent.service; command gpg-agent consumed CPU during victim spike"}],"confidence":"medium","classification":"background suspicious","notes":"gulp watch spiked; likely related to system-spike-watch.service"}
JSON
}

write_fake_enriched_events() {
    local state_dir=$1
    local today offset xorg_started xorg_ended chromium_started chromium_ended docker_started docker_ended audio_started audio_ended

    today=$(date '+%Y-%m-%d')
    offset=$(date '+%z')
    xorg_started="${today}T12:10:00${offset}"
    xorg_ended="${today}T12:10:03${offset}"
    chromium_started="${today}T12:15:00${offset}"
    chromium_ended="${today}T12:15:03${offset}"
    docker_started="${today}T12:20:00${offset}"
    docker_ended="${today}T12:20:03${offset}"
    audio_started="${today}T12:30:00${offset}"
    audio_ended="${today}T12:30:03${offset}"
    mkdir -p "${state_dir}/events"
    cat >"${state_dir}/events/${today}.jsonl" <<JSON
{"schema_version":1,"event_id":"test-xorg-kitty-context","started_at":"${xorg_started}","ended_at":"${xorg_ended}","duration_s":3.0,"trigger_process":{"pid":1320,"comm":"Xorg","unit":"sddm.service"},"trigger_cpu_pct":52.0,"victim":{"pid":1320,"comm":"Xorg","unit":"sddm.service"},"victim_kind":"xorg","top_processes":[{"pid":1320,"comm":"Xorg","cmdline":"/usr/lib/Xorg","unit":"sddm.service","cpu_pct":52.0,"first_seen":0.0,"last_seen":3.0},{"pid":9001,"comm":"compile","cmdline":"compile project","cwd":"/home/aaaa/project","unit":"kitty-19679-0.scope","cpu_pct":98.0,"first_seen":0.1,"last_seen":2.9}],"top_units":[{"unit":"kitty-19679-0.scope","cpu_pct":98.0},{"unit":"sddm.service","cpu_pct":52.0}],"suspects":[{"pid":9001,"comm":"compile","cmdline":"compile project","unit":"kitty-19679-0.scope","cpu_pct":98.0,"first_seen":0.1,"last_seen":2.9,"reason":"same burst cgroup/unit kitty-19679-0.scope; command compile consumed CPU during victim spike"}],"context":{"kitty":[{"unit":"kitty-19679-0.scope","pid":19679,"socket":"unix:/run/user/1000/kitty-cwd-home__aaaa__project.sock","status":"ok","unit_processes":[{"pid":9001,"comm":"compile","cmdline":"compile project","cwd":"/home/aaaa/project","unit":"kitty-19679-0.scope","cpu_pct":98.0}],"windows":[{"id":1,"title":"project","cwd":"/home/aaaa/project","last_reported_cmdline":"compile project","foreground_processes":[{"pid":9001,"comm":"compile","cmdline":"compile project","cwd":"/home/aaaa/project"}]}]}]},"confidence":"high","classification":"interactive-path critical","notes":"Xorg spiked; likely related to kitty-19679-0.scope"}
{"schema_version":1,"event_id":"test-chromium-context","started_at":"${chromium_started}","ended_at":"${chromium_ended}","duration_s":3.0,"trigger_process":{"pid":16668,"comm":"chromium","unit":"browser-chromium-test.scope"},"trigger_cpu_pct":180.0,"victim":{"pid":16668,"comm":"chromium","unit":"browser-chromium-test.scope"},"victim_kind":"generic","top_processes":[{"pid":16668,"comm":"chromium","cmdline":"/usr/lib/chromium/chromium --remote-debugging-port=9222","unit":"browser-chromium-test.scope","cpu_pct":180.0,"first_seen":0.0,"last_seen":3.0},{"pid":16690,"comm":"chromium","cmdline":"/usr/lib/chromium/chromium --type=renderer --renderer-client-id=7 --remote-debugging-port=9222","unit":"browser-chromium-test.scope","cpu_pct":121.0,"first_seen":0.0,"last_seen":3.0}],"top_units":[{"unit":"browser-chromium-test.scope","cpu_pct":301.0}],"suspects":[{"pid":16668,"comm":"chromium","cmdline":"/usr/lib/chromium/chromium --remote-debugging-port=9222","unit":"browser-chromium-test.scope","cpu_pct":301.0,"first_seen":0.0,"last_seen":3.0,"role":"dominant-unit","reason":"victim process belongs to the dominant burst unit; unit total 301.0% CPU"}],"context":{"browsers":[{"browser":"chromium","unit":"browser-chromium-test.scope","debug_port":9222,"status":"ok","processes":[{"pid":16690,"comm":"chromium","cmdline":"/usr/lib/chromium/chromium --type=renderer --renderer-client-id=7 --remote-debugging-port=9222","unit":"browser-chromium-test.scope","cpu_pct":121.0,"kind":"renderer","renderer_client_id":"7"}],"tabs":[{"id":"ABC","type":"page","title":"Docs","url":"https://example.test/docs","active":true,"match":"active-window-title"}]}]},"confidence":"medium","classification":"background suspicious","notes":"chromium spiked; likely related to browser-chromium-test.scope"}
{"schema_version":1,"event_id":"test-docker-context","started_at":"${docker_started}","ended_at":"${docker_ended}","duration_s":3.0,"trigger_process":{"pid":2401,"comm":"java","unit":"docker-3c013d0077ceb6ed40d4a8061c2868e1c2bc9602e250a9c9adfbf414bc4535c4.scope"},"trigger_cpu_pct":220.0,"victim":{"pid":2401,"comm":"java","unit":"docker-3c013d0077ceb6ed40d4a8061c2868e1c2bc9602e250a9c9adfbf414bc4535c4.scope"},"victim_kind":"generic","top_processes":[{"pid":2401,"comm":"java","cmdline":"java -jar app.jar","unit":"docker-3c013d0077ceb6ed40d4a8061c2868e1c2bc9602e250a9c9adfbf414bc4535c4.scope","cpu_pct":220.0,"first_seen":0.0,"last_seen":3.0}],"top_units":[{"unit":"docker-3c013d0077ceb6ed40d4a8061c2868e1c2bc9602e250a9c9adfbf414bc4535c4.scope","cpu_pct":220.0}],"suspects":[{"pid":2401,"comm":"java","cmdline":"java -jar app.jar","unit":"docker-3c013d0077ceb6ed40d4a8061c2868e1c2bc9602e250a9c9adfbf414bc4535c4.scope","cpu_pct":220.0,"first_seen":0.0,"last_seen":3.0,"role":"dominant-unit","reason":"victim process belongs to the dominant burst unit; unit total 220.0% CPU"}],"context":{"docker":[{"unit":"docker-3c013d0077ceb6ed40d4a8061c2868e1c2bc9602e250a9c9adfbf414bc4535c4.scope","container_id":"3c013d0077ceb6ed40d4a8061c2868e1c2bc9602e250a9c9adfbf414bc4535c4","short_id":"3c013d0077ce","name":"hypothesis-web","image":"hypothesis-self-hosted:latest","container_status":"running","health":"healthy","compose_project":"hypothesis","compose_service":"web","inspect_status":"ok","processes":[{"pid":2401,"comm":"java","cmdline":"java -jar app.jar","unit":"docker-3c013d0077ceb6ed40d4a8061c2868e1c2bc9602e250a9c9adfbf414bc4535c4.scope","cpu_pct":220.0}]}]},"confidence":"medium","classification":"background suspicious","notes":"java spiked; likely related to docker-3c013d0077ceb6ed40d4a8061c2868e1c2bc9602e250a9c9adfbf414bc4535c4.scope"}
{"schema_version":1,"event_id":"test-audio-context","started_at":"${audio_started}","ended_at":"${audio_ended}","duration_s":3.0,"trigger_process":{"pid":3216,"comm":"pipewire","unit":"pipewire.service"},"trigger_cpu_pct":44.0,"victim":{"pid":3216,"comm":"pipewire","cmdline":"/usr/bin/pipewire","unit":"pipewire.service"},"victim_kind":"audio","top_processes":[{"pid":3216,"comm":"pipewire","cmdline":"/usr/bin/pipewire","unit":"pipewire.service","cpu_pct":44.0,"first_seen":0.0,"last_seen":3.0},{"pid":3217,"comm":"wireplumber","cmdline":"/usr/bin/wireplumber","unit":"wireplumber.service","cpu_pct":8.0,"first_seen":0.0,"last_seen":3.0}],"top_units":[{"unit":"pipewire.service","cpu_pct":44.0},{"unit":"wireplumber.service","cpu_pct":8.0}],"suspects":[{"pid":3217,"comm":"wireplumber","cmdline":"/usr/bin/wireplumber","unit":"wireplumber.service","cpu_pct":8.0,"first_seen":0.0,"last_seen":3.0,"reason":"same burst cgroup/unit wireplumber.service; command wireplumber consumed CPU during victim spike"}],"context":{"audio":{"status":"ok","processes":[{"pid":3216,"comm":"pipewire","cmdline":"/usr/bin/pipewire","unit":"pipewire.service","cpu_pct":44.0},{"pid":3217,"comm":"wireplumber","cmdline":"/usr/bin/wireplumber","unit":"wireplumber.service","cpu_pct":8.0}],"nodes":[{"id":59,"state":"R","name":"source_filter.rnnoise","description":"RNNoise Source","media_class":"Audio/Source","app_name":"filter-chain","quantum":"1024","rate":"48000","wait":"3.1us","busy":"9.4us","wait_quantum":"0.00","busy_quantum":"0.42","format":"F32LE 2 48000","busy_score":0.42},{"id":82,"state":"R","name":"alsa_output.test","description":"USB DAC","media_class":"Audio/Sink","quantum":"1024","rate":"48000","wait":"1.0us","busy":"4.0us","wait_quantum":"0.00","busy_quantum":"0.18","format":"S16LE 2 48000","busy_score":0.18}]}},"confidence":"medium","classification":"interactive-path critical","notes":"pipewire spiked; likely related to wireplumber.service"}
JSON
}

write_fake_concurrent_top_event() {
    local state_dir=$1
    local today offset started ended

    today=$(date '+%Y-%m-%d')
    offset=$(date '+%z')
    started="${today}T12:25:00${offset}"
    ended="${today}T12:25:03${offset}"
    mkdir -p "${state_dir}/events"
    cat >"${state_dir}/events/${today}.jsonl" <<JSON
{"schema_version":1,"event_id":"test-concurrent-top","started_at":"${started}","ended_at":"${ended}","duration_s":3.0,"trigger_process":{"pid":4782,"comm":"gulp watch","unit":"hypothesis-self-hosted.service"},"trigger_cpu_pct":183.0,"victim":{"pid":4782,"comm":"gulp watch","cmdline":"gulp watch","unit":"hypothesis-self-hosted.service"},"victim_kind":"generic","top_processes":[{"pid":4782,"comm":"gulp watch","cmdline":"gulp watch","unit":"hypothesis-self-hosted.service","cpu_pct":183.0,"first_seen":0.0,"last_seen":3.0},{"pid":5986,"comm":"MainThread","cmdline":"python MainThread","cwd":"/home/aaaa/dotfiles/playbooks","unit":"kitty-5986-0.scope","cpu_pct":220.0,"first_seen":0.0,"last_seen":3.0}],"top_units":[{"unit":"kitty-5986-0.scope","cpu_pct":220.0},{"unit":"hypothesis-self-hosted.service","cpu_pct":183.0}],"suspects":[{"pid":5986,"comm":"MainThread","cmdline":"python MainThread","unit":"kitty-5986-0.scope","cpu_pct":220.0,"first_seen":0.0,"last_seen":3.0,"reason":"same burst cgroup/unit kitty-5986-0.scope; command MainThread consumed CPU during victim spike"}],"context":{"kitty":[{"unit":"kitty-5986-0.scope","status":"unit-processes-only","unit_processes":[{"pid":5986,"comm":"MainThread","cmdline":"python MainThread","cwd":"/home/aaaa/dotfiles/playbooks","unit":"kitty-5986-0.scope","cpu_pct":220.0}]}]},"confidence":"medium","classification":"background suspicious","notes":"gulp watch spiked; likely related to kitty-5986-0.scope"}
JSON
}

write_fake_xorg_incident_events() {
    local state_dir=$1
    local today offset first second third ended_first ended_second ended_third

    today=$(date '+%Y-%m-%d')
    offset=$(date '+%z')
    first="${today}T12:40:00${offset}"
    second="${today}T12:41:10${offset}"
    third="${today}T12:42:20${offset}"
    ended_first="${today}T12:40:03${offset}"
    ended_second="${today}T12:41:13${offset}"
    ended_third="${today}T12:42:23${offset}"
    mkdir -p "${state_dir}/events"
    cat >"${state_dir}/events/${today}.jsonl" <<JSON
{"schema_version":1,"event_id":"test-xorg-incident-1","started_at":"${first}","ended_at":"${ended_first}","duration_s":3.0,"trigger_process":{"pid":1320,"comm":"Xorg","unit":"sddm.service"},"trigger_cpu_pct":83.0,"victim":{"pid":1320,"comm":"Xorg","unit":"sddm.service"},"victim_kind":"xorg","top_processes":[{"pid":1320,"comm":"Xorg","cmdline":"/usr/lib/Xorg","unit":"sddm.service","cpu_pct":83.0,"first_seen":0.0,"last_seen":3.0},{"pid":16690,"comm":"chromium","cmdline":"/usr/lib/chromium/chromium --type=renderer --renderer-client-id=30","unit":"browser-chromium-test.scope","cpu_pct":67.7,"first_seen":0.0,"last_seen":3.0}],"top_units":[{"unit":"sddm.service","cpu_pct":83.0},{"unit":"browser-chromium-test.scope","cpu_pct":67.7}],"suspects":[{"pid":16690,"comm":"chromium","cmdline":"/usr/lib/chromium/chromium --type=renderer --renderer-client-id=30","unit":"browser-chromium-test.scope","cpu_pct":67.7,"first_seen":0.0,"last_seen":3.0,"reason":"concurrent burst cgroup/unit browser-chromium-test.scope; command chromium consumed CPU during victim spike"}],"confidence":"high","classification":"interactive-path critical","notes":"Xorg spiked; likely related to browser-chromium-test.scope"}
{"schema_version":1,"event_id":"test-xorg-incident-2","started_at":"${second}","ended_at":"${ended_second}","duration_s":3.0,"trigger_process":{"pid":1320,"comm":"Xorg","unit":"sddm.service"},"trigger_cpu_pct":97.0,"victim":{"pid":1320,"comm":"Xorg","unit":"sddm.service"},"victim_kind":"xorg","top_processes":[{"pid":1320,"comm":"Xorg","cmdline":"/usr/lib/Xorg","unit":"sddm.service","cpu_pct":97.0,"first_seen":0.0,"last_seen":3.0},{"pid":9001,"comm":"marksman","cmdline":"marksman server","unit":"kitty-19679-0.scope","cpu_pct":17.5,"first_seen":0.0,"last_seen":3.0}],"top_units":[{"unit":"sddm.service","cpu_pct":97.0},{"unit":"kitty-19679-0.scope","cpu_pct":17.5}],"suspects":[{"pid":9001,"comm":"marksman","cmdline":"marksman server","unit":"kitty-19679-0.scope","cpu_pct":17.5,"first_seen":0.0,"last_seen":3.0,"reason":"concurrent burst cgroup/unit kitty-19679-0.scope; command marksman consumed CPU during victim spike"}],"confidence":"high","classification":"interactive-path critical","notes":"Xorg spiked; likely related to kitty-19679-0.scope"}
{"schema_version":1,"event_id":"test-xorg-incident-3","started_at":"${third}","ended_at":"${ended_third}","duration_s":3.0,"trigger_process":{"pid":1320,"comm":"Xorg","unit":"sddm.service"},"trigger_cpu_pct":98.0,"victim":{"pid":1320,"comm":"Xorg","unit":"sddm.service"},"victim_kind":"xorg","top_processes":[{"pid":1320,"comm":"Xorg","cmdline":"/usr/lib/Xorg","unit":"sddm.service","cpu_pct":98.0,"first_seen":0.0,"last_seen":3.0},{"pid":11872,"comm":"python3","cmdline":"/usr/bin/python3 playbooks/check.py","cwd":"/home/aaaa/dotfiles/playbooks","unit":"kitty-11872-0.scope","cpu_pct":12.8,"first_seen":0.0,"last_seen":3.0}],"top_units":[{"unit":"sddm.service","cpu_pct":98.0},{"unit":"kitty-11872-0.scope","cpu_pct":12.8}],"suspects":[{"pid":11872,"comm":"python3","cmdline":"/usr/bin/python3 playbooks/check.py","unit":"kitty-11872-0.scope","cpu_pct":12.8,"first_seen":0.0,"last_seen":3.0,"reason":"concurrent burst cgroup/unit kitty-11872-0.scope; command python3 consumed CPU during victim spike"}],"confidence":"high","classification":"interactive-path critical","notes":"Xorg spiked; likely related to kitty-11872-0.scope"}
JSON
}

write_fake_sddm_suspect_event() {
    local state_dir=$1
    local today offset started ended

    today=$(date '+%Y-%m-%d')
    offset=$(date '+%z')
    started="${today}T12:45:00${offset}"
    ended="${today}T12:45:03${offset}"
    mkdir -p "${state_dir}/events"
    cat >"${state_dir}/events/${today}.jsonl" <<JSON
{"schema_version":1,"event_id":"test-xorg-sddm-suspect","started_at":"${started}","ended_at":"${ended}","duration_s":3.0,"trigger_process":{"pid":1320,"comm":"Xorg","unit":"sddm.service"},"trigger_cpu_pct":88.0,"victim":{"pid":1320,"comm":"Xorg","unit":"sddm.service"},"victim_kind":"xorg","top_processes":[{"pid":1320,"comm":"Xorg","cmdline":"/usr/lib/Xorg","unit":"sddm.service","cpu_pct":88.0,"first_seen":0.0,"last_seen":3.0},{"pid":1321,"comm":"sddm-helper","cmdline":"/usr/lib/sddm/sddm-helper","unit":"sddm.service","cpu_pct":20.0,"first_seen":0.0,"last_seen":3.0},{"pid":16690,"comm":"chromium","cmdline":"/usr/lib/chromium/chromium --type=renderer --renderer-client-id=40","unit":"browser-chromium-test.scope","cpu_pct":14.5,"first_seen":0.0,"last_seen":3.0}],"top_units":[{"unit":"sddm.service","cpu_pct":108.0},{"unit":"browser-chromium-test.scope","cpu_pct":14.5}],"suspects":[{"pid":1321,"comm":"sddm-helper","cmdline":"/usr/lib/sddm/sddm-helper","unit":"sddm.service","cpu_pct":20.0,"first_seen":0.0,"last_seen":3.0,"reason":"concurrent burst cgroup/unit sddm.service; command sddm-helper consumed CPU during victim spike"},{"pid":16690,"comm":"chromium","cmdline":"/usr/lib/chromium/chromium --type=renderer --renderer-client-id=40","unit":"browser-chromium-test.scope","cpu_pct":14.5,"first_seen":0.0,"last_seen":3.0,"role":"concurrent","reason":"concurrent burst cgroup/unit browser-chromium-test.scope; command chromium consumed CPU during victim spike"}],"confidence":"high","classification":"interactive-path critical","notes":"Xorg spiked; likely related to sddm.service"}
JSON
}

write_fake_browser_candidate_event() {
    local state_dir=$1
    local today offset started ended

    today=$(date '+%Y-%m-%d')
    offset=$(date '+%z')
    started="${today}T12:50:00${offset}"
    ended="${today}T12:50:03${offset}"
    mkdir -p "${state_dir}/events"
    cat >"${state_dir}/events/${today}.jsonl" <<JSON
{"schema_version":1,"event_id":"test-brave-candidate-tabs","started_at":"${started}","ended_at":"${ended}","duration_s":3.0,"trigger_process":{"pid":196388,"comm":"brave","unit":"browser-brave-test.scope"},"trigger_cpu_pct":160.0,"victim":{"pid":196388,"comm":"brave","unit":"browser-brave-test.scope"},"victim_kind":"generic","top_processes":[{"pid":196388,"comm":"brave","cmdline":"/usr/bin/brave --remote-debugging-port=9223","unit":"browser-brave-test.scope","cpu_pct":80.0,"first_seen":0.0,"last_seen":3.0},{"pid":196400,"comm":"brave","cmdline":"/usr/bin/brave --type=renderer --renderer-client-id=753 --remote-debugging-port=9223","unit":"browser-brave-test.scope","cpu_pct":79.3,"first_seen":0.0,"last_seen":3.0}],"top_units":[{"unit":"browser-brave-test.scope","cpu_pct":160.0}],"suspects":[{"pid":196388,"comm":"brave","cmdline":"/usr/bin/brave --remote-debugging-port=9223","unit":"browser-brave-test.scope","cpu_pct":160.0,"first_seen":0.0,"last_seen":3.0,"role":"victim-unit","reason":"victim process belongs to the dominant burst unit; unit total 160.0% CPU"}],"context":{"browsers":[{"browser":"brave","unit":"browser-brave-test.scope","debug_port":9223,"status":"ok","task_sampler_status":"ok","task_sampler_age_s":1.1,"processes":[{"pid":196400,"comm":"brave","cmdline":"/usr/bin/brave --type=renderer --renderer-client-id=753 --remote-debugging-port=9223","unit":"browser-brave-test.scope","cpu_pct":79.3,"kind":"renderer","renderer_client_id":"753"}],"tabs":[{"id":"A","type":"page","title":"Music Queue","url":"https://example.test/music","probable":true,"score":42.0,"score_reason":"task 35.0ms; script 8.0ms; visibility hidden","visibility_state":"hidden","task_ms":35.0,"script_ms":8.0,"browser_task_cpu_pct":16.0,"browser_task_process_id":10,"browser_task_os_pid":1361246,"browser_task_source":"chrome.processes","browser_task_age_s":1.1},{"id":"B","type":"page","title":"Long Notes Document","url":"https://example.test/notes","probable":true,"score":18.5,"score_reason":"task 12.0ms; visibility visible","visibility_state":"visible","task_ms":12.0},{"id":"C","type":"page","title":"Chat","url":"https://example.test/chat","score":2.0,"visibility_state":"hidden","task_ms":2.0}]}]},"confidence":"medium","classification":"background suspicious","notes":"brave spiked; likely related to browser-brave-test.scope"}
JSON
}

write_fake_node_kitty_browser_event() {
    local state_dir=$1
    local today offset started ended

    today=$(date '+%Y-%m-%d')
    offset=$(date '+%z')
    started="${today}T12:55:00${offset}"
    ended="${today}T12:55:03${offset}"
    mkdir -p "${state_dir}/events"
    cat >"${state_dir}/events/${today}.jsonl" <<JSON
{"schema_version":1,"event_id":"test-node-kitty-browser-context","started_at":"${started}","ended_at":"${ended}","duration_s":3.0,"trigger_process":{"pid":1155015,"comm":"node","unit":"kitty-826606-0.scope"},"trigger_cpu_pct":109.0,"victim":{"pid":1155015,"comm":"node","cmdline":"node chrome-devtools-mcp/build/src/telemetry/watchdog/main.js","cwd":"/home/aaaa/data/apps/dev-tools/ai-tools/.npm","unit":"kitty-826606-0.scope"},"victim_kind":"generic","top_processes":[{"pid":1155015,"comm":"node","cmdline":"node chrome-devtools-mcp/build/src/telemetry/watchdog/main.js","cwd":"/home/aaaa/data/apps/dev-tools/ai-tools/.npm","unit":"kitty-826606-0.scope","cpu_pct":82.0,"first_seen":0.0,"last_seen":3.0},{"pid":670212,"comm":"brave","cmdline":"/opt/brave-bin/brave --type=renderer --renderer-client-id=671","unit":"browser-brave-test.scope","cpu_pct":2.6,"first_seen":0.0,"last_seen":3.0},{"pid":11601,"comm":"chromium","cmdline":"/usr/lib/chromium/chromium --type=renderer --renderer-client-id=21","unit":"browser-chromium-test.scope","cpu_pct":4.9,"first_seen":0.0,"last_seen":3.0}],"top_units":[{"unit":"kitty-826606-0.scope","cpu_pct":82.0},{"unit":"browser-chromium-test.scope","cpu_pct":4.9},{"unit":"browser-brave-test.scope","cpu_pct":2.6}],"suspects":[{"pid":1155015,"comm":"node","cmdline":"node chrome-devtools-mcp/build/src/telemetry/watchdog/main.js","cwd":"/home/aaaa/data/apps/dev-tools/ai-tools/.npm","unit":"kitty-826606-0.scope","cpu_pct":82.0,"first_seen":0.0,"last_seen":3.0,"role":"victim-unit","reason":"victim process belongs to the dominant burst unit; unit total 82.0% CPU"}],"context":{"kitty":[{"unit":"kitty-826606-0.scope","status":"unit-processes-only","unit_processes":[{"pid":1155015,"comm":"node","cmdline":"node chrome-devtools-mcp/build/src/telemetry/watchdog/main.js","cwd":"/home/aaaa/data/apps/dev-tools/ai-tools/.npm","unit":"kitty-826606-0.scope","cpu_pct":82.0}]}],"browsers":[{"browser":"brave","unit":"browser-brave-test.scope","debug_port":9223,"status":"ok","processes":[{"pid":670212,"comm":"brave","cmdline":"/opt/brave-bin/brave --type=renderer --renderer-client-id=671","unit":"browser-brave-test.scope","cpu_pct":2.6,"kind":"renderer","renderer_client_id":"671"}],"tabs":[{"id":"A","type":"page","title":"Low CPU tab","url":"https://example.test/low","probable":true,"browser_task_cpu_pct":2.0,"visibility_state":"hidden"}]},{"browser":"chromium","unit":"browser-chromium-test.scope","debug_port":9222,"status":"ok","processes":[{"pid":11601,"comm":"chromium","cmdline":"/usr/lib/chromium/chromium --type=renderer --renderer-client-id=21","unit":"browser-chromium-test.scope","cpu_pct":4.9,"kind":"renderer","renderer_client_id":"21"}],"tabs":[{"id":"B","type":"page","title":"Gather","url":"https://example.test/gather","probable":true,"browser_task_cpu_pct":5.0,"visibility_state":"hidden"}]}]},"confidence":"medium","classification":"background suspicious","notes":"node spiked; likely related to kitty-826606-0.scope"}
JSON
}

case "${DOTFILES_TEST_CASE:-}" in
dotfiles-spikes-generates-xorg-suspect-report)
    state="${DOTFILES_TEST_TMP}/state"
    foam="${DOTFILES_TEST_TMP}/foam/ops/system-health/spikes"
    home="${DOTFILES_TEST_TMP}/home"
    mkdir -p "$home"
    write_fake_xorg_event "$state"

    HOME="$home" DOTFILES_SPIKES_STATE_DIR="$state" DOTFILES_SPIKES_DIR="$foam" "$spikes_script" update

    grep -q 'Spikes today: `1`' "${foam}/system-spikes.md"
    grep -q 'High-confidence events: `1`' "${foam}/system-spikes.md"
    grep -q '`Xorg` <- `display-health-check.service`' "${foam}/system-spikes.md"
    grep -q 'display-health-check.service' "${foam}/system-spikes.md"
    grep -q 'command xrandr consumed CPU during victim spike' "${foam}/sources/system-spike-xorg.md"
    [[ -f "${foam}/system-spike-rules.md" ]]
    [[ -f "${foam}/system-spike-runbook.md" ]]
    [[ -f "${foam}/system-spike-coverage.md" ]]
    grep -q 'Node.js process spikes at lower-than-generic CPU levels.' "${foam}/system-spike-coverage.md"
    [[ -f "${foam}/reports/$(date '+%Y')/system-spikes-$(date '+%Y-%m').md" ]]
    ;;
dotfiles-spikes-prefers-dominant-unit-over-monitor)
    state="${DOTFILES_TEST_TMP}/state"
    foam="${DOTFILES_TEST_TMP}/foam/ops/system-health/spikes"
    home="${DOTFILES_TEST_TMP}/home"
    mkdir -p "$home"
    write_fake_generic_monitor_event "$state"

    HOME="$home" DOTFILES_SPIKES_STATE_DIR="$state" DOTFILES_SPIKES_DIR="$foam" "$spikes_script" update

    grep -q 'Events with monitor overhead: `1`' "${foam}/system-spikes.md"
    grep -q '`gulp watch` <- `hypothesis-self-hosted.service`' "${foam}/system-spikes.md"
    refute grep -q '`gulp watch` <- `system-spike-watch.service`' "${foam}/system-spikes.md"
    refute grep -q 'likely related to system-spike-watch.service' "${foam}/system-spikes.md"
    grep -q 'gulp watch spiked inside active victim unit hypothesis-self-hosted.service; other burst units are concurrent context' "${foam}/system-spikes.md"
    grep -q 'monitor `20.9%` while victim `gulp watch` top unit `hypothesis-self-hosted.service`' "${foam}/system-spikes.md"
    grep -q 'top units: hypothesis-self-hosted.service 187.0%, system-spike-watch.service 20.9%' "${foam}/sources/system-spike-generic.md"
    ;;
dotfiles-spikes-prefers-active-victim-unit-over-concurrent-top)
    state="${DOTFILES_TEST_TMP}/state"
    foam="${DOTFILES_TEST_TMP}/foam/ops/system-health/spikes"
    home="${DOTFILES_TEST_TMP}/home"
    mkdir -p "$home"
    write_fake_concurrent_top_event "$state"

    HOME="$home" DOTFILES_SPIKES_STATE_DIR="$state" DOTFILES_SPIKES_DIR="$foam" "$spikes_script" update

    grep -q '`gulp watch` <- `hypothesis-self-hosted.service`' "${foam}/system-spikes.md"
    refute grep -q '`gulp watch` <- `kitty-5986-0.scope`' "${foam}/system-spikes.md"
    grep -q 'gulp watch spiked inside active victim unit hypothesis-self-hosted.service; other burst units are concurrent context' "${foam}/system-spikes.md"
    grep -q 'context: concurrent kitty process MainThread 220.0% cwd /home/aaaa/dotfiles/playbooks cmd `python MainThread`' "${foam}/system-spikes.md"
    grep -q 'concurrent `MainThread` unit `kitty-5986-0.scope`' "${foam}/sources/system-spike-generic.md"
    ;;
dotfiles-spikes-groups-recent-incidents)
    state="${DOTFILES_TEST_TMP}/state"
    foam="${DOTFILES_TEST_TMP}/foam/ops/system-health/spikes"
    home="${DOTFILES_TEST_TMP}/home"
    mkdir -p "$home"
    write_fake_xorg_incident_events "$state"

    HOME="$home" DOTFILES_SPIKES_STATE_DIR="$state" DOTFILES_SPIKES_DIR="$foam" "$spikes_script" update

    grep -q 'Recorded spikes: `3`' "${foam}/system-spikes.md"
    grep -q 'Unique incidents: `1`' "${foam}/system-spikes.md"
    grep -q 'victim `Xorg` unit `sddm.service` events `3` suspects `browser-chromium-test.scope x1, kitty-19679-0.scope x1, kitty-11872-0.scope x1`' "${foam}/system-spikes.md"
    ;;
dotfiles-spikes-skips-sddm-xorg-suspect)
    state="${DOTFILES_TEST_TMP}/state"
    foam="${DOTFILES_TEST_TMP}/foam/ops/system-health/spikes"
    home="${DOTFILES_TEST_TMP}/home"
    mkdir -p "$home"
    write_fake_sddm_suspect_event "$state"

    HOME="$home" DOTFILES_SPIKES_STATE_DIR="$state" DOTFILES_SPIKES_DIR="$foam" "$spikes_script" update

    grep -q '`Xorg` <- `browser-chromium-test.scope`' "${foam}/system-spikes.md"
    refute grep -q '`Xorg` <- `sddm.service`' "${foam}/system-spikes.md"
    grep -q 'suspect `browser-chromium-test.scope` top unit `browser-chromium-test.scope`' "${foam}/system-spikes.md"
    ;;
dotfiles-spikes-renders-specific-browser-candidates)
    state="${DOTFILES_TEST_TMP}/state"
    foam="${DOTFILES_TEST_TMP}/foam/ops/system-health/spikes"
    home="${DOTFILES_TEST_TMP}/home"
    mkdir -p "$home"
    write_fake_browser_candidate_event "$state"

    HOME="$home" DOTFILES_SPIKES_STATE_DIR="$state" DOTFILES_SPIKES_DIR="$foam" "$spikes_script" update

    grep -q 'context brave renderer 79.3% renderer-client-id 753; probable tabs Music Queue cpu 16.0% hidden https://example.test/music; Long Notes Document score 18.5 task 12.0ms visible https://example.test/notes; Chat score 2.0 task 2.0ms hidden https://example.test/chat' "${foam}/system-spikes.md"
    grep -q 'brave candidate tabs via DevTools/task sampler `9223`: probable `Music Queue` `https://example.test/music` browser cpu `16.0%` browser-process-id `10` os-pid `1361246` source `chrome.processes` age `1.1s` reason `task 35.0ms; script 8.0ms; visibility hidden` visibility `hidden`; probable `Long Notes Document` `https://example.test/notes` score `18.5` reason `task 12.0ms; visibility visible` visibility `visible`; `Chat` `https://example.test/chat` score `2.0` task `2.0ms` visibility `hidden`' "${foam}/sources/system-spike-generic.md"
    ;;
dotfiles-spikes-prioritizes-victim-kitty-context)
    state="${DOTFILES_TEST_TMP}/state"
    foam="${DOTFILES_TEST_TMP}/foam/ops/system-health/spikes"
    home="${DOTFILES_TEST_TMP}/home"
    mkdir -p "$home"
    write_fake_node_kitty_browser_event "$state"

    HOME="$home" DOTFILES_SPIKES_STATE_DIR="$state" DOTFILES_SPIKES_DIR="$foam" "$spikes_script" update

    grep -q 'context: kitty victim node 109.0% cwd /home/aaaa/data/apps/dev-tools/ai-tools/.npm cmd `node chrome-devtools-mcp/build/src/telemetry/watchdog/main.js`' "${foam}/system-spikes.md"
    refute grep -q 'context: concurrent brave renderer' "${foam}/system-spikes.md"
    grep -q 'suspect `node` unit `kitty-826606-0.scope` cwd `/home/aaaa/data/apps/dev-tools/ai-tools/.npm` cmd `node chrome-devtools-mcp/build/src/telemetry/watchdog/main.js`' "${foam}/sources/system-spike-generic.md"
    ;;
dotfiles-spikes-renders-enriched-context)
    state="${DOTFILES_TEST_TMP}/state"
    foam="${DOTFILES_TEST_TMP}/foam/ops/system-health/spikes"
    home="${DOTFILES_TEST_TMP}/home"
    mkdir -p "$home"
    write_fake_enriched_events "$state"

    HOME="$home" DOTFILES_SPIKES_STATE_DIR="$state" DOTFILES_SPIKES_DIR="$foam" "$spikes_script" update

    grep -q 'context: chromium renderer 121.0% renderer-client-id 7; active tab Docs https://example.test/docs' "${foam}/system-spikes.md"
    grep -q 'context: kitty process compile 98.0% cwd /home/aaaa/project cmd `compile project`' "${foam}/system-spikes.md"
    grep -q 'kitty unit `kitty-19679-0.scope` process evidence: `compile` 98.0% cwd `/home/aaaa/project` cmd `compile project`' "${foam}/sources/system-spike-xorg.md"
    grep -q 'kitty window `1` title `project` cwd `/home/aaaa/project` last cmd `compile project` foreground `compile` cwd `/home/aaaa/project` cmd `compile project`' "${foam}/sources/system-spike-xorg.md"
    grep -q 'chromium unit `browser-chromium-test.scope` process evidence: `chromium` kind `renderer` renderer-client-id `7` 121.0% cmd `/usr/lib/chromium/chromium --type=renderer --renderer-client-id=7 --remote-debugging-port=9222`' "${foam}/sources/system-spike-generic.md"
    grep -q 'chromium candidate tabs via DevTools `9222`: active `Docs` `https://example.test/docs` match `active-window-title`' "${foam}/sources/system-spike-generic.md"
    grep -q 'context: docker container hypothesis-web image hypothesis-self-hosted:latest compose service web process java 220.0%' "${foam}/system-spikes.md"
    grep -q 'context: audio node RNNoise Source class Audio/Source B/Q 0.42' "${foam}/system-spikes.md"
    grep -q 'context: audio node USB DAC class Audio/Sink B/Q 0.18' "${foam}/system-spikes.md"
    grep -q 'docker unit `docker-3c013d0077ceb6ed40d4a8061c2868e1c2bc9602e250a9c9adfbf414bc4535c4.scope` container `hypothesis-web` id `3c013d0077ce` image `hypothesis-self-hosted:latest` status `running` health `healthy` compose project `hypothesis` compose service `web`' "${foam}/sources/system-spike-generic.md"
    grep -q 'docker unit `docker-3c013d0077ceb6ed40d4a8061c2868e1c2bc9602e250a9c9adfbf414bc4535c4.scope` process evidence: `java` 220.0% cmd `java -jar app.jar`' "${foam}/sources/system-spike-generic.md"
    grep -q 'audio process evidence: `pipewire` 44.0% cmd `/usr/bin/pipewire`, `wireplumber` 8.0% cmd `/usr/bin/wireplumber`' "${foam}/sources/system-spike-audio.md"
    grep -q 'pipewire node evidence: node `RNNoise Source` id `59` class `Audio/Source` app `filter-chain` B/Q `0.42` BUSY `9.4us` W/Q `0.00` format `F32LE 2 48000`; node `USB DAC` id `82` class `Audio/Sink` B/Q `0.18` BUSY `4.0us` W/Q `0.00` format `S16LE 2 48000`' "${foam}/sources/system-spike-audio.md"
    ;;
dotfiles-spikes-check)
    state="${DOTFILES_TEST_TMP}/state"
    foam="${DOTFILES_TEST_TMP}/foam/ops/system-health/spikes"
    home="${DOTFILES_TEST_TMP}/home"
    mkdir -p "$home"
    write_fake_xorg_event "$state"

    HOME="$home" DOTFILES_SPIKES_STATE_DIR="$state" DOTFILES_SPIKES_DIR="$foam" "$spikes_script" check >"${DOTFILES_TEST_TMP}/check.out"

    grep -q '^events=1$' "${DOTFILES_TEST_TMP}/check.out"
    grep -q "^state_dir=${state}$" "${DOTFILES_TEST_TMP}/check.out"
    grep -q "^spikes_dir=${foam}$" "${DOTFILES_TEST_TMP}/check.out"
    ;;
dotfiles-health-links-spike-count)
    state="${DOTFILES_TEST_TMP}/state"
    notes="${DOTFILES_TEST_TMP}/foam"
    health="${notes}/ops/system-health"
    home="${DOTFILES_TEST_TMP}/home"
    mkdir -p "$home"
    write_fake_xorg_event "$state"

    HOME="$home" DOTFILES_HEALTH_NOTES_ROOT="$notes" DOTFILES_HEALTH_DIR="$health" DOTFILES_SPIKES_STATE_DIR="$state" "$health_script" update

    grep -q 'CPU spike events today: `1`' "${health}/system-health.md"
    grep -q '\[\[system-spikes\]\]: `1 CPU spike events today`' "${health}/system-health.md"
    grep -q '\[\[system-spikes\]\]: lightweight CPU spike events' "${health}/sources/discovery/system-health-coverage.md"
    ;;
system-spike-watch-check)
    state="${DOTFILES_TEST_TMP}/state"
    home="${DOTFILES_TEST_TMP}/home"
    cache="${DOTFILES_TEST_TMP}/cache"
    mkdir -p "$home"

    HOME="$home" XDG_CACHE_HOME="$cache" DOTFILES_SYSTEM_SPIKE_WATCH_SOURCE_DIR="${DOTFILES_TEST_ROOT}/utilities/dot-local/share/dotfiles/system-spike-watch" "$watch_script" check --state-dir "$state" >"${DOTFILES_TEST_TMP}/watch-check.out"

    grep -q "^state_dir=${state}$" "${DOTFILES_TEST_TMP}/watch-check.out"
    grep -q "^events_dir=${state}/events$" "${DOTFILES_TEST_TMP}/watch-check.out"
    grep -q '^hz=' "${DOTFILES_TEST_TMP}/watch-check.out"
    grep -q '^cpu_count=' "${DOTFILES_TEST_TMP}/watch-check.out"
    ;;
system-spike-watch-compile-cache)
    home="${DOTFILES_TEST_TMP}/home"
    cache="${DOTFILES_TEST_TMP}/cache"
    linked_source="${DOTFILES_TEST_TMP}/linked-source"
    linked_cache="${DOTFILES_TEST_TMP}/linked-cache"
    mkdir -p "$home"
    mkdir -p "$linked_source"
    ln -s "${DOTFILES_TEST_ROOT}/utilities/dot-local/share/dotfiles/system-spike-watch/go.mod" "$linked_source/go.mod"
    ln -s "${DOTFILES_TEST_ROOT}/utilities/dot-local/share/dotfiles/system-spike-watch/main.go" "$linked_source/main.go"
    ln -s "${DOTFILES_TEST_ROOT}/utilities/dot-local/share/dotfiles/system-spike-watch/main_test.go" "$linked_source/main_test.go"

    HOME="$home" XDG_CACHE_HOME="$cache" DOTFILES_SYSTEM_SPIKE_WATCH_SOURCE_DIR="${DOTFILES_TEST_ROOT}/utilities/dot-local/share/dotfiles/system-spike-watch" "$watch_script" --compile-cache >"${DOTFILES_TEST_TMP}/compile-1.out"
    HOME="$home" XDG_CACHE_HOME="$cache" DOTFILES_SYSTEM_SPIKE_WATCH_SOURCE_DIR="${DOTFILES_TEST_ROOT}/utilities/dot-local/share/dotfiles/system-spike-watch" "$watch_script" --compile-cache >"${DOTFILES_TEST_TMP}/compile-2.out"
    HOME="$home" XDG_CACHE_HOME="$linked_cache" DOTFILES_SYSTEM_SPIKE_WATCH_SOURCE_DIR="$linked_source" "$watch_script" --compile-cache >"${DOTFILES_TEST_TMP}/compile-symlink.out"

    grep -q '^compiled$' "${DOTFILES_TEST_TMP}/compile-1.out"
    grep -q '^compiled$' "${DOTFILES_TEST_TMP}/compile-symlink.out"
    [[ -x "${cache}/dotfiles/system-spike-watch/system-spike-watch" ]]
    [[ -x "${linked_cache}/dotfiles/system-spike-watch/system-spike-watch" ]]
    [[ ! -s "${DOTFILES_TEST_TMP}/compile-2.out" ]]
    "${cache}/dotfiles/system-spike-watch/system-spike-watch" check --state-dir "${DOTFILES_TEST_TMP}/state" >"${DOTFILES_TEST_TMP}/compiled-check.out"
    grep -q "^state_dir=${DOTFILES_TEST_TMP}/state$" "${DOTFILES_TEST_TMP}/compiled-check.out"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
