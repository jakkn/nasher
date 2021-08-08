## This module implements configuration options. Configuration options can be
## passed as command-line options or stored in a `user.cfg` file, either locally
## to the package or globally to the user. A table is populated with default
## values for the options, then the global and local `user.cfg` files are read
## into the table, overwriting the default values. Finally, command-line options
## are read into the table, overriding those.

import os, streams, strutils, parsecfg
from strtabs import nil

import cligen/parseopt3

import ./cli

type
  Options* = strtabs.StringTableRef

  SyntaxError* = object of CatchableError

const
  nasherCommands* = ["init", "config", "list", "unpack", "convert", "compile",
                     "pack", "install", "play", "test", "serve"]

proc `[]`*(opts: Options, key: string): string =
  ## Returns the string stored at ``key`` in the ``opts`` table. ``key`` is
  ## normalized (i.e., all characters lower case and hyphens and underscores
  ## removed). Throws a `KeyError` if ``key`` does not exist in ``opts``.
  strtabs.`[]`(opts, key.optionNormalize)

proc `[]=`*(opts: Options, key, value: string) =
  ## Sets the string stored at ``key`` in the ``opts`` table to ``value``.
  ## ``key`` is normalized (i.e., all characters lower case and hyphens and
  ## underscores removed.).
  strtabs.`[]=`(opts, key.optionNormalize, value)

proc `[]=`*[T: int|bool](opts: Options, key: string, value: T) =
  ## Overloaded ``[]=`` operator that converts value to a string before setting
  ## opts[key]
  opts[key] = $value

proc hasKey*(opts: Options, key: string): bool =
  ## Returns whether ``opts`` has the key ``key``. ``key`` is normalized (i.e.,
  ## all characters lower case and hyphens and underscores removed).
  strtabs.hasKey(opts, key.optionNormalize)

proc contains*(opts: Options, key: string): bool =
  ## Alias of ``hasKey(opts, key)`` for use with the ``in`` operator.
  hasKey(opts, key)

proc len*(opts: Options): int =
  ## Returns the number of key-value pairs in ``opts``.
  strtabs.len(opts)

proc newOptionsTable*(keyValuePairs: varargs[tuple[key, value: string]]): Options =
  ## Return a new options table initialized with ``keyValuePairs``.
  result = strtabs.newStringTable(strtabs.modeStyleInsensitive)
  for pair in keyValuePairs:
    result[pair.key] = pair.value

converter toBool(s: string): bool =
  ## Converts ``s`` to a `bool` value. An empty string is treated as `true` in
  ## order to support flags passed without an explicit value. Throws a
  ## `ValueError` if ``s`` cannot be converted to `bool`.
  s == "" or s.parseBool

converter toInt(s: string): int =
  ## Converts ``s`` to an `int` value. Throws a `ValueError` if ``s`` cannot be
  ## converted to `int`.
  s.parseInt

proc getOrDefault*[T: int|bool|string](opts: Options, keys: openarray[string], default: T = ""): T =
  ## Checks ``opts`` for each key in ``keys`` and returns the value of the first
  ## one of type `T`. If none of the keys are set or none of the keys can be
  ## converted to `T`, returns ``default``. ``key`` is normalized (i.e., all
  ## characters lower case and hyphens and underscores removed).
  result = default
  for key in keys:
    if opts.hasKey(key):
      try:
        let tmpValue = opts[key]
        when T is string:
          result = opts[key]
        elif T is bool:
          result = opts[key].toBool
        elif T is int:
          result = opts[key].toInt
      except ValueError:
        discard

proc getOrDefault*[T: int|bool|string](opts: Options, key: string, default: T): T =
  ## Returns the value of type `T` located at `opts[key]`. ``key`` is normalized
  ## (i.e., all characters lower case and hyphens and underscores removed). If
  ## ``key`` is not present in ``opts`` or cannot be converted to `T`, returns
  ## ``default``.
  getOrDefault(opts, [key], default)

proc get*[T: string|bool|int](opts: Options, keys: openarray[string], default: T = ""): T =
  ## Alias for ``getOrDefault`` that returns the same type as ``default``.
  getOrDefault(opts, keys, default)

proc get*[T: string|bool|int](opts: Options, key: string, default: T = ""): T =
  ## Alias for ``getOrDefault`` that returns the same type as ``default``.
  opts.getOrDefault(key, default)

proc hasKeyOrPut*[T: string|int|bool](opts: Options, key: string, value: T): bool =
  ## Returns true if ``key`` is in ``opts``. ``key`` is normalized (i.e., all
  ## characters lower case and hyphens and underscores removed). Otherwise, sets
  ## ``opts[key]`` to ``value`` and returns false. If ``value`` is not a string,
  ## it will be converted to one.
  if hasKey(opts, key):
    result = true
  else:
    opts[key] = value

proc getOrPut*[T: string|bool|int](opts: Options, key: string, value: T): T =
  ## Returns the value located at `opts[key]`. ``key`` is normalized (i.e., all
  ## characters lower case and hyphens and underscores removed). If the key does
  ## not exist or cannot be converted to ``T``, it is set to ``value``, which is
  ## returned.
  result = value
  if opts.hasKeyOrPut(key, value):
    let tmpValue = opts[key]
    try:
      when T is bool:
        result = tmpValue.toBool
      elif T is int:
        result = tmpValue.toInt
      else:
        result = tmpValue
    except ValueError:
      opts[key] = value

proc putKeyOrHelp*[T: string|bool|int](opts: Options, keys: openarray[string], value: T) =
  ## Checks ``opts`` for each key in ``keys``, setting the first missing key to
  ## ``value``. If all ``keys`` are set, sets the ``help`` key to `true`.
  for key in keys:
    if key notin opts:
      opts[key] = value
      return
  opts["help"] = true

proc getPackageRoot*(dir = getCurrentDir()): string =
  ## Walks the path ``dir`` and its parents seeking a `nasher.cfg` file. If
  ## found, returns the directory containing it. Otherwise, returns an empty
  ## string.
  let path = dir.absolutePath
  if dirExists(path):
    for dir in path.parentDirs:
      if fileExists(dir / "nasher.cfg"):
        return dir

proc getConfigFile*(pkgDir = ""): string =
  ## Returns the cofiguration file for the package containing ``pkgDir``. If
  ## ``pkgDir`` is not in a nasher project, returns an empty string. If
  ## ``pkgDir`` is blank, returns the user's global configuration file.
  if pkgDir.len > 0:
    let root = pkgDir.getPackageRoot
    if root.len > 0:
      return root / ".nasher" / "user.cfg"
  else:
    return getConfigDir() / "nasher" / "user.cfg"

proc loadStream*(opts: Options, s: Stream, filename = "[stream]") =
  ## Loads all key/value pairs from ``s`` into ``opts``. Will throw a
  ## `SyntaxError` if invalid syntax was found. ``filename`` is used only for
  ## pretty error messages.
  var
    p: CfgParser
    e: CfgEvent
  p.open(s, fileName)
  while true:
    e = p.next
    case e.kind
    of cfgKeyValuePair, cfgOption:
      opts[e.key] = e.value
    of cfgEof:
      break
    of cfgError:
      raise newException(SyntaxError, e.msg)
    else:
      discard
  p.close

proc loadString*(opts: Options, s: string, filename = "[stream]") =
  ## Loads all key/value pairs from ``s`` into ``opts``. Will throw a
  ## `SyntaxError` if invalid syntax was found. ``filename`` is used only for
  ## pretty error messages.
  opts.loadStream(newStringStream(s), filename)

proc loadFile*(opts: Options, file: string) =
  ## Loads all key/value pairs from ``file`` into ``opts``. Will throw an
  ## `IOError` if ``file`` does not exist or a `SyntaxError` if invalid syntax
  ## was found in the file.
  opts.loadStream(openFileStream(file), file)

proc parseCommandLine*(opts: Options, params: seq[string] = commandLineParams()) =
  ## Parses the command-line parameters in ``params`` into ``opts``. During
  ## parsing, options are cli-style-insensitive; that is, hypens and underscores
  ## are ignored and case is ignored in all but the first character. Passing an
  ## unknown option is not an error; this allows for path aliases to be passed
  ## as options.
  const
    shortFlags = {'h', 'v', 'y', 'n'}
    longFlags = @["help", "version", "color", "no-color", "debug", "verbose",
                  "quiet", "yes", "no", "default", "get", "set", "unset",
                  "list", "global", "local", "clean", "no-convert",
                  "no-compile", "no-pack", "no-install", "remove-deleted",
                  "remove-unused-areas", "use-module-folder"]
  for kind, key, val in getopt(params, shortNoVal = shortFlags, longNoVal = longFlags):
    case kind
    of cmdArgument:
      # echo "Got arg: ", key, " => ", val
      case opts.get("command")
      of "init":
        opts.putKeyOrHelp(["directory", "file"], key)
      of "config":
        opts.putKeyOrHelp((["config-key", "config-value"]), key)
      of "list":
        opts.putKeyOrHelp(["target"], key)
      of "convert", "compile", "pack", "install", "play", "test", "serve":
        if opts.hasKeyOrPut("targets", key):
          opts["targets"] = opts["targets"] & ";" & key
      of "unpack":
        opts.putKeyOrHelp(["target", "file"], key)
      else:
        if key in nasherCommands:
          opts["command"] = key
        else:
          opts["help"] = true
          break
    of cmdLongOption, cmdShortOption:
      # echo "Got option: ", key, " =>  ", val
      let normalKey = key.optionNormalize
      case normalKey
      of "h", "help", "command":
        opts["help"] = true
      of "v", "version":
        opts["version"] = true
      of "color", "nocolor":
        try:
          let show = val.toBool
          cli.setShowColor(if normalKey == "nocolor": not show else: show)
        except ValueError:
          raise newException(SyntaxError, "Expected bool value for option --$1 but got $2" % [key, val.escape])
      of "quiet":
        cli.setLogLevel(HighPriority)
      of "verbose":
        cli.setLogLevel(LowPriority)
      of "debug":
        cli.setLogLevel(DebugPriority)
      of "y", "yes":
        cli.setForceAnswer(Yes)
      of "n", "no":
        cli.setForceAnswer(No)
      of "default":
        cli.setForceAnswer(Default)
      of "forceanswer":
        try:
          cli.setForceAnswer(parseEnum[cli.Answer](val))
        except ValueError:
          raise newException(SyntaxError, "Expected one of [None, Yes, No, Default] for option --$1 but got $2" % [key, val.escape])
      else:
        case opts.get("command")
        of "config":
          case normalKey
          of "g", "get": opts.putKeyOrHelp(["config-op"], "get")
          of "s", "set": opts.putKeyOrHelp(["config-op"], "set")
          of "u", "unset": opts.putKeyOrHelp(["config-op"], "unset")
          of "l", "list": opts.putKeyOrHelp(["config-op"], "list")
          of "global", "local": opts.putKeyOrHelp(["config-scope"], key)
          of "d", "dir", "directory": opts.putKeyOrHelp(["directory"], val)
          else:
            opts.putKeyOrHelp(["config-key"], key)
            opts.putKeyOrHelp(["config-value"], val)
        of "compile":
          case key
          of "f", "file":
            if opts.hasKeyOrPut("files", val):
              opts["files"] = opts["files"] & ";" & val
          else:
            opts[key] = val
        else:
          opts[key] = val
    else:
      # echo kind
      discard

proc parseCommandLine*(opts: Options, params: string) =
  ## Alias for `parseCommandLine` that takes a string. Mostly useful for
  ## testing.
  parseCommandLine(opts, params.parseCmdLine)
