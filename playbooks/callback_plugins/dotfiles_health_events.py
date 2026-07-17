from __future__ import annotations

import json
import os
import socket
import uuid
from datetime import datetime
from pathlib import Path
from typing import Any

from ansible.plugins.callback import CallbackBase
from ansible.utils.display import Display


DOCUMENTATION = r"""
callback: dotfiles_health_events
type: notification
short_description: Record Ansible warnings and failures for dotfiles-health
description:
  - Writes compact JSONL events for warnings and failures emitted by this workstation's Ansible playbooks.
options: {}
"""


_ACTIVE_CALLBACK: "CallbackModule | None" = None
_ORIGINAL_DISPLAY_WARNING = None


class CallbackModule(CallbackBase):
    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = "notification"
    CALLBACK_NAME = "dotfiles_health_events"
    CALLBACK_NEEDS_ENABLED = True

    def __init__(self) -> None:
        super().__init__()
        self.run_id = str(uuid.uuid4())
        self.playbook = ""
        self.cwd = os.getcwd()
        self._seen_warning_messages: set[str] = set()
        self._install_display_warning_hook()

    def v2_playbook_on_start(self, playbook: Any) -> None:
        self.playbook = str(getattr(playbook, "_file_name", "") or "")

    def v2_runner_on_ok(self, result: Any) -> None:
        task_result = self._clean_result(result)
        self._write_result_events(result=result, task_result=task_result)
        warnings = task_result.get("warnings") or []
        if isinstance(warnings, str):
            warnings = [warnings]
        for warning in warnings:
            self._write_warning(
                result=result,
                message=str(warning),
                event_type="task_warning",
            )

    def _write_result_events(self, *, result: Any, task_result: dict[str, Any]) -> None:
        events = task_result.get("dotfiles_health_events") or []
        if isinstance(events, dict):
            events = [events]
        for event in events:
            if not isinstance(event, dict):
                continue
            severity = self._event_severity(str(event.get("severity") or "warning"))
            message = event.get("message") or event.get("msg")
            if not message:
                continue
            compact_message = self._compact_message(str(message))
            if severity == "warning":
                self._seen_warning_messages.add(compact_message)
            self._write_event(
                severity=severity,
                result=result,
                message=compact_message,
                event_type=str(event.get("event_type") or "repository_event"),
            )

    def _install_display_warning_hook(self) -> None:
        global _ACTIVE_CALLBACK, _ORIGINAL_DISPLAY_WARNING
        _ACTIVE_CALLBACK = self
        if _ORIGINAL_DISPLAY_WARNING is not None:
            return

        _ORIGINAL_DISPLAY_WARNING = Display.warning

        def warning(display: Display, msg: str, *args: Any, **kwargs: Any) -> None:
            _ORIGINAL_DISPLAY_WARNING(display, msg, *args, **kwargs)
            callback = _ACTIVE_CALLBACK
            if callback is not None:
                callback._write_warning(
                    result=None,
                    message=str(msg),
                    event_type="display_warning",
                )

        Display.warning = warning

    def _write_warning(
        self, *, result: Any | None, message: str, event_type: str
    ) -> None:
        compact = self._compact_message(message)
        if compact in self._seen_warning_messages:
            return
        self._seen_warning_messages.add(compact)
        self._write_event(
            severity="warning",
            result=result,
            message=compact,
            event_type=event_type,
        )

    def v2_runner_on_failed(self, result: Any, ignore_errors: bool = False) -> None:
        task_result = self._clean_result(result)
        message = (
            task_result.get("msg")
            or task_result.get("stderr")
            or task_result.get("exception")
            or "Task failed"
        )
        self._write_event(
            severity="error",
            result=result,
            message=str(message),
            event_type="task_failed",
            ignored=bool(ignore_errors),
        )

    def v2_runner_on_unreachable(self, result: Any) -> None:
        task_result = self._clean_result(result)
        message = task_result.get("msg") or "Host unreachable"
        self._write_event(
            severity="error",
            result=result,
            message=str(message),
            event_type="host_unreachable",
        )

    def _clean_result(self, result: Any) -> dict[str, Any]:
        task_result = dict(getattr(result, "_result", {}) or {})
        if task_result.get("_ansible_no_log"):
            return {"msg": "Task result hidden by no_log"}
        task_result.pop("invocation", None)
        task_result.pop("diff", None)
        return task_result

    def _write_event(
        self,
        *,
        severity: str,
        result: Any | None,
        message: str,
        event_type: str,
        ignored: bool = False,
    ) -> None:
        now = datetime.now().astimezone()
        event = {
            "schema": "dotfiles.ansible-event.v1",
            "timestamp": now.isoformat(timespec="seconds"),
            "severity": severity,
            "event_type": event_type,
            "ignored": ignored,
            "host": self._host_name(result),
            "task": self._task_name(result),
            "playbook": self.playbook,
            "cwd": self.cwd,
            "run_id": self.run_id,
            "controller": socket.gethostname(),
            "message": self._compact_message(message),
        }
        self._append_event(now, event)

    def _append_event(self, now: datetime, event: dict[str, Any]) -> None:
        events_dir = self._events_dir() / "events"
        events_dir.mkdir(parents=True, exist_ok=True)
        event_file = events_dir / f"{now.date().isoformat()}.jsonl"
        with event_file.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(event, sort_keys=True, ensure_ascii=False) + "\n")

    def _events_dir(self) -> Path:
        configured = os.environ.get("DOTFILES_ANSIBLE_EVENTS_DIR")
        if configured:
            return Path(configured).expanduser()
        return Path.home() / ".local" / "state" / "dotfiles" / "ansible-events"

    def _host_name(self, result: Any | None) -> str:
        host = getattr(result, "_host", None)
        return str(getattr(host, "name", "") or "")

    def _task_name(self, result: Any | None) -> str:
        task = getattr(result, "_task", None)
        return str(getattr(task, "name", "") or "")

    def _compact_message(self, message: str) -> str:
        return " ".join(str(message).split())[:1000]

    def _event_severity(self, severity: str) -> str:
        normalized = severity.lower()
        if normalized in {"trace", "debug", "info", "warning", "error"}:
            return normalized
        return "warning"
