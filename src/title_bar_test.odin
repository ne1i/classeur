package classeur

import "core:testing"
import "gt:testkit/session"

// The sidebar closed: the title bar's head keeps the sidebar's button whole, before the first tabs, with no logo (the
// head took the sidebar's width, 0 once closed: the logo and the button ran over the first tab).
@(test)
test_the_head_keeps_its_button_when_the_sidebar_closes :: proc(t: ^testing.T) {
	dir := make_fixture(t, {"a.txt"})
	s, app := start(t, {dir})
	testing.expect(t, session.find(s, "logo") != nil, "the sidebar open: the logo")
	act_toggle_sidebar(app)
	session.frames(s, 3)
	testing.expect(t, !sidebar_shown(app), "the sidebar closed")
	testing.expect(t, session.find(s, "logo") == nil, "no logo in a head too narrow for it")
	head, button, tabs := session.find(s, "head"), session.find(s, "sidebar"), session.find(s, "tabs0")
	if !testing.expect(t, head != nil && button != nil && tabs != nil, "the head, its button and the first tabs") { return }
	testing.expectf(t, button.rect.min.x >= head.rect.min.x && button.rect.max.x <= head.rect.max.x, "the button %v inside the head %v", button.rect, head.rect)
	testing.expectf(t, tabs.rect.min.x >= head.rect.max.x - 1, "the tabs %v after the head %v", tabs.rect, head.rect)
}
