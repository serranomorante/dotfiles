from __future__ import annotations

from ansible.errors import AnsibleError
from ansible.plugins.action import ActionBase


class ActionModule(ActionBase):
    TRANSFERS_FILES = False
    VALID_SEVERITIES = {"trace", "debug", "info", "warning", "error"}

    def run(self, tmp=None, task_vars=None):
        super().run(tmp, task_vars)
        args = self._task.args.copy()
        raw_params = args.get("_raw_params")
        message = args.get("msg") or args.get("message")
        severity = str(args.get("severity") or args.get("level") or "warning").lower()
        event_type = str(args.get("event_type") or "repository_event")
        if severity not in self.VALID_SEVERITIES:
            valid = ", ".join(sorted(self.VALID_SEVERITIES))
            raise AnsibleError(f"dotfiles_health_event severity must be one of: {valid}")
        if message and raw_params:
            message = f"{message} {raw_params}"
        elif raw_params:
            message = raw_params
        if not message:
            raise AnsibleError("dotfiles_health_event requires msg or message")
        message = str(message)
        event = {
            "severity": severity,
            "event_type": event_type,
            "message": message,
        }
        result = {
            "changed": False,
            "msg": message,
            "dotfiles_health_events": [event],
        }
        if severity == "warning":
            result["warnings"] = [message]
        return result
