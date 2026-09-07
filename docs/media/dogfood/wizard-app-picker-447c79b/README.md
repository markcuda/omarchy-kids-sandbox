# Starter-app picker failure

Original VM screenshots from candidate `447c79b8b8baa937f7317d7abc3813b0efbcaaab`, package SHA-256 `1bbacfee67fa7ab3c5525cf8a71cefc5cf4ad9c26a3ce645eba9caf4da76b5a6`. Fresh Catppuccin Latte parent session with Quickshell watching verified; display1280×800, Foot1256×750. Ben is an invented fixture. This was an installed `--dry-run` preview; Apply was never selected.

The operator chose Ages6–8 and Advanced, selected Starter apps, and pressed Enter once. The screen returned with no apps selected, without presenting an app confirmation. The first two frames show the original eight apps and selected editor row. The third filename reflects the expected GCompris prompt; its actual contents show the failed empty-list result. Root and an independent session inspected the originals.

- [Eight apps before editing](w172-latte-eight-08-advanced-default.png)
- [Starter apps selected](w172-latte-eight-09-apps-selected.png)
- [Actual result after Enter: no apps selected](w172-latte-eight-10-gcompris.png)

This records a failed editing check, not a completed scenario or restoration. The app picker function is unchanged from merged main069c584. `apps_pick_walk` passes its app-list input stream into the interactive confirmation at `bin/omarchy-kids-wizard:325–339`; a local owned PTY fixture reproduces the non-terminal stdin. Actual Gum error details were not retained by these screenshots.
