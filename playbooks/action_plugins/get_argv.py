# Source - https://stackoverflow.com/a
# Posted by Konstantin Suvorov, modified by community. See post 'Timeline' for change history
# Retrieved 2025-11-11, License - CC BY-SA 4.0

from ansible.plugins.action import ActionBase
import sys


class ActionModule(ActionBase):
    TRANSFERS_FILES = False

    def run(self, tmp=None, task_vars=None):
        return {"changed": False, "ansible_facts": {"argv": sys.argv}}
