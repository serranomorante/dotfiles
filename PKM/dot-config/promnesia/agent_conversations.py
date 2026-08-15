'''
Promnesia source that indexes web links referenced inside AI agent
conversations (claude, codex, gemini, opencode).

Each conversation is scanned for its session id, title, working directory and
timestamp (reusing the layout and parsing conventions of
utilities/bin/agent-session-store), then every message is searched for URLs.
For each distinct link found a Visit is emitted with:

- url      -- the referenced link
- locator  -- title: "<provider>: <conversation title>"
              href: editor:///agent_conversation/<cwd>/<session-id>
              which routes through nvr_open_nvim.sh -> open_in_nvim
              agent_conversation -> agent-tasks to resume the session in Neovim
- context  -- the message text around the link

Configured from ~/.config/promnesia/config.py as:

    Source(
        agent_conversations.index,
        '~/.claude/projects',
        '~/.codex/sessions',
        '~/.gemini/tmp',
        '~/.local/share/opencode',
        name='agent-conversations',
    )

If no roots are passed the provider default locations above are used.
'''

from __future__ import annotations

import json
import re
import sqlite3
import urllib.parse
from collections.abc import Iterator, Sequence
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from promnesia.common import Loc, PathIsh, Results, Visit, extract_urls

# Root per provider, mirrors utilities/dot-local/share/dotfiles/agent-session-store/main.go
PROVIDER_ROOTS = {
    'claude': '~/.claude/projects',
    'codex': '~/.codex/sessions',
    'gemini': '~/.gemini/tmp',
    'opencode': '~/.local/share/opencode',
}

# Bounded read so huge transcripts cannot balloon index memory.
READ_BYTES = 8 * 1024 * 1024
TITLE_MAX = 200
CONTEXT_MAX = 700
MESSAGE_MAX = 4000
MESSAGES_MAX = 300
# A unix epoch in milliseconds is far larger than any plausible seconds epoch.
MS_EPOCH = 100_000_000_000

GENERATED_PREFIXES = (
    '# AGENTS.md instructions for ',
    '<environment_context>',
    '<permissions instructions>',
    '<collaboration_mode>',
    '<skills_instructions>',
    '<command-name>',
    '<local-command-stdout>',
    'The following is the Codex agent history',
)


@dataclass(frozen=True, kw_only=True)
class Conversation:
    provider: str
    id: str
    title: str
    cwd: str
    dt: datetime
    messages: tuple[str, ...]


def _compact(text: str, limit: int = TITLE_MAX) -> str:
    joined = ' '.join(text.split())
    if len(joined) > limit:
        joined = joined[:limit].rstrip() + '...'
    return joined


def _is_generated(text: str) -> bool:
    t = _compact(text)
    return any(t.startswith(p) for p in GENERATED_PREFIXES)


def _norm_title(text: str) -> str:
    t = _compact(text)
    if not t or _is_generated(t):
        return ''
    return t


def _content_text(content) -> str:
    parts: list[str] = []

    def walk(value) -> None:
        if isinstance(value, str):
            parts.append(value)
        elif isinstance(value, list):
            for item in value:
                walk(item)
        elif isinstance(value, dict):
            if isinstance(value.get('text'), str):
                parts.append(value['text'])
            elif isinstance(value.get('content'), (str, list, dict)):
                walk(value['content'])

    walk(content)
    return '\n'.join(parts)


def _parse_dt(value) -> datetime | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        number = float(value)
        if number <= 0:
            return None
        if number > MS_EPOCH:
            return datetime.fromtimestamp(number / 1000, tz=timezone.utc)
        return datetime.fromtimestamp(number, tz=timezone.utc)
    if isinstance(value, str):
        try:
            return datetime.fromisoformat(value.replace('Z', '+00:00'))
        except ValueError:
            return None
    return None


def _mtime_dt(path: Path) -> datetime:
    try:
        return datetime.fromtimestamp(path.stat().st_mtime, tz=timezone.utc)
    except OSError:
        return datetime.min.replace(tzinfo=timezone.utc)


def _iter_jsonl(path: Path, max_bytes: int = READ_BYTES) -> Iterator[dict]:
    try:
        data = path.read_bytes()
    except OSError:
        return
    data = data[:max_bytes]
    for line in data.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            yield json.loads(line)
        except json.JSONDecodeError:
            continue


def _claude_conversation(path: Path) -> Conversation | None:
    session_id = None
    cwd = None
    ts = None
    ai_title = ''
    title_from_prompt = ''
    last_prompt = ''
    messages: list[str] = []
    for item in _iter_jsonl(path):
        if session_id is None:
            value = item.get('sessionId')
            if isinstance(value, str):
                session_id = value
        if cwd is None:
            value = item.get('cwd')
            if isinstance(value, str):
                cwd = value
        if ts is None:
            value = item.get('timestamp')
            if isinstance(value, str):
                ts = value
        if not ai_title:
            value = item.get('aiTitle')
            if isinstance(value, str):
                ai_title = _norm_title(value)
        if not last_prompt:
            value = item.get('lastPrompt')
            if isinstance(value, str):
                last_prompt = _norm_title(value)
        message = item.get('message')
        if isinstance(message, dict):
            text = _content_text(message.get('content'))
            if text:
                if message.get('role') == 'user' and not title_from_prompt:
                    title_from_prompt = _norm_title(text)
                messages.append(text[:MESSAGE_MAX])
                if len(messages) >= MESSAGES_MAX:
                    break
    if not messages:
        return None
    if session_id is None:
        session_id = path.stem
    if not session_id:
        return None
    title = ai_title or title_from_prompt or last_prompt
    dt = _parse_dt(ts) or _mtime_dt(path)
    return Conversation(
        provider='claude',
        id=session_id,
        title=title,
        cwd=cwd or '',
        dt=dt,
        messages=tuple(messages),
    )


def _codex_conversation(path: Path) -> Conversation | None:
    session_id = None
    cwd = None
    ts = None
    thread_source = None
    title_from_prompt = ''
    messages: list[str] = []
    for item in _iter_jsonl(path):
        item_type = item.get('type')
        payload = item.get('payload')
        if not isinstance(payload, dict):
            continue
        if item_type == 'session_meta':
            if session_id is None:
                value = payload.get('id')
                if isinstance(value, str):
                    session_id = value
            if cwd is None:
                value = payload.get('cwd')
                if isinstance(value, str):
                    cwd = value
            if ts is None:
                value = payload.get('timestamp')
                if isinstance(value, str):
                    ts = value
            thread_source = payload.get('thread_source')
        elif item_type == 'response_item' and payload.get('type') == 'message':
            role = payload.get('role')
            text = _content_text(payload.get('content'))
            if not text:
                continue
            if role == 'user' and not _is_generated(text):
                if not title_from_prompt:
                    title_from_prompt = _norm_title(text)
                messages.append(text[:MESSAGE_MAX])
            elif role == 'assistant':
                messages.append(text[:MESSAGE_MAX])
            if len(messages) >= MESSAGES_MAX:
                break
        elif item_type == 'event_msg' and payload.get('type') == 'user_message':
            value = payload.get('message')
            if isinstance(value, str) and value:
                if not title_from_prompt:
                    title_from_prompt = _norm_title(value)
                messages.append(value[:MESSAGE_MAX])
                if len(messages) >= MESSAGES_MAX:
                    break
    if thread_source == 'subagent':
        return None
    if not messages:
        return None
    if session_id is None:
        session_id = path.stem
    if not session_id:
        return None
    dt = _parse_dt(ts) or _mtime_dt(path)
    return Conversation(
        provider='codex',
        id=session_id,
        title=title_from_prompt,
        cwd=cwd or '',
        dt=dt,
        messages=tuple(messages),
    )


def _gemini_cwd(path: Path) -> str:
    project_dir = path.parents[1]
    root_file = project_dir / '.project_root'
    try:
        value = root_file.read_text().strip()
    except OSError:
        value = ''
    if value:
        return value
    return str(project_dir)


def _gemini_messages(messages) -> list[str]:
    collected: list[str] = []
    if not isinstance(messages, list):
        return collected
    for message in messages:
        if not isinstance(message, dict):
            continue
        content = message.get('content')
        text = content if isinstance(content, str) else _content_text(content)
        if text:
            collected.append(text[:MESSAGE_MAX])
        if len(collected) >= MESSAGES_MAX:
            break
    return collected


def _gemini_conversation(path: Path) -> Conversation | None:
    try:
        data = path.read_bytes()[:READ_BYTES]
    except OSError:
        return None
    session_id = None
    ts = None
    messages: list[str] = []
    if path.suffix == '.json':
        try:
            item = json.loads(data)
        except json.JSONDecodeError:
            item = None
        if isinstance(item, dict):
            value = item.get('sessionId')
            if isinstance(value, str):
                session_id = value
            value = item.get('startTime')
            if isinstance(value, str):
                ts = value
            messages = _gemini_messages(item.get('messages'))
    else:
        for line in data.splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                item = json.loads(line)
            except json.JSONDecodeError:
                continue
            if not isinstance(item, dict):
                continue
            if session_id is None:
                value = item.get('sessionId')
                if isinstance(value, str):
                    session_id = value
            if ts is None:
                value = item.get('startTime')
                if isinstance(value, str):
                    ts = value
            if isinstance(item.get('messages'), list):
                messages = _gemini_messages(item.get('messages'))
    if not messages:
        return None
    if session_id is None:
        session_id = path.stem
    if not session_id:
        return None
    dt = _parse_dt(ts) or _mtime_dt(path)
    title = _norm_title(messages[0])
    return Conversation(
        provider='gemini',
        id=session_id,
        title=title,
        cwd=_gemini_cwd(path),
        dt=dt,
        messages=tuple(messages),
    )


def _opencode_text(value) -> str:
    parts: list[str] = []

    def walk(item) -> None:
        if isinstance(item, str):
            if item:
                parts.append(item)
        elif isinstance(item, list):
            for child in item:
                walk(child)
        elif isinstance(item, dict):
            kind = item.get('type')
            if kind == 'text' or kind == 'reasoning':
                if isinstance(item.get('text'), str):
                    parts.append(item['text'])
            elif kind == 'tool':
                state = item.get('state')
                if isinstance(state, dict):
                    output = state.get('output')
                    if isinstance(output, str) and output:
                        parts.append(output)
                    state_input = state.get('input')
                    if isinstance(state_input, dict):
                        command = state_input.get('command')
                        if isinstance(command, str) and command:
                            parts.append(command)
            elif kind == 'subtask':
                for key in ('description', 'prompt'):
                    if isinstance(item.get(key), str):
                        parts.append(item[key])

    walk(value)
    return '\n'.join(parts)


def _opencode_conversations(db_path: Path) -> Iterator[Conversation]:
    connection = None
    for uri in (f'file:{db_path}?mode=ro', f'file:{db_path}?immutable=1'):
        try:
            connection = sqlite3.connect(uri, uri=True)
            connection.execute('PRAGMA query_only = ON')
            break
        except sqlite3.Error:
            connection = None
    if connection is None:
        return
    try:
        rows = connection.execute(
            'SELECT id, title, directory, time_created FROM session ORDER BY time_created'
        ).fetchall()
        for session_id, title, directory, created in rows:
            if not isinstance(session_id, str) or not session_id:
                continue
            messages: list[str] = []
            for (data,) in connection.execute(
                'SELECT data FROM part WHERE session_id = ? ORDER BY time_created', (session_id,)
            ):
                if not isinstance(data, str):
                    continue
                try:
                    part = json.loads(data)
                except json.JSONDecodeError:
                    continue
                text = _opencode_text(part)
                if text:
                    messages.append(text[:MESSAGE_MAX])
                if len(messages) >= MESSAGES_MAX:
                    break
            if not messages:
                continue
            dt = _parse_dt(created) or _mtime_dt(db_path)
            yield Conversation(
                provider='opencode',
                id=session_id,
                title=_norm_title(title) if isinstance(title, str) else '',
                cwd=directory if isinstance(directory, str) else '',
                dt=dt,
                messages=tuple(messages),
            )
    finally:
        connection.close()


def _detect_provider(root: Path) -> str | None:
    low = str(root).lower()
    if '.claude' in low:
        return 'claude'
    if '.codex' in low:
        return 'codex'
    if '.gemini' in low:
        return 'gemini'
    if 'opencode' in low:
        return 'opencode'
    return None


def _parse_known_file(path: Path, provider: str) -> Conversation | None:
    name = path.name
    if provider == 'claude':
        return _claude_conversation(path) if name.endswith('.jsonl') else None
    if provider == 'codex':
        return _codex_conversation(path) if name.endswith('.jsonl') else None
    if provider == 'gemini':
        if name.startswith('session-') and (name.endswith('.json') or name.endswith('.jsonl')):
            return _gemini_conversation(path)
        return None
    return None


def _parse_unknown_file(path: Path) -> Conversation | None:
    for parser in (_gemini_conversation, _claude_conversation, _codex_conversation):
        try:
            conversation = parser(path)
        except Exception:
            conversation = None
        if conversation is not None:
            return conversation
    return None


def _iter_conversations(roots: Sequence[PathIsh]) -> Iterator[Conversation]:
    for raw in roots:
        root = Path(raw).expanduser()
        if not root.exists():
            continue
        provider = _detect_provider(root)
        if provider == 'opencode' or root.is_file() and root.name == 'opencode.db':
            db_path = root if root.is_file() else root / 'opencode.db'
            if db_path.exists():
                yield from _opencode_conversations(db_path)
            continue
        if root.is_file():
            conversation = _parse_known_file(root, provider) if provider else _parse_unknown_file(root)
            if conversation is not None:
                yield conversation
            continue
        for path in sorted(root.rglob('*')):
            if not path.is_file():
                continue
            conversation = _parse_known_file(path, provider) if provider else _parse_unknown_file(path)
            if conversation is not None:
                yield conversation


def _agent_href(conversation: Conversation) -> str:
    # editor:///agent_conversation/<cwd>/<session-id>. nvr_open_nvim.sh routes
    # this back to open_in_nvim --cwd <cwd> agent_conversation <session-id>.
    # The cwd is stripped of its leading slash so the separator is unambiguous;
    # the router re-prepends it.
    cwd = (conversation.cwd or str(Path.home())).strip('/') or '/'
    encoded = urllib.parse.quote(cwd, safe='/')
    return f'editor:///agent_conversation/{encoded}/{conversation.id}'


def _locator_title(conversation: Conversation) -> str:
    title = conversation.title or conversation.id
    return f'{conversation.provider}: {title}'


def _snippet(text: str, url: str) -> str:
    index = text.find(url)
    if index < 0:
        index = 0
    start = max(0, index - CONTEXT_MAX // 2)
    end = min(len(text), index + len(url) + CONTEXT_MAX // 2)
    snippet = text[start:end].strip()
    if start > 0:
        snippet = '...' + snippet
    if end < len(text):
        snippet = snippet + '...'
    return snippet


_URL_HINT = ('://', 'www.')
_SCHEME_RE = re.compile(r'^(?:https?|ftp)://|^www\.', re.IGNORECASE)


def _message_links(message: str) -> tuple[str, ...]:
    # Cheap pre-filter: almost no message carries a URL, and urlextract is the
    # dominant cost. Only run the full matcher when a hint is present. Keep the
    # common web schemes; bare domains and filenames are too noisy for this use.
    if not any(hint in message for hint in _URL_HINT):
        return ()
    return tuple(
        url
        for url in extract_urls(message, syntax='markdown')
        if _SCHEME_RE.match(url)
    )


def _conversation_visits(conversation: Conversation) -> Iterator[Visit]:
    locator = Loc(title=_locator_title(conversation), href=_agent_href(conversation))
    seen: set[str] = set()
    for message in conversation.messages:
        for url in _message_links(message):
            if url in seen:
                continue
            seen.add(url)
            yield Visit(
                url=url,
                dt=conversation.dt,
                locator=locator,
                context=_snippet(message, url),
            )


def index(*roots: PathIsh) -> Results:
    '''
    Yield a Visit for every distinct link referenced in an agent conversation.

    :param roots: directories (or files) to scan. When empty, the provider
                  default locations are scanned.
    '''
    if len(roots) == 0:
        roots = tuple(PROVIDER_ROOTS.values())
    for conversation in _iter_conversations(roots):
        try:
            yield from _conversation_visits(conversation)
        except Exception as e:
            yield e
