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

# Expose `Components` shortcuts a well as `Services` and `console` in all
# modules.
{ classes: Cc, interfaces: Ci, utils: Cu } = Components

Cu.import('resource://gre/modules/Services.jsm')
Cu.import('resource://gre/modules/devtools/Console.jsm')

do (global = this) ->
  isFrameScript = (typeof content != 'undefined')

  if isFrameScript
    [ global.__SCRIPT_URI_SPEC__ ] = sendSyncMessage('VimFx:tabCreated')
    return if __SCRIPT_URI_SPEC__ == false

  shutdownHandlers = []

  createURI = (path, base = null) -> Services.io.newURI(path, null, base)
  baseURI   = createURI(__SCRIPT_URI_SPEC__)

  # Everything up to the first `!` is the absolute path to the .xpi.
  dirname = (uri) -> uri.match(///^ [^!]+!/ (.+) /[^/]+ $///)[1]

  require = (path, moduleRoot = '.', dir = '.') ->
    unless path[0] == '.'
      # Allow `require('module/lib/foo')` in additon to `require('module')`.
      [ match, name, subPath ] = path.match(///^ ([^/]+) (?: /(.+) )? ///)
      base = require.data[moduleRoot]?[name] ? moduleRoot
      dir  = "#{ base }/node_modules/#{ name }"
      main = require.data[dir]?['']
      path = subPath ? main ? 'index'
      moduleRoot = dir

    fullPath = createURI("#{ dir }/#{ path }.js", baseURI).spec

    unless require.scopes[fullPath]?
      module =
        exports:    {}
        onShutdown: Function::call.bind(Array::push, shutdownHandlers)
      require.scopes[fullPath] = scope =
        require: (path) -> require(path, moduleRoot, "./#{ dirname(fullPath) }")
        module:  module
        exports: module.exports
      Services.scriptloader.loadSubScript(fullPath, scope, 'UTF-8')

    return require.scopes[fullPath].module.exports

  require.scopes = {}
  require.data   = require('./require-data')

  unless isFrameScript
    # Set default prefs and apply migrations as early as possible.
    { applyMigrations } = require('./lib/legacy')
    migrations          = require('./lib/migrations')
    prefs               = require('./lib/prefs')

    prefs.default._init()
    applyMigrations(migrations)

  main = if isFrameScript then './lib/main-frame' else './lib/main'
  global.startup = require(main)

  global.shutdown = (data, reason) ->
    for shutdownHandler in shutdownHandlers
      try
        shutdownHandler()
      catch error
        Cu.reportError(error)
    shutdownHandlers = null
    removeEventListener('unload', shutdown, true) if isFrameScript

    # Release everything in `require`d modules. This must be done _after_ all
    # shutdownHandlers, since they use variables in these scopes.
    for path, scope of require.scopes
      for name of scope
        scope[name] = null
    require.scopes = null

  global.install = (data, reason) ->

  global.uninstall = (data, reason) ->

  if isFrameScript
    addEventListener('unload', shutdown, true)
    startup()
