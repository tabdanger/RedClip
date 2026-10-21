#!/usr/bin/env python3
"""App Store Connect API helper for the upload workflow. Standard library + openssl only.

    asc.py check                 test the API key; report the app record, bundle ID, certificates
    asc.py prepare <folder>      make a temporary Apple Distribution certificate and an App Store
                                 profile for com.tabdanger.redclip (files go in <folder>)
    asc.py cleanup <folder>      revoke that certificate and delete that profile

Environment: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (the .p8 file), BUNDLE_ID (optional),
ASC_TOKEN_STYLE ("team" or "individual", set by `check`). Nothing secret is ever printed.
"""
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

API = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = os.environ.get("BUNDLE_ID", "com.tabdanger.redclip")


def say(level, title, message):
    message = str(message).replace("%", "%25").replace("\r", "").replace("\n", "%0A")
    print(f"::{level} title={title}::{message}", flush=True)


def b64url(raw):
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def der_signature_to_raw(der):
    """openssl gives ECDSA signatures as DER; a JWT wants r and s as 32 bytes each."""
    index = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)
    out = b""
    for _ in range(2):
        if der[index] != 0x02:
            raise ValueError("unexpected signature format")
        length = der[index + 1]
        value = der[index + 2:index + 2 + length].lstrip(b"\x00")
        out += value.rjust(32, b"\x00")
        index += 2 + length
    return out


def token(style):
    header = {"alg": "ES256", "kid": os.environ["ASC_KEY_ID"].strip(), "typ": "JWT"}
    now = int(time.time())
    payload = {"iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"}
    if style == "team":
        payload["iss"] = os.environ.get("ASC_ISSUER_ID", "").strip()
    else:
        payload["sub"] = "user"          # an Individual API key
    signing_input = (b64url(json.dumps(header, separators=(",", ":")).encode()) + "." +
                     b64url(json.dumps(payload, separators=(",", ":")).encode())).encode()
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", os.environ["ASC_KEY_PATH"]],
                         input=signing_input, capture_output=True, check=True).stdout
    return signing_input.decode() + "." + b64url(der_signature_to_raw(der))


def call(method, path, body=None, style=None):
    style = style or os.environ.get("ASC_TOKEN_STYLE", "team")
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(API + path, data=data, method=method)
    request.add_header("Authorization", "Bearer " + token(style))
    if data is not None:
        request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            raw = response.read()
            return response.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as error:
        raw = error.read()
        try:
            return error.code, json.loads(raw)
        except Exception:
            return error.code, {"raw": raw.decode(errors="replace")[:400]}


def problem(js):
    errors = js.get("errors") or []
    if errors:
        e = errors[0]
        return f"{e.get('title', '')}: {e.get('detail', '')}".strip(": ")
    return js.get("raw", "")


def check():
    status_by_style = {}
    style, apps = None, None
    for candidate in ("team", "individual"):
        status, js = call("GET", "/v1/apps?limit=200", style=candidate)
        status_by_style[candidate] = (status, problem(js))
        if status == 200:
            style, apps = candidate, js.get("data", [])
            break
    if style is None:
        team = status_by_style.get("team")
        say("error", "API key", f"App Store Connect refused the API key (team key: HTTP {team[0]} {team[1]}; "
            f"individual key: HTTP {status_by_style.get('individual', ('-', ''))[0]}). Check ASC_KEY_ID, ASC_ISSUER_ID "
            "and that ASC_KEY_P8 is the .p8 of that same key, and that the key is still active.")
        sys.exit(1)
    github_env = os.environ.get("GITHUB_ENV")
    if github_env:
        with open(github_env, "a") as f:
            f.write(f"ASC_TOKEN_STYLE={style}\n")
    say("notice", "API key", f"The API key works ({style} key).")
    blocking = []

    app = next((a for a in apps if a.get("attributes", {}).get("bundleId") == BUNDLE_ID), None)
    if app and github_env:
        with open(github_env, "a") as f:
            f.write(f"ASC_APP_ID={app['id']}\n")
    if app:
        a = app["attributes"]
        say("notice", "App record", f"Found the app in App Store Connect: {a.get('name')} ({BUNDLE_ID}), Apple ID {app['id']}.")
    else:
        names = ", ".join(f"{a['attributes'].get('name')} ({a['attributes'].get('bundleId')})" for a in apps) or "none"
        say("error", "App record", f"No app in App Store Connect uses {BUNDLE_ID} (apps this key sees: {names}). "
            "Create it first: App Store Connect › Apps › + › New App, bundle ID com.tabdanger.redclip.")
        if os.environ.get("ALLOW_MISSING_APP") != "1":
            blocking.append("app record")

    status, js = call("GET", f"/v1/bundleIds?filter[identifier]={BUNDLE_ID}&limit=50")
    if status == 200:
        found = any(d["attributes"].get("identifier") == BUNDLE_ID for d in js.get("data", []))
        # Codemagic runs without an APPLE_TEAM_ID secret: the bundle ID's prefix is the Team ID.
        seed = next((d["attributes"].get("seedId") for d in js.get("data", []) if d["attributes"].get("seedId")), None)
        if seed and not os.environ.get("APPLE_TEAM_ID") and github_env:
            with open(github_env, "a") as f:
                f.write(f"APPLE_TEAM_ID={seed}\n")
        say("notice", "Bundle ID", f"{BUNDLE_ID} is {'registered' if found else 'not registered yet (the upload will register it)'}.")
    else:
        say("warning", "Bundle ID", f"Can't read identifiers (HTTP {status} {problem(js)}). Signing needs an Admin API key.")

    status, js = call("GET", "/v1/certificates?limit=200")
    if status == 200:
        kinds = {}
        for c in js.get("data", []):
            kind = c["attributes"].get("certificateType")
            kinds[kind] = kinds.get(kind, 0) + 1
        say("notice", "Certificates", "Signing access OK. Certificates on the account: " +
            (", ".join(f"{k} x{v}" for k, v in kinds.items()) or "none"))
    else:
        say("error", "Certificates", f"This API key can't manage certificates (HTTP {status} {problem(js)}). "
            "Make a key with the Admin role: App Store Connect › Users and Access › Integrations › Team Keys.")
        blocking.append("signing access")
    if blocking:
        sys.exit(1)


def builds():
    """The latest builds of the app and where Apple is with each (processing, valid, invalid)."""
    app_id = os.environ.get("ASC_APP_ID")
    if not app_id:
        say("error", "Builds", "No app record found, so there are no builds to show.")
        sys.exit(1)
    status, js = call("GET", f"/v1/builds?filter[app]={app_id}&sort=-uploadedDate&limit=5&include=preReleaseVersion")
    if status != 200:
        say("error", "Builds", f"Couldn't read builds: HTTP {status} {problem(js)}")
        sys.exit(1)
    versions = {v["id"]: v["attributes"].get("version") for v in js.get("included", []) if v.get("type") == "preReleaseVersions"}
    rows = []
    for b in js.get("data", []):
        a = b["attributes"]
        pre = (b.get("relationships", {}).get("preReleaseVersion", {}) or {}).get("data") or {}
        rows.append(f"{versions.get(pre.get('id'), '?')} ({a.get('version')}): {a.get('processingState')}, "
                    f"uploaded {str(a.get('uploadedDate', '')).replace('T', ' ')}"
                    + (", expired" if a.get("expired") else ""))
    say("notice", "Builds", " | ".join(rows) if rows else "No builds yet (a fresh upload can take a few minutes to appear).")


def next_build():
    """Prints one more than the highest build number App Store Connect has for the app."""
    app_id = os.environ.get("ASC_APP_ID")
    status, js = call("GET", f"/v1/builds?filter[app]={app_id}&sort=-uploadedDate&limit=200")
    if status != 200:
        say("error", "Build number", f"Couldn't read builds: HTTP {status} {problem(js)}")
        sys.exit(1)
    numbers = [int(b["attributes"]["version"]) for b in js.get("data", []) if str(b["attributes"].get("version", "")).isdigit()]
    print(max(numbers, default=0) + 1)


def testflight():
    """Why a build does or doesn't show in the TestFlight app: its beta state, the tester groups,
    which groups have it, and how many testers each group has (counts only, no names)."""
    app_id = os.environ.get("ASC_APP_ID")
    if not app_id:
        say("error", "TestFlight", "No app record found.")
        sys.exit(1)
    status, js = call("GET", f"/v1/builds?filter[app]={app_id}&sort=-uploadedDate&limit=3")
    for b in js.get("data", []) if status == 200 else []:
        a = b["attributes"]
        s2, d = call("GET", f"/v1/builds/{b['id']}/buildBetaDetail")
        detail = d.get("data", {}).get("attributes", {}) if s2 == 200 else {}
        say("notice", "Build " + str(a.get("version")),
            f"processing {a.get('processingState')} · internal testing: {detail.get('internalBuildState', '?')} · "
            f"external testing: {detail.get('externalBuildState', '?')} · encryption declared: {a.get('usesNonExemptEncryption')} · "
            f"minimum iPadOS {a.get('minOsVersion')} · expired {a.get('expired')}")
    status, js = call("GET", f"/v1/apps/{app_id}/betaGroups?limit=50")
    if status != 200:
        say("error", "Tester groups", f"Couldn't read tester groups: HTTP {status} {problem(js)}")
        return
    groups = js.get("data", [])
    if not groups:
        say("warning", "Tester groups", "There are no TestFlight tester groups for this app yet.")
    for g in groups:
        a = g["attributes"]
        s3, t = call("GET", f"/v1/betaGroups/{g['id']}/betaTesters?limit=200")
        testers = len(t.get("data", [])) if s3 == 200 else "?"
        s4, bl = call("GET", f"/v1/betaGroups/{g['id']}/builds?limit=50")
        builds = ", ".join(x["attributes"].get("version", "?") for x in bl.get("data", [])) if s4 == 200 else "?"
        say("notice", "Tester group",
            f"\"{a.get('name')}\" · {'internal' if a.get('isInternalGroup') else 'external'} · "
            f"gets every build automatically: {a.get('hasAccessToAllBuilds')} · testers: {testers} · builds in it: {builds or 'none'}"
            + (f" · public link: {a.get('publicLink')}" if a.get("publicLinkEnabled") else ""))
        for tester in (t.get("data", []) if s3 == 200 else []):
            ta = tester["attributes"]
            say("notice", "Tester", f"in \"{a.get('name')}\": invitation {ta.get('state')} (sent by {ta.get('inviteType')})")


def wait(build_number, minutes=35):
    """Waits until Apple has processed the uploaded build, then adds it to the internal tester
    groups that don't receive every build automatically (otherwise TestFlight shows no builds)."""
    app_id = os.environ.get("ASC_APP_ID")
    deadline = time.time() + minutes * 60
    build, state = None, None
    while time.time() < deadline:
        status, js = call("GET", f"/v1/builds?filter[app]={app_id}&filter[version]={build_number}&limit=5")
        data = js.get("data", []) if status == 200 else []
        if data:
            build = data[0]
            state = build["attributes"].get("processingState")
            print(f"build {build_number}: {state}", flush=True)
            if state in ("VALID", "INVALID", "FAILED"):
                break
        else:
            print(f"build {build_number}: not visible yet", flush=True)
        time.sleep(30)
    if build is None or state == "PROCESSING":
        say("warning", "Processing", f"Apple is still processing build {build_number}. Check again later with mode \"status\".")
        return
    if state != "VALID":
        say("error", "Processing", f"Apple marked build {build_number} {state}. The reason is in the email App Store Connect "
            "sends to the account holder (look for ITMS codes).")
        sys.exit(1)
    say("notice", "Processing", f"Apple finished processing build {build_number}: VALID.")
    status, js = call("GET", f"/v1/apps/{app_id}/betaGroups?limit=50")
    for group in js.get("data", []) if status == 200 else []:
        a = group["attributes"]
        if a.get("isInternalGroup") and not a.get("hasAccessToAllBuilds"):
            s2, j2 = call("POST", f"/v1/betaGroups/{group['id']}/relationships/builds",
                          {"data": [{"type": "builds", "id": build["id"]}]})
            if s2 in (200, 201, 204):
                say("notice", "TestFlight", f"Added build {build_number} to the internal group \"{a.get('name')}\".")
            else:
                say("warning", "TestFlight", f"Couldn't add build {build_number} to \"{a.get('name')}\": HTTP {s2} {problem(j2)}")
    time.sleep(20)
    s3, d = call("GET", f"/v1/builds/{build['id']}/buildBetaDetail")
    if s3 == 200:
        say("notice", "TestFlight", f"Build {build_number}: internal testing {d['data']['attributes'].get('internalBuildState')}.")


def find_build(app_id, build_number):
    if build_number:
        status, js = call("GET", f"/v1/builds?filter[app]={app_id}&filter[version]={build_number}&limit=5")
    else:
        status, js = call("GET", f"/v1/builds?filter[app]={app_id}&filter[processingState]=VALID&sort=-uploadedDate&limit=1")
    data = js.get("data", []) if status == 200 else []
    return data[0] if data else None


def upsert(list_path, item_type, match, attributes, create_relationships):
    """Updates the first item at list_path that `match` accepts, or creates one."""
    status, js = call("GET", list_path)
    existing = next((d for d in js.get("data", []) if match(d["attributes"])), None) if status == 200 else None
    if existing:
        s2, j2 = call("PATCH", f"/v1/{item_type}/{existing['id']}",
                      {"data": {"type": item_type, "id": existing["id"], "attributes": attributes}})
        return s2 == 200, f"HTTP {s2} {problem(j2)}"
    s2, j2 = call("POST", f"/v1/{item_type}", {"data": {"type": item_type, "attributes": attributes,
                                                         "relationships": create_relationships}})
    return s2 == 201, f"HTTP {s2} {problem(j2)}"


def external(build_number):
    """Fills in TestFlight's test information, adds the build to the external group and sends it
    to Beta App Review, so the group's public link can be shared once Apple approves it."""
    app_id = os.environ["ASC_APP_ID"]
    here = os.path.dirname(os.path.abspath(__file__))
    description = open(os.path.join(here, "..", "testflight", "beta-description.txt")).read().strip()
    what_to_test = open(os.path.join(here, "..", "testflight", "what-to-test.txt")).read().strip()
    feedback = os.environ.get("FEEDBACK_EMAIL", "").strip()
    contact = {
        "contactFirstName": os.environ.get("CONTACT_FIRST", "").strip(),
        "contactLastName": os.environ.get("CONTACT_LAST", "").strip(),
        "contactPhone": os.environ.get("CONTACT_PHONE", "").strip(),
        "contactEmail": os.environ.get("CONTACT_EMAIL", "").strip(),
    }

    # Anything left empty keeps what App Store Connect already has (saved by the first
    # submission), so later builds need no typing.
    status, js = call("GET", f"/v1/apps/{app_id}/betaAppLocalizations")
    saved_local = next((d for d in js.get("data", []) if str(d["attributes"].get("locale", "")).startswith("en")), None) if status == 200 else None
    if not feedback and saved_local:
        feedback = (saved_local["attributes"].get("feedbackEmail") or "").strip()
    status, js = call("GET", f"/v1/apps/{app_id}/betaAppReviewDetail")
    if status != 200:
        say("error", "Review contact", f"Couldn't read the review details: HTTP {status} {problem(js)}")
        sys.exit(1)
    detail_id = js["data"]["id"]
    saved = js["data"].get("attributes", {})
    for key in contact:
        if not contact[key]:
            contact[key] = (saved.get(key) or "").strip()
    if not feedback or not all(contact.values()):
        say("error", "External testing", "Feedback email and the review contact (name, phone, email) are all needed, and App Store Connect doesn't have them yet.")
        sys.exit(1)
    contact["demoAccountRequired"] = False

    ok, why = upsert(f"/v1/apps/{app_id}/betaAppLocalizations", "betaAppLocalizations",
                     lambda a: str(a.get("locale", "")).startswith("en"),
                     {"description": description, "feedbackEmail": feedback},
                     {"app": {"data": {"type": "apps", "id": app_id}}})
    if not ok:
        say("error", "Test information", f"Couldn't save the beta description and feedback email: {why}")
        sys.exit(1)
    say("notice", "Test information", "Saved the beta description and feedback email.")

    s2, j2 = call("PATCH", f"/v1/betaAppReviewDetails/{detail_id}",
                  {"data": {"type": "betaAppReviewDetails", "id": detail_id, "attributes": contact}})
    if s2 != 200:
        say("error", "Review contact", f"Couldn't save the review contact: HTTP {s2} {problem(j2)}")
        sys.exit(1)
    say("notice", "Review contact", "Beta App Review contact is set.")

    build = find_build(app_id, build_number)
    if build is None:
        say("error", "Build", f"Build {build_number or '(latest valid)'} isn't in App Store Connect.")
        sys.exit(1)
    number = build["attributes"].get("version")
    if build["attributes"].get("processingState") != "VALID":
        say("error", "Build", f"Build {number} is {build['attributes'].get('processingState')}, not VALID.")
        sys.exit(1)

    ok, why = upsert(f"/v1/builds/{build['id']}/betaBuildLocalizations", "betaBuildLocalizations",
                     lambda a: str(a.get("locale", "")).startswith("en"),
                     {"whatsNew": what_to_test}, {"build": {"data": {"type": "builds", "id": build["id"]}}})
    if ok:
        say("notice", "What to Test", f"Saved the What to Test notes for build {number}.")
    else:
        say("warning", "What to Test", f"Couldn't save the What to Test notes: {why}")

    status, js = call("GET", f"/v1/apps/{app_id}/betaGroups?limit=50")
    groups = [g for g in js.get("data", []) if not g["attributes"].get("isInternalGroup")] if status == 200 else []
    if not groups:
        say("error", "External group", "There is no external tester group.")
        sys.exit(1)
    for group in groups:
        s0, j0 = call("GET", f"/v1/betaGroups/{group['id']}/builds?limit=50")
        if s0 == 200:
            had = sorted((d["attributes"].get("version", "?") for d in j0.get("data", [])), key=lambda v: int(v) if str(v).isdigit() else 0)
            say("notice", "External group", f"\"{group['attributes'].get('name')}\" had builds: {', '.join(had) or 'none'}.")
        s3, j3 = call("POST", f"/v1/betaGroups/{group['id']}/relationships/builds",
                      {"data": [{"type": "builds", "id": build["id"]}]})
        name = group["attributes"].get("name")
        if s3 in (200, 201, 204):
            say("notice", "External group", f"Added build {number} to \"{name}\"."
                + (f" Public link: {group['attributes'].get('publicLink')}" if group["attributes"].get("publicLinkEnabled") else ""))
        else:
            say("warning", "External group", f"Couldn't add build {number} to \"{name}\": HTTP {s3} {problem(j3)}")

    s4, j4 = call("POST", "/v1/betaAppReviewSubmissions",
                  {"data": {"type": "betaAppReviewSubmissions",
                            "relationships": {"build": {"data": {"type": "builds", "id": build["id"]}}}}})
    if s4 == 201:
        say("notice", "Beta App Review", f"Build {number} was sent to Apple for Beta App Review.")
    else:
        say("error", "Beta App Review", f"Apple didn't accept the review submission: HTTP {s4} {problem(j4)}")
        sys.exit(1)
    time.sleep(10)
    s5, d = call("GET", f"/v1/builds/{build['id']}/buildBetaDetail")
    if s5 == 200:
        say("notice", "Beta App Review", f"Build {number}: external testing {d['data']['attributes'].get('externalBuildState')}.")


def tester(email, name, group_kind):
    """Adds one person to a TestFlight group.

    internal: the person must be a member of the App Store Connect team. If they aren't, this
    sends them a team invitation (Developer role, this app only, no certificate access) and
    stops; once they accept it, running this again adds them to the internal group.
    external: adds them to the external group straight away (TestFlight emails them)."""
    app_id = os.environ["ASC_APP_ID"]
    email = email.strip().lower()
    parts = name.strip().split()
    first = parts[0] if parts else ""
    last = " ".join(parts[1:]) if len(parts) > 1 else ""
    if "@" not in email:
        say("error", "Tester", "Give the tester's email address.")
        sys.exit(1)

    status, js = call("GET", f"/v1/apps/{app_id}/betaGroups?limit=50")
    groups = js.get("data", []) if status == 200 else []
    internal = group_kind.strip().lower() != "external"
    group = next((g for g in groups if bool(g["attributes"].get("isInternalGroup")) == internal), None)
    if group is None:
        say("error", "Tester", f"There is no {'internal' if internal else 'external'} tester group.")
        sys.exit(1)
    group_name = group["attributes"].get("name")

    if internal:
        s1, users = call("GET", "/v1/users?limit=200")
        member = next((u for u in users.get("data", []) if str(u["attributes"].get("username", "")).lower() == email), None) \
            if s1 == 200 else None
        if member is None:
            s2, invites = call("GET", "/v1/userInvitations?limit=200")
            pending = next((i for i in invites.get("data", []) if str(i["attributes"].get("email", "")).lower() == email), None) \
                if s2 == 200 else None
            if pending:
                expires = str(pending["attributes"].get("expirationDate") or "")
                still_open = expires > time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime())
                if still_open:
                    # Replacing a live invitation would expire the link already in their inbox.
                    say("notice", "Team invitation",
                        f"{email} already has an open invitation (until {expires}). They accept the email from "
                        "App Store Connect, then run this again to add them to the internal group.")
                    return
                # Expired: Apple has no "resend", so the old invitation is replaced.
                call("DELETE", f"/v1/userInvitations/{pending['id']}")
            body = {"data": {"type": "userInvitations",
                             "attributes": {"email": email, "firstName": first or "Tester", "lastName": last or "Red Clip",
                                            "roles": ["DEVELOPER"], "allAppsVisible": False, "provisioningAllowed": False},
                             "relationships": {"visibleApps": {"data": [{"type": "apps", "id": app_id}]}}}}
            s3, j3 = call("POST", "/v1/userInvitations", body)
            for _ in range(6):
                # Right after an old invitation is removed Apple can still say the email is in
                # use for a little while: wait and try again.
                if s3 != 409:
                    break
                time.sleep(20)
                s3, j3 = call("POST", "/v1/userInvitations", body)
            if s3 == 201:
                say("notice", "Team invitation",
                    f"Invited {email} to the App Store Connect team (Developer role, Red Clip only, no certificate access). "
                    "Apple sends them an email: they accept it and sign in once, then run this again to add them to "
                    f"\"{group_name}\".")
            else:
                say("error", "Team invitation", f"Couldn't invite {email}: HTTP {s3} {problem(j3)}")
                sys.exit(1)
            return

    # Already a tester somewhere? Then just add them to the group.
    s4, found = call("GET", f"/v1/betaTesters?filter[email]={email}&limit=5")
    existing = (found.get("data") or [None])[0] if s4 == 200 else None
    if existing:
        s5, j5 = call("POST", f"/v1/betaGroups/{group['id']}/relationships/betaTesters",
                      {"data": [{"type": "betaTesters", "id": existing["id"]}]})
        ok = s5 in (200, 201, 204)
        why = f"HTTP {s5} {problem(j5)}"
    else:
        attributes = {"email": email}
        if first:
            attributes["firstName"] = first
        if last:
            attributes["lastName"] = last
        s5, j5 = call("POST", "/v1/betaTesters",
                      {"data": {"type": "betaTesters", "attributes": attributes,
                                "relationships": {"betaGroups": {"data": [{"type": "betaGroups", "id": group["id"]}]}}}})
        ok = s5 == 201
        why = f"HTTP {s5} {problem(j5)}"
    if ok:
        say("notice", "Tester", f"Added {email} to \"{group_name}\". TestFlight emails them an invitation to install Red Clip.")
    else:
        say("error", "Tester", f"Couldn't add {email} to \"{group_name}\": {why}")
        sys.exit(1)


def write_state(folder, state):
    with open(os.path.join(folder, "state.json"), "w") as f:
        json.dump(state, f)


PLUGIN_BUNDLE_ID = BUNDLE_ID + ".AUv3"


def bundle_id(identifier, name):
    """The registered App ID for `identifier`, registering it if needed."""
    status, js = call("GET", f"/v1/bundleIds?filter[identifier]={identifier}&limit=50")
    bundle = next((d for d in js.get("data", []) if d["attributes"].get("identifier") == identifier), None) if status == 200 else None
    if bundle is None:
        status, js = call("POST", "/v1/bundleIds", {"data": {"type": "bundleIds", "attributes": {
            "identifier": identifier, "name": name, "platform": "IOS"}}})
        if status != 201:
            say("error", "Bundle ID", f"Couldn't register {identifier}: HTTP {status} {problem(js)}")
            sys.exit(1)
        bundle = js["data"]
        say("notice", "Bundle ID", f"Registered {identifier}.")
    return bundle


def prepare(folder):
    """A temporary distribution certificate and App Store profiles for the app and its AUv3
    plug-in (each needs its own), for when Xcode's cloud signing isn't available."""
    os.makedirs(folder, exist_ok=True)
    state = {}
    bundle = bundle_id(BUNDLE_ID, "Red Clip")
    plugin_bundle = bundle_id(PLUGIN_BUNDLE_ID, "Red Clip AUv3")

    key = os.path.join(folder, "signing.key")
    csr = os.path.join(folder, "signing.csr")
    subprocess.run(["openssl", "req", "-new", "-newkey", "rsa:2048", "-nodes", "-keyout", key, "-out", csr,
                    "-subj", "/CN=Red Clip GitHub upload/O=Red Clip/C=US"], check=True, capture_output=True)
    csr_text = open(csr).read()
    certificate = None
    for kind in ("DISTRIBUTION", "IOS_DISTRIBUTION"):
        status, js = call("POST", "/v1/certificates", {"data": {"type": "certificates", "attributes": {
            "certificateType": kind, "csrContent": csr_text}}})
        if status == 201:
            certificate = js["data"]
            break
        last = f"HTTP {status} {problem(js)}"
    if certificate is None:
        say("error", "Certificate", f"Apple wouldn't create a distribution certificate: {last}. "
            "(An account can hold only a few; revoke unused ones at developer.apple.com › Certificates.)")
        sys.exit(1)
    state["certificate_id"] = certificate["id"]
    write_state(folder, state)
    with open(os.path.join(folder, "signing.cer"), "wb") as f:
        f.write(base64.b64decode(certificate["attributes"]["certificateContent"]))
    say("notice", "Certificate", f"Made a temporary {certificate['attributes'].get('certificateType')} certificate (revoked again after the upload).")

    run = os.environ.get('GITHUB_RUN_ID', int(time.time()))
    for target, key_name, file_name in ((bundle, "profile_id", "profile.mobileprovision"),
                                        (plugin_bundle, "plugin_profile_id", "plugin.mobileprovision")):
        name = f"Red Clip App Store upload {run}" + (" AUv3" if target is plugin_bundle else "")
        status, js = call("POST", "/v1/profiles", {"data": {"type": "profiles",
            "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
            "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": target["id"]}},
                              "certificates": {"data": [{"type": "certificates", "id": certificate["id"]}]}}}})
        if status != 201:
            say("error", "Profile", f"Apple wouldn't create the App Store profile \"{name}\": HTTP {status} {problem(js)}")
            sys.exit(1)
        profile = js["data"]
        state[key_name] = profile["id"]
        write_state(folder, state)
        with open(os.path.join(folder, file_name), "wb") as f:
            f.write(base64.b64decode(profile["attributes"]["profileContent"]))
        say("notice", "Profile", f"Made the App Store profile \"{name}\".")


def cleanup(folder):
    path = os.path.join(folder, "state.json")
    if not os.path.exists(path):
        return
    state = json.load(open(path))
    for key_name in ("profile_id", "plugin_profile_id"):
        if state.get(key_name):
            status, js = call("DELETE", f"/v1/profiles/{state[key_name]}")
            print(f"{key_name} delete: HTTP {status}")
    if state.get("certificate_id"):
        status, js = call("DELETE", f"/v1/certificates/{state['certificate_id']}")
        print(f"certificate revoke: HTTP {status}")
        if status not in (200, 204):
            say("warning", "Certificate", f"Couldn't revoke the temporary certificate (HTTP {status} {problem(js)}); "
                "revoke it at developer.apple.com › Certificates.")


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else "check"
    if command == "check":
        check()
    elif command == "builds":
        builds()
    elif command == "nextbuild":
        next_build()
    elif command == "external":
        external(sys.argv[2] if len(sys.argv) > 2 else "")
    elif command == "wait":
        wait(sys.argv[2])
    elif command == "testflight":
        builds()
        testflight()
    elif command == "tester":
        tester(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "", sys.argv[4] if len(sys.argv) > 4 else "internal")
    elif command == "prepare":
        prepare(sys.argv[2])
    elif command == "cleanup":
        cleanup(sys.argv[2])
    else:
        sys.exit(f"unknown command {command}")
