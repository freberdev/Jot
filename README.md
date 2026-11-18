# Jot

The fastest place to capture a thought on macOS. Press a shortcut, type, close. The text is saved for you.

No titles, no folders, no question about where the note should go. Jot does one thing: it shortens the distance between having a thought and having it written down.

- Lives in the menu bar and opens with a global shortcut, ⇧⌘J by default.
- The insertion point is already in the text when the window appears.
- Everything is saved as you type. There is no Save button and nothing to confirm.
- Earlier notes sit in a list beside the text, newest first, with search.
- Notes stay on your Mac. Jot contains no networking code.
- English and Swedish, light and dark.

Requires macOS 26 or later.

## Using Jot

Press the shortcut anywhere to open a new note. Press it again, or Escape, to close. If the window is open but you have clicked into another app, the shortcut brings you back to the note you were writing.

Your earlier notes are listed to the right of the text. ⌘F takes you to the list's search field; from there ↓ moves onto the notes. The note you stand on is shown in the text area straight away, so ⇧⌘J, ⌘F, ↓ is all it takes to be reading your latest note. Return puts the insertion point in it. Escape takes you back to the note you came from.

| Key | In the text | In the list |
|---|---|---|
| ⇧⌘J (configurable) | Close | Close |
| Esc | Close | Back to the note you came from |
| ⌘F | Go to the list's search field | Go to the search field |
| ↓ ↑ | | Move through the notes, showing each one |
| Return, Tab | | Edit the note that is shown, or the first match of a search |
| ⌥⌘S | Hide or show the list | Hide or show the list |
| ⌘N | Start a new note | Start a new note |
| ⇧⌘C | Copy the whole note | Copy the selected note |
| ⌘C | | Copy the selected note, when on the notes |
| ⌘⌫ | | Delete the selected note, when on the notes |
| ⌘Z | | Bring back the note you just deleted, when on the notes |
| ⌘, | Settings | Settings |

In the list, typing always goes to the search field, and typing a search does not change the note you are looking at. Choosing a note clears the search, as do Escape and ⌘N. ↓ moves onto the notes, and that is where ⌘C, ⌘⌫ and ⌘Z act on notes instead of on the search text. A deleted note can be restored with ⌘Z until the window is closed. A click on a note opens it.

The list can be hidden with ⌥⌘S or the button below the text; ⌘F brings it back. Whether it is shown when Jot opens is a setting. Showing the list makes the window wider rather than the text area narrower.

A note that is empty is never saved. A note you empty completely is removed when you close the window or start a new note. Until then, choosing it in the list brings its text back.

Settings let you change the shortcut, open Jot at login, choose whether the list is shown, see where notes are stored, and delete all notes.

## Your notes

Notes are stored as one JSON file each in

```
~/Library/Application Support/Jot/Notes/
```

The folder is readable only by your user account. Each file holds the text and the times the note was created and last changed. Files in the folder that Jot does not recognise are left alone.

Nothing is uploaded, synchronised or analysed. Deleting a note, or clearing the history, removes the files for good; they do not go to the Trash.

Notes are not encrypted by Jot. Turn on FileVault to protect them if your Mac is lost.

## Building

Jot is a Swift package with no dependencies. You need Xcode 26 or later.

```bash
swift test
```

```bash
scripts/build-app.sh --install
```

The script builds `build/Jot.app`, signs it and, with `--install`, copies it to `/Applications`. Without `--install` it only builds.

"Open at login" turns itself on the first time Jot runs from `/Applications`. You can turn it off in Settings.

### Signing

`scripts/build-app.sh` signs with the identity in the environment variable `JOT_SIGN_IDENTITY`, or else the first line of a file named `.signing-identity` in the project folder. With neither, the app is signed ad hoc, which works but makes macOS treat every build as a new app.

```bash
security find-identity -v -p codesigning
```

lists the identities on your Mac. `.signing-identity` is ignored by git.

### A disk image for others

```bash
scripts/build-dmg.sh
```

builds a universal app (Apple silicon and Intel), signs it with a Developer ID certificate, and produces `build/Jot-<version>.dmg`, notarized by Apple.

- The certificate comes from `JOT_RELEASE_IDENTITY` or the first line of `.release-identity`.
- The notarization credentials come from a keychain profile named in `JOT_NOTARY_PROFILE` or the first line of `.notary-profile`. Create the profile once with `xcrun notarytool store-credentials`.

Both files are ignored by git. Without a notary profile the image is signed but not notarized.

### Development options

Two command-line options help when working on Jot:

```bash
open build/Jot.app --args -notesDirectory /tmp/jot-notes -appearance dark
```

`-notesDirectory` keeps your real notes out of the way, and `-appearance` (`dark` or `light`) overrides the system setting.

### Layout

- `Sources/JotCore` holds the logic: notes on disk, autosave, search, the key table. It does not use AppKit and is covered by the tests in `Tests/JotCoreTests`.
- `Sources/Jot` is the app: the floating panel, the views, the global shortcut and settings.
- `Resources` holds `Info.plist`, the icon and the English and Swedish strings.
- `scripts/make-icon.swift` draws the icon: `swift scripts/make-icon.swift`.

## License

MIT. See [LICENSE](LICENSE).
