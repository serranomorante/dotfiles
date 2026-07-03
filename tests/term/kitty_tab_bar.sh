#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: term
# dotfiles-test-tags: term kitty python
# dotfiles-test-readonly: /home/aaaa/.local/kitty.app
# dotfiles-test-case: kitty-tab-bar-config-loads
# dotfiles-test-case: kitty-tab-bar-launch-cwd
# dotfiles-test-case: kitty-tab-bar-title-without-launch-cwd
# dotfiles-test-case: kitty-tab-bar-title-with-launch-cwd
# dotfiles-test-case: kitty-tab-bar-title-width

# Purpose: Verify custom Kitty tab bar title and launch-cwd behavior.

kitty_bin="/home/aaaa/.local/kitty.app/bin/kitty"
python_case="${DOTFILES_TEST_TMP}/kitty-tab-bar-case.py"

run_python_case() {
    cat >"$python_case" <<'PY'
import importlib.util
import os
from pathlib import Path
from types import SimpleNamespace


ROOT = Path(os.environ["DOTFILES_TEST_ROOT"])
TMP = Path(os.environ["DOTFILES_TEST_TMP"])
CASE = os.environ["DOTFILES_TEST_CASE"]
TAB_BAR_PATH = ROOT / "term/dot-config/kitty/tab_bar.py"
CONFIG_PATH = ROOT / "term/dot-config/kitty/kitty.conf"


def assert_equal(expected, actual):
    if expected != actual:
        raise AssertionError(f"expected {expected!r}, got {actual!r}")


def load_tab_bar():
    spec = importlib.util.spec_from_file_location("dotfiles_kitty_tab_bar", TAB_BAR_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def tab(
    active_wd,
    active_exe,
    title="",
    active_oldest_wd="/old/cwd",
    active_oldest_exe="/usr/bin/bash",
    is_active=True,
    foreground_processes=None,
    last_reported_cmdline="",
    at_prompt=True,
):
    return {
        "title": title,
        "tab": SimpleNamespace(
            active_wd=str(active_wd),
            active_exe=active_exe,
            active_oldest_wd=active_oldest_wd,
            active_oldest_exe=active_oldest_exe,
            is_active=is_active,
        ),
        "layout_name": "tall",
        "num_windows": 1,
        "index": 7,
        "tab_id": 17,
        "foreground_processes": foreground_processes,
        "last_reported_cmdline": last_reported_cmdline,
        "at_prompt": at_prompt,
    }


if CASE == "kitty-tab-bar-config-loads":
    from kitty.config import load_config

    bad = []
    opts = load_config(str(CONFIG_PATH), accumulate_bad_lines=bad)
    assert_equal([], [str(line) for line in bad])
    assert_equal("{bell_symbol}{activity_symbol}{fmt.fg.tab}{custom}", opts.tab_title_template)
    assert_equal(frozenset({"no-cursor"}), opts.shell_integration)

elif CASE == "kitty-tab-bar-launch-cwd":
    m = load_tab_bar()
    home = Path.home().resolve()
    launch = (TMP / "project").resolve()
    child = (launch / "src/api").resolve()
    relative_base = (TMP / "relative-base").resolve()
    relative_base.mkdir(parents=True, exist_ok=True)

    assert_equal("", m.launch_cwd_from_argv(["kitty"]))
    assert_equal(str(launch), m.launch_cwd_from_argv(["kitty", "-d", str(launch)]))
    assert_equal(str(child), m.launch_cwd_from_argv(["kitty", "--directory", str(child)]))
    assert_equal(str(child), m.launch_cwd_from_argv(["kitty", f"--working-directory={child}"]))

    old_cwd = Path.cwd()
    try:
        os.chdir(relative_base)
        assert_equal(str(relative_base / "nested"), m.launch_cwd_from_argv(["kitty", "-d", "nested"]))
    finally:
        os.chdir(old_cwd)

    m.launch_cwd_from_argv = lambda argv_=None: ""
    assert_equal("", m.launch_cwd_label())
    m.launch_cwd_from_argv = lambda argv_=None: str(home)
    assert_equal("", m.launch_cwd_label())
    m.launch_cwd_from_argv = lambda argv_=None: str(home / "work/project")
    assert_equal("~/work/project", m.launch_cwd_label())
    m.launch_cwd_from_argv = lambda argv_=None: str(launch)
    assert_equal(str(launch), m.launch_cwd_label())

elif CASE == "kitty-tab-bar-title-without-launch-cwd":
    m = load_tab_bar()
    cwd = (TMP / "plain").resolve()
    m.launch_cwd_from_argv = lambda argv_=None: ""

    assert_equal("", m.tab_label(tab("", "/usr/bin/bash")))
    assert_equal("nvim", m.tab_label(tab("", "/usr/bin/nvim")))
    assert_equal(str(cwd), m.tab_label(tab(cwd, "/usr/bin/bash")))
    assert_equal("nvim", m.tab_label(tab(cwd, "/usr/bin/nvim")))
    assert_equal("nvim", m.tab_label(tab(cwd, "/usr/bin/nvim", title="base-title")))
    assert_equal("nvim", m.tab_label(tab(cwd, "/usr/bin/nvim", title="aaaa@archlinux:~/dotfiles/playbooks")))
    assert_equal(str(cwd), m.tab_label(tab(cwd, "/usr/bin/bash", title="aaaa@archlinux:~/dotfiles/playbooks")))
    assert_equal(str(cwd), m.tab_label(tab(cwd, "/usr/bin/bash", title="~/plain")))
    assert_equal(str(cwd), m.tab_label(tab(cwd, "/usr/bin/bash", title="nvim README.md", last_reported_cmdline="nvim README.md")))
    assert_equal("nvim", m.tab_label(tab(cwd, "/usr/bin/bash", title="nvim README.md", last_reported_cmdline="nvim README.md", at_prompt=False)))
    assert_equal("nvim", m.tab_label(tab(cwd, "/usr/bin/bash", title="sudo -E nvim README.md", at_prompt=False)))
    assert_equal("nvim", m.tab_label(tab(cwd, "/usr/bin/bash", title="base-title", foreground_processes=[
        {"cmdline": ["bash", "/home/aaaa/bin/nvim"]},
        {"cmdline": ["/home/aaaa/.local/bin/nvim", "--listen", "/tmp/nvim.sock"]},
    ])))
    assert_equal("manual-title", m.tab_label(tab(cwd, "/usr/bin/nvim", title="manual-title")))
    manual_data = tab(cwd, "/usr/bin/nvim", title="manual-title")
    del manual_data["foreground_processes"]
    del manual_data["last_reported_cmdline"]
    del manual_data["at_prompt"]
    original_active_window_from_data = m.active_window_from_data
    try:
        m.active_window_from_data = lambda data: (_ for _ in ()).throw(AssertionError("unexpected active window lookup"))
        assert_equal("manual-title", m.tab_label(manual_data))
    finally:
        m.active_window_from_data = original_active_window_from_data

elif CASE == "kitty-tab-bar-title-with-launch-cwd":
    m = load_tab_bar()
    launch = (TMP / "project").resolve()
    child = (launch / "src/api").resolve()
    outside = (TMP / "outside").resolve()
    m.launch_cwd_from_argv = lambda argv_=None: str(launch)

    assert_equal("7. nvim", m.draw_title(tab(launch, "/usr/bin/nvim")))
    assert_equal("/src/api", m.tab_label(tab(child, "/usr/bin/bash", active_oldest_wd=str(launch), active_oldest_exe="/usr/bin/bash")))
    assert_equal("nvim", m.tab_label(tab(child, "/usr/bin/nvim", active_oldest_wd=str(launch), active_oldest_exe="/usr/bin/bash")))
    assert_equal(str(outside), m.tab_label(tab(outside, "/usr/bin/bash")))
    assert_equal("manual-title", m.tab_label(tab(launch, "/usr/bin/nvim", title="manual-title")))
    assert_equal("manual-child", m.tab_label(tab(child, "/usr/bin/nvim", title="manual-child")))
    assert_equal("manual-outside", m.tab_label(tab(outside, "/usr/bin/bash", title="manual-outside")))

    stack_data = tab(launch, "/usr/bin/nvim")
    stack_data["layout_name"] = "stack"
    stack_data["num_windows"] = 2
    assert_equal("  7. nvim", m.draw_title(stack_data))

elif CASE == "kitty-tab-bar-title-width":
    m = load_tab_bar()
    launch = (TMP / "project").resolve()
    child = (launch / "vendor/app/public/modules/performance").resolve()
    m.launch_cwd_from_argv = lambda argv_=None: str(launch)

    assert_equal("...ublic/modules/performance", m.fit_tab_label(m.tab_label(tab(child, "/usr/bin/bash")), 28, active=True))
    assert_equal("...c/modules/performance", m.fit_tab_label(m.tab_label(tab(child, "/usr/bin/bash", is_active=False)), 28, active=False))
    assert_equal("...hat-is-not-a-path", m.fit_tab_label("long-manual-title-that-is-not-a-path", 20, active=False))
    assert_equal("def", m.fit_text_label("abcdef", 3))
    assert_equal("...f", m.fit_text_label("abcdef", 4))
    assert_equal(8, m.title_cell_budget(10, 0))
    assert_equal(7, m.title_cell_budget(10, 24))

    m._current_max_tab_length = 34
    assert_equal("7. ...p/public/modules/performance", m.draw_title(tab(child, "/usr/bin/bash")))
    assert_equal("7. ...c/modules/performance", m.draw_title(tab(child, "/usr/bin/bash", is_active=False)))
    m._current_max_tab_length = 5
    assert_equal("7. le", m.draw_title(tab(child, "/usr/bin/nvim", title="manual-title")))
    compact_title = tab(child, "/usr/bin/nvim", title="manual-title")
    compact_title["index"] = 123
    m._current_max_tab_length = 3
    assert_equal("3. ", m.draw_title(compact_title))
    m._current_max_tab_length = None

    launch_label = "~/code/work/repos/webapp.frontend.example.app"
    assert_equal("~/.../webapp.frontend.example.app", m.fit_path_label(launch_label, 36, active=True))

    class FakeScreen:
        def __init__(self):
            self.cursor = SimpleNamespace(x=0, fg=1, bg=0)
            self.columns = 80
            self.drawn = []

        def draw(self, text):
            self.drawn.append(text)
            self.cursor.x += len(text)

    class FakeColor:
        def contrast(self, other):
            return 0

    screen = FakeScreen()
    draw_data = SimpleNamespace(
        default_bg=0,
        powerline_style="angled",
        bell_on_tab="",
        tab_activity_symbol="",
        inactive_bg=FakeColor(),
        inactive_fg=FakeColor(),
    )

    m.launch_cwd_from_argv = lambda argv_=None: str(Path.home() / "code/work/repos/webapp.frontend.example.app")
    left_screen = FakeScreen()
    m.draw_left_launch_cwd(draw_data, left_screen)
    assert_equal([f"{launch_label} "], left_screen.drawn)

    direct_tab = SimpleNamespace(
        title="/home/aaaa/dotfiles/playbooks",
        tab_id=-1,
        is_active=True,
        layout_name="tall",
        num_windows=1,
        num_window_groups=1,
        needs_attention=False,
        has_activity_since_last_focus=False,
    )
    m._current_max_tab_length = m.title_cell_budget(18, 0)
    m.draw_tab_powerline(draw_data, screen, direct_tab, 0, 18, 2, SimpleNamespace(next_tab=None), 0, 1)
    direct_output = "".join(screen.drawn)
    assert "2. ..." in direct_output
    assert "playbooks" in direct_output
    assert "…" not in direct_output
    m._current_max_tab_length = None

else:
    raise SystemExit(f"unknown DOTFILES_TEST_CASE: {CASE}")
PY

    "$kitty_bin" +runpy "exec(compile(open('${python_case}', 'r', encoding='utf-8').read(), '${python_case}', 'exec'), globals())"
}

case "${DOTFILES_TEST_CASE:-}" in
kitty-tab-bar-config-loads | kitty-tab-bar-launch-cwd | kitty-tab-bar-title-without-launch-cwd | kitty-tab-bar-title-with-launch-cwd | kitty-tab-bar-title-width)
    run_python_case
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
