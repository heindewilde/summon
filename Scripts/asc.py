#!/usr/bin/env python3
"""App Store Connect, from the command line.

The pieces of shipping that have no Xcode button worth clicking: what state a build is
in, getting it in front of testers, and pushing the listing text from a file that can
be reviewed in a diff rather than retyped into a web form.

    Scripts/asc.py builds              # what has been uploaded, and where it got to
    Scripts/asc.py testflight          # latest build of each platform to the testers
    Scripts/asc.py metadata            # docs/store/metadata.json → the listing
    Scripts/asc.py state               # version state for both platforms
    Scripts/asc.py screenshots         # docs/screenshots/appstore → the listing
    Scripts/asc.py ready               # what is still missing before submission

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


# Which file belongs to which of Apple's display sizes. The name decides, so a new
# screenshot needs no code — only the right prefix and the right pixels.
SCREENSHOT_SETS = {
    "iphone-": ("APP_IPHONE_67", (1320, 2868)),
    "ipad-": ("APP_IPAD_PRO_3GEN_129", (2064, 2752)),
    "mac-": ("APP_DESKTOP", (2880, 1800)),
}

# A set belongs to one platform's version; sending an iPhone frame to the Mac listing
# is rejected, slowly, after the upload.
SET_PLATFORMS = {"APP_IPHONE_67": "IOS", "APP_IPAD_PRO_3GEN_129": "IOS",
                 "APP_DESKTOP": "MAC_OS"}


def cmd_screenshots() -> None:
    """Uploads docs/screenshots/appstore to the listing, replacing what is there.

    Three steps per image, which is why this is a command and not a drag: reserve a
    slot and get back the pieces to upload, PUT the bytes at each one, then commit with
    an MD5 of the file so Apple can tell a truncated upload from a finished one.
    """
    import hashlib

    directory = Path(__file__).resolve().parent.parent / "docs/screenshots/appstore"
    images = sorted(p for p in directory.glob("*.png"))
    if not images:
        sys.exit(f"No screenshots in {directory}.")

    app = app_id()
    versions = {v["attributes"]["platform"]: v
                for v in call("GET", f"apps/{app}/appStoreVersions", limit=10)["data"]}

    for platform, version in versions.items():
        localization = call("GET", f"appStoreVersions/{version['id']}/appStoreVersionLocalizations")["data"][0]
        existing = {s["attributes"]["screenshotDisplayType"]: s
                    for s in call("GET", f"appStoreVersionLocalizations/{localization['id']}/appScreenshotSets")["data"]}

        for prefix, (display_type, size) in SCREENSHOT_SETS.items():
            if SET_PLATFORMS[display_type] != platform:
                continue
            files = [p for p in images if p.name.startswith(prefix)]
            if not files:
                continue

            screenshot_set = existing.get(display_type)
            if screenshot_set is None:
                screenshot_set = call("POST", "appScreenshotSets", body={"data": {
                    "type": "appScreenshotSets",
                    "attributes": {"screenshotDisplayType": display_type},
                    "relationships": {"appStoreVersionLocalization": {"data": {
                        "type": "appStoreVersionLocalizations", "id": localization["id"]}}},
                }})["data"]
            else:
                # Replaced rather than added to: uploading twice otherwise leaves the
                # old frames beside the new ones, in an order nobody chose.
                for old in call("GET", f"appScreenshotSets/{screenshot_set['id']}/appScreenshots")["data"]:
                    call("DELETE", f"appScreenshots/{old['id']}")

            for image in files:
                data = image.read_bytes()
                reserved = call("POST", "appScreenshots", body={"data": {
                    "type": "appScreenshots",
                    "attributes": {"fileSize": len(data), "fileName": image.name},
                    "relationships": {"appScreenshotSet": {"data": {
                        "type": "appScreenshotSets", "id": screenshot_set["id"]}}},
                }})["data"]

                for operation in reserved["attributes"]["uploadOperations"]:
                    chunk = data[operation["offset"]:operation["offset"] + operation["length"]]
                    request = urllib.request.Request(operation["url"], method=operation["method"],
                                                     data=chunk)
                    for header in operation["requestHeaders"]:
                        request.add_header(header["name"], header["value"])
                    urllib.request.urlopen(request).read()

                call("PATCH", f"appScreenshots/{reserved['id']}", body={"data": {
                    "type": "appScreenshots", "id": reserved["id"],
                    "attributes": {"uploaded": True,
                                   "sourceFileChecksum": hashlib.md5(data).hexdigest()},
                }})
                print(f"{platform}: {image.name} → {display_type}")


def cmd_ready() -> None:
    """What Apple still wants, asked of Apple rather than remembered.

    Two of these cannot be answered through the API at all — the privacy questionnaire
    and the CloudKit schema — so they are listed as reminders rather than checked.
    """
    app = app_id()
    info = call("GET", f"apps/{app}/appInfos", limit=5)["data"][0]
    full = call("GET", f"appInfos/{info['id']}", include="primaryCategory,secondaryCategory")
    categories = [i["id"] for i in full.get("included", []) if i["type"] == "appCategories"]

    print(f"categories        {', '.join(categories) if categories else 'MISSING'}")
    for localization in call("GET", f"appInfos/{info['id']}/appInfoLocalizations")["data"]:
        attributes = localization["attributes"]
        print(f"name              {attributes.get('name')}")
        print(f"subtitle          {attributes.get('subtitle')}")
        print(f"privacy policy    {'set' if attributes.get('privacyPolicyUrl') else 'MISSING'}")

    try:
        call("GET", f"apps/{app}/appPriceSchedule")
        print("price             set")
    except SystemExit:
        print("price             MISSING")

    for version in call("GET", f"apps/{app}/appStoreVersions", limit=10)["data"]:
        platform = version["attributes"]["platform"]
        detail = call("GET", f"appStoreVersions/{version['id']}", include="build,appStoreReviewDetail")
        included = {item["type"] for item in detail.get("included", [])}
        localization = call("GET", f"appStoreVersions/{version['id']}/appStoreVersionLocalizations")["data"][0]
        shots = sum(len(call("GET", f"appScreenshotSets/{s['id']}/appScreenshots")["data"])
                    for s in call("GET", f"appStoreVersionLocalizations/{localization['id']}/appScreenshotSets")["data"])
        attributes = localization["attributes"]
        print(f"\n{platform}  {version['attributes']['appStoreState']}")
        print(f"  build           {'attached' if 'builds' in included else 'MISSING'}")
        print(f"  review details  {'set' if 'appStoreReviewDetails' in included else 'MISSING'}")
        print(f"  description     {len(attributes.get('description') or '')} characters")
        print(f"  keywords        {'set' if attributes.get('keywords') else 'MISSING'}")
        print(f"  screenshots     {shots}")

    print("\nNot visible to this API, and both are yours to do in a browser:")
    print("  · App privacy answers  — App Store Connect › App Privacy › Data Not Collected")
    print("  · CloudKit schema      — CloudKit Console › Record Types › Deploy Schema Changes")


COMMANDS = {"state": cmd_state, "ready": cmd_ready, "builds": cmd_builds, "screenshots": cmd_screenshots,
            "testflight": cmd_testflight, "metadata": cmd_metadata}

if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in COMMANDS:
        sys.exit(__doc__)
    COMMANDS[sys.argv[1]]()
