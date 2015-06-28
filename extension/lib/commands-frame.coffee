###
# Copyright Simon Lydell 2015.
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

hints = require('./hints')
prefs = require('./prefs')
utils = require('./utils')

{ isProperLink, isTextInputElement, isContentEditable } = utils

XULDocument = Ci.nsIDOMXULDocument

storage  = {}
commands = {}

commands.go_up_path = ({ content, count }) ->
  content.location.pathname = content.location.pathname.replace(
    /// (?: /[^/]+ ){1,#{ count ? 1 }} /?$ ///, ''
  )

commands.go_to_root = ({ content }) ->
  content.location.href = content.location.origin

axisMap =
  x: ['left', 'scrollLeftMax', 'clientWidth',  'horizontalScrollDistance',  5]
  y: ['top',  'scrollTopMax',  'clientHeight', 'verticalScrollDistance',   20]

commands.scroll = ({ method, type, axis, amount, count, state }) ->
  activeElement = utils.getActiveElement(content)
  document = activeElement.ownerDocument
  element =
    if state.scrollableElements.has(activeElement)
      activeElement
    else
      document.documentElement

  [ direction, max, dimension, distance, lineAmount ] = axisMap[axis]

  if method == 'scrollTo'
    amount = Math.min(amount, element[max])
  else
    unit = switch type
      when 'lines'
        prefs.root.get("toolkit.scrollbox.#{ distance }") * lineAmount
      when 'pages'
        element[dimension]
    amount *= unit * (count ? 1)

  options = {}
  options[direction] = amount
  if prefs.root.get('general.smoothScroll') and
     prefs.root.get("general.smoothScroll.#{ type }")
    options.behavior = 'smooth'

  prefs.root.tmp(
    'layout.css.scroll-behavior.spring-constant',
    vim.options["smoothScroll.#{ type }.spring-constant"],
    ->
      element[method](options)
      # When scrolling the whole page, the body sometimes needs to be scrolled
      # too.
      if element == document.documentElement
        document.body?[method](options)
  )

# Combine links with the same href.
combine = (hrefs, wrapper) ->
  if wrapper.type == 'link'
    { href } = wrapper
    if href of hrefs
      parent = hrefs[href]
      wrapper.parent = parent
      parent.weight += wrapper.weight
      parent.numChildren++
    else
      hrefs[href] = wrapper
  return wrapper

commands.follow = ->
  hrefs = {}
  storage.markerElements = []
  filter = (element, getElementShape) ->
    document = element.ownerDocument
    isXUL = (document instanceof XULDocument)
    semantic = true
    switch
      when isProperLink(element)
        type = 'link'
      when isTextInputElement(element) or isContentEditable(element)
        type = 'text'
      when element.tabIndex > -1 and
           not (isXUL and element.nodeName.endsWith('box'))
        type = 'clickable'
        unless isXUL or element.nodeName in ['A', 'INPUT', 'BUTTON']
          semantic = false
      when element != document.documentElement and
           vim.state.scrollableElements.has(element)
        type = 'scrollable'
      when element.hasAttribute('onclick') or
           element.hasAttribute('onmousedown') or
           element.hasAttribute('onmouseup') or
           element.hasAttribute('oncommand') or
           element.getAttribute('role') in ['link', 'button'] or
           # Twitter special-case.
           element.classList.contains('js-new-tweets-bar') or
           # Feedly special-case.
           element.hasAttribute('data-app-action') or
           element.hasAttribute('data-uri') or
           element.hasAttribute('data-page-action')
        type = 'clickable'
        semantic = false
      # Putting markers on `<label>` elements is generally redundant, because
      # its `<input>` gets one. However, some sites hide the actual `<input>`
      # but keeps the `<label>` to click, either for styling purposes or to keep
      # the `<input>` hidden until it is used. In those cases we should add a
      # marker for the `<label>`.
      when element.nodeName == 'LABEL'
        if element.htmlFor
          input = document.getElementById(element.htmlFor)
          if input and not getElementShape(input)
            type = 'clickable'
      # Elements that have “button” somewhere in the class might be clickable,
      # unless they contain a real link or button or yet an element with
      # “button” somewhere in the class, in which case they likely are
      # “button-wrapper”s. (`<SVG element>.className` is not a string!)
      when not isXUL and typeof element.className == 'string' and
           element.className.toLowerCase().contains('button')
        unless element.querySelector('a, button, [class*=button]')
          type = 'clickable'
          semantic = false
      # When viewing an image it should get a marker to toggle zoom.
      when document.body?.childElementCount == 1 and
           element.nodeName == 'IMG' and
           (element.classList.contains('overflowing') or
            element.classList.contains('shrinkToFit'))
        type = 'clickable'
    return unless type
    return unless shape = getElementShape(element)
    length = storage.markerElements.push(element)
    return combine(hrefs, {elementIndex: length - 1, shape, semantic, type})

  return hints.getMarkableElementsAndViewport(content, filter)

commands.follow_in_tab = ->
  hrefs = {}
  storage.markerElements = []
  filter = (element, getElementShape) ->
    return unless isProperLink(element)
    return unless shape = getElementShape(element)
    length = storage.markerElements.push(element)
    return combine(
      hrefs, {elementIndex: length - 1, shape, semantic: true, type: 'link'}
    )

  return hints.getMarkableElementsAndViewport(content, filter)

commands.follow_copy = ->
  hrefs = {}
  storage.markerElements = []
  filter = (element, getElementShape) ->
    type = switch
      when isProperLink(element)       then 'link'
      when isTextInputElement(element) then 'textInput'
      when isContentEditable(element)  then 'contenteditable'
    return unless type
    return unless shape = getElementShape(element)
    length = storage.markerElements.push(element)
    return combine(
      hrefs, {elementIndex: length - 1, shape, semantic: true, type}
    )

  return hints.getMarkableElementsAndViewport(content, filter)

commands.follow_focus = ->
  storage.markerElements = []
  filter = (element, getElementShape) ->
    type = switch
      when element.tabIndex > -1
        'focusable'
      when element != element.ownerDocument.documentElement and
           vim.state.scrollableElements.has(element)
        'scrollable'
    return unless type
    return unless shape = getElementShape(element)
    length = storage.markerElements.push(element)
    return {elementIndex: length - 1, shape, semantic: true, type}

  return hints.getMarkableElementsAndViewport(content, filter)

commands.focus_marker_element = ({ elementIndex, options }) ->
  element = storage.markerElements[elementIndex]
  utils.focusElement(element, options)

commands.click_marker_element = ({ elementIndex, preventTargetBlank }) ->
  element = storage.markerElements[elementIndex]
  if element.target == '_blank' and preventTargetBlank
    targetReset = element.target
    element.target = ''
  utils.simulateClick(element)
  element.target = targetReset if targetReset

commands.copy_marker_element = ({ elementIndex, property }) ->
  element = storage.markerElements[elementIndex]
  utils.writeToClipboard(element[property])

commands.follow_pattern = ({ type, options }) ->
  { document } = content

  # If there’s a `<link rel=prev/next>` element we use that.
  for link in document.head?.getElementsByTagName('link')
    # Also support `rel=previous`, just like Google.
    if type == link.rel.toLowerCase().replace(/^previous$/, 'prev')
      content.location.href = link.href
      return

  # Otherwise we look for a link or button on the page that seems to go to the
  # previous or next page.
  candidates = document.querySelectorAll(options.pattern_selector)

  # Note: Earlier patterns should be favored.
  { patterns } = options

  # Search for the prev/next patterns in the following attributes of the
  # element. `rel` should be kept as the first attribute, since the standard way
  # of marking up prev/next links (`rel="prev"` and `rel="next"`) should be
  # favored. Even though some of these attributes only allow a fixed set of
  # keywords, we pattern-match them anyways since lots of sites don’t follow the
  # spec and use the attributes arbitrarily.
  attrs = options.pattern_attrs

  matchingLink = do ->
    # Helper function that matches a string against all the patterns.
    matches = (text) -> patterns.some((regex) -> regex.test(text))

    # First search in attributes (favoring earlier attributes) as it's likely
    # that they are more specific than text contexts.
    for attr in attrs
      for element in candidates
        return element if matches(element.getAttribute(attr))

    # Then search in element contents.
    for element in candidates
      return element if matches(element.textContent)

    return null

  utils.simulateClick(matchingLink) if matchingLink

commands.focus_text_input = ({ count }) ->
  { lastFocusedTextInput } = state
  inputs = Array.filter(
    content.document.querySelectorAll('input, textarea'), (element) ->
      return utils.isTextInputElement(element) and utils.area(element) > 0
  )
  if lastFocusedTextInput and lastFocusedTextInput not in inputs
    inputs.push(lastFocusedTextInput)
  return unless inputs.length > 0
  inputs.sort((a, b) -> a.tabIndex - b.tabIndex)
  unless count?
    count =
      if lastFocusedTextInput
        inputs.indexOf(lastFocusedTextInput) + 1
      else
        1
  index = Math.min(count, inputs.length) - 1
  utils.focusElement(inputs[index], {select: true})
  storage.inputs = inputs

commands.clear_inputs = -> storage.inputs = null

commands.move_focus = ({ direction, skip }) ->
  if storage.inputs
    index = storage.inputs.indexOf(utils.getActiveElement(content))
    if index == -1
      storage.inputs = null
    else
      { inputs } = storage
      nextInput = inputs[(index + direction) %% inputs.length]
      utils.focusElement(nextInput, {select: true})
      return

  return if skip

  focusManager = Cc['@mozilla.org/focus-manager;1']
    .getService(Ci.nsIFocusManager)
  directionFlag =
    if direction == -1
      focusManager.MOVEFOCUS_BACKWARD
    else
      focusManager.MOVEFOCUS_FORWARD
  focusManager.moveFocus(
    null, # Use current window.
    null, # Move relative to the currently focused element.
    directionFlag,
    focusManager.FLAG_BYKEY
  )

commands.esc = ({ content })
  utils.blurActiveElement(content)

  { document } = content
  if document.exitFullscreen
    document.exitFullscreen()
  else
    document.mozCancelFullScreen()

commands.blur_active_element = ->
    utils.blurActiveElement(content)

module.exports = commands
