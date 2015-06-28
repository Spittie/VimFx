###
# Copyright Anton Khodakivskiy 2012, 2013.
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

messageManager = require('./message-manager')
utils          = require('./utils')

class Vim
  constructor: (@window, @_parent) ->
    Object.defineProperty(this, 'options', {
      get: => @_parent.options
      enumerable: true
    })
    @_storage = {}

    if @isBlacklisted()
      @enterMode('ignore')
    else
      @enterMode('normal') if force or @mode == 'ignore'

    @_parent.emit('load', {vim: this, location: @window.location}) # FIXME

  isBlacklisted: ->
    url = @window.gBrowser.currentURI.spec
    return @options.black_list.some((regex) -> regex.test(url))

  # `args` is an array of arguments to be passed to the mode's `onEnter` method.
  enterMode: (mode, args...) ->
    return false if @mode == mode

    unless utils.has(@_parent.modes, mode)
      modes = Object.keys(@_parent.modes).join(', ')
      throw new Error("VimFx: Unknown mode. Available modes are: #{ modes }.
                       Got: #{ mode }")

    @_call('onLeave') if @mode?
    @mode = mode
    @_call('onEnter', null, args...)
    @_parent.emit('modeChange', this) if @_parent.getCurrentVim() == this
    return true

  onInput: (event) ->
    match = @_parent.consumeKeyEvent(event, this)
    return null unless match
    suppress = @_call('onInput', {event, count: match.count}, match)
    return suppress

  _call: (method, data = {}, extraArgs...) ->
    args = Object.assign({vim: this, storage: @storage[@mode] ?= {}}, data)
    currentMode = @_parent.modes[@mode]
    currentMode[method].call(currentMode, args, extraArgs...)

  _run: (name, data = {}, callback = null) ->
    fn = null
    if callback
      data.callback = true
      fn = ({ data }) -> callback(data)
    messageManager.send('runCommand', {name, data}, fn,
                        @window.gBrowser.selectedBrowser.messageManager)

module.exports = Vim
