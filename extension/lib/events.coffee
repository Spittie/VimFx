###
# Copyright Anton Khodakivskiy 2012, 2013, 2014.
# Copyright Simon Lydell 2013, 2014.
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

button = require('./button')
utils  = require('./utils')

{ interfaces: Ci } = Components

HTMLDocument     = Ci.nsIDOMHTMLDocument
HTMLInputElement = Ci.nsIDOMHTMLInputElement

# Will be set by `addEventListeners`. It’s a bit hacky, but will do for now.
vimfx     = null
vimBucket = null

# When a menu or panel is shown VimFx should temporarily stop processing
# keyboard input, allowing accesskeys to be used.
popupPassthrough = false
checkPassthrough = (event) ->
  if event.target.nodeName in ['menupopup', 'panel']
    popupPassthrough = switch event.type
      when 'popupshown'  then true
      when 'popuphidden' then false

suppress = false
suppressEvent = (event) ->
  event.preventDefault()
  event.stopPropagation()

# Returns the appropriate vim instance for `event`.
getVimFromEvent = (event) ->
  return unless window = utils.getEventCurrentTabWindow(event)
  return unless vim = vimBucket.get(window)
  return vim

# Save the time of the last user interaction. This is used to determine whether
# a focus event was automatic or voluntarily dispatched.
markLastInteraction = (event, vim = null) ->
  return unless vim ?= getVimFromEvent(event)
  return unless event.originalTarget.ownerDocument instanceof HTMLDocument
  vim.state.lastInteraction = Date.now()

removeVimFromTab = (tab, gBrowser) ->
  return unless browser = gBrowser.getBrowserForTab(tab)
  vimBucket.forget(browser.contentWindow)

attribute = 'vimfx-held-modifiers'
setHeldModifiers = (vim, event, modifiers = null) ->
  mainWindow = vim.rootWindow.document.documentElement
  modifiers ?= mainWindow.getAttribute(attribute)
  isHeld = (modifier) -> event["#{ modifier }Key"]
  mainWindow.setAttribute(attribute,
                          modifiers.split(' ').filter(isHeld).join(' '))

# The following listeners are installed on every top level Chrome window.
windowsListeners =
  keydown: (event) ->
    try
      # No matter what, always reset the `suppress` flag, so we don't suppress
      # more than intended.
      suppress = false

      if popupPassthrough
        # The `popupPassthrough` flag is set a bit unreliably. Sometimes it can
        # be stuck as `true` even though no popup is shown, effectively
        # disabling the extension. Therefore we check if there actually _are_
        # any open popups before stopping processing keyboard input. This is
        # only done when popups (might) be open (not on every keystroke) of
        # performance reasons.
        #
        # The autocomplete popup in text inputs (for example) is technically a
        # panel, but it does not respond to key presses. Therefore
        # `[ignorekeys="true"]` is excluded.
        #
        # coffeelint: disable=max_line_length
        # <https://developer.mozilla.org/en-US/docs/Mozilla/Tech/XUL/PopupGuide/PopupKeys#Ignoring_Keys>
        # coffeelint: enable=max_line_length
        return unless rootWindow = utils.getEventRootWindow(event)
        popups = rootWindow.document.querySelectorAll(
          ':-moz-any(menupopup, panel):not([ignorekeys="true"])'
        )
        for popup in popups
          return if popup.state == 'open'
        popupPassthrough = false # No popup was actually open: Reset the flag.

      return unless vim = getVimFromEvent(event)

      markLastInteraction(event, vim)

      suppress = vim.onInput(event)

      modifiers = if suppress == null then 'alt ctrl meta shift' else ''
      setHeldModifiers(vim, event, modifiers)

      suppressEvent(event) if suppress

    catch error
      console.error(utils.formatError(error))

  keypress: (event) -> suppressEvent(event) if suppress

  keyup: (event) ->
    suppressEvent(event) if suppress
    return unless vim = getVimFromEvent(event)
    setHeldModifiers(vim, event)

  popupshown:  checkPassthrough
  popuphidden: checkPassthrough

  focus: (event) ->
    target = event.originalTarget
    return unless vim = getVimFromEvent(event)

    findBar = vim.rootWindow.gBrowser.getFindBar()
    if target == findBar._findField.mInputField
      vim.enterMode('find')
      return

    if target.ownerDocument instanceof HTMLDocument and
       utils.isTextInputElement(target)
      vim.state.lastFocusedTextInput = target

    # If the user has interacted with the page and the `window` of the page gets
    # focus, it means that the user just switched back to the page from another
    # window or tab. If a text input was focused when the user focused _away_
    # from the page Firefox blurs it and then re-focuses it when the user
    # switches back. Therefore we count this case as an interaction, so the
    # re-focus event isn’t caught as autofocus.
    if vim.state.lastInteraction != null and target == vim.window
      vim.state.lastInteraction = Date.now()

    # Autofocus prevention. Strictly speaking, autofocus may only happen during
    # page load, which means that we should only prevent focus events during
    # page load. However, it is very difficult to reliably determine when the
    # page load ends. Moreover, a page may load very slowly. Then it is likely
    # that the user tries to focus something before the page has loaded fully.
    # Therefore focus events that aren’t reasonably close to a user interaction
    # (click or key press) are blurred (regardless of whether the page is loaded
    # or not -- but that isn’t so bad: if the user doesn’t like autofocus, he
    # doesn’t like any automatic focusing, right? This is actually useful on
    # devdocs.io). There is a slight risk that the user presses a key just
    # before an autofocus, causing it not to be blurred, but that’s not likely.
    # Autofocus prevention is also restricted to `<input>` elements, since only
    # such elements are commonly autofocused.  Many sites have buttons which
    # inserts a `<textarea>` when clicked (which might take up to a second) and
    # then focuses the `<textarea>`. Such focus events should _not_ be blurred.
    # There are also many buttons that do the same thing but insert an `<input>`
    # element. There is sadly always a risk that those events are blurred.
    focusManager = Cc['@mozilla.org/focus-manager;1']
      .getService(Ci.nsIFocusManager)
    if vimfx.options.prevent_autofocus and
        vim.mode in vimfx.options.prevent_autofocus_modes and
        target.ownerDocument instanceof HTMLDocument and
        target instanceof HTMLInputElement and
        # Only blur programmatic events (not caused by clicks or keypresses).
        focusManager.getLastFocusMethod(null) == 0 and
        (vim.state.lastInteraction == null or
         Date.now() - vim.state.lastInteraction > vimfx.options.autofocus_limit)
      vim.state.lastAutofocusPrevention = Date.now()
      target.blur()

  blur: (event) ->
    target = event.originalTarget
    return unless vim = getVimFromEvent(event)

    findBar = vim.rootWindow.gBrowser.getFindBar()
    if target == findBar._findField.mInputField
      vim.enterMode('normal')
      return

    # Some sites (such as icloud.com) re-focuses inputs if they are blurred,
    # causing an infinite loop autofocus prevention and re-focusing. Therefore
    # we suppress blur events that happen just after an autofocus prevention.
    if vim.state.lastAutofocusPrevention != null and
       Date.now() - vim.state.lastAutofocusPrevention < 1
      vim.state.lastAutofocusPrevention = null
      suppressEvent(event)
      return

  click: (event) ->
    target = event.originalTarget
    return unless vim = getVimFromEvent(event)

    # If the user clicks the reload button or a link when in hints mode, we’re
    # going to end up in hints mode without any markers. Or if the user clicks a
    # text input, then that input will be focused, but you can’t type in it
    # (instead markers will be matched). So if the user clicks anything in hints
    # mode it’s better to leave it.
    if vim.mode == 'hints' and not utils.isEventSimulated(event) and
       # Exclude the VimFx button, though, since clicking it returns to normal
       # mode. Otherwise we’d first returned to normal mode and then the button
       # would have opened the help dialog.
       target != vim.rootWindow.document.getElementById(button.BUTTON_ID)
      vim.enterMode('normal')
      return

  mousedown: markLastInteraction
  mouseup:   markLastInteraction

  overflow: (event) ->
    return unless vim = getVimFromEvent(event)
    return unless computedStyle = vim.window.getComputedStyle(event.target)
    return if computedStyle.getPropertyValue('overflow') == 'hidden'
    vim.state.scrollableElements.set(event.target)

  underflow: (event) ->
    return unless vim = getVimFromEvent(event)
    vim.state.scrollableElements.delete(event.target)

  # When the top level window closes we should release all Vims that were
  # associated with tabs in this window.
  DOMWindowClose: (event) ->
    { gBrowser } = event.originalTarget
    return unless gBrowser
    for tab in gBrowser.tabs
      removeVimFromTab(tab, gBrowser)

  TabClose: (event) ->
    { gBrowser } = utils.getEventRootWindow(event) ? {}
    return unless gBrowser
    tab = event.originalTarget
    removeVimFromTab(tab, gBrowser)

  TabSelect: (event) ->
    return unless window = event.originalTarget?.linkedBrowser?.contentDocument
                           ?.defaultView
    # Get the current vim in order to trigger an update event for the toolbar
    # button.
    vimBucket.get(window)


# This listener works on individual tabs within Chrome Window.
tabsListener =
  onLocationChange: (browser, webProgress, request, location) ->
    return unless vim = vimBucket.get(browser.contentWindow)
    vim.resetState()

addEventListeners = (_vimfx, window) ->
  vimfx = _vimfx
  { vimBucket } = _vimfx
  for name, listener of windowsListeners
    window.addEventListener(name, listener, true)

  window.gBrowser.addTabsProgressListener(tabsListener)

  module.onShutdown(->
    for name, listener of windowsListeners
      window.removeEventListener(name, listener, true)

    window.gBrowser.removeTabsProgressListener(tabsListener)
  )

module.exports = {
  addEventListeners
}
