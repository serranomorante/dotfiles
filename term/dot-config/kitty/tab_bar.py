"""Custom Kitty tab bar drawing.

Keep the normal powerline tab rendering and use the otherwise-empty right side
of the tab bar for a compact local date/time readout.
"""

from datetime import datetime
from pathlib import Path
from re import compile as compile_regex
from shlex import split as shlex_split
from sys import argv as fallback_argv

from kitty.tab_bar import (
    DrawData,
    ExtraData,
    TabAccessor,
    TabBarData,
    as_rgb,
    color_as_int,
    powerline_symbols,
)
from kitty.fast_data_types import get_boss


LAUNCH_CWD_FG = 0x6F9FB5
INACTIVE_PATH_LABEL_WIDTH = 24
POWERLINE_TITLE_SAFETY_CELLS = 1
IDLE_PROCESS_NAMES = frozenset(("bash", "dash", "fish", "nu", "sh", "zsh"))
IGNORED_FIXED_TITLES = frozenset(("base-title",))
SHELL_COMMAND_PREFIXES = frozenset(("builtin", "command", "doas", "env", "exec", "firejail", "noglob", "sudo", "time"))
SHELL_BUILTIN_TITLES = frozenset(
    ("alias", "bg", "cd", "declare", "export", "fg", "history", "jobs", "popd", "pushd", "unset")
)
SHELL_DYNAMIC_TITLE_RE = compile_regex(r"^[^@\s]+@[^:\s]+:(?:~|/|[A-Za-z]:)")
SHELL_ASSIGNMENT_RE = compile_regex(r"^[A-Za-z_][A-Za-z0-9_]*=.*")
_current_max_tab_length: int | None = None
_tab_label_cache: dict[int, str] = {}


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
    tab_bg = screen.cursor.bg
    tab_fg = screen.cursor.fg

    if index == 1:
        draw_left_launch_cwd(draw_data, screen)
        before = screen.cursor.x

    global _current_max_tab_length
    previous_max_tab_length = _current_max_tab_length
    _current_max_tab_length = title_cell_budget(max_tab_length, before)
    try:
        end = draw_tab_powerline(
            draw_data,
            screen,
            tab,
            before,
            max_tab_length,
            index,
            extra_data,
            tab_bg,
            tab_fg,
        )
    finally:
        _current_max_tab_length = previous_max_tab_length

    if is_last and not extra_data.for_layout:
        draw_right_datetime(draw_data, screen)
    return end


def draw_tab_powerline(
    draw_data: DrawData,
    screen,
    tab: TabBarData,
    before: int,
    max_tab_length: int,
    index: int,
    extra_data: ExtraData,
    tab_bg,
    tab_fg,
) -> int:
    default_bg = as_rgb(color_as_int(draw_data.default_bg))
    if extra_data.next_tab:
        next_tab_bg = as_rgb(draw_data.tab_bg(extra_data.next_tab))
        needs_soft_separator = next_tab_bg == tab_bg
    else:
        next_tab_bg = default_bg
        needs_soft_separator = False

    separator_symbol, soft_separator_symbol = powerline_symbols.get(
        draw_data.powerline_style,
        ("", ""),
    )
    if screen.cursor.x == 0:
        screen.cursor.bg = tab_bg
        screen.draw(" ")

    screen.cursor.bg = tab_bg
    screen.cursor.fg = tab_fg
    if max_tab_length <= 3:
        screen.draw("…")
    else:
        screen.draw(
            render_tab_title(
                tab_title_data(draw_data, tab, index),
                _current_max_tab_length,
            )
        )

    if not needs_soft_separator:
        screen.draw(" ")
        screen.cursor.fg = tab_bg
        screen.cursor.bg = next_tab_bg
        screen.draw(separator_symbol)
    else:
        previous_fg = screen.cursor.fg
        if tab_bg == tab_fg:
            screen.cursor.fg = default_bg
        elif (
            tab_bg != default_bg
            and draw_data.inactive_bg.contrast(draw_data.default_bg)
            < draw_data.inactive_bg.contrast(draw_data.inactive_fg)
        ):
            screen.cursor.fg = default_bg
        screen.draw(f" {soft_separator_symbol}")
        screen.cursor.fg = previous_fg

    end = screen.cursor.x
    if end < screen.columns:
        screen.draw(" ")
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
    return render_tab_title(data, _current_max_tab_length)


def tab_title_data(draw_data: DrawData, tab: TabBarData, index: int) -> dict:
    window = active_window_for_tab_id(tab.tab_id) if tab.is_active else None
    return {
        "index": index,
        "layout_name": tab.layout_name,
        "num_windows": tab.num_windows,
        "num_window_groups": tab.num_window_groups,
        "title": tab.title,
        "tab": TabAccessor(tab.tab_id) if tab.is_active and tab.tab_id >= 0 else tab,
        "tab_id": tab.tab_id,
        "is_active": tab.is_active,
        "bell_symbol": draw_data.bell_on_tab if tab.needs_attention else "",
        "activity_symbol": draw_data.tab_activity_symbol if tab.has_activity_since_last_focus else "",
        "window": window,
        "foreground_processes": foreground_processes_from_window(window),
        "last_reported_cmdline": getattr(window, "last_cmd_cmdline", "") if window is not None else "",
        "at_prompt": bool(getattr(window, "at_prompt", True)) if window is not None else True,
        "active_wd": active_window_cwd(window),
    }


def render_tab_title(data: dict, max_width: int | None) -> str:
    title = data["title"]
    tab = data["tab"]
    is_active = getattr(tab, "is_active", data.get("is_active", False))
    stack_icon = "  " if data["layout_name"] == "stack" and data["num_windows"] > 1 else ""
    prefix = f"{data.get('bell_symbol', '')}{data.get('activity_symbol', '')}{stack_icon}{data['index']}. "
    label_width = available_label_width(len(prefix)) if max_width is None else max(0, max_width - len(prefix))
    label = fit_tab_label(tab_label(data) or title, label_width, active=is_active)
    rendered = f"{prefix}{label}"
    if max_width is not None and len(rendered) > max_width:
        return fit_text_label(rendered, max_width)
    return rendered


def tab_label(data: dict) -> str:
    title = data["title"]
    generated_title = is_generated_terminal_title(data, title)
    if title and not generated_title:
        return cache_tab_label(data, title)

    if not tab_data_is_active(data):
        cached = cached_tab_label(data)
        if cached:
            return cached
        return cheap_generated_title_label(title)

    tab = data["tab"]
    process = foreground_process_label_from_data(data)
    if process:
        return cache_tab_label(data, process)

    process = foreground_process_label(data.get("active_exe", "") or getattr(tab, "active_exe", "") or "")
    if process:
        return cache_tab_label(data, process)

    process = reported_command_label_from_data(data)
    if process:
        return cache_tab_label(data, process)

    process = shell_command_title_label(title) if generated_title and not active_window_at_prompt(data) else ""
    if process:
        return cache_tab_label(data, process)

    tab_cwd = normalize_existing_path(data.get("active_wd", "") or getattr(tab, "active_wd", "") or "")
    if not tab_cwd:
        return title

    launch_cwd = launch_cwd_from_argv()
    if not launch_cwd:
        return tab_cwd

    relation = path_relation(tab_cwd, launch_cwd)
    if relation and relation != ".":
        return cache_tab_label(data, f"/{relation}")
    return cache_tab_label(data, tab_cwd)


def tab_data_is_active(data: dict) -> bool:
    tab = data["tab"]
    return bool(getattr(tab, "is_active", data.get("is_active", False)))


def cached_tab_label(data: dict) -> str:
    tab_id = data.get("tab_id")
    return _tab_label_cache.get(tab_id, "") if tab_id is not None else ""


def cache_tab_label(data: dict, label: str) -> str:
    tab_id = data.get("tab_id")
    if tab_id is not None and label:
        _tab_label_cache[tab_id] = label
    return label


def cheap_generated_title_label(title: str) -> str:
    if not title or title in IGNORED_FIXED_TITLES:
        return ""
    command_label = shell_command_title_label(title)
    if command_label:
        return command_label
    return title if is_ignored_terminal_title(title) else ""


def process_label(exe: str) -> str:
    return Path(exe).name


def foreground_process_label(exe: str) -> str:
    name = process_label(exe)
    if name in IDLE_PROCESS_NAMES:
        return ""
    return name


def foreground_process_label_from_data(data: dict) -> str:
    for process in reversed(foreground_processes_from_data(data)):
        cmdline = process.get("cmdline") or ()
        exe = cmdline[0] if cmdline else ""
        label = foreground_process_label(exe)
        if label:
            return label
    return ""


def foreground_processes_from_data(data: dict) -> list[dict]:
    if "foreground_processes" in data:
        return data["foreground_processes"] or []

    return foreground_processes_from_window(active_window_from_data(data))


def foreground_processes_from_window(window) -> list[dict]:
    if window is None:
        return []
    try:
        return window.child.foreground_processes
    except Exception:
        return []


def active_window_from_data(data: dict):
    if "window" in data:
        return data["window"]

    tab_id = data.get("tab_id")
    return active_window_for_tab_id(tab_id)


def active_window_for_tab_id(tab_id: int | None):
    if tab_id is None:
        return None
    try:
        boss = get_boss()
        tab = boss.tab_for_id(tab_id) if boss is not None else None
        return tab.active_window if tab is not None else None
    except Exception:
        return None


def active_window_cwd(window) -> str:
    if window is None:
        return ""
    try:
        child = window.child
        return child.current_cwd or child.cwd or ""
    except Exception:
        return ""


def reported_command_label_from_data(data: dict) -> str:
    if active_window_at_prompt(data):
        return ""
    return command_line_label(last_reported_cmdline_from_data(data))


def last_reported_cmdline_from_data(data: dict) -> str:
    if "last_reported_cmdline" in data:
        return data["last_reported_cmdline"] or ""

    window = active_window_from_data(data)
    return getattr(window, "last_cmd_cmdline", "") if window is not None else ""


def active_window_at_prompt(data: dict) -> bool:
    if "at_prompt" in data:
        return bool(data["at_prompt"])

    window = active_window_from_data(data)
    return bool(getattr(window, "at_prompt", False)) if window is not None else False


def is_generated_terminal_title(data: dict, title: str) -> bool:
    if not title:
        return False
    if is_ignored_terminal_title(title):
        return True

    if not looks_like_shell_command_title(title):
        return False

    reported_cmdline = last_reported_cmdline_from_data(data)
    if reported_cmdline and normalize_command_text(reported_cmdline) == normalize_command_text(title):
        return True

    return (
        not active_window_at_prompt(data)
        and shell_command_title_label(title) != ""
        and looks_like_shell_command_title(title)
    )


def command_line_label(command_line: str) -> str:
    if not command_line:
        return ""
    try:
        args = shlex_split(command_line)
    except ValueError:
        args = command_line.split()
    return command_argv_label(args)


def command_argv_label(args: list[str]) -> str:
    i = 0
    while i < len(args):
        arg = args[i]
        name = process_label(arg)
        if SHELL_ASSIGNMENT_RE.match(arg):
            i += 1
            continue
        if name in SHELL_COMMAND_PREFIXES:
            i += 1
            while i < len(args) and (args[i].startswith("-") or SHELL_ASSIGNMENT_RE.match(args[i])):
                i += 1
            continue
        if name in SHELL_BUILTIN_TITLES:
            return ""
        return foreground_process_label(arg)
    return ""


def normalize_command_text(command_line: str) -> str:
    try:
        return " ".join(shlex_split(command_line))
    except ValueError:
        return " ".join(command_line.split())


def shell_command_title_label(title: str) -> str:
    if not title or is_ignored_terminal_title(title):
        return ""
    return command_line_label(title)


def looks_like_shell_command_title(title: str) -> bool:
    return any(char.isspace() for char in title) or "/" in title


def is_ignored_terminal_title(title: str) -> bool:
    return (
        title in IGNORED_FIXED_TITLES
        or title == "~"
        or title.startswith("~/")
        or title.startswith("/")
        or SHELL_DYNAMIC_TITLE_RE.match(title) is not None
    )


def title_cell_budget(max_tab_length: int, before: int) -> int:
    powerline_padding = 1 if before == 0 else 2
    return max(0, max_tab_length - powerline_padding - POWERLINE_TITLE_SAFETY_CELLS)


def available_label_width(prefix_width: int) -> int:
    if _current_max_tab_length is None:
        return 10_000
    return max(0, _current_max_tab_length - prefix_width)


def fit_tab_label(label: str, max_width: int, active: bool) -> str:
    if max_width <= 0:
        return ""
    if len(label) <= max_width:
        return label
    if is_path_label(label):
        path_width = max_width if active else min(max_width, INACTIVE_PATH_LABEL_WIDTH)
        return fit_text_label(label, path_width)
    return fit_text_label(label, max_width)


def fit_path_label(label: str, max_width: int, active: bool) -> str:
    if max_width <= 0:
        return ""
    if len(label) <= max_width:
        return label
    if max_width <= 4:
        return label[-max_width:]

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
    if max_width <= 0:
        return ""
    if len(label) <= max_width:
        return label
    if max_width <= 3:
        return label[-max_width:]
    return f"...{label[-(max_width - 3):]}"


def is_path_label(label: str) -> bool:
    return label.startswith("/") or label.startswith("~/")


def path_marker(label: str) -> str:
    return "~/" if label.startswith("~/") else "/"


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
