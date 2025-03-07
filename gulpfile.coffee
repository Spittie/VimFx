###
# Copyright Simon Lydell 2014.
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

fs          = require('fs')
path        = require('path')
gulp        = require('gulp')
coffee      = require('gulp-coffee')
coffeelint  = require('gulp-coffeelint')
git         = require('gulp-git')
header      = require('gulp-header')
mustache    = require('gulp-mustache')
tap         = require('gulp-tap')
zip         = require('gulp-zip')
marked      = require('marked')
merge       = require('merge2')
precompute  = require('require-precompute')
request     = require('request')
rimraf      = require('rimraf')
runSequence = require('run-sequence')
pkg         = require('./package.json')

DEST   = 'build'
XPI    = 'VimFx.xpi'
LOCALE = 'extension/locale'
TEST   = 'extension/test'

test = '--test' in process.argv or '-t' in process.argv
ifTest = (value) -> if test then [value] else []

{ join } = path
read = (filepath) -> fs.readFileSync(filepath).toString()
template = (data) -> mustache(data, {extension: ''})

gulp.task('default', ['push'])

gulp.task('clean', (callback) ->
  rimraf(DEST, callback)
)

gulp.task('copy', ->
  gulp.src(['extension/**/!(*.coffee|*.tmpl)', 'COPYING', 'LICENSE'])
    .pipe(gulp.dest(DEST))
)

gulp.task('node_modules', ->
  dependencies = (name for name of pkg.dependencies)
  # Note! When installing or updating node modules, make sure that the following
  # glob does not include too much or too little!
  gulp.src("node_modules/+(#{ dependencies.join('|') })/\
            {LICENSE*,{,**/!(test|examples)/}!(*min|*test*|*bench*).js}")
    .pipe(gulp.dest("#{ DEST }/node_modules"))
)

gulp.task('coffee', ->
  gulp.src([
    'extension/bootstrap.coffee'
    'extension/lib/**/*.coffee'
    ifTest('extension/test/**/*.coffee')...
  ], {base: 'extension'})
    .pipe(coffee({bare: true}))
    .pipe(gulp.dest(DEST))
)

gulp.task('chrome.manifest', ->
  gulp.src('extension/chrome.manifest.tmpl')
    .pipe(template({locales: fs.readdirSync(LOCALE).map((locale) -> {locale})}))
    .pipe(gulp.dest(DEST))
)

gulp.task('install.rdf', ->
  [ [ { name: creator } ], developers, contributors, translators ] =
    read('PEOPLE.md').trim().replace(/^#.+\n|^\s*-\s*/mg, '').split('\n\n')
    .map((block) -> block.split('\n').map((name) -> {name}))

  getDescription = (locale) -> read(join(LOCALE, locale, 'description')).trim()

  descriptions = fs.readdirSync(LOCALE)
    .map((locale) -> {
      locale: locale
      description: getDescription(locale)
    })

  gulp.src('extension/install.rdf.tmpl')
    .pipe(template({
      version: pkg.version
      minVersion: pkg.firefoxVersions.min
      maxVersion: pkg.firefoxVersions.max
      creator, developers, contributors, translators
      defaultDescription: getDescription('en-US')
      descriptions
    }))
    .pipe(gulp.dest(DEST))
)

gulp.task('require-data', ['node_modules'], ->
  data = JSON.stringify(precompute('.'), null, 2)
  gulp.src('extension/require-data.js.tmpl')
    .pipe(template({data}))
    .pipe(gulp.dest(DEST))
)

gulp.task('tests-list', ->
  list = JSON.stringify(fs.readdirSync(TEST)
    .map((name) -> name.match(/^(test-.+)\.coffee$/)?[1])
    .filter(Boolean)
  )
  gulp.src("#{ TEST }/tests-list.js.tmpl", {base: 'extension'})
    .pipe(template({list}))
    .pipe(gulp.dest(DEST))
)

gulp.task('templates', [
  'chrome.manifest'
  'install.rdf'
  'require-data'
  ifTest('tests-list')...
])

gulp.task('build', (callback) ->
  runSequence(
    'clean',
    ['copy', 'node_modules', 'coffee', 'templates'],
    callback
  )
)

gulp.task('xpi', ['build'], ->
  gulp.src("#{ DEST }/**/*")
    .pipe(zip(XPI, {compress: false}))
    .pipe(gulp.dest(DEST))
)

gulp.task('push', ['xpi'], ->
  body = fs.readFileSync(join(DEST, XPI))
  request.post({url: 'http://localhost:8888', body })
)

gulp.task('lint', ->
  gulp.src(['extension/**/*.coffee', 'gulpfile.coffee'])
    .pipe(coffeelint())
    .pipe(coffeelint.reporter())
)

gulp.task('release', (callback) ->
  { version } = pkg
  message = "VimFx v#{ version }"
  today = new Date().toISOString()[...10]
  merge([
    gulp.src('package.json'),
    gulp.src('CHANGELOG.md')
      .pipe(header("### #{ version } (#{ today })\n\n"))
      .pipe(gulp.dest('.'))
  ])
    .pipe(git.commit(message))
    .on('end', ->
      git.tag("v#{ version }", message, callback)
    )
)

gulp.task('changelog', ->
  num = 1
  for arg in process.argv when /^-[1-9]$/.test(arg)
    num = Number(arg[1])
  entries = read('CHANGELOG.md').split(/^### .+/m)[1..num].join('')
  process.stdout.write(marked(entries))
)

gulp.task('readme', ->
  process.stdout.write(marked(read('README.md')))
)

gulp.task('faster', ->
  gulp.src('gulpfile.coffee')
    .pipe(coffee({bare: true}))
    .pipe(gulp.dest('.'))
)

gulp.task('sync-locales', ->
  baseLocale = 'en-US'
  for arg in process.argv when arg[...2] == '--'
    baseLocale = arg[2..]
  results = fs.readdirSync(join(LOCALE, baseLocale))
    .filter((file) -> path.extname(file) == '.properties')
    .map(syncLocale.bind(null, baseLocale))
  if baseLocale == 'en-US'
    report = []
    for {fileName, translatedCount, total} in results
      report.push("#{ fileName }:")
      for localeName, count of translatedCount
        paddedName = "#{ localeName }:   "[...6]
        percentage = Math.round((count / total) * 100)
        report.push("  #{ paddedName } #{ percentage }%")
    process.stdout.write(report.join('\n') + '\n')
)

syncLocale = (baseLocaleName, fileName) ->
  basePath = join(LOCALE, baseLocaleName, fileName)
  base = parseLocaleFile(read(basePath))
  oldBasePath = "#{basePath}.old"
  if fs.existsSync(oldBasePath)
    oldBase = parseLocaleFile(read(oldBasePath))
  translatedCount = {}
  for localeName in fs.readdirSync(LOCALE) when localeName != baseLocaleName
    localePath = join(LOCALE, localeName, fileName)
    locale = parseLocaleFile(read(localePath))
    translatedCount[localeName] = 0
    newLocale = base.template.map((line) ->
      if Array.isArray(line)
        [ key ] = line
        oldValue = oldBase?.keys[key]
        value =
          if (oldValue? and oldValue != base.keys[key]) or
             key not of locale.keys
            base.keys[key]
          else
            locale.keys[key]
        translatedCount[localeName]++ if value != base.keys[key] or value == ''
        return "#{ key }=#{ value }"
      else
        return line
    )
    fs.writeFileSync(localePath, newLocale.join(base.newline))
  return {fileName, translatedCount, total: Object.keys(base.keys).length}

parseLocaleFile = (fileContents) ->
  keys  = {}
  lines = []
  [ newline ] = fileContents.match(/\r?\n/)
  for line in fileContents.split(newline)
    line = line.trim()
    [ match, key, value ] = line.match(///^ ([^=]+) = (.*) $///) ? []
    if match
      keys[key] = value
      lines.push([key])
    else
      lines.push(line)
  return {keys, template: lines, newline}

helpHTMLFile = 'help.html'
gulp.task(helpHTMLFile, ->
  unless fs.existsSync(helpHTMLFile)
    console.log("""
      First enable the “Copy to clipboard” line in help.coffee, show the help
      dialog and finally dump the clipboard into #{ helpHTMLFile }.
    """)
    return
  gulp.src('help.html')
    .pipe(tap((file) ->
      file.contents = new Buffer(generateHelpHTML(file.contents.toString()))
    ))
    .pipe(gulp.dest('.'))
)

helpHTMLPrelude = '''
  <!doctype html>
  <meta charset=utf-8>
  <title>VimFx help</title>
  <style>
    * { margin: 0; }
    body > :first-child { min-height: 100vh; }
  </style>
  <link rel=stylesheet href=extension/skin/style.css>
'''

generateHelpHTML = (dumpedHTML) ->
  return helpHTMLPrelude + dumpedHTML
    .replace(/^<\w+ xmlns="[^"]+"/, '<div')
    .replace(/\w+>$/, 'div>')
    .replace(/<(\w+)([^>]*)\/>/g, '<$1$2></$1>')
