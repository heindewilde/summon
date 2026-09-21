#!/usr/bin/env python3
"""App Store Connect, from the command line.

The pieces of shipping that have no Xcode button worth clicking: what state a build is
in, getting it in front of testers, and pushing the listing text from a file that can
be reviewed in a diff rather than retyped into a web form.

    Scripts/asc.py builds              # what has been uploaded, and where it got to
    Scripts/asc.py testflight          # latest build of each platform to the testers
    Scripts/asc.py metadata            # docs/store/metadata.json → the listing
    Scripts/asc.py state               # version state for both platforms

Credentials, which this never prints: the .p8 in ~/.appstoreconnect/private_keys,
named by SUMMON_ASC_KEY_ID, plus SUMMON_ASC_ISSUER_ID. The key needs the Admin role —
App Manager cannot mint the distribution certificates an upload is signed with.
"""

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature

API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE_ID = "com.heindewilde.summon"


def b64(data: bytes) -> str:
    import base64

    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def token() -> str:
    """A twenty-minute ES256 token, which is what the API takes instead of a password."""
    key_id = os.environ.get("SUMMON_ASC_KEY_ID")
    issuer = os.environ.get("SUMMON_ASC_ISSUER_ID")
    if not key_id or not issuer:
        sys.exit("Set SUMMON_ASC_KEY_ID and SUMMON_ASC_ISSUER_ID.")
    path = Path.home() / ".appstoreconnect/private_keys" / f"AuthKey_{key_id}.p8"
    if not path.exists():
        sys.exit(f"No key at {path}.")

    private_key = serialization.load_pem_private_key(path.read_bytes(), password=None)
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {
        "iss": issuer,
        "iat": int(time.time()),
        "exp": int(time.time()) + 20 * 60,
        "aud": "appstoreconnect-v1",
    }
    signing_input = f"{b64(json.dumps(header).encode())}.{b64(json.dumps(payload).encode())}"
    der = private_key.sign(signing_input.encode(), ec.ECDSA(hashes.SHA256()))
    r, s = decode_dss_signature(der)
    signature = r.to_bytes(32, "big") + s.to_bytes(32, "big")
    return f"{signing_input}.{b64(signature)}"


def call(method: str, path: str, body=None, tolerate: str | None = None, **params):
    url = f"{API}/{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    request = urllib.request.Request(url, method=method)
    request.add_header("Authorization", f"Bearer {token()}")
    if body is not None:
        request.add_header("Content-Type", "application/json")
        request.data = json.dumps(body).encode()
    try:
        with urllib.request.urlopen(request) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode()
        if tolerate and tolerate in detail:
            return None
        # Apple's errors are specific and worth reading in full; the status alone
        # ("409") never says which field it disliked.
        sys.exit(f"{method} {path} failed ({error.code}):\n{detail}")


def app_id() -> str:
    apps = call("GET", "apps", **{"filter[bundleId]": BUNDLE_ID})["data"]
    if not apps:
        sys.exit(f"No app record for {BUNDLE_ID}. Create it in App Store Connect first.")
    return apps[0]["id"]


def cmd_state() -> None:
    app = app_id()
    for version in call("GET", f"apps/{app}/appStoreVersions", limit=10)["data"]:
        attributes = version["attributes"]
        print(f"{attributes['platform']:10} {attributes['versionString']:8} {attributes['appStoreState']}")


def cmd_builds() -> None:
    builds = call("GET", "builds", **{"filter[app]": app_id(), "limit": 10,
                                      "sort": "-uploadedDate"})["data"]
    if not builds:
        print("Nothing uploaded yet.")
        return
    for build in builds:
        attributes = build["attributes"]
        print(f"{attributes.get('version', '?'):>4}  "
              f"{attributes.get('processingState', '?'):12} "
              f"{attributes.get('uploadedDate', '')}  "
              f"expires: {attributes.get('expired')}")


def cmd_testflight() -> None:
    """Where each uploaded build has got to in TestFlight.

    Internal testers receive every build automatically once it processes — there is
    nothing to attach, and the API refuses if you try ("Cannot add internal group to a
    build"). So this reports rather than acts: `IN_BETA_TESTING` means it is installable
    from TestFlight right now.

    External testing is the one that needs a submission, and a beta review with it.
    """
    app = app_id()
    response = call("GET", "builds", **{"filter[app]": app, "limit": 10,
                                        "sort": "-uploadedDate",
                                        "include": "buildBetaDetail,preReleaseVersion"})
    included = {item["id"]: item for item in response.get("included", [])}
    if not response["data"]:
        print("Nothing uploaded yet.")
        return

    for build in response["data"]:
        pre = build["relationships"].get("preReleaseVersion", {}).get("data")
        platform = included.get(pre["id"], {}).get("attributes", {}).get("platform", "?") if pre else "?"
        detail_ref = build["relationships"].get("buildBetaDetail", {}).get("data")
        detail = included.get(detail_ref["id"], {}).get("attributes", {}) if detail_ref else {}
        print(f"{platform:8} build {build['attributes'].get('version'):>3}  "
              f"processing={build['attributes'].get('processingState'):8}  "
              f"internal={detail.get('internalBuildState')}  "
              f"external={detail.get('externalBuildState')}")


def cmd_metadata() -> None:
    """Pushes docs/store/metadata.json into every version that is still editable.

    A listing is text, and text belongs in a file that can be reviewed in a diff —
    not retyped into a web form twice, once per platform.
    """
    source = Path(__file__).resolve().parent.parent / "docs/store/metadata.json"
    listing = json.loads(source.read_text())
    app = app_id()

    for version in call("GET", f"apps/{app}/appStoreVersions", limit=10)["data"]:
        state = version["attributes"]["appStoreState"]
        platform = version["attributes"]["platform"]
        if state not in {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
                         "METADATA_REJECTED", "WAITING_FOR_REVIEW"}:
            print(f"{platform}: {state} — left alone.")
            continue

        localizations = call("GET", f"appStoreVersions/{version['id']}/appStoreVersionLocalizations")["data"]
        for localization in localizations:
            attributes = dict(listing["version"])
            result = call("PATCH", f"appStoreVersionLocalizations/{localization['id']}",
                          body={"data": {"type": "appStoreVersionLocalizations",
                                         "id": localization["id"],
                                         "attributes": attributes}},
                          tolerate="'whatsNew' cannot be edited")
            if result is None:
                # A first release has nothing to be new against, and Apple refuses the
                # field rather than ignoring it. Kept in the file for the next version.
                attributes.pop("whatsNew", None)
                call("PATCH", f"appStoreVersionLocalizations/{localization['id']}",
                     body={"data": {"type": "appStoreVersionLocalizations",
                                    "id": localization["id"],
                                    "attributes": attributes}})
                print(f"{platform}: updated {localization['attributes']['locale']} (no release notes on a first version).")
            else:
                print(f"{platform}: updated {localization['attributes']['locale']}.")

    # Name, subtitle and privacy policy live on the app, not the version.
    for localization in call("GET", f"apps/{app}/appInfos", limit=5)["data"]:
        infos = call("GET", f"appInfos/{localization['id']}/appInfoLocalizations")["data"]
        for info in infos:
            call("PATCH", f"appInfoLocalizations/{info['id']}",
                 body={"data": {"type": "appInfoLocalizations", "id": info["id"],
                                "attributes": listing["app"]}})
            print(f"app info: updated {info['attributes']['locale']}.")


COMMANDS = {"state": cmd_state, "builds": cmd_builds,
            "testflight": cmd_testflight, "metadata": cmd_metadata}

if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in COMMANDS:
        sys.exit(__doc__)
    COMMANDS[sys.argv[1]]()
