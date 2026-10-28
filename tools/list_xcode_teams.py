#!/usr/bin/env python3
"""List the development teams of the Apple IDs signed in to Xcode.

Reads Xcode's preferences as an XML plist on stdin, as produced by
    defaults export com.apple.dt.Xcode -
and prints one "TEAMID<TAB>description" line per team, personal teams first.
Prints nothing if the preferences can't be read.
"""

import plistlib
import sys


def main():
    try:
        prefs = plistlib.loads(sys.stdin.buffer.read())
    except Exception:
        return
    if not isinstance(prefs, dict):
        return

    teams = {}
    # Newer Xcode versions use the first key, older ones the second.
    for key in ("IDEProvisioningTeamByIdentifier", "IDEProvisioningTeams"):
        accounts = prefs.get(key)
        if not isinstance(accounts, dict):
            continue
        for entries in accounts.values():
            if not isinstance(entries, list):
                continue
            for team in entries:
                if not isinstance(team, dict):
                    continue
                team_id = team.get("teamID")
                if not team_id or team_id in teams:
                    continue
                name = team.get("teamName") or team_id
                personal = bool(team.get("isFreeProvisioningTeam"))
                if personal:
                    label = f"{name} (Personal Team)"
                elif team.get("teamType"):
                    label = f"{name} ({team['teamType']})"
                else:
                    label = name
                teams[team_id] = (not personal, name.lower(), label)

    for team_id, (_order, _name, label) in sorted(teams.items(), key=lambda t: t[1]):
        print(f"{team_id}\t{label}")


if __name__ == "__main__":
    main()
