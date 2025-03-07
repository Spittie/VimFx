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

translate = require('./l10n')
utils     = require('./utils')

CONTAINER_ID  = 'VimFxHelpDialogContainer'
MAX_FONT_SIZE = 20

injectHelp = (rootWindow, vimfx) ->
  removeHelp(rootWindow)

  { document } = rootWindow

  container = document.createElement('box')
  container.id = CONTAINER_ID

  wrapper = document.createElement('box')
  container.appendChild(wrapper)

  header = createHeader(document, vimfx)
  wrapper.appendChild(header)

  content = createContent(document, vimfx)
  wrapper.appendChild(content)

  rootWindow.gBrowser.mCurrentBrowser.parentNode.appendChild(container)

  # The font size of menu items is used by default, which is usually quite
  # small. Try to increase it without causing a scrollbar.
  computedStyle = rootWindow.getComputedStyle(container)
  fontSize = originalFontSize =
    parseFloat(computedStyle.getPropertyValue('font-size'))
  while wrapper.clientHeight < container.clientHeight and
        fontSize <= MAX_FONT_SIZE
    fontSize++
    container.style.fontSize = "#{ fontSize }px"
  container.style.fontSize = "#{ Math.max(fontSize - 1, originalFontSize) }px"

  # Uncomment this line if you want to use `gulp help.html`!
  # utils.writeToClipboard(container.outerHTML)

removeHelp = (rootWindow) ->
  rootWindow.document.getElementById(CONTAINER_ID)?.remove()

createHeader = (document, vimfx) ->
  $ = utils.createBox.bind(null, document)

  header = $('header')

  mainHeading = $('heading-main', header)
  $('logo',  mainHeading) # Content is added by CSS.
  $('title', mainHeading, translate('help.title'))

  closeButton = $('close-button', header, '×')
  closeButton.onclick = removeHelp.bind(null, document.defaultView)

  return header

createContent = (document, vimfx) ->
  $ = utils.createBox.bind(null, document)

  content = $('content')

  for mode in vimfx.getGroupedCommands({enabledOnly: true})
    modeHeading = $('heading-mode', null, mode.name)

    for category, index in mode.categories
      categoryContainer = $('category', content)

      # Append the mode heading inside the first category container, rather than
      # before it, for layout purposes.
      if index == 0
        categoryContainer.appendChild(modeHeading)
        categoryContainer.classList.add('first')

      $('heading-category', categoryContainer, category.name) if category.name

      for { command, enabledSequences } in category.commands
        commandContainer = $('command', categoryContainer)
        for sequence in enabledSequences
          $('key-sequence', commandContainer, sequence)
        $('description', commandContainer, command.description())

  return content

module.exports = {
  injectHelp
  removeHelp
}
