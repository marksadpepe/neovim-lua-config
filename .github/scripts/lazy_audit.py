#!/usr/bin/env python3
"""Аудит плагинов lazy.nvim.

Плагины здесь — не пакеты из реестра, а git-репозитории, пришпиленные
коммитами в lazy-lock.json. Поэтому проверяем не «версию из базы CVE»,
а целостность самих пинов:

  lock     — спеки в lua/plugins/*.lua и lazy-lock.json описывают одно и то же
  upstream — пришпиленный коммит всё ещё существует у апстрима и лежит
             в объявленной ветке (ловит force-push и угон репозитория)
  osv      — коммиты и репозитории против базы OSV

Запускается без зависимостей: только стандартная библиотека.
"""

import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LOCK = ROOT / "lazy-lock.json"
PLUGIN_DIR = ROOT / "lua" / "plugins"

# lazy.nvim ставит себя сам из lua/config/lazy.lua, спека в lua/plugins/ у неё нет.
BOOTSTRAP = {"lazy.nvim": {"repo": "folke/lazy.nvim", "branch": None, "tag": None}}

SPEC_RE = re.compile(r'\{\s*"([\w.\-]+/[\w.\-]+)"((?:[^{}]|\n)*?)\}')
FIELD_RE = re.compile(r'(\w+)\s*=\s*"([^"]*)"')
SHA_RE = re.compile(r"^[0-9a-f]{40}$")


def fail(msg):
    print(f"::error::{msg}")
    return 1


def note(msg):
    print(f"  {msg}")


def read_specs():
    """owner/repo и пины из lua/plugins/*.lua, ключ — имя каталога плагина."""
    specs = dict(BOOTSTRAP)
    for path in sorted(PLUGIN_DIR.glob("*.lua")):
        text = path.read_text(encoding="utf-8")
        for repo, tail in SPEC_RE.findall(text):
            fields = dict(FIELD_RE.findall(tail))
            name = repo.split("/")[-1]
            specs[name] = {
                "repo": repo,
                "branch": fields.get("branch"),
                "tag": fields.get("tag"),
                "file": path.relative_to(ROOT).as_posix(),
            }
    return specs


def read_lock():
    try:
        data = json.loads(LOCK.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        sys.exit(fail(f"lazy-lock.json — невалидный JSON: {e}"))
    if not isinstance(data, dict):
        sys.exit(fail("lazy-lock.json: ожидался объект на верхнем уровне"))
    return data


def cmd_lock():
    specs, lock = read_specs(), read_lock()
    errors = 0

    for name, entry in sorted(lock.items()):
        if not isinstance(entry, dict):
            errors += fail(f"{name}: запись в локе не объект")
            continue
        commit = entry.get("commit")
        if not isinstance(commit, str) or not SHA_RE.match(commit):
            errors += fail(f"{name}: commit не полный 40-символьный hex в нижнем регистре: {commit!r}")

    missing = sorted(set(specs) - set(lock))
    for name in missing:
        errors += fail(f"{name}: объявлен в {specs[name].get('file', 'lua/config/lazy.lua')}, но отсутствует в lazy-lock.json")

    orphans = sorted(set(lock) - set(specs))
    for name in orphans:
        errors += fail(f"{name}: есть в lazy-lock.json, но ни одна спека в lua/plugins/*.lua его не объявляет")

    # Ветка в локе должна совпадать с явно объявленной в спеке: иначе пин
    # уедет на другую ветку при следующем sync и это не будет видно в диффе.
    for name, spec in sorted(specs.items()):
        if spec["branch"] and name in lock:
            locked = lock[name].get("branch")
            if locked != spec["branch"]:
                errors += fail(f"{name}: спека требует ветку {spec['branch']!r}, в локе {locked!r}")

    if not errors:
        note(f"{len(lock)} плагинов: спеки и лок сходятся, все SHA полные")
    return errors


class RateLimited(Exception):
    """Исчерпан лимит GitHub API — это не находка, а невозможность проверить."""


def gh_api(path, token):
    """Возвращает (данные, ошибка). 404 — настоящее «нет объекта»,
    403/429 — лимит, его нельзя путать с находкой."""
    req = urllib.request.Request(
        f"https://api.github.com{path}",
        headers={
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "nvim-config-audit",
            **({"Authorization": f"Bearer {token}"} if token else {}),
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read()), None
    except urllib.error.HTTPError as e:
        if e.code in (403, 429) and e.headers.get("X-RateLimit-Remaining") == "0":
            raise RateLimited(
                "исчерпан лимит GitHub API. В Actions передайте GITHUB_TOKEN "
                "(лимит 1000 запросов в час), локально — свой PAT."
            )
        if e.code == 404:
            return None, "404"
        return None, f"HTTP {e.code}"
    except urllib.error.URLError as e:
        return None, f"сеть: {e.reason}"


def cmd_upstream():
    specs, lock = read_specs(), read_lock()
    token = os.environ.get("GITHUB_TOKEN", "")
    errors = 0

    for name, entry in sorted(lock.items()):
        spec = specs.get(name)
        if not spec:
            continue  # про сироту уже сказала проверка lock
        repo, commit = spec["repo"], entry["commit"]

        _, err = gh_api(f"/repos/{repo}/commits/{commit}", token)
        if err == "404":
            errors += fail(f"{name}: коммита {commit[:8]} у {repo} больше нет — историю переписали или репозиторий удалён")
            continue
        if err:
            errors += fail(f"{name}: проверить {commit[:8]} у {repo} не удалось ({err})")
            continue

        # Пин на тег: сверяем сам тег. Ветку при этом не проверяем — теги
        # релизов часто не лежат в истории ветки по умолчанию (у telescope
        # ровно так), и сравнение с веткой дало бы ложную тревогу.
        if spec["tag"]:
            tag_data, tag_err = gh_api(f"/repos/{repo}/git/ref/tags/{spec['tag']}", token)
            if tag_err:
                errors += fail(f"{name}: тег {spec['tag']} не найден у {repo} ({tag_err})")
                continue
            obj = (tag_data or {}).get("object") or {}
            sha = obj.get("sha")
            if not sha:
                errors += fail(f"{name}: GitHub вернул тег {spec['tag']} без SHA — ответ не разобран")
                continue
            if obj.get("type") == "tag":  # аннотированный тег — разыменовываем
                deref, deref_err = gh_api(f"/repos/{repo}/git/tags/{sha}", token)
                if deref_err:
                    errors += fail(f"{name}: не удалось разыменовать тег {spec['tag']} ({deref_err})")
                    continue
                sha = ((deref or {}).get("object") or {}).get("sha")
                if not sha:
                    errors += fail(f"{name}: аннотированный тег {spec['tag']} не разыменовался")
                    continue
            if sha != commit:
                errors += fail(f"{name}: спека пришпилена к тегу {spec['tag']} ({sha[:8]}), а лок к {commit[:8]} — тег переставили")
                continue
            branch = None
        else:
            # Коммит существует — но лежит ли он в объявленной ветке? Если нет,
            # пин указывает на объект вне ветки: форк, чужой PR, висячий коммит.
            branch = entry.get("branch") or spec["branch"]
            if branch:
                cmp_data, cmp_err = gh_api(f"/repos/{repo}/compare/{branch}...{commit}", token)
                if cmp_err:
                    errors += fail(f"{name}: не удалось сравнить {commit[:8]} с веткой {branch} ({cmp_err})")
                    continue
                status = (cmp_data or {}).get("status")
                if status not in ("behind", "identical"):
                    errors += fail(f"{name}: коммит {commit[:8]} не является предком {branch} (статус {status})")
                    continue

        pin = f"тег {spec['tag']}" if spec["tag"] else f"ветка {branch}"
        note(f"{name}: {commit[:8]} на месте у {repo} ({pin})")

    return errors


def cmd_osv():
    lock = read_lock()
    specs = read_specs()
    queries = []
    labels = []
    for name, entry in sorted(lock.items()):
        queries.append({"commit": entry["commit"]})
        labels.append(name)
        repo = specs.get(name, {}).get("repo")
        if repo:
            queries.append({"package": {"name": f"github.com/{repo}", "ecosystem": "Go"}})
            labels.append(name)

    req = urllib.request.Request(
        "https://api.osv.dev/v1/querybatch",
        data=json.dumps({"queries": queries}).encode(),
        headers={"Content-Type": "application/json", "User-Agent": "nvim-config-audit"},
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            results = json.loads(r.read()).get("results", [])
    except (urllib.error.URLError, urllib.error.HTTPError) as e:
        return fail(f"OSV недоступен: {e}")

    hits = {}
    for label, res in zip(labels, results):
        for v in res.get("vulns", []) or []:
            hits.setdefault(label, set()).add(v.get("id", "?"))

    if hits:
        for name, ids in sorted(hits.items()):
            fail(f"{name}: OSV сообщает об уязвимостях: {', '.join(sorted(ids))}")
        return len(hits)

    note(f"OSV: по {len(lock)} пришпиленным коммитам известных уязвимостей нет")
    note("важно: базы уязвимостей почти не покрывают плагины Neovim, поэтому")
    note("чистый результат здесь — отсутствие сигнала, а не доказательство безопасности")
    return 0


COMMANDS = {"lock": cmd_lock, "upstream": cmd_upstream, "osv": cmd_osv}

if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in COMMANDS:
        sys.exit(f"использование: {sys.argv[0]} {{{'|'.join(COMMANDS)}}}")
    try:
        sys.exit(1 if COMMANDS[sys.argv[1]]() else 0)
    except RateLimited as e:
        sys.exit(fail(str(e)))
