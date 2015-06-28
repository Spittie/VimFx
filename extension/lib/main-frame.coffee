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

commands       = require('./commands-frame')
events         = require('./events-frame')
messageManager = require('./message-manager')

module.exports = ->
  state = events.addListeners()

  messageManager.listen('runCommand', ({ data: { name, data } }) ->
    result = commands[name](Object.assign({state}, data))
    messageManager.send("#{ name }:callback", result) if data.callback
  )
