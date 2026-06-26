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
MIN_TAB_LABEL_WIDTH = 12
INACTIVE_PATH_LABEL_WIDTH = 24
LAUNCH_CWD_LABEL_WIDTH = 36
_current_max_tab_length: int | None = None


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
        draw_left_launch_cwd(draw_data, screen, max_tab_length)
        before = screen.cursor.x

    global _current_max_tab_length
    previous_max_tab_length = _current_max_tab_length
    _current_max_tab_length = max_tab_length
    try:
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
    finally:
        _current_max_tab_length = previous_max_tab_length

    if is_last and not extra_data.for_layout:
        draw_right_datetime(draw_data, screen)
    return end


def draw_left_launch_cwd(draw_data: DrawData, screen, max_tab_length: int) -> None:
    text = fit_path_label(launch_cwd_label(), max_launch_cwd_width(screen, max_tab_length), active=True)
    if not text:
        return

    screen.cursor.fg = as_rgb(LAUNCH_CWD_FG)
    screen.cursor.bg = as_rgb(color_as_int(draw_data.default_bg))
    screen.cursor.bold = False
    screen.cursor.italic = False
    screen.draw(f"{text} ")


def draw_title(data: dict) -> str:
    title = data["title"]
    tab = data["tab"]
    is_active = getattr(tab, "is_active", data.get("is_active", False))
    stack_icon = "  " if data["layout_name"] == "stack" and data["num_windows"] > 1 else ""
    prefix = f"{stack_icon}{data['index']}. "
    label = fit_tab_label(tab_label(data) or title, available_label_width(len(prefix)), active=is_active)
    return f"{prefix}{label}"


def tab_label(data: dict) -> str:
    title = data["title"]
    if is_manual_title(title):
        return title

    tab = data["tab"]
    tab_cwd = normalize_existing_path(getattr(tab, "active_wd", "") or "")
    if not tab_cwd:
        return title

    launch_cwd = launch_cwd_from_argv()
    if not launch_cwd:
        return tab_cwd

    relation = path_relation(tab_cwd, launch_cwd)
    if relation == ".":
        return process_label(getattr(tab, "active_exe", "") or "") or title
    if relation:
        return f"/{relation}"
    return tab_cwd


def process_label(exe: str) -> str:
    return Path(exe).name


def is_manual_title(title: str) -> bool:
    return bool(title) and not title.startswith("base-title")


def available_label_width(prefix_width: int) -> int:
    if _current_max_tab_length is None:
        return 0
    return max(MIN_TAB_LABEL_WIDTH, _current_max_tab_length - prefix_width)


def fit_tab_label(label: str, max_width: int, active: bool) -> str:
    if not max_width or len(label) <= max_width:
        return label
    if is_path_label(label):
        path_width = max_width if active else min(max_width, INACTIVE_PATH_LABEL_WIDTH)
        return fit_path_label(label, path_width, active=active)
    return fit_text_label(label, max_width)


def fit_path_label(label: str, max_width: int, active: bool) -> str:
    if not max_width or len(label) <= max_width:
        return label
    if max_width <= 4:
        return label[:max_width]

    marker = path_marker(label)
    components = [part for part in label.removeprefix(marker).split("/") if part]
    if not components:
        return fit_text_label(label, max_width)

    compact = f"{marker}{components[-1]}"
    if len(compact) <= max_width and not active:
        return compact

    suffix = components[-1]
    while len(f"{marker}.../{suffix}") > max_width and len(suffix) > 1:
        suffix = suffix[1:]
    if len(f"{marker}.../{suffix}") > max_width:
        return fit_text_label(compact, max_width)

    selected = [components[-1]]
    for component in reversed(components[:-1]):
        candidate = [component, *selected]
        text = f"{marker}.../{'/'.join(candidate)}"
        if len(text) > max_width:
            break
        selected = candidate
    return f"{marker}.../{'/'.join(selected)}"


def fit_text_label(label: str, max_width: int) -> str:
    if len(label) <= max_width:
        return label
    if max_width <= 3:
        return label[:max_width]
    return f"{label[: max_width - 3]}..."


def is_path_label(label: str) -> bool:
    return label.startswith("/") or label.startswith("~/")


def path_marker(label: str) -> str:
    return "~/" if label.startswith("~/") else "/"


def max_launch_cwd_width(screen, max_tab_length: int) -> int:
    if max_tab_length >= 48:
        return min(72, max(LAUNCH_CWD_LABEL_WIDTH, screen.columns // 3))
    return max(20, min(LAUNCH_CWD_LABEL_WIDTH, screen.columns // 5))


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
