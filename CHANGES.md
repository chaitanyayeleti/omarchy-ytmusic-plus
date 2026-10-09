# YTMusic Plus — Local Change Log

Consolidated record of the modifications made to this checkout. The
release-note format (with the full upstream history) lives in
[CHANGELOG.md](CHANGELOG.md); this file is the single-document summary of
the local work, newest first.

---

## v2.6.0 — Tidy release

- `test/run.sh`: in-repo offline regression suite (fake HOME/XDG sandbox,
  generated opus, null audio, 25 checks; MPRIS asserted by sandbox pid).
- Settings tab: hairline dividers between sections (SectionHeader).
- Now playing: 64 px artwork with an accent halo while playing.

---

## v2.5.0 — Interaction polish

- **Seek bar scrub preview**: a time bubble follows the pointer while
  hovering/dragging, clamped to the bar's ends, fades in/out.
- **Feedback pill**: notices/errors render inside a rounded accent (notice)
  or red (error) wash instead of a bare colored line; text elides and the
  full message is in the hover tooltip.
- **Empty states**: each empty tab (Find/Queue/Playlist/Favourite/Local)
  shows its own dimmed dock glyph above the guidance text.
- **Search field**: leading magnifier that accents on focus, plus a
  one-tap clear (×) button whenever text is present.
- **Wheel volume**: scrolling over the −/70/+ cluster nudges the volume.
- **Shortcut hints in tooltips**: Play/Pause · Space, Save · F,
  Download · D, dock tabs · 1–8.
- All new animations go through `Style.duration()` (respects reduce-motion).

## v2.4.0 — Modern face

- **Icon dock**: the 8 text tabs became uniform icon cells
  (compass / magnify / playlist-play / playlist-music / heart / download /
  note / cog) with the tab name in the hover tooltip and its number
  (1–8); sliding highlight keeps a constant width; icons scale on hover.
  Every glyph was verified against the installed Nerd Font before use.
- **Ambient backdrop**: the current cover, blurred on the GPU
  (`MultiEffect`), slightly desaturated/darkened, sits behind every
  surface; fades in/out per track; a surface wash keeps text contrast
  over bright artwork. Replaces the old flat 5% image.

## v2.3.0 — Desktop-native

- **Reboot-proof session**: queue + current track + position are
  snapshotted to `~/.local/share/omarchy-ytmusic-plus/session.json`
  (atomic, throttled from status polls); new `session-restore` command
  rehydrates it on shell start (idempotent); cold-start play resumes
  mid-track via mpv `--start` instead of restarting from zero;
  `queue-clear` drops the snapshot; 512 KB caps, 30-day resume age cap.
- **MPRIS integration** (via mpv-mpris, part of Omarchy's base packages):
  - real title/artist pushed with `--force-media-title` (streams would
    otherwise show a bare googlevideo URL; locals keep their tags),
  - cover art pushed with `--cover-art-files` from a cached thumbnail
    (`~/.cache/omarchy-ytmusic-plus/art-<id>.jpg`, 1 MB cap) because
    resolved stream URLs carry none — mpv-mpris prefers it over every
    other art source,
  - the Omarchy media panel, OSD and lockscreen widgets now show the
    real track; Play/Pause media keys work through MPRIS.
- **Media keys**: `XF86AudioNext/Previous/Stop` bound in
  `hypr-bindings.lua` (Play/Pause deliberately left to Omarchy's own
  binding — a second toggle would fight it; MPRIS reports
  canGoNext/Previous as false for mpv, so Next/Prev need the binds).
- **In-player keyboard shortcuts**: Space play/pause · ←/→ seek ±5 s ·
  ↑/↓ volume · `/` search · `f` save · `d` download · `1–8` switch tabs.
- `togglePlayback` cold start now resumes the on-air track (backend
  state) instead of always queue[0].

## Files touched

| File | Change |
|---|---|
| `bin/ytmusic-plus` | session snapshot/restore (`snapshot_session`, `snapshot_session_live`, `maybe_snapshot`), `session-restore` command, mid-track resume, MPRIS args + art cache (`mpris_installed`, `art_for`, `build_mpris_args`), `queue-clear`/empty-queue session cleanup |
| `Player.qml` | shortcuts, resume-aware toggle, blurred ambient backdrop, icon dock, scrub preview, feedback pill, empty-state glyphs, search clear, wheel volume, shortcut tooltips, version stamp |
| `BarWidget.qml` | `session-restore` on shell start (idempotent) + status refresh |
| `hypr-bindings.lua` | media-key binds with rationale comments |
| `manifest.json` / `CHANGELOG.md` / `README.md` | version bumps, release notes, docs (session file, art cache, media keys, privacy note for the ytimg art fetch) |

## Verification performed

- Codified in `test/run.sh` (v2.6.0): offline sandbox covering queue →
  play → seek → throttled snapshot → stop (live snapshot) → runtime wipe →
  restore → resume at the saved position → dead polls preserve position →
  `next` advances the session → `queue-clear` drops it; plus static
  syntax checks. 25/25 passing.
- Ad-hoc during development: MPRIS `xesam:title` + `mpris:artUrl` on real
  and sandboxed playback; real-environment popup open/close after each UI
  slice with zero QML errors in the shell log.

## Local integration (outside this repository)

- Installed at `~/.config/omarchy/plugins/local.ytmusic-plus` (with
  `.git`), enabled via `omarchy plugin enable local.ytmusic-plus`.
- `~/.config/hypr/bindings.lua` ends with
  `pcall(dofile, os.getenv("HOME") .. "/.config/omarchy/plugins/local.ytmusic-plus/hypr-bindings.lua")`
  (backup: `bindings.lua.bak.1791575492`); `hyprctl reload` +
  `configerrors` clean.
- Repo: `github.com/chaitanyayeleti/omarchy-ytmusic-plus` — the built-in
  anti-hijack check verifies this origin (https or ssh); anything else is
  refused with exit 2. Install with
  `omarchy plugin add https://github.com/chaitanyayeleti/omarchy-ytmusic-plus.git --enable`.
- Commits: `0f24ff6` (v2.3.0), `02ac1d8` (v2.4.0), `5a920a5` (v2.5.0),
  `b30c2c7` (v2.5.1 rebrand), v2.6.0 tidy release.
- The original upstream is kept as a local `upstream` remote for merging
  future fixes; it is not referenced by any shipped code.
