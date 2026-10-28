"""Finder layout for the transparent 660 x 360 drag-to-install guide."""

# dmgbuild supplies `defines` from make-dmg.sh, keeping all paths relocatable.
format = "UDZO"
filesystem = "HFS+"
files = [defines["app"]]
symlinks = {"Applications": defines["applications"]}
background = defines["background"]

window_rect = ((200, 150), (660, 360))
default_view = "icon-view"
include_icon_view_settings = True
include_list_view_settings = False
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
arrange_by = None
scroll_position = (0, 0)
icon_size = 128
text_size = 14
label_pos = "bottom"
icon_locations = {
    "TimingBomb.app": (160, 160),
    "Applications": (500, 160),
}
