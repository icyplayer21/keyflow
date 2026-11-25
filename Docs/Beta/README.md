# Keyflow Beta — read me first

Thanks for testing Keyflow, a typing trainer for the Mac. This is
**Keyflow {{VERSION}}**: a beta, so expect rough edges, and please tell me
about them.

## What you need

- A Mac with **macOS {{MIN_MACOS}} (Sequoia) or later**.
- An Apple silicon or Intel Mac. Keyflow is built for both, but this beta
  has only been tried on Apple silicon so far, so Intel reports are
  especially welcome.
- A keyboard with the US English (QWERTY) layout gives the most accurate
  finger guidance. Other layouts work for typing, but the technique checks
  are written for US QWERTY.

## Install

1. Double-click **{{DMG}}**. A window called "{{VOLUME}}" opens.
2. Drag **Keyflow** onto the **Applications** folder in that window.
3. Eject "{{VOLUME}}" (the eject button next to it in the Finder sidebar).
   You can then delete the .dmg file.

## First launch: macOS will block it once

This beta is **not notarized** by Apple: notarization needs a paid Apple
developer account, and this is a hobby beta. macOS therefore refuses to open
it the first time. That is expected, and you only need to allow it once:

1. Open **Applications** and double-click **Keyflow**. macOS says it can't
   verify Keyflow. Click **Done** (not "Move to Trash").
2. Open **System Settings ▸ Privacy & Security**, and scroll down to
   **Security**. You'll see a message that "Keyflow" was blocked.
3. Click **Open Anyway**, and confirm with your password or Touch ID.
4. In the dialog that follows, click **Open Anyway** again.

After that, Keyflow opens normally like any other app. This allows only
Keyflow; Gatekeeper stays on for everything else. Please don't turn off
Gatekeeper or use Terminal commands to get round this.

If "Open Anyway" doesn't appear, try opening Keyflow once more, then go back to
Privacy & Security; the button appears for about an hour after a blocked
attempt.

## Using it

Keyflow opens on Practice. The bar at the top has **Learn**, **Practice**, **Test**
and **Progress**. Learn opens on **Today**: today's Daily Flow with one Start
button, the days you practised this week, and a way back into Lessons, Finger
Focus and Key Repetition. Prefer a sidebar? Click
the button at the right end of the bar, or press ⌥⌘S; press it again to switch
back. Settings are under **Keyflow ▸ Settings…** (⌘,).

Keyflow does not need any special permissions. It only reads the keys you type
while its window is in front, and nothing you type leaves your Mac.

## Send feedback

{{FEEDBACK}}

Everything is welcome: bugs, crashes, things that look wrong, typing that is
counted wrong, ideas, and trouble installing. Screenshots help a lot
(⇧⌘4 takes one). The testing checklist that came with this README lists
things worth trying.

## Uninstall

1. Quit Keyflow (⌘Q).
2. Drag **Keyflow** from Applications to the Trash.

That leaves your practice history on the Mac, so a later beta can pick it up.
To remove it too, open Finder, choose **Go ▸ Go to Folder…** (⇧⌘G), and move
these to the Trash:

- `~/Library/Application Support/Keyflow`
- `~/Library/Preferences/app.keyflow.Keyflow.plist`

## Updating to a later beta

Quit Keyflow, then install the new DMG the same way and choose **Replace**
when asked. Your history and settings are kept.
