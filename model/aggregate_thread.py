from collections import defaultdict

DEV_ACTIVITIES = {
    "PULL_REQUEST", "TESTING", "CI",
    "REVIEW", "MERGE", "COMMIT", "ISSUE",
}

# Action labels produced by ACTION_RULES that signal dev work
DEV_ACTIONS = {"MERGED", "REVIEWED", "OPENED"}

def aggregate_thread(group, dev_threshold=3.0):
    activity_contrib = defaultdict(float)
    action_contrib = defaultdict(int)

    dev_weight = 0.0

    for acts, sbert_d in zip(group["inferred_activities"], group["sbert_conf"]):
        for a in acts:
            prob = sbert_d.get(a, 1.0) if isinstance(sbert_d, dict) else 1.0
            activity_contrib[a] += prob
            if a in DEV_ACTIVITIES:
                dev_weight += 1.0  # flat weight; SBERT already filters via intersection

    for acts in group["inferred_actions"]:
        indirect_cue = 0
        for a in acts:
            action_contrib[a] += 1
            if a in DEV_ACTIONS:
                indirect_cue = 1  # cap at 1 per message
        dev_weight += indirect_cue

    if dev_weight == 0:
        thread_type = "NON_DEV"
        dominant_activity = None
    elif dev_weight < dev_threshold:
        thread_type = "COORDINATION_ONLY"
        dominant_activity = None
    else:
        thread_type = "DEV"
        dominant_activity = max(activity_contrib, key=activity_contrib.get) if activity_contrib else None

    return {
        "thread_type": thread_type,
        "dev_weight": dev_weight,
        "dominant_activity": dominant_activity,
        "activity_contrib": dict(activity_contrib),
        "action_contrib": dict(action_contrib),
        "num_messages": len(group),
    }
