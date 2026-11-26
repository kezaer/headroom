#!/bin/sh
set -eu
exec python3 - "$@" <<'PYTHON'
import argparse
from pathlib import Path
import re

parser = argparse.ArgumentParser(description="List or remove Pacemark test preference files.")
mode = parser.add_mutually_exclusive_group()
mode.add_argument("--delete", action="store_true")
mode.add_argument("--count", action="store_true")
args = parser.parse_args()
prefixes = """
AccountEmailContinuityTests-
CompanionDemoModeTests.
DemoScreenshotDataVariantsTests.
HeadroomT3Antigravity.
HeadroomT3Safety.
HeadroomT3Tests.
co.zantos.headroom.app-interactions.
co.zantos.headroom.bench.
co.zantos.headroom.bench.accounts.
co.zantos.headroom.capability-demo.
co.zantos.headroom.check-now-generation.
co.zantos.headroom.demo.accounts.
co.zantos.headroom.demo.multi.
co.zantos.headroom.loading-render.
co.zantos.headroom.menu-bar-sizing.
co.zantos.headroom.notifications-pane.
co.zantos.headroom.popover-columns.
co.zantos.headroom.popover-height-fit.
co.zantos.headroom.render.
co.zantos.headroom.render.accounts.
co.zantos.headroom.tests.settings-drain.
co.zantos.headroom.update-test.
headroom.banked-notice.
headroom.banked-resets.
headroom.checknow.composition.
headroom.checknow.identity.
headroom.checknow.mac.
headroom.claude-identity.tests.
headroom.continuity-cache.tests.
headroom.continuity.tests.
headroom.copilot-provider.tests.
headroom.default-login.tests.
headroom.demo-fixture.tests.
headroom.demo-parity.tests.
headroom.display-merge.grok.
headroom.display.tests.
headroom.footer-sources.
headroom.fullrefresh.
headroom.identity-refusal.tests.
headroom.merged-rows.
headroom.notification-coordinator.
headroom.notification-prefs.
headroom.notification-store.
headroom.opencode-store.tests.
headroom.phone-display.
headroom.phone-projection.
headroom.phone-triggers.
headroom.pollphasing.tests.
headroom.publisher.
headroom.refresh-run.
headroom.remembered-aging.tests.
headroom.remembered-rows.
headroom.render-harness.tests.
headroom.scheduler.tests.
headroom.session-composition.tests.
headroom.session-reliability.tests.
headroom.signout.
headroom.signout.tests.
headroom.tests.
headroom.tests.default-login-records.
headroom.use-it-up.
headroom.widget-cache.tests.
PacemarkT3Antigravity.
PacemarkT3Safety.
PacemarkT3Tests.
org.pacemark.app-interactions.
org.pacemark.banked-notice.
org.pacemark.banked-resets.
org.pacemark.bench.
org.pacemark.bench.accounts.
org.pacemark.capability-demo.
org.pacemark.check-now-generation.
org.pacemark.checknow.composition.
org.pacemark.checknow.identity.
org.pacemark.checknow.mac.
org.pacemark.claude-identity.tests.
org.pacemark.continuity-cache.tests.
org.pacemark.continuity.tests.
org.pacemark.copilot-provider.tests.
org.pacemark.default-login.tests.
org.pacemark.demo-fixture.tests.
org.pacemark.demo-parity.tests.
org.pacemark.demo.accounts.
org.pacemark.demo.multi.
org.pacemark.display-merge.grok.
org.pacemark.display.tests.
org.pacemark.footer-sources.
org.pacemark.fullrefresh.
org.pacemark.identity-refusal.tests.
org.pacemark.loading-render.
org.pacemark.menu-bar-sizing.
org.pacemark.merged-rows.
org.pacemark.notification-coordinator.
org.pacemark.notification-prefs.
org.pacemark.notification-store.
org.pacemark.notifications-pane.
org.pacemark.opencode-store.tests.
org.pacemark.phone-display.
org.pacemark.phone-projection.
org.pacemark.phone-triggers.
org.pacemark.pollphasing.tests.
org.pacemark.popover-columns.
org.pacemark.popover-height-fit.
org.pacemark.publisher.
org.pacemark.refresh-run.
org.pacemark.remembered-aging.tests.
org.pacemark.remembered-rows.
org.pacemark.render-harness.tests.
org.pacemark.render.
org.pacemark.render.accounts.
org.pacemark.scheduler.tests.
org.pacemark.session-composition.tests.
org.pacemark.session-reliability.tests.
org.pacemark.signout.
org.pacemark.signout.tests.
org.pacemark.tests.
org.pacemark.tests.default-login-records.
org.pacemark.tests.settings-drain.
org.pacemark.update-test.
org.pacemark.use-it-up.
org.pacemark.widget-cache.tests.
""".split()
hex_digit = "[0-9A-Fa-f]"
uuid = rf"{hex_digit}{{8}}(?:-{hex_digit}{{4}}){{3}}-{hex_digit}{{12}}"
known = "(?:" + "|".join(map(re.escape, prefixes)) + ")"
qa = re.escape("org.pacemark.qa.")
pattern = re.compile(rf"(?:{known}{uuid}|{qa}(?:{uuid}|{hex_digit}{{32}}))\.plist")
directory = Path.home() / "Library/Preferences"
paths = sorted(p for p in directory.iterdir() if pattern.fullmatch(p.name) and not p.is_symlink() and p.is_file())
for p in paths:
    if not args.count:
        print(p.name)
    if args.delete:
        p.unlink()
print(f"{'Removed' if args.delete else 'Matched'} {len(paths)} files")
PYTHON
