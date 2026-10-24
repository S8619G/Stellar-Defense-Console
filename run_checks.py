"""Run the curated pre-release regression gate with Godot 4.7."""
from pathlib import Path
import argparse
import json
import re
import shutil
import subprocess
import os
import signal

HERE = Path(__file__).resolve().parent
DEFAULT_GAME = HERE / "source/Stellar_Defense_Console"
if not DEFAULT_GAME.exists():
    DEFAULT_GAME = HERE / "Stellar_Defense_Console"
TESTS = [
    "test_rebrand", "test_v130_features", "test_v129_features", "test_v128_features",
    "test_v127_features", "test_v123_features", "test_v122_features", "test_v121_features",
    "test_v120_features", "test_v120_waves_run", "test_v111_features", "test_v110_features",
    "test_v109_features", "test_v107_features", "test_v106_features", "test_v104_features",
    "test_v102_combat_feel", "test_heavy_update", "test_firewall_combat", "test_gunship",
    "test_returning_update", "test_regression", "test_console", "test_alerts",
    "test_v103_features", "test_v105_features", "test_waves_update", "test_center_weapon_button",
    "test_arrival_alert_scope",
    "test_hull_shield",
    "test_controller", "test_controller_status", "test_hull_percentage",
    "test_internal_names",
    "test_launch_readiness", "test_bonus_pick_input", "test_bonus_pick_round_end", "test_protect_convoy",
    "test_damage_effects", "test_sdc_109"
]
DISPLAY_TESTS = {"test_v103_features", "test_v105_features", "test_waves_update", "test_center_weapon_button", "test_hull_shield", "test_controller", "test_controller_status", "test_hull_percentage", "test_bonus_pick_input", "test_bonus_pick_round_end", "test_damage_effects", "test_sdc_109"}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("godot", help="Path to Godot 4.7 executable")
    parser.add_argument("--project", type=Path, default=DEFAULT_GAME)
    parser.add_argument("--virtual-display", action="store_true", help="Use xvfb-run for display-dependent checks on Linux")
    parser.add_argument("--logs", type=Path, default=HERE/"verification")
    parser.add_argument("--only", choices=TESTS, help="Run one suite; merge its result into an existing summary")
    args = parser.parse_args()
    args.logs.mkdir(parents=True, exist_ok=True)
    rows = []
    if args.only and (args.logs/"checks_summary.json").exists():
        rows = json.loads((args.logs/"checks_summary.json").read_text())["suites"]
        rows = [row for row in rows if row["suite"] != args.only]
    for name in ([args.only] if args.only else TESTS):
        command = [args.godot, "--path", str(args.project), "--audio-driver", "Dummy",
                   "--script", f"res://verification/{name}.gd"]
        if name in DISPLAY_TESTS:
            if args.virtual_display:
                if not shutil.which("xvfb-run"):
                    raise SystemExit("xvfb-run is required for --virtual-display")
                command = ["xvfb-run", "-a", "-s", "-screen 0 1920x1080x24"] + command
        else:
            command.insert(1, "--headless")
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   text=True, start_new_session=(os.name == "posix"))
        try:
            output, _ = process.communicate(timeout=180)
            exit_code = process.returncode
        except subprocess.TimeoutExpired:
            if os.name == "posix":
                os.killpg(process.pid, signal.SIGKILL)
            else:
                process.kill()
            output, _ = process.communicate()
            exit_code = 124
        (args.logs/(name+".log")).write_text(output)
        match = re.search(r"(?:\w+_)?RESULT checks=(\d+) failures=(\d+)", output)
        row = {"suite": name, "exit_code": exit_code,
               "checks": int(match[1]) if match else 0,
               "failures": int(match[2]) if match else None,
               "engine_error": bool(re.search(r"(?:SCRIPT ERROR|Parse Error|ERROR:)",output))}
        rows.append(row)
        print(json.dumps(row), flush=True)
    summary = {"suites":rows, "checks":sum(r["checks"] for r in rows),
               "passed":all(r["exit_code"]==0 and r["failures"]==0 and not r["engine_error"] for r in rows)}
    (args.logs/"checks_summary.json").write_text(json.dumps(summary,indent=2)+"\n")
    print("TOTAL", json.dumps({k:v for k,v in summary.items() if k!="suites"}))
    raise SystemExit(0 if summary["passed"] else 1)

if __name__ == "__main__":
    main()
