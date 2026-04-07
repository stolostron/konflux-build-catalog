#!/usr/bin/env python3
"""
Sync local Tekton Pipeline YAML files from konflux-ci/build-definitions.

- Merge .spec.params (add upstream params, keep downstream-only params).
  For pipeline-level params only, keep `default` from this repo when present.
- Merge .spec.tasks and .spec.finally: upstream order and non-taskRef fields
  from upstream; preserve local taskRef; merge per-entry params (if upstream
  `value` is empty (`[]`, `''`, or absent) and the repo has a non-empty value,
  keep the repo value; if both upstream and repo `value` are non-empty lists,
  merge them—upstream order first, then append repo items not already present);
  merge `when` arrays (upstream order; match clauses by
  `cel` or `input`+`operator`; fill empty upstream fields from repo; append
  repo-only clauses); keep
  allowlisted custom tasks; drop other local-only tasks; inject upstream-only
  tasks.
- After merge, drop `spec.params` entries whose `name` never appears as
  `$(params.<name>)` anywhere in the merged pipeline (including other params).
- Output uses ruamel.yaml round-trip. Any scalar value containing a newline is
  emitted as a literal block (|), regardless of key. Indentation matches common
  yq-style 2-space YAML.

Exit codes: 0 if nothing changed, 200 if at least one pipeline file was updated,
1 on errors (e.g. missing mapped file).
"""

from __future__ import annotations

import argparse
import copy
import re
import sys
import urllib.error
import urllib.request
from io import StringIO
from pathlib import Path
from typing import Any, Dict, List, Optional, Set

from ruamel.yaml import YAML
from ruamel.yaml.comments import CommentedMap, CommentedSeq
from ruamel.yaml.scalarstring import FoldedScalarString, LiteralScalarString

# Upstream map and fetched YAML use the safe loader (no custom tags).
_safe_yaml = YAML(typ="safe")

# Tekton pipeline param refs: $(params.name), $(params.name[*]), etc.
_PARAM_REF_RE = re.compile(r"\$\(params\.([^\[\)\.]+)[\[\)\.]")


def collect_param_refs_from_obj(obj: Any) -> Set[str]:
    """Collect $(params.<name>) references anywhere in obj."""
    names: Set[str] = set()
    if isinstance(obj, str):
        names.update(m.group(1) for m in _PARAM_REF_RE.finditer(obj))
        return names
    if isinstance(obj, dict):
        for v in obj.values():
            names |= collect_param_refs_from_obj(v)
        return names
    if isinstance(obj, list):
        for v in obj:
            names |= collect_param_refs_from_obj(v)
        return names
    return names


def prune_unused_spec_params(merged: Dict[str, Any]) -> None:
    """Drop spec.params entries not referenced as $(params.<name>) in doc."""
    spec = merged.get("spec")
    if not spec or "params" not in spec:
        return
    params = spec["params"]
    if not isinstance(params, list):
        return
    refs = collect_param_refs_from_obj(merged)
    kept: List[Any] = []
    for p in params:
        if not isinstance(p, dict):
            kept.append(p)
            continue
        name = p.get("name")
        if name is None:
            kept.append(p)
            continue
        if name in refs:
            kept.append(p)
    spec["params"] = kept


def make_roundtrip_yaml() -> YAML:
    """ruamel YAML tuned for yq-like spacing and readable long lines."""
    y = YAML(typ="rt")
    y.preserve_quotes = True
    # yq/Kubernetes style: 2-space indent; sequence indent under mapping key.
    y.indent(mapping=2, sequence=4, offset=2)
    y.width = 1024
    return y


def load_map(path: Path) -> tuple[Dict[str, List[str]], List[str]]:
    raw = _safe_yaml.load(path.read_text())
    pipelines = raw.get("pipelines")
    if not pipelines or not isinstance(pipelines, dict):
        msg = f"{path}: missing 'pipelines' map"
        raise SystemExit(msg)
    custom = raw.get("custom-tasks") or []
    if not isinstance(custom, list):
        custom = []
    return pipelines, [str(x) for x in custom]


def fetch_upstream(pipeline: str) -> Dict[str, Any]:
    url = (
        "https://raw.githubusercontent.com/konflux-ci/build-definitions/"
        f"refs/heads/main/pipelines/{pipeline}/{pipeline}.yaml"
    )
    ua = "konflux-build-catalog-sync"
    req = urllib.request.Request(url, headers={"User-Agent": ua})
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            data = resp.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        raise SystemExit(f"HTTP {e.code} fetching {url}: {e.reason}") from e
    except urllib.error.URLError as e:
        raise SystemExit(f"Failed to fetch {url}: {e}") from e
    return _safe_yaml.load(data)


def commented_to_plain(obj: Any) -> Any:
    """Convert ruamel round-trip structures to plain Python for merge logic."""
    if isinstance(obj, CommentedMap):
        return {k: commented_to_plain(v) for k, v in obj.items()}
    if isinstance(obj, CommentedSeq):
        return [commented_to_plain(v) for v in obj]
    if isinstance(obj, dict):
        return {k: commented_to_plain(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [commented_to_plain(v) for v in obj]
    if isinstance(obj, (LiteralScalarString, FoldedScalarString)):
        return str(obj)
    return obj


def plain_to_roundtrip_tree(plain: Any, yaml_rt: YAML) -> Any:
    """Round-trip plain data; result is CommentedMap/Seq for dump."""
    buf = StringIO()
    yaml_rt.dump(plain, buf)
    buf.seek(0)
    return yaml_rt.load(buf)


def _needs_literal_block(val: Any) -> bool:
    """True if we should emit a YAML literal block (|) for this scalar."""
    if isinstance(val, LiteralScalarString):
        return False
    if isinstance(val, FoldedScalarString):
        return "\n" in str(val)
    if isinstance(val, str):
        return "\n" in val
    return False


def ensure_literal_scalar_for_newlines(node: Any) -> None:
    """
    Mutate ruamel tree in place: wrap any scalar string that contains a newline
    in LiteralScalarString so output uses | block style (any key/path).
    """
    if isinstance(node, CommentedMap):
        for k in list(node.keys()):
            v = node[k]
            ensure_literal_scalar_for_newlines(v)
            if _needs_literal_block(v):
                node[k] = LiteralScalarString(str(v))
        return
    if isinstance(node, CommentedSeq):
        for i in range(len(node)):
            v = node[i]
            ensure_literal_scalar_for_newlines(v)
            if _needs_literal_block(v):
                node[i] = LiteralScalarString(str(v))
        return
    if isinstance(node, dict):
        for k in list(node.keys()):
            v = node[k]
            ensure_literal_scalar_for_newlines(v)
            if _needs_literal_block(v):
                node[k] = LiteralScalarString(str(v))
        return
    if isinstance(node, list):
        for i in range(len(node)):
            v = node[i]
            ensure_literal_scalar_for_newlines(v)
            if _needs_literal_block(v):
                node[i] = LiteralScalarString(str(v))
        return


def _param_value_is_empty(value: Any) -> bool:
    """True if a task param `value` is unset or explicitly empty ([] or '')."""
    if value is None:
        return True
    if value == []:
        return True
    if value == "":
        return True
    return False


def _merge_param_value_lists(up_val: Any, loc_val: Any) -> Optional[List[Any]]:
    """
    If both values are lists, return upstream order plus repo-only items
    (append each local element if not already in the merged list).
    """
    if not isinstance(up_val, list) or not isinstance(loc_val, list):
        return None
    out: List[Any] = [copy.deepcopy(x) for x in up_val]
    for x in loc_val:
        if x not in out:
            out.append(copy.deepcopy(x))
    return out


def merge_param_lists(
    local_params: Optional[List[Dict[str, Any]]],
    upstream_params: Optional[List[Dict[str, Any]]],
    *,
    prefer_local_default: bool = False,
    prefer_local_value_when_upstream_empty: bool = False,
) -> List[Dict[str, Any]]:
    local_params = local_params or []
    upstream_params = upstream_params or []
    up_set = {p.get("name") for p in upstream_params if p.get("name")}
    local_by_name = {p.get("name"): p for p in local_params if p.get("name")}
    out: List[Dict[str, Any]] = []
    for up in upstream_params:
        name = up.get("name")
        if not name:
            out.append(copy.deepcopy(up))
            continue
        loc = local_by_name.get(name)
        if loc:
            merged = copy.deepcopy(loc)
            for k, v in up.items():
                merged[k] = copy.deepcopy(v)
            if prefer_local_default and "default" in loc:
                merged["default"] = copy.deepcopy(loc["default"])
            if prefer_local_value_when_upstream_empty:
                up_val = up.get("value")
                loc_val = loc.get("value")
                if _param_value_is_empty(up_val) and not _param_value_is_empty(loc_val):
                    merged["value"] = copy.deepcopy(loc_val)
                elif (
                    isinstance(up_val, list)
                    and isinstance(loc_val, list)
                    and not _param_value_is_empty(up_val)
                    and not _param_value_is_empty(loc_val)
                ):
                    merged_list = _merge_param_value_lists(up_val, loc_val)
                    if merged_list is not None:
                        merged["value"] = merged_list
            out.append(merged)
        else:
            out.append(copy.deepcopy(up))
    for loc in local_params:
        name = loc.get("name")
        if name and name not in up_set:
            out.append(copy.deepcopy(loc))
    return out


def _when_clause_key(w: Any) -> Optional[tuple]:
    """Match key for Tekton WhenExpression / cel entries."""
    if not isinstance(w, dict):
        return None
    if "cel" in w:
        c = w.get("cel")
        return ("cel", str(c) if c is not None else "")
    inp, op = w.get("input"), w.get("operator")
    if inp is not None and op is not None:
        return ("io", str(inp), str(op))
    return None


def _merge_when_clause(
    up_clause: Dict[str, Any], loc_clause: Dict[str, Any]
) -> Dict[str, Any]:
    """Start from upstream clause; fill empty upstream fields from repo."""
    merged = copy.deepcopy(up_clause)
    for key, lv in loc_clause.items():
        uv = up_clause.get(key)
        if _param_value_is_empty(uv) and not _param_value_is_empty(lv):
            merged[key] = copy.deepcopy(lv)
    return merged


def merge_when_lists(
    upstream_when: Optional[List[Any]],
    local_when: Optional[List[Any]],
) -> List[Any]:
    """
    Upstream order; pair each upstream clause with the first unused local
    clause with the same key (`cel` or `input`+`operator`); merge fields;
    append any remaining local clauses in local order.
    """
    up = upstream_when or []
    loc = local_when or []
    if not loc:
        return copy.deepcopy(up)
    if not up:
        return copy.deepcopy(loc)

    used = [False] * len(loc)
    out: List[Any] = []

    for u in up:
        k = _when_clause_key(u)
        merged: Optional[Dict[str, Any]] = None
        if k is not None and isinstance(u, dict):
            for i, lw in enumerate(loc):
                if used[i] or not isinstance(lw, dict):
                    continue
                if _when_clause_key(lw) == k:
                    used[i] = True
                    merged = _merge_when_clause(u, lw)
                    break
        if merged is not None:
            out.append(merged)
        else:
            out.append(copy.deepcopy(u))

    for i, lw in enumerate(loc):
        if not used[i]:
            out.append(copy.deepcopy(lw))

    return out


def merge_task_entry(
    upstream_task: Dict[str, Any], local_task: Optional[Dict[str, Any]]
) -> Dict[str, Any]:
    if local_task is None:
        return copy.deepcopy(upstream_task)
    out = copy.deepcopy(upstream_task)
    if "taskRef" in local_task:
        out["taskRef"] = copy.deepcopy(local_task["taskRef"])
    out["params"] = merge_param_lists(
        local_task.get("params"),
        upstream_task.get("params"),
        prefer_local_value_when_upstream_empty=True,
    )
    out["when"] = merge_when_lists(
        upstream_task.get("when"),
        local_task.get("when") if local_task else None,
    )
    for key in list(out.keys()):
        if out[key] is None or out[key] == []:
            del out[key]
    return out


def _names_in_order(task_list: Optional[List[Dict[str, Any]]]) -> List[str]:
    if not task_list:
        return []
    return [t["name"] for t in task_list if t.get("name")]


def sync_task_list(
    local_tasks: Optional[List[Dict[str, Any]]],
    upstream_tasks: Optional[List[Dict[str, Any]]],
    custom_allowed: Set[str],
) -> List[Dict[str, Any]]:
    """
    Build merged task list: strict upstream order for upstream-defined names,
    merged fields (taskRef from local); insert allowlisted custom-only tasks at
    positions implied by local order.
    """
    local_tasks = local_tasks or []
    upstream_tasks = upstream_tasks or []
    up_order = _names_in_order(upstream_tasks)
    up_by = {t["name"]: t for t in upstream_tasks if t.get("name")}
    loc_by = {t["name"]: t for t in local_tasks if t.get("name")}

    result: List[Dict[str, Any]] = []
    for name in up_order:
        result.append(merge_task_entry(up_by[name], loc_by.get(name)))

    custom_only: List[tuple[str, Dict[str, Any]]] = []
    for t in local_tasks:
        n = t.get("name")
        if not n or n in up_by:
            continue
        if n in custom_allowed:
            custom_only.append((n, copy.deepcopy(t)))

    for n, task_copy in custom_only:
        idx = next(
            (i for i, lt in enumerate(local_tasks) if lt.get("name") == n),
            -1,
        )
        if idx < 0:
            continue
        pred: Optional[str] = None
        for j in range(idx - 1, -1, -1):
            pn = local_tasks[j].get("name")
            if not pn:
                continue
            if pn in up_by or pn in {c[0] for c in custom_only}:
                pred = pn
                break
        if pred is None:
            insert_at = 0
        else:
            pos = next(
                (i for i, r in enumerate(result) if r.get("name") == pred),
                None,
            )
            if pos is None:
                insert_at = len(result)
            else:
                insert_at = pos + 1
        result.insert(insert_at, task_copy)

    return result


def merge_pipeline(
    local_doc: Dict[str, Any],
    upstream_doc: Dict[str, Any],
    custom_allowed: Set[str],
) -> Dict[str, Any]:
    out = copy.deepcopy(local_doc)
    local_spec = local_doc.get("spec") or {}
    upstream_spec = upstream_doc.get("spec") or {}
    if "spec" not in out:
        out["spec"] = {}
    spec = out["spec"]
    spec["params"] = merge_param_lists(
        local_spec.get("params"),
        upstream_spec.get("params"),
        prefer_local_default=True,
    )
    spec["tasks"] = sync_task_list(
        local_spec.get("tasks"), upstream_spec.get("tasks"), custom_allowed
    )
    spec["finally"] = sync_task_list(
        local_spec.get("finally"),
        upstream_spec.get("finally"),
        custom_allowed,
    )
    prune_unused_spec_params(out)
    return out


def dump_merged_pipeline(merged_plain: Dict[str, Any], yaml_rt: YAML) -> str:
    """Merged plain dict to round-trip YAML; newline scalars use | blocks."""
    merged_rt = plain_to_roundtrip_tree(merged_plain, yaml_rt)
    ensure_literal_scalar_for_newlines(merged_rt)
    buf = StringIO()
    yaml_rt.dump(merged_rt, buf)
    return buf.getvalue()


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Sync pipelines/ YAML from konflux-ci/build-definitions "
            "per upstream-map.yaml"
        )
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print actions only; do not write files",
    )
    parser.add_argument(
        "pipeline_file",
        nargs="?",
        default=None,
        help="(Optional) Pipeline file to sync"
    )
    args = parser.parse_args()

    yaml_rt = make_roundtrip_yaml()
    repo_root = Path(__file__).resolve().parent
    map_path = repo_root / "upstream-map.yaml"
    pipelines_map, custom_tasks = load_map(map_path)
    custom_set = set(custom_tasks)
    pipelines_dir = repo_root / "pipelines"
    if not pipelines_dir.is_dir():
        raise SystemExit(f"Not a directory: {pipelines_dir}")

    exit_code = 0
    any_updates = False
    for upstream_name, rel_files in pipelines_map.items():
        if not isinstance(rel_files, list):
            continue
        msg = f"Fetching upstream pipeline {upstream_name!r} ..."
        print(msg, file=sys.stderr)
        upstream_doc = fetch_upstream(upstream_name)
        for rel in rel_files:
            path = pipelines_dir / rel
            if not path.is_file():
                print(f"  skip missing file: {path}", file=sys.stderr)
                exit_code = 1
                continue
            if args.pipeline_file and path != repo_root / args.pipeline_file:
                continue
            original_text = path.read_text(encoding="utf-8")
            local_rt = yaml_rt.load(original_text)
            local_plain = commented_to_plain(local_rt)
            merged_plain = merge_pipeline(
                local_plain, upstream_doc, custom_set)
            text = dump_merged_pipeline(merged_plain, yaml_rt)
            changed = text != original_text
            if changed:
                any_updates = True
            if args.dry_run:
                if changed:
                    print(f"Would write {path}", file=sys.stderr)
                continue
            if changed:
                path.write_text(text, encoding="utf-8")
                print(f"Updated {path}", file=sys.stderr)

    if exit_code:
        sys.exit(exit_code)
    if any_updates:
        sys.exit(200)


if __name__ == "__main__":
    main()
