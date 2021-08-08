## Configuration options testing. Configuration options can be passed as
## command-line options or stored in a `user.cfg` file, either locally to the
## package or globally to the user. A table is populated with default values for
## the options, then the global and local `user.cfg` files are read into the
## table, overwriting the default values. Finally, command-line options are read
## into the table, overriding those.

import unittest, os, strutils

import nasher/utils/[optsparser, cli]

let
  packagePath = getTempDir() / "nasher_test"
  packageFile = packagePath / "nasher.cfg"
  localCfgFile = packagePath / ".nasher" / "user.cfg"
  globalCfgFile = getConfigDir() / "nasher" / "user.cfg"

suite "Options file location":
  createDir(packagePath / ".nasher")
  writeFile(packageFile, "")

  test "Return no config file if path is not nasher project":
    check getConfigFile(getTempDir()) == ""

  test "Get path to local config file":
    check getConfigFile(packagePath) == localCfgFile

  test "Get path to global config file":
    check getConfigFile() == globalCfgFile

  # Suite teardown
  removeDir(packagePath)

suite "Options table parsing":
  createDir(packagePath / ".nasher")
  writeFile(packageFile, "")

  teardown:
    removeFile(localCfgFile)

  test "New options table is empty by default":
    let opts = newOptionsTable()
    check:
      opts.len == 0

  test "Options table initialized with key/value pairs":
    let opts = newOptionsTable(("foo", "bar"), ("baz", "foobar"))
    check:
      opts.len == 2
      opts["foo"] == "bar"
      opts["baz"] == "foobar"

  test "Setting and getting a key is case- and style-insensitive":
    let opts = newOptionsTable()
    opts["fooBar"] = "baz"
    check:
      opts["fooBar"] == "baz"
      opts["foobar"] == "baz"
      opts["FOOBAR"] == "baz"
      opts["foo_bar"] == "baz"
      opts["FOO_BAR"] == "baz"
      opts["foo-bar"] == "baz"
      opts["FOO-BAR"] == "baz"

    opts["FOO_BAR"] = "qux"
    check:
      opts["FOO_BAR"] == "qux"
      opts["FOOBAR"] == "qux"
      opts["fooBar"] == "qux"
      opts["foobar"] == "qux"
      opts["foo_bar"] == "qux"
      opts["foo-bar"] == "qux"
      opts["FOO-BAR"] == "qux"

  test "Loading non-existent file throws exception":
    expect IOError:
      let opts = newOptionsTable()
      opts.loadFile("foo.cfg")

  test "Parsing error throws exception":
     expect SyntaxError:
       let opts = newOptionsTable()
       opts.loadString("""
       foo = "bar
       """)

  test "Reloading adds new keys":
    let opts = newOptionsTable()
    opts.loadString("""
    foo = "bar"
    bar = "baz"
    """)
    opts.loadString("""
    baz = "qux"
    """)

    check:
      opts.len == 3
      opts["foo"] == "bar"
      opts["bar"] == "baz"
      opts["baz"] == "qux"

  test "Reloading overwrites existing keys":
    let opts = newOptionsTable()
    opts.loadString("""
    foo = "bar"
    bar = "baz"
    """)
    opts.loadString("""
    bar = "qux"
    """)

    check:
      opts.len == 2
      opts["foo"] == "bar"
      opts["bar"] == "qux"

suite "Options table access":
  setup:
    let opts = newOptionsTable()

  test "Return default value if key not present":
    check:
      opts.get("foo") == ""
      opts.get("foo", "bar") == "bar"
      opts.get("foo", true) == true
      opts.get("foo", 1) == 1

    check:
      opts.get(@["foo", "bar"], "baz") == "baz"
      opts.get(@["foo", "baz"], true) == true
      opts.get(@["foo", "qux"], 1) == 1

    opts.loadString("""
    bar = "foobar"
    baz = false
    qux = 2
    """)
    check:
      opts.get(@["foo", "bar"], "baz") == "foobar"
      opts.get(@["foo", "baz"], true) == false
      opts.get(@["foo", "qux"], 1) == 2

  test "Return on/off, true/false, 1/0 as bool values":
    opts.loadString("""
    a = on
    b = off
    c = true
    d = false
    e = 1
    f = 0
    """)

    check:
      opts.get("a", false) == true
      opts.get("b", false) == false
      opts.get("c", false) == true
      opts.get("d", false) == false
      opts.get("e", false) == true
      opts.get("f", false) == false

  test "Return bool flag with no value as true":
    opts.loadString("foo")

    check:
      opts.get("foo", false) == true
      opts.get("bar", false) == false

  test "Return default value if option cannot be converted to default's type":
    opts.loadString("""
    foo = "bar"
    """)

    check:
      opts.get("foo", false) == false
      opts.get("foo", 0) == 0

  test "Return int flag with no value as default":
    opts.loadString("foo")
    check: opts.get("foo", 0) == 0

  test "Return numbers as int values":
    opts.loadString("a = 1")
    check: opts.get("a", 0) == 1

  test "Non-string values converted to string when setting":
    opts["foo"] = true
    opts["bar"] = 1
    check:
      opts.get("foo") == "true"
      opts.get("bar") == "1"
  
  test "Return value if set; put if not set or not convertible":
    opts["strval1"] = "foo"
    opts["intval1"] = 1
    opts["boolval1"] = true

    check:
      opts.getOrPut("strval1", "bar") == "foo"
      opts.getOrPut("strval2", "bar") == "bar"
      opts["strval1"] == "foo"
      opts["strval2"] == "bar"

      opts.getOrPut("intval1", 2) == 1
      opts.getOrPut("intval2", 2) == 2
      opts["intval1"] == "1"
      opts["intval2"] == "2"

      opts.getOrPut("boolval1", false) == true
      opts.getOrPut("boolval2", false) == false
      opts["boolval1"] == "true"
      opts["boolval2"] == "false"

    check:
      opts.getOrPut("strval1", true) == true
      opts.getOrPut("strval2", 1) == 1
      opts["strval1"] == "true"
      opts["strval2"] == "1"

      opts.getOrPut("intval1", "foo") == "1"
      opts.getOrPut("intval2", true) == true
      opts["intval1"] == "1"
      opts["intval2"] == "true"

      opts.getOrPut("boolval1", "foo") == "true"
      opts.getOrPut("boolval2", 1) == 1
      opts["boolval1"] == "true"
      opts["boolval2"] == "1"

suite "Command-line options parsing":
  setup:
    var opts: Options

    template withParams(params: varargs[string], body: untyped): untyped =
      for param in params:
        opts = newOptionsTable()
        opts.parseCommandLine(param)
        body

  test "Empty command-line yields empty table":
    withParams "":
      check opts.len == 0

  test "Parse single key-value pair":
    withParams "--modMinGameVersion 1.74":
      check:
        opts.len == 1
        opts["modMinGameVersion"] == "1.74"

  test "Parse multiple key-value pairs":
    withParams "--modMinGameVersion 1.74 --modName demo":
      check:
        opts.len == 2
        opts["modMinGameVersion"] == "1.74"
        opts["modName"] == "demo"

  test "Parse words inside whitespace as single value":
    withParams "--modName \"Demo Module\"":
      check:
        opts.len == 1
        opts["modName"] == "Demo Module"

  test "Parse first argument as command":
    withParams "init":
      check:
        opts.len == 1
        opts["command"] == "init"

  test "Valid commands limited":
    for command in nasherCommands:
      withParams command:
        check opts["command"] == command

  test "Show help on unrecognized command":
    withParams "foo":
      check:
        not opts.hasKey("command")
        opts["help"] == "true"

  test "Show help if trying to pass command as option":
    withParams "--command init":
      check:
        not opts.hasKey("command")
        opts["help"] == "true"

  test "Positional arguments for init":
    withParams "init":
      check:
        opts["command"] == "init"
        "directory" notin opts
        "file" notin opts
        "help" notin opts

    withParams "init foo":
      check:
        opts["command"] == "init"
        opts["directory"] == "foo"
        "file" notin opts
        "help" notin opts

    withParams "init foo bar":
      check:
        opts["command"] == "init"
        opts["directory"] == "foo"
        opts["file"] == "bar"
        "help" notin opts

    withParams "init foo bar baz":
      check:
        opts["command"] == "init"
        opts["directory"] == "foo"
        opts["file"] == "bar"
        opts["help"] == "true"

  test "Positional arguments for unpack":
    withParams "unpack":
      check:
        opts["command"] == "unpack"
        "directory" notin opts
        "file" notin opts
        "help" notin opts

    withParams "unpack foo":
      check:
        opts["command"] == "unpack"
        opts["target"] == "foo"
        "file" notin opts
        "help" notin opts

    withParams "unpack foo bar":
      check:
        opts["command"] == "unpack"
        opts["target"] == "foo"
        opts["file"] == "bar"
        "help" notin opts

    withParams "unpack foo bar baz":
      check:
        opts["command"] == "unpack"
        opts["target"] == "foo"
        opts["file"] == "bar"
        opts["help"] == "true"

  test "Positional arguments for list":
    withParams "list":
      check:
        opts["command"] == "list"
        "target" notin opts
    withParams "list foo":
      check:
        opts["command"] == "list"
        opts["target"] == "foo"

    withParams "list foo bar":
      check:
        opts["command"] == "list"
        opts["target"] == "foo"
        opts["help"] == "true"

  test "Positional arguments for pack loop added to target list":
    let commands = ["convert", "compile", "pack", "install", "play", "test", "serve"]
    for command in commands:
      withParams command & " foo":
        check:
          opts["command"] == command
          opts["targets"] == "foo"

    for command in commands:
      withParams command & " foo bar":
        check:
          opts["command"] == command
          opts["targets"] == "foo;bar"

  test "No value required for -h or --help":
    withParams "-h", "--help":
      check: opts["help"] == "true"

  test "No value required for -v or --version":
    withParams "-v", "--version":
      check: opts["version"] == "true"

  test "Parse --[no-]color as flags":
    withParams "--color":
      check cli.getShowColor()

    withParams "--no-color":
      check not cli.getShowColor()

  test "Parse --[no-]color as options":
    withParams "--color=false":
      check not cli.getShowColor()

    withParams "--no-color=false":
      check cli.getShowColor()

    for params in ["--color=foo", "--no-color=foo"]:
      expect SyntaxError:
        withParams params:
          discard

  test "Set forced answer with --force-answer":
    for answer in cli.Answer:
      withParams "--force-answer=" & toLowerAscii($answer):
        check cli.getForceAnswer() == answer

    expect SyntaxError:
      withParams "--force-answer=foo":
        discard

  test "Set forced answer with --yes, --no, and --default":
    withParams "-y", "--yes":
      check cli.getForceAnswer() == Yes

    withParams "-n", "--no":
      check cli.getForceAnswer() == No

    withParams "--default":
      check cli.getForceAnswer() == Default

  test "Set verbosity with --debug, --verbose, and --quiet":
    withParams "--debug":
      check cli.getLogLevel() == DebugPriority

    withParams "--verbose":
      check cli.getLogLevel() == LowPriority

    withParams "--quiet":
      check cli.getLogLevel() == HighPriority

  test "Set config operation with --get, --set, --unset, or --list":
    withParams "config -g", "config --get":
      check opts["config-op"] == "get"
    withParams "config -s", "config --set":
      check opts["config-op"] == "set"
    withParams "config -u", "config --unset":
      check opts["config-op"] == "unset"
    withParams "config -l", "config --list":
      check opts["config-op"] == "list"

  test "Set config scope with --global or --local":
    withParams "config --global":
      check opts["config-scope"] == "global"

    withParams "config --local":
      check opts["config-scope"] == "local"

  test "Set config key and value as arguments":
    withParams "config foo":
      check:
        opts["config-key"] == "foo"
        "config-value" notin opts

    withParams "config foo bar":
      check:
        opts["config-key"] == "foo"
        opts["config-value"] == "bar"

  test "Set config key and value as option":
    withParams "config --foo":
      check:
        opts["config-key"] == "foo"
        opts["config-value"] == ""

    withParams "config --foo bar":
      check:
        opts["config-key"] == "foo"
        opts["config-value"] == "bar"

