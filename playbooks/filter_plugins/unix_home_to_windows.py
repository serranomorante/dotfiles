from ansible.plugins.filter.core import FilterModule as FModule
import re


def unix_home_to_windows(value):
    """Convert /home/user/data to Z:\\home\\user\\data"""
    return "Z:{}".format(re.sub(r"/", r"\\\\", value))


class FilterModule(FModule):
    def filters(self):
        return {"unix_home_to_windows": unix_home_to_windows}
