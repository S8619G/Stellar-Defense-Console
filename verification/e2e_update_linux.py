"""1.1.1 end-to-end update run with real exported Linux games (sandbox, tests only).

Builds an Update Test 1.1.1 and a pretend 1.1.2 from this project, serves 1.1.2 from
update_test_server.py (a local stand-in for the GitHub releases page) and lets the real
1.1.1 game update itself, go back, and meet the failure cases. The game is driven by the
Update Test only option --sdc-update-test-press (presses the pop-up buttons as a click
would). Screens are captured from the virtual display.

Usage: python3 e2e_update_linux.py <godot> <project> <work folder>
Writes <work>/e2e_report.json and captures in <work>/captures.
"""
import hashlib
import json
import os
import shutil
import signal
import subprocess
import sys
import tarfile
import time
from pathlib import Path

GODOT, PROJECT, WORK = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3])
SCREEN = os.environ.get("E2E_SCREEN", "1600x900")
WORK.mkdir(parents=True, exist_ok=True)
CAP = WORK / "captures"
CAP.mkdir(exist_ok=True)
DATA = WORK / "data"
USER = DATA / "Stellar Defense Console"
INSTALL = WORK / "install"
GAME = INSTALL / "Stellar_Defense_Console_1.1.1_Linux.x86_64"
FILES = WORK / "files"
REPORT = {"checks": [], "failures": 0}
HERE = Path(__file__).resolve().parent


def check(ok, label):
    REPORT["checks"].append({"ok": bool(ok), "label": label})
    if not ok:
        REPORT["failures"] += 1
    print(("PASS " if ok else "FAIL ") + label, flush=True)


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def run(cmd, **kw):
    print("$", " ".join(str(c) for c in cmd), flush=True)
    return subprocess.run([str(c) for c in cmd], check=True, **kw)


def export(version, out):
    proj = WORK / ("p" + version.replace(".", ""))
    if proj.exists():
        shutil.rmtree(proj)
    shutil.copytree(PROJECT, proj, ignore=shutil.ignore_patterns(".godot"))
    pg = (proj / "project.godot").read_text()
    pg = pg.replace('config/version="1.1.1"', 'config/version="%s"' % version)
    (proj / "project.godot").write_text(pg)
    ep = (proj / "export_presets.cfg").read_text()
    head, _, rest = ep.partition('name="Linux x86_64"')
    rest = rest.replace('custom_features=""', 'custom_features="update_test"', 1)
    (proj / "export_presets.cfg").write_text(head + 'name="Linux x86_64"' + rest)
    subprocess.run([GODOT, "--headless", "--path", str(proj), "--import"], capture_output=True, timeout=600)
    run([GODOT, "--headless", "--path", proj, "--export-release", "Linux x86_64", out], capture_output=True, timeout=600)
    return out


def game_pids():
    out = subprocess.run(["ps", "-eo", "pid,comm"], capture_output=True, text=True).stdout
    return [int(l.split()[0]) for l in out.splitlines()[1:] if l.split()[1].startswith("Stellar_Defens")]


def kill_games():
    for pid in game_pids():
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(1.0)
    for pid in game_pids():
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def state():
    path = USER / "updates" / "update_state.cfg"
    return path.read_text() if path.exists() else ""


def logs_text():
    d = USER / "logs"
    if not d.exists():
        return ""
    return "\n".join(p.read_text(errors="replace") for p in sorted(d.glob("radar_session_*.log")))


def wait_for(cond, seconds, step=0.25):
    end = time.time() + seconds
    while time.time() < end:
        if cond():
            return True
        time.sleep(step)
    return cond()


def capture(name):
    path = CAP / ("%s_%s.png" % (name, SCREEN))
    subprocess.run(["import", "-display", DISPLAY, "-window", "root", str(path)], capture_output=True)
    return path


def start_game(*args):
    env = dict(os.environ, DISPLAY=DISPLAY, XDG_DATA_HOME=str(DATA))
    return subprocess.Popen([str(GAME), "--audio-driver", "Dummy", "--sdc-update-test-api=%s/api/latest" % BASE] + list(args),
                            env=env, stdout=open(WORK / "game_stdout.log", "a"), stderr=subprocess.STDOUT)


def write_cfg(**extra):
    cfg = {"files": str(FILES), "redirect": True, "latest": LATEST}
    cfg.update(extra)
    (WORK / "server.json").write_text(json.dumps(cfg))


# ---------------------------------------------------------------- builds
builds = WORK / "builds"
builds.mkdir(exist_ok=True)
b111 = builds / "Stellar_Defense_Console_1.1.1_Linux.x86_64"
b112 = builds / "Stellar_Defense_Console_1.1.2_Linux.x86_64"
if not b111.exists() or os.environ.get("E2E_REBUILD"):
    export("1.1.1", b111)
    export("1.1.2", b112)
H111, H112 = sha(b111), sha(b112)
check(H111 != H112 and b111.stat().st_size > 10_000_000, "Update Test builds 1.1.1 and pretend 1.1.2 exported")

if FILES.exists():
    shutil.rmtree(FILES)
FILES.mkdir()
tar_name = "Stellar_Defense_Console_1.1.2_Linux.tar.gz"
with tarfile.open(FILES / tar_name, "w:gz") as t:
    t.add(b112, arcname=b112.name)
# A 1.1.2 that cannot start: the bare engine without the game inside.
broken_dir = WORK / "broken"
broken_dir.mkdir(exist_ok=True)
template = Path.home() / ".local/share/godot/export_templates/4.7.stable/linux_release.x86_64"
shutil.copy(template, broken_dir / b112.name)
os.chmod(broken_dir / b112.name, 0o755)
broken_name = "Stellar_Defense_Console_1.1.3_Linux.tar.gz"
with tarfile.open(FILES / broken_name, "w:gz") as t:
    t.add(broken_dir / b112.name, arcname=b112.name)
(FILES / "SHA256SUMS.txt").write_text("%s  %s\n%s  %s\n" % (sha(FILES / tar_name), tar_name, sha(FILES / broken_name), broken_name))


def latest(version, name):
    return {"tag_name": "v" + version, "html_url": "{base}/releases/tag/v" + version,
            "published_at": "2026-11-02T10:00:00Z", "draft": False, "prerelease": False,
            "body": "## New in %s\n\n- **Practice update.** TEST: this is a practice release for the update test.\n- **Second line.** Nothing else changes." % version,
            "assets": [{"name": "SHA256SUMS.txt", "browser_download_url": "{base}/download/SHA256SUMS.txt", "size": (FILES / "SHA256SUMS.txt").stat().st_size},
                       {"name": name, "browser_download_url": "{base}/download/" + name, "size": (FILES / name).stat().st_size}]}


LATEST = latest("1.1.2", tar_name)
write_cfg()
server = subprocess.Popen([sys.executable, str(HERE / "update_test_server.py"), str(WORK / "server.json")], stdout=subprocess.PIPE, text=True)
BASE = "http://127.0.0.1:" + server.stdout.readline().split()[1]

disp_no = 90 + (os.getpid() % 9)
DISPLAY = ":%d" % disp_no
xvfb = subprocess.Popen(["Xvfb", DISPLAY, "-screen", "0", SCREEN + "x24", "-nolisten", "tcp"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(1.5)

try:
    kill_games()
    if DATA.exists():
        shutil.rmtree(DATA)
    if INSTALL.exists():
        subprocess.run(["chmod", "-R", "u+w", str(INSTALL)])
        shutil.rmtree(INSTALL)
    INSTALL.mkdir()
    shutil.copy(b111, GAME)
    os.chmod(GAME, 0o755)

    # ---------------- 1. update 1.1.1 -> 1.1.2 (with one dropped connection) ----------------
    write_cfg(drop_once=[tar_name], file_delay=0.01)
    p = start_game("--sdc-update-test-press=update")
    time.sleep(2.0)
    capture("01_splash")
    ok = wait_for(lambda: "startup: version 1.1.2 offered" in logs_text(), 15)
    time.sleep(0.4)
    capture("02_startup_popup")
    check(ok, "Real game: startup check finds 1.1.2 and shows the pop-up")
    ok = wait_for(lambda: "update test: pressed update" in logs_text(), 10)
    time.sleep(1.0)
    capture("03_downloading")
    check(ok, "UPDATE NOW pressed")
    ok = wait_for(lambda: p.poll() is not None, 90)
    check(ok and p.returncode == 0, "Old 1.1.1 closed by itself after the new copy started")
    check(sha(GAME) == H112, "The game file now holds 1.1.2 (same name and place)")
    log = (WORK / "server.json.log").read_text()
    check(("DROP " + tar_name) in log and "range=bytes=" in log, "Dropped download was resumed by the real game")
    ok = wait_for(lambda: "Updated from 1.1.1" in state() and not (USER / "updates" / "pending.cfg").exists(), 30)
    check(ok, "New 1.1.2 copy confirmed its start and tidied up")
    check(sorted(os.listdir(INSTALL)) == [GAME.name], "Game folder holds only the game file (old copy removed)")
    backup = USER / "backup" / GAME.name
    st = state()
    check(backup.exists() and sha(backup) == H111 and '[backup]' in st and 'version="1.1.1"' in st.split('[backup]', 1)[1], "1.1.1 kept as the one backup")
    REPORT["state_after_update"] = st
    check(len(game_pids()) == 1, "Exactly one copy of the game running (the new one)")
    time.sleep(3.0)
    capture("04_after_update")
    kill_games()

    # ---------------- 2. GO BACK 1.1.2 -> 1.1.1 ----------------
    write_cfg()
    p = start_game("--sdc-update-test-press=goback,confirm")
    ok = wait_for(lambda: "update test: pressed goback" in logs_text(), 20)
    time.sleep(0.4)
    capture("05_go_back_confirm")
    check(ok, "GO BACK asked to confirm in the real game")
    ok = wait_for(lambda: p.poll() is not None, 60)
    check(ok and sha(GAME) == H111, "GO BACK: 1.1.1 back in place, 1.1.2 copy closed")
    ok = wait_for(lambda: "Went back from 1.1.2" in state() and not (USER / "updates" / "pending.cfg").exists(), 30)
    check(ok and 'skipped_version="1.1.2"' in state() and not backup.exists(), "GO BACK: backup used up, 1.1.2 skipped at startup, note written")
    check(sorted(os.listdir(INSTALL)) == [GAME.name], "Game folder clean after GO BACK")
    kill_games()

    # ---------------- 3. skipped version is not offered at startup ----------------
    before = logs_text()
    p = start_game("--sdc-update-test-press=quit")
    ok = wait_for(lambda: p.poll() is not None, 30)
    new_log = logs_text()[len(before):]
    check(ok and "startup update check: version 1.1.2 available" in new_log and "offered" not in new_log, "After GO BACK, 1.1.2 is not offered at startup")

    # ---------------- 4. a new version that does not start: put back ----------------
    LATEST = latest("1.1.3", broken_name)
    write_cfg()
    p = start_game("--sdc-update-test-press=update")
    ok = wait_for(lambda: "update stopped: NEW VERSION DID NOT START" in logs_text(), 90)
    time.sleep(0.5)
    capture("06_did_not_start")
    check(ok and sha(GAME) == H111, "New version that does not start: 1.1.1 put back and still running")
    check(sorted(os.listdir(INSTALL)) == [GAME.name] and p.poll() is None, "Game folder clean, 1.1.1 keeps running")
    kill_games()

    # ---------------- 5. wrong checksum ----------------
    good = (FILES / "SHA256SUMS.txt").read_text()
    (FILES / "SHA256SUMS.txt").write_text("%s  %s\n" % ("0" * 64, tar_name))
    LATEST = latest("1.1.2", tar_name)
    state_path = USER / "updates" / "update_state.cfg"
    state_path.write_text(state().replace('skipped_version="1.1.2"', 'skipped_version=""'))
    write_cfg()
    p = start_game("--sdc-update-test-press=update")
    ok = wait_for(lambda: "update stopped: DOWNLOAD DID NOT CHECK OUT" in logs_text(), 60)
    time.sleep(0.5)
    capture("07_wrong_checksum")
    check(ok and sha(GAME) == H111 and sorted(os.listdir(INSTALL)) == [GAME.name], "Wrong checksum: nothing changed")
    kill_games()
    (FILES / "SHA256SUMS.txt").write_text(good)

    # ---------------- 6. protected folder ----------------
    os.chmod(INSTALL, 0o555)
    p = start_game("--sdc-update-test-press=update")
    ok = wait_for(lambda: "update stopped: FOLDER IS PROTECTED" in logs_text() or "update stopped: PERMISSION NOT GIVEN" in logs_text(), 60)
    time.sleep(0.5)
    capture("08_protected_folder")
    check(ok and sha(GAME) == H111, "Protected folder (no permission prompt here): plain message, nothing changed")
    kill_games()
    os.chmod(INSTALL, 0o755)

    # ---------------- 7. no internet: quiet start ----------------
    before = logs_text()
    env = dict(os.environ, DISPLAY=DISPLAY, XDG_DATA_HOME=str(DATA))
    p = subprocess.Popen([str(GAME), "--audio-driver", "Dummy", "--sdc-update-test-api=http://127.0.0.1:9/api/latest", "--sdc-update-test-press=quit"], env=env,
                         stdout=open(WORK / "game_stdout.log", "a"), stderr=subprocess.STDOUT)
    ok = wait_for(lambda: p.poll() is not None, 30)
    new_log = logs_text()[len(before):]
    check(ok and "startup update check: failed" in new_log and "battle starts" in new_log, "No internet: battle starts, nothing shown")
finally:
    kill_games()
    try:
        os.chmod(INSTALL, 0o755)
    except OSError:
        pass
    server.terminate()
    xvfb.terminate()

(WORK / "e2e_report.json").write_text(json.dumps(REPORT, indent=1))
print("E2E_RESULT checks=%d failures=%d" % (len(REPORT["checks"]), REPORT["failures"]))
sys.exit(1 if REPORT["failures"] else 0)
