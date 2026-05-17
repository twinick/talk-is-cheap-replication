from collections import defaultdict
from .config_analysis import ACTIVITY_RULES, ACTION_RULES

def tag_message(text: str):
    tokens = text.split()

    activity_conf = defaultdict(int)
    action_conf = defaultdict(int)

    for t in tokens:
        for a, kws in ACTIVITY_RULES.items():
            if t in kws:
                activity_conf[a] += 1

        for a, kws in ACTION_RULES.items():
            if t in kws:
                action_conf[a] += 1

    return dict(activity_conf), dict(action_conf)