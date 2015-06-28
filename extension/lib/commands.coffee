###
# Copyright Anton Khodakivskiy 2012, 2013, 2014.
# Copyright Simon Lydell 2013, 2014.
# Copyright Wang Zhuochun 2013, 2014.
#
# This file is part of VimFx.
#
# VimFx is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# VimFx is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with VimFx.  If not, see <http://www.gnu.org/licenses/>.
###

help  = require('./help')
utils = require('./utils')

commands = {}



commands.focus_location_bar = ({ vim }) ->
  # This function works even if the Address Bar has been removed.
  vim.window.focusAndSelectUrlBar()

commands.focus_search_bar = ({ vim }) ->
  # The `.webSearch()` method opens a search engine in a tab if the Search Bar
  # has been removed. Therefore we first check if it exists.
  if vim.window.BrowserSearch.searchBar
    vim.window.BrowserSearch.webSearch()

helper_paste_and_go = (event, { vim }) ->
  { gURLBar, goDoCommand } = vim.window
  gURLBar.value = vim.window.readFromClipboard()
  gURLBar.handleCommand(event)

commands.paste_and_go = helper_paste_and_go.bind(null, null)

commands.paste_and_go_in_tab = helper_paste_and_go.bind(null, {altKey: true})

commands.copy_current_url = ({ vim }) ->
  utils.writeToClipboard(vim.window.gBrowser.currentURI.spec)

# Go up one level in the URL hierarchy.
commands.go_up_path = ({ vim, count }) ->
  vim._run('go_up_path', {count})

# Go up to root of the URL hierarchy.
commands.go_to_root = ({ vim }) ->
  vim._run('go_to_root')

commands.go_home = ({ vim }) ->
  vim.window.BrowserHome()

helper_go_history = (num, { vim, count }) ->
  { gBrowser } = vim.window
  { index, count: length } = gBrowser.sessionHistory
  newIndex = index + num * (count ? 1)
  newIndex = Math.max(newIndex, 0)
  newIndex = Math.min(newIndex, length - 1)
  gBrowser.gotoIndex(newIndex) unless newIndex == index

commands.history_back    = helper_go_history.bind(null, -1)

commands.history_forward = helper_go_history.bind(null, +1)

commands.reload = ({ vim }) ->
  vim.window.BrowserReload()

commands.reload_force = ({ vim }) ->
  vim.window.BrowserReloadSkipCache()

commands.reload_all = ({ vim }) ->
  vim.window.gBrowser.reloadAllTabs()

commands.reload_all_force = ({ vim }) ->
  for tab in vim.window.gBrowser.visibleTabs
    gBrowser = tab.linkedBrowser
    consts = gBrowser.webNavigation
    flags = consts.LOAD_FLAGS_BYPASS_PROXY | consts.LOAD_FLAGS_BYPASS_CACHE
    gBrowser.reload(flags)
  return

commands.stop = ({ vim }) ->
  vim.window.BrowserStop()

commands.stop_all = ({ vim }) ->
  for tab in vim.window.gBrowser.visibleTabs
    tab.linkedBrowser.stop()
  return


helper_scroll = (method, type, axis, amount, { vim, count }) ->
  vim._run('scroll', {method, type, axis, amount, count})

scroll = Function::bind.bind(helper_scroll, null)

commands.scroll_left           = scroll('scrollBy', 'lines', 'x', -1)
commands.scroll_right          = scroll('scrollBy', 'lines', 'x', +1)
commands.scroll_down           = scroll('scrollBy', 'lines', 'y', +1)
commands.scroll_up             = scroll('scrollBy', 'lines', 'y', -1)
commands.scroll_page_down      = scroll('scrollBy', 'pages', 'y', +1)
commands.scroll_page_up        = scroll('scrollBy', 'pages', 'y', -1)
commands.scroll_half_page_down = scroll('scrollBy', 'pages', 'y', +0.5)
commands.scroll_half_page_up   = scroll('scrollBy', 'pages', 'y', -0.5)
commands.scroll_to_top         = scroll('scrollTo', 'other', 'y', 0)
commands.scroll_to_bottom      = scroll('scrollTo', 'other', 'y', Infinity)
commands.scroll_to_left        = scroll('scrollTo', 'other', 'x', 0)
commands.scroll_to_right       = scroll('scrollTo', 'other', 'x', Infinity)



commands.tab_new = ({ vim }) ->
  vim.window.BrowserOpenTab()

commands.tab_duplicate = ({ vim }) ->
  { gBrowser } = vim.window
  gBrowser.duplicateTab(gBrowser.selectedTab)

absoluteTabIndex = (relativeIndex, gBrowser) ->
  tabs = gBrowser.visibleTabs
  { selectedTab } = gBrowser

  currentIndex  = tabs.indexOf(selectedTab)
  absoluteIndex = currentIndex + relativeIndex
  numTabs       = tabs.length

  wrap = (Math.abs(relativeIndex) == 1)
  if wrap
    absoluteIndex %%= numTabs
  else
    absoluteIndex = Math.max(0, absoluteIndex)
    absoluteIndex = Math.min(absoluteIndex, numTabs - 1)

  return absoluteIndex

helper_switch_tab = (direction, { vim, count }) ->
  { gBrowser } = vim.window
  gBrowser.selectTabAtIndex(absoluteTabIndex(direction * (count ? 1), gBrowser))

commands.tab_select_previous = helper_switch_tab.bind(null, -1)

commands.tab_select_next     = helper_switch_tab.bind(null, +1)

helper_move_tab = (direction, { vim, count }) ->
  { gBrowser }    = vim.window
  { selectedTab } = gBrowser
  { pinned }      = selectedTab

  index = absoluteTabIndex(direction * (count ? 1), gBrowser)

  if index < gBrowser._numPinnedTabs
    gBrowser.pinTab(selectedTab) unless pinned
  else
    gBrowser.unpinTab(selectedTab) if pinned

  gBrowser.moveTabTo(selectedTab, index)

commands.tab_move_backward = helper_move_tab.bind(null, -1)

commands.tab_move_forward  = helper_move_tab.bind(null, +1)

commands.tab_select_first = ({ vim }) ->
  vim.window.gBrowser.selectTabAtIndex(0)

commands.tab_select_first_non_pinned = ({ vim }) ->
  firstNonPinned = vim.window.gBrowser._numPinnedTabs
  vim.window.gBrowser.selectTabAtIndex(firstNonPinned)

commands.tab_select_last = ({ vim }) ->
  vim.window.gBrowser.selectTabAtIndex(-1)

commands.tab_toggle_pinned = ({ vim }) ->
  currentTab = vim.window.gBrowser.selectedTab
  if currentTab.pinned
    vim.window.gBrowser.unpinTab(currentTab)
  else
    vim.window.gBrowser.pinTab(currentTab)

commands.tab_close = ({ vim, count }) ->
  { gBrowser } = vim.window
  return if gBrowser.selectedTab.pinned
  currentIndex = gBrowser.visibleTabs.indexOf(gBrowser.selectedTab)
  for tab in gBrowser.visibleTabs[currentIndex...(currentIndex + (count ? 1))]
    gBrowser.removeTab(tab)
  return

commands.tab_restore = ({ vim, count }) ->
  vim.window.undoCloseTab() for [1..count ? 1] by 1

commands.tab_close_to_end = ({ vim }) ->
  { gBrowser } = vim.window
  gBrowser.removeTabsToTheEndFrom(gBrowser.selectedTab)

commands.tab_close_other = ({ vim }) ->
  { gBrowser } = vim.window
  gBrowser.removeAllTabsBut(gBrowser.selectedTab)



follow_callback = (vim, { inTab, inBackground }, marker, count, keyStr) ->
  isLast = (count == 1)
  isLink = (marker.wrapper.type == 'link')

  switch
    when keyStr.startsWith(vim.options.hints_toggle_in_tab)
      inTab = not inTab
    when keyStr.startsWith(vim.options.hints_toggle_in_background)
      inTab = true
      inBackground = not inBackground
    else
      unless isLast
        inTab = true
        inBackground = true

  inTab = false unless isLink

  if marker.type == 'text' or (isLink and not (inTab and inBackground))
    isLast = true

  { elementIndex } = marker.wrapper
  vim._run('focus_marker_element', {elementIndex})

  if inTab
    utils.openTab(vim.window, marker.wrapper.href, {
      inBackground
      relatedToCurrent: true
    })
  else
    vim._run('click_marker_element', {
      elementIndex
      preventTargetBlank: vim.options.prevent_target_blank
    })

  return not isLast

helper_follow = (callback, name, { vim, count }) ->
  vim._run(name, null, ({ wrappers, viewport }) ->
    vim.enterMode('hints', wrappers, viewport, callback, count)
  )

# Follow links, focus text inputs and click buttons with hint markers.
commands.follow = do ->
  callback = follow_callback.bind(null, vim, {inTab: false, inBackground: true})
  return helper_follow.bind(null, callback, 'follow')

# Follow links in a new background tab with hint markers.
commands.follow_in_tab = do ->
  callback = follow_callback.bind(null, vim, {inTab: true, inBackground: true})
  return helper_follow.bind(null, callback, 'follow_in_tab')

# Follow links in a new foreground tab with hint markers.
commands.follow_in_focused_tab = (args) ->
  callback = follow_callback.bind(null, vim, {inTab: true, inBackground: false})
  return helper_follow.bind(null, callback, 'follow_in_tab')

# Like command_follow but multiple times.
commands.follow_multiple = (args) ->
  args.count = Infinity
  commands.follow(args)

# Copy the URL or text of a markable element to the system clipboard.
commands.follow_copy = do ->
  callback = (marker) ->
    { elementIndex } = marker.wrapper
    property = switch marker.wrapper.type
      when 'link'            then 'href'
      when 'textInput'       then 'value'
      when 'contenteditable' then 'textContent'
    vim._run('copy_marker_element', {elementIndex, property})
  return helper_follow.bind(null, callback, 'follow_copy')

# Focus element with hint markers.
commands.follow_focus = ({ vim }) ->
  callback = (marker) ->
    { elementIndex } = marker.wrapper
    vim._run('focus_marker_element', {elementIndex, options: {select: true}})
  return helper_follow.bind(null, callback, 'follow_focus')

helper_follow_pattern = (type, { vim }) ->
  options =
    pattern_selector: vim.options.pattern_selector
    pattern_attrs:    vim.options.pattern_attrs
    patterns:         vim.options["#{ type }_patterns"]
  vim._run('follow_pattern', {type, options})

commands.follow_previous = helper_follow_pattern.bind(null, 'prev')

commands.follow_next     = helper_follow_pattern.bind(null, 'next')

# Focus last focused or first text input.
commands.focus_text_input = ({ vim, count }) ->
  vim._run('focus_text_input', {count})

# Switch between text inputs or simulate `<tab>`.
helper_move_focus = (direction, { vim, _skipMoveFocus }) ->
  vim._run('move_focus', {direction, skip: _skipMoveFocus})

commands.focus_next     = helper_move_focus.bind(null, +1)
commands.focus_previous = helper_move_focus.bind(null, -1)



findStorage = {lastSearchString: ''}

helper_find = (highlight, { vim }) ->
  findBar = vim.window.gBrowser.getFindBar()

  findBar.onFindCommand()
  utils.focusElement(findBar._findField, {select: true})

  return unless highlightButton = findBar.getElement('highlight')
  if highlightButton.checked != highlight
    highlightButton.click()

# Open the find bar, making sure that hightlighting is off.
commands.find = helper_find.bind(null, false)

# Open the find bar, making sure that hightlighting is on.
commands.find_highlight_all = helper_find.bind(null, true)

helper_find_again = (direction, { vim }) ->
  findBar = vim.window.gBrowser.getFindBar()
  if findStorage.lastSearchString.length > 0
    findBar._findField.value = findStorage.lastSearchString
    findBar.onFindAgainCommand(direction)

commands.find_next     = helper_find_again.bind(null, false)

commands.find_previous = helper_find_again.bind(null, true)



commands.enter_mode_ignore = ({ vim }) ->
  vim.enterMode('ignore')

# Quote next keypress (pass it through to the page).
commands.quote = ({ vim, count }) ->
  vim.enterMode('ignore', count ? 1)

# Display the Help Dialog.
commands.help = ({ vim }) ->
  help.injectHelp(vim.window, vim._parent)

# Open and focus the Developer Toolbar.
commands.dev = ({ vim }) ->
  vim.window.DeveloperToolbar.show(true) # `true` to focus.

commands.esc = ({ vim, event }) ->
  vim._run('esc')
  utils.blurActiveElement(vim.window)
  help.removeHelp(vim.window)
  vim.window.DeveloperToolbar.hide()
  vim.window.gBrowser.getFindBar().close()
  vim.window.TabView.hide()



module.exports = {
  commands
  findStorage
}
