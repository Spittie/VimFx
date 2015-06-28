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

namespace = (name) -> "VimFx:#{ name }"

defaultMM =
  if IS_FRAME_SCRIPT
    this
  else
    Cc['@mozilla.org/globalmessagemanager;1']
      .getService(Ci.nsIMessageListenerManager)

load = (name, messageManager = defaultMM) ->
  # Randomize URI to work around bug 1051238.
  url = "chrome://vimfx/content/#{ name }.js?#{ Math.random() }"
  messageManager.loadFrameScript(url, true)
  module.onShutdown(->
    messageManager.removeDelayedFrameScript(url)
  )

listen = (name, listener, messageManager = defaultMM) ->
  namespacedName = namespace(name)
  messageManager.addMessageListener(namespacedName, listener)
  module.onShutdown(->
    messageManager.removeMessageListener(namespacedName, listener)
  )

listenOnce = (name, listener, messageManager = defaultMM) ->
  namespacedName = namespace(name)
  fn = (data) ->
    messageManager.removeMessageListener(namespacedName, fn)
    listener(data)
  messageManager.addMessageListener(namespacedName, fn)

send = (name, data = null, messageManager = defaultMM, callback = null) ->
  if typeof messageManager == 'function'
    callback = messageManager
    messageManager = defaultMM
  namespacedName = namespace(name)
  if callback
    listenOnce("#{ namespacedName }:callback", callback, messageManager)
  if messageManager.broadcastAsyncMessage
    messageManager.broadcastAsyncMessage(namespacedName, data)
  else
    messageManager.sendAsyncMessage(namespacedName, data)

module.exports = {
  load
  listen
  send
}
