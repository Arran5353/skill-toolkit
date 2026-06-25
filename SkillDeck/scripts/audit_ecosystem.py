#!/usr/bin/env python3
"""
SkillDeck ecosystem audit.

Surveys real Claude Code plugins across every registered marketplace and reports
which skill/command/MCP layouts SkillDeck's scanner would (or would NOT) detect —
so we find format gaps proactively instead of one bug report at a time.

It mirrors SkillDeck's detection rules:
  - skills:   <root>/skills/<name>/SKILL.md   (standard)
              + any path declared in plugin.json "skills"
              + (audit-only) any SKILL.md found anywhere = potential gap
  - commands: <root>/commands/*.md
  - mcp:      <root>/.mcp.json  (or "mcpServers" wrapper)

Usage:
  python3 scripts/audit_ecosystem.py            # audit local (already-cloned) sources
  python3 scripts/audit_ecosystem.py --clone N  # also shallow-clone up to N git-subdir plugins to inspect

Output: a summary table + a list of "GAP" plugins whose content the standard
scanner would miss, written to scripts/audit-report.md
"""
import json, os, sys, subprocess, tempfile, shutil, glob
from collections import Counter

HOME = os.path.expanduser("~")
MP_DIR = f"{HOME}/.claude/plugins/marketplaces"
REPORT = os.path.join(os.path.dirname(__file__), "audit-report.md")

def load_manifests():
    out = []
    for f in glob.glob(f"{MP_DIR}/*/.claude-plugin/marketplace.json"):
        try:
            d = json.load(open(f))
        except Exception as e:
            out.append(("<unparseable>", f, [], str(e))); continue
        mp_root = os.path.dirname(os.path.dirname(f))  # the marketplace repo root
        out.append((d.get("name", "?"), mp_root, d.get("plugins", []), None))
    return out

def detect_layout(plugin_dir):
    """Given a plugin source dir, return what a scanner finds + whether content is hidden."""
    found = {"skills_standard": 0, "skills_declared": 0, "commands": 0, "mcp": 0}
    notes = []
    if not os.path.isdir(plugin_dir):
        return found, ["dir-missing"]
    # standard skills
    sdir = os.path.join(plugin_dir, "skills")
    if os.path.isdir(sdir):
        for sub in os.listdir(sdir):
            if os.path.isfile(os.path.join(sdir, sub, "SKILL.md")):
                found["skills_standard"] += 1
    # commands
    cdir = os.path.join(plugin_dir, "commands")
    if os.path.isdir(cdir):
        found["commands"] = len([x for x in os.listdir(cdir) if x.endswith(".md")])
    # mcp
    if os.path.isfile(os.path.join(plugin_dir, ".mcp.json")):
        found["mcp"] = 1
    # plugin.json declared skills (non-standard paths)
    pj = os.path.join(plugin_dir, ".claude-plugin", "plugin.json")
    if os.path.isfile(pj):
        try:
            pjd = json.load(open(pj))
            sk = pjd.get("skills")
            paths = [sk] if isinstance(sk, str) else (sk or [])
            for rel in paths:
                p = os.path.normpath(os.path.join(plugin_dir, rel))
                if os.path.isfile(os.path.join(p, "SKILL.md")):
                    found["skills_declared"] += 1
        except Exception:
            notes.append("plugin.json-unparseable")
    # GAP DETECTION: any SKILL.md anywhere the standard scanner wouldn't reach
    all_skillmd = glob.glob(os.path.join(plugin_dir, "**", "SKILL.md"), recursive=True)
    standard_paths = set(glob.glob(os.path.join(plugin_dir, "skills", "*", "SKILL.md")))
    hidden = [p for p in all_skillmd if p not in standard_paths
              and "/skills/" not in p.replace(plugin_dir, "")]  # not under a standard skills dir
    if hidden and found["skills_declared"] == 0:
        notes.append(f"HIDDEN-skills:{len(hidden)}")  # SKILL.md exists in a place we don't scan
    return found, notes

def resolve_local(mp_root, src):
    """Return a local dir for the plugin if its source is a local relative path; else None."""
    if isinstance(src, str):                      # "./foo"
        return os.path.normpath(os.path.join(mp_root, src))
    if isinstance(src, dict) and src.get("source") in ("local", None) and src.get("path"):
        return os.path.normpath(os.path.join(mp_root, src["path"]))
    return None

def main():
    clone_n = 0
    if "--clone" in sys.argv:
        clone_n = int(sys.argv[sys.argv.index("--clone")+1])

    manifests = load_manifests()
    rows = []          # (mp, plugin, found, notes, resolved?)
    gaps = []
    git_subdir = []    # plugins whose source is an external git repo (need clone to inspect)

    for mp, mp_root, plugins, err in manifests:
        if err:
            rows.append((mp, "<manifest>", {}, [f"manifest-error:{err}"], False)); continue
        for p in plugins:
            name = p.get("name", "?")
            src = p.get("source")
            local = resolve_local(mp_root, src)
            if local and os.path.isdir(local):
                found, notes = detect_layout(local)
                rows.append((mp, name, found, notes, True))
                if any(n.startswith("HIDDEN") for n in notes):
                    gaps.append((mp, name, notes))
            else:
                git_subdir.append((mp, name, src))
                rows.append((mp, name, {}, ["external-git (not inspected locally)"], False))

    # optional: shallow-clone a sample of external plugins to inspect their real layout
    cloned_findings = []
    if clone_n and git_subdir:
        tmp = tempfile.mkdtemp(prefix="sd-audit-")
        for mp, name, src in git_subdir[:clone_n]:
            if not isinstance(src, dict) or not src.get("url"): continue
            url = src["url"]; sub = src.get("path", "")
            dest = os.path.join(tmp, name)
            try:
                subprocess.run(["git","clone","--depth","1","--quiet",url,dest],
                               timeout=60, check=True)
                pdir = os.path.join(dest, sub) if sub else dest
                found, notes = detect_layout(pdir)
                cloned_findings.append((mp, name, found, notes))
                if any(n.startswith("HIDDEN") for n in notes):
                    gaps.append((mp, name, notes))
            except Exception as e:
                cloned_findings.append((mp, name, {}, [f"clone-failed:{type(e).__name__}"]))
        shutil.rmtree(tmp, ignore_errors=True)

    # ---- report ----
    inspectable = [r for r in rows if r[4]]
    lines = []
    lines.append(f"# SkillDeck ecosystem audit\n")
    lines.append(f"- Marketplaces: {len(manifests)}")
    lines.append(f"- Plugins total: {len(rows)}")
    lines.append(f"- Locally inspectable: {len(inspectable)}")
    lines.append(f"- External git-subdir (need --clone to inspect): {len(git_subdir)}")
    if clone_n: lines.append(f"- Cloned & inspected this run: {len(cloned_findings)}")
    lines.append(f"- **Potential GAPS (content a standard scan would miss): {len(gaps)}**\n")

    # tally layouts among inspectable
    tally = Counter()
    for mp,name,found,notes,ok in inspectable:
        if found.get("skills_standard"): tally["standard skills dir"]+=1
        if found.get("skills_declared"): tally["declared (custom) skills path"]+=1
        if found.get("commands"): tally["has commands/"]+=1
        if found.get("mcp"): tally["mcp-server plugin"]+=1
        if not any(found.values()): tally["no detectable skill/cmd/mcp"]+=1
    lines.append("## Layout tally (locally inspectable plugins)")
    for k,v in tally.most_common(): lines.append(f"- {k}: {v}")
    lines.append("")

    if gaps:
        lines.append("## ⚠️ GAPS — plugins with SKILL.md in non-standard, undetected locations")
        for mp,name,notes in gaps:
            lines.append(f"- `{mp}` / **{name}** — {', '.join(notes)}")
        lines.append("")

    if cloned_findings:
        lines.append("## Cloned external plugins (sample)")
        for mp,name,found,notes in cloned_findings:
            lines.append(f"- `{mp}`/{name}: {dict(found)} {notes}")

    open(REPORT,"w").write("\n".join(lines))
    print("\n".join(lines))
    print(f"\n→ written to {REPORT}")

if __name__ == "__main__":
    main()
