"""1.1.1: reproduces the Windows ARM64 "certificate could not be verified" failure and
checks the fallback, against the real practice page on GitHub.

Usage: python3 tls_fallback_test.py <godot> <project folder> <work folder>
Copies the project, hides GitHub's certificate authorities (Sectigo Root E46, USERTrust ECC,
ISRG) from the engine's default list with network/tls/certificate_bundle_override, then
runs verification/tls_fallback_check.gd. Needs the internet.
"""
import re, shutil, subprocess, sys, os
godot, project, work = sys.argv[1:4]
copy = os.path.join(work, "tls_copy")
shutil.rmtree(copy, ignore_errors=True)
shutil.copytree(project, copy, ignore=shutil.ignore_patterns(".godot"))
pem = open(os.path.join(copy, "assets/certs/trusted_roots.crt")).read()
keep = []
for c in re.findall(r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----", pem, re.S):
    s = subprocess.run(["openssl", "x509", "-noout", "-subject"], input=c, capture_output=True, text=True).stdout
    if any(k in s for k in ("Sectigo Public Server Authentication Root E46", "USERTrust ECC", "ISRG Root")):
        continue
    keep.append(c)
open(os.path.join(copy, "missing_roots.crt"), "w").write("\n".join(keep) + "\n")
pg = os.path.join(copy, "project.godot")
s = open(pg).read().replace("[rendering]", '[network]\n\ntls/certificate_bundle_override="res://missing_roots.crt"\n\n[rendering]', 1)
open(pg, "w").write(s)
subprocess.run([godot, "--headless", "--path", copy, "--import"], capture_output=True, timeout=600)
r = subprocess.run([godot, "--headless", "--path", copy, "-s", "res://verification/tls_fallback_check.gd"], capture_output=True, text=True, timeout=300)
print(r.stdout)
sys.exit(r.returncode)
