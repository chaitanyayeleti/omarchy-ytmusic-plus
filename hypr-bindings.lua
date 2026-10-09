-- Load from ~/.config/hypr/bindings.lua with:
-- pcall(dofile, os.getenv("HOME") .. "/.config/omarchy/plugins/local.ytmusic-plus/hypr-bindings.lua")

o.window(
  { class = "^org.quickshell$", title = "^YTMusic Plus$" },
  {
    tag = "-default-opacity",
    float = true,
    size = { 410, 560 },
    move = { 10, 38 },
    rounding = 8,
    focus_on_activate = true,
    opacity = "0.98 0.98",
  }
)

o.bind(
  "SUPER + CTRL + SHIFT + M",
  "YTMusic Plus",
  "omarchy-shell shell toggle local.ytmusic-plus '{}'"
)

-- Media keys. Play/Pause is deliberately NOT bound here: Omarchy's own
-- XF86AudioPlay binding already reaches the player through MPRIS (mpv-mpris),
-- and a second toggle would fight it. Next/Previous DO need a bind: mpv has no
-- playlist of its own, so MPRIS reports canGoNext/canGoPrevious as false and
-- Omarchy's media.next/previous skip us. Stop is unbound upstream too.
local ytmp_cli = os.getenv("HOME") .. "/.config/omarchy/plugins/local.ytmusic-plus/bin/ytmusic-plus"

o.bind("XF86AudioNext", "YTMusic Plus next", ytmp_cli .. " next")
o.bind("XF86AudioPrev", "YTMusic Plus previous", ytmp_cli .. " previous")
o.bind("XF86AudioStop", "YTMusic Plus stop", ytmp_cli .. " stop")
