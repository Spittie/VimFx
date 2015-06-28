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

notation = require('vim-like-key-notation')
prefs    = require('./prefs')
utils    = require('./utils')

DIGIT     = /^\d$/
FORCE_KEY = '<force>'

class VimFx extends utils.EventEmitter
  constructor: (@modes, @options) ->
    super()
    @vims = new WeakMap()
    @createKeyTrees()
    @reset()
    @on('modechange', ({mode}) => @reset(mode))

  getCurrentVim: (window) -> @vims.get(window.gBrowser.selectedBrowser)

  reset: (mode = null) ->
    @currentKeyTree = if mode then @keyTrees[mode] else {}
    @lastInputTime = 0
    @count = ''

  getCurrentLocation: -> null # @currentVim?.window.location # FIXME

  createKeyTrees: ->
    {@keyTrees, @forceCommands, @errors} = createKeyTrees(@modes)

  stringifyKeyEvent: (event) ->
    return notation.stringify(event, {
      ignoreKeyboardLayout: @options.ignore_keyboard_layout
      translations: @options.translations
    })

  consumeKeyEvent: (event, vim) ->
    { mode } = vim
    return unless keyStr = @stringifyKeyEvent(event)

    now = Date.now()
    @reset(mode) if now - @lastInputTime >= @options.timeout
    @lastInputTime = now

    toplevel = (@currentKeyTree == @keyTrees[mode])

    if toplevel and @options.keyValidator
      unless @options.keyValidator(keyStr, mode)
        @reset(mode)
        return

    type = 'none'
    command = null

    switch
      when keyStr of @currentKeyTree
        next = @currentKeyTree[keyStr]
        if next instanceof Leaf
          type = 'full'
          command = next.command
        else
          @currentKeyTree = next
          type = 'partial'

      when toplevel and DIGIT.test(keyStr) and
           not (keyStr == '0' and @count == '')
        @count += keyStr
        type = 'count'

      else
        @reset(mode)

    count = if @count == '' then undefined else Number(@count)
    force = if command then (command.pref of @forceCommands) else false
    focus = @getFocusType(vim, event, keyStr)
    unmodifiedKey = notation.parse(keyStr).key
    @reset(mode) if type == 'full'
    return {type, focus, command, count, force, keyStr, unmodifiedKey, toplevel}

  getFocusType: (vim, event, keyStr) ->
    return unless target = event.originalTarget # For the tests.
    document = target.ownerDocument

    { activatable_element_keys, adjustable_element_keys } = @options
    return switch
      when utils.isTextInputElement(target) or
           utils.isContentEditable(target)
        'editable'
      when (utils.isActivatable(target) and
            keyStr in activatable_element_keys)
        'activatable'
      when (utils.isAdjustable(target) and
            keyStr in adjustable_element_keys)
        'adjustable'
      when vim.rootWindow.TabView.isVisible() or
           document.fullscreenElement or document.mozFullScreenElement
        'other'
      else
        null

  getGroupedCommands: (options = {}) ->
    modes = {}
    for modeName, mode of @modes
      if options.enabledOnly
        usedSequences = getUsedSequences(@keyTrees[modeName])
      for commandName, command of mode.commands
        enabledSequences = null
        if options.enabledOnly
          enabledSequences = utils.removeDuplicates(
            command._sequences.filter((sequence) ->
              return (usedSequences[sequence] == command.pref)
            )
          )
          continue if enabledSequences.length == 0
        categories = modes[modeName] ?= {}
        category = categories[command.category] ?= []
        category.push({command, enabledSequences, order: command.order})

    modesSorted = []
    for modeName, categories of modes
      categoriesSorted = []
      for categoryName, commands of categories
        category = @options.categories[categoryName]
        categoriesSorted.push({
          name:     category.name()
          _name:    categoryName
          order:    category.order
          commands: commands.sort(byOrder)
        })
      mode = @modes[modeName]
      modesSorted.push({
        name:       mode.name()
        _name:      modeName
        order:      mode.order
        categories: categoriesSorted.sort(byOrder)
      })
    return modesSorted.sort(byOrder)

byOrder = (a, b) -> a.order - b.order

class Leaf
  constructor: (@command, @originalSequence) ->

createKeyTrees = (modes) ->
  keyTrees = {}
  errors = {}
  forceCommands = {}

  pushError = (error, command) ->
    (errors[command.pref] ?= []).push(error)

  pushOverrideErrors = (command, tree) ->
    for { command: overriddenCommand, originalSequence } in getLeaves(tree)
      error =
        id:      'overridden_by'
        subject: command.description()
        context: originalSequence
      pushError(error, overriddenCommand)
    return

  pushForceKeyError = (command, originalSequence) ->
    error =
      id: 'illegal_force_key'
      subject: FORCE_KEY
      context: originalSequence
    pushError(error, command)

  for modeName, { commands } of modes
    keyTrees[modeName] = {}
    for commandName, command of commands
      { shortcuts, errors: parseErrors } = parseShortcutPref(command.pref)
      pushError(error, command) for error in parseErrors
      command._sequences = []

      for shortcut in shortcuts
        [ prefixKeys..., lastKey ] = shortcut.normalized
        tree = keyTrees[modeName]
        command._sequences.push(shortcut.original)

        for prefixKey, index in prefixKeys
          if prefixKey == FORCE_KEY
            if index == 0
              forceCommands[command.pref] = true
            else
              pushForceKeyError(command, shortcut.original)
            continue

          if prefixKey of tree
            next = tree[prefixKey]
            if next instanceof Leaf
              pushOverrideErrors(command, next)
              tree = tree[prefixKey] = {}
            else
              tree = next
          else
            tree = tree[prefixKey] = {}

        if lastKey == FORCE_KEY
          pushForceKeyError(command, shortcut.original)
          continue
        if lastKey of tree
          pushOverrideErrors(command, tree[lastKey])
        tree[lastKey] = new Leaf(command, shortcut.original)

  return {keyTrees, forceCommands, errors}

parseShortcutPref = (pref) ->
  shortcuts = []
  errors    = []

  # The shorcut prefs are read from root in order to support other extensions to
  # extend VimFx with custom commands.
  prefValue = prefs.root.get(pref).trim()

  unless prefValue == ''
    for sequence in prefValue.split(/\s+/)
      shortcut = []
      errored  = false
      for key in notation.parseSequence(sequence)
        try
          shortcut.push(notation.normalize(key))
        catch error
          throw error unless error.id?
          errors.push(error)
          errored = true
          break
      shortcuts.push({normalized: shortcut, original: sequence}) unless errored

  return {shortcuts, errors}

getLeaves = (node) ->
  if node instanceof Leaf
    return [node]
  leaves = []
  for key, value of node
    leaves.push(getLeaves(value)...)
  return leaves

getUsedSequences = (tree) ->
  usedSequences = {}
  for leaf in getLeaves(tree)
    usedSequences[leaf.originalSequence] = leaf.command.pref
  return usedSequences

module.exports = VimFx
