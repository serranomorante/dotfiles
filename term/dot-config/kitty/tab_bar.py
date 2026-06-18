"""Custom Kitty tab bar drawing.

Keep the normal powerline tab rendering and use the otherwise-empty right side
of the tab bar for a compact local date/time readout.
"""

from datetime import datetime
from pathlib import Path
from sys import argv as fallback_argv

from kitty.tab_bar import (
    DrawData,
    ExtraData,
    TabBarData,
    as_rgb,
    color_as_int,
    draw_tab_with_powerline,
)


LAUNCH_CWD_FG = 0x6F9FB5


def draw_tab(
    draw_data: DrawData,
    screen,
    tab: TabBarData,
    before: int,
    max_tab_length: int,
    index: int,
    is_last: bool,
    extra_data: ExtraData,
) -> int:
    if index == 1:
        draw_left_launch_cwd(draw_data, screen)
        before = screen.cursor.x

    end = draw_tab_with_powerline(
        draw_data,
        screen,
        tab,
        before,
        max_tab_length,
        index,
        is_last,
        extra_data,
    )
    if is_last and not extra_data.for_layout:
        draw_right_datetime(draw_data, screen)
    return end


def draw_left_launch_cwd(draw_data: DrawData, screen) -> None:
    text = launch_cwd_label()
    if not text:
        return

    screen.cursor.fg = as_rgb(LAUNCH_CWD_FG)
    screen.cursor.bg = as_rgb(color_as_int(draw_data.default_bg))
    screen.cursor.bold = False
    screen.cursor.italic = False
    screen.draw(f"{text} ")


def draw_title(data: dict) -> str:
    title = data["title"]
    label = tab_label(data)
    stack_icon = "  " if data["layout_name"] == "stack" and data["num_windows"] > 1 else ""
    return f"{stack_icon}{data['index']}. {label or title}"


def tab_label(data: dict) -> str:
    title = data["title"]
    tab = data["tab"]
    tab_cwd = normalize_existing_path(getattr(tab, "active_wd", "") or "")
    if not tab_cwd:
        return title

    launch_cwd = launch_cwd_from_argv()
    if not launch_cwd:
        return tab_cwd if title.startswith("base-title") else title

    relation = path_relation(tab_cwd, launch_cwd)
    if relation == ".":
        return process_label(getattr(tab, "active_exe", "") or "") or title
    if relation:
        return f"/{relation}"
    return tab_cwd


def process_label(exe: str) -> str:
    return Path(exe).name


def normalize_existing_path(path: str) -> str:
    if not path:
        return ""
    return str(Path(path).expanduser().resolve(strict=False))


def path_relation(path: str, base: str) -> str:
    try:
        relative = Path(path).relative_to(base)
    except ValueError:
        return ""
    relative_text = relative.as_posix()
    return "." if relative_text == "." else relative_text


def launch_cwd_label() -> str:
    cwd = launch_cwd_from_argv()
    if not cwd:
        return ""

    home = str(Path.home())
    if cwd == home:
        return ""
    if cwd.startswith(f"{home}/"):
        return f"~/{cwd.removeprefix(f'{home}/')}"
    return cwd


def launch_cwd_from_argv(argv_: list[str] | None = None) -> str:
    args = proc_self_argv() if argv_ is None else argv_
    for i, arg in enumerate(args):
        if arg in ("-d", "--directory", "--working-directory"):
            if i + 1 < len(args):
                return normalize_cwd_arg(args[i + 1])
            return ""
        for prefix in ("--directory=", "--working-directory="):
            if arg.startswith(prefix):
                return normalize_cwd_arg(arg.removeprefix(prefix))
    return ""


def proc_self_argv() -> list[str]:
    try:
        data = Path("/proc/self/cmdline").read_bytes()
    except OSError:
        return list(fallback_argv)

    args = [arg.decode("utf-8", "surrogateescape") for arg in data.split(b"\0") if arg]
    return args or list(fallback_argv)


def normalize_cwd_arg(cwd: str) -> str:
    if not cwd:
        return ""
    path = Path(cwd).expanduser()
    if not path.is_absolute():
        path = Path.cwd() / path
    return str(path.resolve(strict=False))


def draw_right_datetime(draw_data: DrawData, screen) -> None:
    text = datetime.now().strftime("%Y-%m-%d %H:%M")
    start = screen.columns - len(text) - 1
    if start <= screen.cursor.x:
        return

    screen.cursor.x = start
    screen.cursor.fg = as_rgb(color_as_int(draw_data.inactive_fg))
    screen.cursor.bg = as_rgb(color_as_int(draw_data.default_bg))
    screen.cursor.bold = False
    screen.cursor.italic = False
    screen.draw(text)
