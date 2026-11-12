#!/usr/bin/env python3
"""Puts an uploaded build in front of the public TestFlight group.

Waits for App Store Connect to finish processing the build, then gives it its
What to Test text, adds it to the group and submits it for beta review. Every
step may already be done, so running it again is safe.

Reads APP_ID, BETA_GROUP_NAME, KEY_ID, ISSUER_ID and KEY_PATH from the
environment. Uses only the standard library and the openssl command.

With --update-feed it instead writes what the apps read to learn of an update:
the newest build public testers can install now. A build still waiting for beta
review does not count, so nobody is told about a build they cannot get. Given a
build number, it waits a while for that build first. Writes nothing when no
build can be installed yet.

Usage: publish-testflight.py <build number> [--dry-run]
       publish-testflight.py --update-feed <file> [<build number to wait for>]
"""

import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com"
WHAT_TO_TEST = "Fixes and improvements. Please tell us about anything that looks wrong."
PROCESSING_TIMEOUT_SECONDS = 60 * 60
POLL_INTERVAL_SECONDS = 30
BETA_REVIEW_WAIT_SECONDS = 30 * 60


def encode(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=")


def read_der_integer(signature, offset):
    """Returns the bytes of the DER integer at offset, and the offset after it."""
    if signature[offset] != 0x02:
        raise ValueError("publish-testflight: the signature is not two integers")
    length = signature[offset + 1]
    start = offset + 2
    return signature[start : start + length], start + length


def raw_signature(der):
    """ES256 in a token is r and s side by side, 32 bytes each; openssl writes DER."""
    start = 3 if der[1] & 0x80 else 2
    first, offset = read_der_integer(der, start)
    second, _ = read_der_integer(der, offset)
    return first.lstrip(b"\0").rjust(32, b"\0") + second.lstrip(b"\0").rjust(32, b"\0")


def make_token():
    now = int(time.time())
    header = {"alg": "ES256", "kid": os.environ["KEY_ID"], "typ": "JWT"}
    claims = {"iss": os.environ["ISSUER_ID"], "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"}
    signing_input = encode(json.dumps(header).encode()) + b"." + encode(json.dumps(claims).encode())
    der = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", os.environ["KEY_PATH"]],
        input=signing_input,
        capture_output=True,
        check=True,
    ).stdout
    return (signing_input + b"." + encode(raw_signature(der))).decode()


def call(method, path, body=None):
    """Returns the status and the decoded answer. A refusal is returned, not raised."""
    request = urllib.request.Request(API + path, method=method)
    request.add_header("Authorization", "Bearer " + make_token())
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, data, timeout=60) as response:
            text = response.read()
            return response.status, json.loads(text) if text else {}
    except urllib.error.HTTPError as error:
        text = error.read()
        return error.code, json.loads(text) if text else {}


def require(status, answer, action):
    if status >= 300:
        details = [item.get("detail", "") for item in answer.get("errors", [])]
        sys.exit(f"publish-testflight: {action} failed with {status}: {details}")
    return answer


def find_build(app_id, version):
    query = urllib.parse.urlencode({"filter[app]": app_id, "filter[version]": version, "fields[builds]": "version,processingState"})
    answer = require(*call("GET", f"/v1/builds?{query}"), "reading the build")
    return answer["data"][0] if answer["data"] else None


def wait_for_build(app_id, version):
    deadline = time.time() + PROCESSING_TIMEOUT_SECONDS
    while time.time() < deadline:
        build = find_build(app_id, version)
        state = build["attributes"]["processingState"] if build else "not listed yet"
        print(f"build {version}: {state}", flush=True)
        if build and state == "VALID":
            return build["id"]
        if state in ("FAILED", "INVALID"):
            sys.exit(f"publish-testflight: build {version} is {state}")
        time.sleep(POLL_INTERVAL_SECONDS)
    sys.exit(f"publish-testflight: build {version} was not ready in time")


def find_group(app_id, name):
    query = urllib.parse.urlencode({"filter[app]": app_id, "filter[name]": name, "filter[isInternalGroup]": "false"})
    answer = require(*call("GET", f"/v1/betaGroups?{query}"), "reading the group")
    if len(answer["data"]) != 1:
        sys.exit(f"publish-testflight: expected one group named {name}, found {len(answer['data'])}")
    return answer["data"][0]["id"]


def set_what_to_test(build_id):
    answer = require(*call("GET", f"/v1/builds/{build_id}/betaBuildLocalizations"), "reading What to Test")
    if answer["data"]:
        for localization in answer["data"]:
            if localization["attributes"].get("whatsNew"):
                continue
            body = {"data": {"type": "betaBuildLocalizations", "id": localization["id"], "attributes": {"whatsNew": WHAT_TO_TEST}}}
            require(*call("PATCH", f"/v1/betaBuildLocalizations/{localization['id']}", body), "writing What to Test")
        return
    body = {
        "data": {
            "type": "betaBuildLocalizations",
            "attributes": {"locale": "en-US", "whatsNew": WHAT_TO_TEST},
            "relationships": {"build": {"data": {"type": "builds", "id": build_id}}},
        }
    }
    require(*call("POST", "/v1/betaBuildLocalizations", body), "writing What to Test")


def submit_for_review(build_id):
    body = {"data": {"type": "betaAppReviewSubmissions", "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}}
    status, answer = call("POST", "/v1/betaAppReviewSubmissions", body)
    if status == 409:
        details = " ".join(item.get("detail", "") for item in answer.get("errors", []))
        print(f"not submitted again: {details}")
        return
    require(status, answer, "submitting for beta review")


def find_installable_build(app_id, group_id):
    """Returns the version and number of the newest build the group can install, or None."""
    query = urllib.parse.urlencode(
        {
            "filter[app]": app_id,
            "filter[betaGroups]": group_id,
            "filter[expired]": "false",
            "filter[processingState]": "VALID",
            "sort": "-uploadedDate",
            "limit": "20",
            "include": "buildBetaDetail,preReleaseVersion",
            "fields[builds]": "version,buildBetaDetail,preReleaseVersion",
            "fields[buildBetaDetails]": "externalBuildState",
            "fields[preReleaseVersions]": "version",
        }
    )
    answer = require(*call("GET", f"/v1/builds?{query}"), "reading the group's builds")
    included = {(item["type"], item["id"]): item["attributes"] for item in answer.get("included", [])}
    newest = None
    for build in answer["data"]:
        detail = build["relationships"]["buildBetaDetail"]["data"]
        version = build["relationships"]["preReleaseVersion"]["data"]
        if included.get((detail["type"], detail["id"]), {}).get("externalBuildState") != "IN_BETA_TESTING":
            continue
        number = int(build["attributes"]["version"])
        if newest is None or number > newest["build"]:
            newest = {"version": included[(version["type"], version["id"])]["version"], "build": number}
    return newest


def write_update_feed(path, wanted_build):
    app_id = os.environ["APP_ID"]
    group_id = find_group(app_id, os.environ["BETA_GROUP_NAME"])
    deadline = time.time() + BETA_REVIEW_WAIT_SECONDS
    newest = find_installable_build(app_id, group_id)
    while wanted_build is not None and (newest is None or newest["build"] < wanted_build) and time.time() < deadline:
        print(f"build {wanted_build}: not installable yet, newest is {newest}", flush=True)
        time.sleep(POLL_INTERVAL_SECONDS)
        newest = find_installable_build(app_id, group_id)
    if newest is None:
        print("no build can be installed yet")
        return
    with open(path, "w", encoding="utf-8") as feed:
        json.dump(newest, feed)
    print(f"update feed: {newest}")


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "--update-feed":
        write_update_feed(sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else None)
        return
    arguments = [argument for argument in sys.argv[1:] if argument != "--dry-run"]
    if len(arguments) != 1:
        sys.exit(__doc__)
    is_dry_run = "--dry-run" in sys.argv
    version = arguments[0]
    app_id = os.environ["APP_ID"]
    group_id = find_group(app_id, os.environ["BETA_GROUP_NAME"])
    if is_dry_run:
        build = find_build(app_id, version)
        print("group found;", "build found:" if build else "build not found", build["attributes"] if build else "")
        return
    build_id = wait_for_build(app_id, version)
    set_what_to_test(build_id)
    body = {"data": [{"type": "builds", "id": build_id}]}
    require(*call("POST", f"/v1/betaGroups/{group_id}/relationships/builds", body), "adding the build to the group")
    submit_for_review(build_id)
    detail = require(*call("GET", f"/v1/builds/{build_id}/buildBetaDetail"), "reading the result")
    print(f"build {version}: external state {detail['data']['attributes'].get('externalBuildState')}")


if __name__ == "__main__":
    main()
