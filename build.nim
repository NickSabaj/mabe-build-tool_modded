import os, osproc
import terminal #colorations
import streams #stringStream, read/write
import strformat #&
import strutils #removeSuffix
import sequtils #zip, toSeq
import tables
import mabe_extras
import httpclient_tlse
import parseopt
import strscans

const minimum_cmake_version_string = "3.13.3" # 3.13.3
const minimum_cmake_version = minimum_cmake_version_string.replace(".","").parse_int()

const MODULE_TYPES = ["Archivist","Brain","Genome","Optimizer","World"]
var cmake_exe:string
when defined(windows):
  if exists_file "C:\\Program Files\\CMake\\bin\\cmake.exe":
    cmake_exe = "C:\\Program Files\\CMake\\bin\\cmake.exe"
  else:
    cmake_exe = "cmake"
when defined(linux):
  cmake_exe = "cmake"
when defined(macosx):
  cmake_exe = "/Applications/CMake.app/Contents/bin/cmake"
  if exists_file "/Applications/CMake.app/Contents/bin/cmake":
    cmake_exe = "/Applications/CMake.app/Contents/bin/cmake"
  else:
    cmake_exe = "cmake"

## This _was_ using argparse successfully,
## but it has far too many bugs necessitating
## duplicate functionality and a page of if statements.
## Docopt would have also worked, but included 4 dependencies,
## and the help text format would be restrictive.
## Here's my own CLI interface for posix-style
## space-separated arguments.
## Use register_command(word,nargs=2) 
## then use capture_command(word) for
## the CLI system to watch out for 'word'
## on the command line, and grab 2 things
## after it, WITHOUT crashing if there
## aren't 2 things after it.
## Automatically generated variables: word_enabled:bool, word_args:seq[string]
template register_command(command:untyped, nargs:Natural = 0, aliases:openArray = new_seq[string]()) {.dirty.} =
  when not defined(`command`):
    let `command` :string = ""
  var
    `command _ args` {.used.} = new_seq[string]()
    `command _ enabled` = false
    `command _ args _ len` {.used.} = nargs
    `all _ command _ alias _ list`:seq[string] # [command, alias1, alias2, ...]
  if aliases.len > 0:
    `all _ command _ alias _ list` = concat(@[`command`.astToStr],to_seq(aliases))
  else:
    `all _ command _ alias _ list` = @[`command`.astToStr]
## Use p.capture_command(word) in a standard parseOpts
## while-case loop (see docs https://nim-lang.org/docs/parseopt.html)
## then after the loop, the variables word_enabled:bool, word_args:seq[string]
## will be set for you
template capture_command(p:OptParser, command:untyped) {.dirty.} =
  if p.key in `all _ command _ alias _ list`:
    `command _ enabled` = true
    for capture_command_i in 1 .. `command _ args _ len`:
      p.next()
      if p.kind == cmdEnd: break # assume we're using parseopt while loop convention
      `command _ args`.add p.key
    continue

## register all cli arguments
when defined(windows):
  register_command(vs)
register_command(force,aliases=["f"])
register_command(quick,aliases=["q"])
register_command(init,aliases=["refresh"])
register_command(cxx,nargs=1,aliases=["c"])
register_command(debug,aliases=["d"])
register_command(generate,nargs=1,aliases=["gen"])
register_command(new,nargs=2)
register_command(copy,nargs=3,aliases=["cp"])
register_command(download,nargs=1,aliases=["dl"])
register_command(help,aliases=["h"])

proc count_cores():int =
  let num_reported = count_processors()
  result = if num_reported mod 2 == 0: num_reported div 2
           else: num_reported

proc write_error(alert:string="",msg:string="") =
  stderr.writeLine ""
  styledWriteLine(stderr, fgRed, alert, resetStyle, msg)

proc write_success(alert:string="",msg:string="") =
  stdout.writeLine ""
  styled_write_line(stdout, fgGreen, alert, resetStyle, msg)

proc write_warning(alert:string="",msg:string="") =
  stdout.writeLine ""
  styledWriteLine(stdout, fgYellow, alert, resetStyle, msg)

proc exe_exists(exe:string):bool = result = (find_exe(exe) != "")

proc vccmake_exists():bool {.used.} =
  const vsdir = "C:\\Program Files (x86)\\Microsoft Visual Studio"
  if dir_exists vsdir:
    for file_type,edition_name in walk_dir(vsdir, relative=true):
      if file_type == pcDir and edition_name.len == 4:
        for version in ["Community","Professional","Enterprise","BuildTools"]:
          for file_type,file_name in walk_dir(vsdir / edition_name / version / "Common7\\IDE\\CommonExtensions\\Microsoft\\CMake\\CMake\\bin", relative=true):
            if file_name == "cmake.exe": return true
  return false

proc vcvars_exists():bool {.used.} =
  const vsdir = "C:\\Program Files (x86)\\Microsoft Visual Studio"
  if dir_exists vsdir:
    for file_type,edition_name in walk_dir(vsdir, relative=true):
      if file_type == pcDir and edition_name.len == 4:
        for version in ["Community","Professional","Enterprise","BuildTools"]:
          for file_type,file_name in walk_dir(vsdir / edition_name / version / "VC\\Auxiliary\\Build", relative=true):
            if file_name == "vcvars64.bat": return true
  return false

proc cmake_exists():bool =
  when defined(windows):
    result = (file_exists cmake_exe) or (exe_exists cmake_exe)
  when defined(linux):
    result = exe_exists "cmake"
  when defined(macosx):
    result = file_exists "/Applications/CMake.app/Contents/bin/cmake"

proc good_cmake_version():bool =
  if cmake_exists():
    let (cmake_output, _) = execCmdEx(command=cmake_exe&" --version")
    # possible strings variations (first lines only):
    # cmake version 3.14.2-rc02
    # cmake version 3.15.3
    try:
      let version_number = cmake_output.split_lines[0].split('-')[0].split()[2].replace(".","").parse_int()
      if version_number >= minimum_cmake_version: result = true
      else: result = false
    except:
      write_error("Error: ","couldn't get proper cmake version information. Do you have a non-standard cmake installed?")
      quit(1)

proc error_if_no_code_cmake_cmakelists_modules_or_build() =
  # check for ./code/
  if not dir_exists "code":
    write_error("Error: ","No code/ dir found. Is this a complete MABE project?")
    quit(1)
  # prepare (clean out cmake cache) ./build/
  if not quick_enabled:
    remove_file "build" / "CMakeCache.txt"
  create_dir "build"
  # prepare ./work/
  create_dir "work"
  # check for ./CMakeLists.txt
  if not file_exists "CMakeLists.txt":
    write_error("Error: ","No CMakeLists.txt file found. Is this a complete MABE project?")
    quit(1)
  # check for cmake in path
  when defined(windows):
    let cmake_found = vccmake_exists() or cmake_exists()
  when not defined(windows):
    let cmake_found = cmake_exists()
  if not cmake_found:
    when defined(windows):
      write_error("Error: ","cmake does not appear to be installed\n       (C:\\Program Files\\CMake\\bin\\cmake.exe)")
    when not defined(windows):
      write_error("Error: ","cmake does not appear to be installed")
    quit(1)
  if not file_exists "modules.txt":
    write_warning("Warning: ","No modules.txt found. It will be created from the installed modules if necessary...")

proc run_cmake_configure(args:seq[string] = @[]) =
  let all_args = concat([@[".."], args])
  var cmake_process = start_process(command=cmake_exe, working_dir="build", args=all_args, options={poStdErrToStdOut, poUsePath, poParentStreams})
  # defer the process cleanly closing before the function exists for any reason
  defer: close cmake_process
  let cmake_errorcode = cmake_process.wait_for_exit()
  if cmake_errorcode != 0:
    write_error("Error: ","cmake configuration failed. See above for details.")
    quit(1)
  else:
    write_success("Configuration Succeeded: ","module detection and source file generation finished.")

proc run_cmake_build(args:string = "") =
  let default_args = split(&"--build . -j {count_cores()} --")
  let user_args = if args.strip().len == 0: @[] else: args.strip().split()
  let all_args = concat(default_args,user_args)
  var cmake_process = start_process(command=cmake_exe, working_dir="build", args=all_args, options={poStdErrToStdOut, poUsePath, poParentStreams})
  # defer the process cleanly closing before the function exists for any reason
  defer: close cmake_process
  let cmake_errorcode = cmake_process.wait_for_exit()
  if cmake_errorcode != 0:
    write_error("Error: ","build failed. See above for details.")
    quit(1)
  else:
    var ext = ""
    when defined(windows):
      ext = ".exe"
    when not defined(windows):
      ext = ""
    write_success("Build Succeeded: ", &"mabe executable build as work/mabe{ext}")

type ModuleProperties = tuple[enabled:bool,default:bool] # single module, and it's enabled status
type ModuleList = Table[string,ModuleProperties] # list of modules all belonging to the same group (ex: all Brains)
type ModulesTable = Table[string,ModuleList] # list of module lists, keyd by group (ex: Brain)

proc new_module_properties(enabled:bool,default:bool=false):ModuleProperties =
  result = (enabled:enabled,default:default)

proc new_module_list():auto = init_table[string,ModuleProperties]()

proc get_code_modules():ModulesTable =
  # scans the ./code/ dir for all module names
  for module_type in MODULE_TYPES:
    for filetype,filename in walk_dir "code" / module_type:
      if filetype == pcDir:
        var module_name = filename.split_path.tail
        module_name.remove_suffix module_type
        result.mget_or_put(module_type,new_module_list())[module_name] = new_module_properties(enabled=false)
        # explore CMakeLists.txt and scrape default status
        if exists_file filename / "CMakeLists.txt":
          for line in lines(filename / "CMakeLists.txt"):
            var ignoreme:string
            if scanf(line, """option$s($senable_$*ON$s)$s""", ignoreme):
              result[module_type][module_name].default = true


proc enable_default_modules(allmodules:var ModulesTable) =
  const default_modules = ["LODwAP","CGP","Circular","Simple","Test"]
  for i,(module_type,module_name) in zip(MODULE_TYPES,default_modules):
    if allmodules[module_type].has_key module_name:
      allmodules[module_type][module_name].enabled = true
      allmodules[module_type][module_name].default = true

proc get_human_readable_formatting(allmodules:ModulesTable):string =
  var content = new_string_stream()
  defer: close content
  for module_type,module_list in allmodules:
    content.write_line &"% {module_type}"
    for module_name,module_properties in module_list:
      let enabled_char = if not module_properties.default:
                            if module_properties.enabled: '+'
                            else: '-'
                         else: '*'
      content.write_line &"  {enabled_char} {module_name}"
    content.write_line "" # separate sections
  content.set_position 0
  result = content.read_all()

proc get_txt_modules():ModulesTable =
  var file = new_file_stream("modules.txt")
  var
    module_type = ""
    module_name = ""
    enabled = false
    default = false
  for line in file.lines:
    if line.len == 0: continue
    if line[0]=='%':
      module_type = line.split()[1]
      continue
    else:
      let fields = line.strip().split()
      enabled = if fields[0][0]!='-': true else: false
      default = if fields[0][0]=='*': true else: false
      module_name = fields[1]
      result.mget_or_put(module_type,new_module_list())[module_name] = new_module_properties(enabled=enabled,default=default)
      continue

proc verify_and_merge_module_tables(txt,code:ModulesTable):ModulesTable =
  result = code
  for txt_module_type,txt_module_list in txt:
    for txt_module_name,txt_module_properties in txt_module_list:
      if not code[txt_module_type].has_key txt_module_name:
        write_warning("Removing module: ",&"'{txt_module_name}{txt_module_type}' in modules.txt does not exist in MABE (code/)")
      else:
        result[txt_module_type][txt_module_name].enabled = txt[txt_module_type][txt_module_name].enabled
        result[txt_module_type][txt_module_name].default = txt[txt_module_type][txt_module_name].default

proc convert_modules_table_to_cmake_options_string(modulestable:ModulesTable):seq[string] =
  for module_type,module_list in modulestable:
    for module_name,module_properties in module_list:
      if module_properties.enabled:
        result.add &"-Denable_{module_type}_{module_name}=1"
      else:
        result.add &"-Denable_{module_type}_{module_name}=0"
      if module_properties.default:
        result.add &"-Ddefault_{module_type}={module_name}"

proc get_supported_cmake_projects():OrderedTable[string,string] =
  if not good_cmake_version():
    write_error("CMake outdated: ",&"Minimum required cmake version is '{minimum_cmake_version_string}'")
    quit(1)
  when defined(windows):
    const full_table_to_short_commands = {
      "MSYS Makefiles":"make",
      "Unix Makefiles":"umake",
      "MinGW Makefiles":"mmake",
      "Visual Studio 16 2019":"vs",
      "Visual Studio 15 2017 [arch]":"vs2017",
      "CodeBlocks - MinGW Makefiles":"cbmmake",
      "CodeBlocks - NMake Makefiles":"cbnmake",
      "CodeBlocks - Ninja":"cbninja",
      "CodeBlocks - Unix Makefiles":"cbmake",
      "CodeLite - MinGW Makefiles":"cdmmake",
      "CodeLite - NMake Makefiles":"cdnmake",
      "CodeLite - Ninja":"cdninja",
      "CodeLite - Unix Makefiles":"clmake",
      "Sublime Text 2 - MinGW Makefiles":"submmake",
      "Sublime Text 2 - NMake Makefiles":"subnmake",
      "Sublime Text 2 - Ninja":"subninja",
      "Sublime Text 2 - Unix Makefiles":"submake",
      "Kate - MinGW Makefiles":"katemmake",
      "Kate - NMake Makefiles":"katenmake",
      "Kate - Ninja":"kateninja",
      "Kate - Unix Makefiles":"katemake",
      "Eclipse CDT4 - MinGW Makefiles":"eclipsemmake",
      "Eclipse CDT4 - NMake Makefiles":"eclipsenmake",
      "Eclipse CDT4 - Ninja":"eclipseninja",
      "Eclipse CDT4 - Unix Makefiles":"eclipsemake"}.toTable
  when defined(linux):
    const full_table_to_short_commands = {
      "Unix Makefiles":"make",
      "Ninja":"ninja",
      "CodeBlocks - Ninja":"cbninja",
      "CodeBlocks - Unix Makefiles":"cbmake",
      "CodeLite - Ninja":"cdninja",
      "CodeLite - Unix Makefiles":"clmake",
      "Sublime Text 2 - Ninja":"subninja",
      "Sublime Text 2 - Unix Makefiles":"submake",
      "Kate - Ninja":"kateninja",
      "Kate - Unix Makefiles":"katemake",
      "Eclipse CDT4 - Ninja":"eclipseninja",
      "Eclipse CDT4 - Unix Makefiles":"eclipsemake"}.toTable
  when defined(macosx):
    const full_table_to_short_commands = {
      "Unix Makefiles":"make",
      "Xcode":"xcode",
      "Ninja":"ninja",
      "CodeBlocks - Ninja":"cbninja",
      "CodeBlocks - Unix Makefiles":"cbmake",
      "CodeLite - Ninja":"cdninja",
      "CodeLite - Unix Makefiles":"clmake",
      "Sublime Text 2 - Ninja":"subninja",
      "Sublime Text 2 - Unix Makefiles":"submake",
      "Kate - Ninja":"kateninja",
      "Kate - Unix Makefiles":"katemake",
      "Eclipse CDT4 - Ninja":"eclipseninja",
      "Eclipse CDT4 - Unix Makefiles":"eclipsemake"}.toTable
  if not cmake_exists():
    return #empty
  else:
    let (cmake_output, _) = execCmdEx(command=cmake_exe&" --help")
    var found_generators = false
    var generator_name:string
    for line in cmake_output.split_lines:
      if line.len == 0: continue
      if (not line.starts_with("Generators")) and (not found_generators): continue
      elif not found_generators:
        found_generators = true
        continue
      # example line, we want "CodeLite - Ninja"
      # and "CodeLite - Unix Makefiles" from below:
      #* CodeLite - Unix Makefiles    = Generates CodeLite project files.
      #  CodeLite - Ninja             = Generates CodeLite project files.
      if line[2] != ' ':
        generator_name = line[2 ..< ^1].split('=')[0].strip(leading=false,trailing=true)
        if full_table_to_short_commands.has_key generator_name:
          # be sure to replace visual studio's "[arch]" placeholder with "Win64"
          # now that we don't need the exact string anymore for matching
          result[ full_table_to_short_commands[generator_name] ] = generator_name.replace("[arch]","Win64")
    return

proc list_generator_options() =
  var generator_options = get_supported_cmake_projects()
  # find length of largest short name, so
  # we can right-alignt the long names
  var biggest_short_name_size = 0
  for short_name,full_name in generator_options:
    if short_name.len > biggest_short_name_size: biggest_short_name_size = short_name.len
  # show all options with proper right-alignment for full names
  echo "Supported CMake Project Generator options"
  echo ""
  for short_name,full_name in generator_options:
    echo &"  {short_name} "  &  indent(&"= \"{full_name}\"",biggest_short_name_size-short_name.len)
  quit(0)

proc refresh_and_get_modules(new_module_type:string="",new_module_name:string=""):ModulesTable =
  # makes sure modules.txt is up to date and returns the contents
  var txt_modules,code_modules,final_modules:ModulesTable
  # if no modules.txt (or if forcing), make it from reading ./code/ files
  code_modules = get_code_modules()
  if force_enabled or not file_exists "modules.txt":
    #enable_default_modules code_modules
    var content = get_human_readable_formatting code_modules
    "modules.txt".write_file content
  else:
    # now read modules.txt
    txt_modules = get_txt_modules()
    final_modules = verify_and_merge_module_tables(txt=txt_modules,code=code_modules)
    # enable new default module, if non-zero string
    if new_module_type.len != 0 and new_module_name.len != 0:
      let module_type = new_module_type.to_lower_ascii.capitalize_ascii
      for module_name in final_modules[module_type].keys:
        if module_name == new_module_name:
          final_modules[module_type][module_name].enabled = true
          final_modules[module_type][module_name].default = true
        else:
          final_modules[module_type][module_name].default = false
    var final_content = get_human_readable_formatting  final_modules
    "modules.txt".write_file final_content
  write_success("modules.txt Success: ","modules.txt up to date")
  result = final_modules

proc add_cxx_compiler(cmake_options:var seq[string], compiler:string) =
  cmake_options.add &"-DCMAKE_CXX_COMPILER={compiler}"

proc generate_and_build() =
  if generate_enabled and (generate_args.len == 0 or generate_args[0] == "help"):
    list_generator_options()

  var modules_txt_table = refresh_and_get_modules()
  var cmake_options = convert_modules_table_to_cmake_options_string  modules_txt_table

  # clean out build dir if requested
  if force_enabled:
    var removed_all_okay = true
    for file_type,file_name in walk_dir("build"):
      try:
        if file_type == pcFile: remove_file file_name
        elif file_type == pcDir: remove_dir file_name
      except OSError:
        removed_all_okay = false
        write_warning("Warning: ",&"file '{file_name}' seems to be in use and couldn't be removed")
    if removed_all_okay: write_success("build/ Cleaned: ","all files removed")
    else: write_warning("Warning: ","not all files in build/ could be removed")

  # build a visual studio project file if no g++ or clang, or if the user wanted it
  var vs_was_specified = false
  when defined(windows):
    vs_was_specified = vs_enabled
  if vs_was_specified or ( (not exe_exists "g++") and (not exe_exists "clang++") ):
    if cxx_args.len != 0:
      write_warning("Compiler Not Found: ",&"'{cxx_args[0]}' not found. Using Visual Studio.")
    if generate_args.len != 0:
      write_warning("Only VS Installed: ","Only Visual Studio found, so only VS project files can be created. gcc / clang needed for most other types.")
    run_cmake_configure cmake_options
    if (generate_args.len == 0) and (not vcvars_exists()):
      write_error("Error: ","Trying to build with Visual Studio, but no Visual Studio found")
      quit(1)
    if (generate_args.len == 0):
      var BUILD_TYPE = if debug_enabled: "Debug" else: "Release"
      run_cmake_build &"-p:OutDir=../work/ -p:AssemblyName=mabe.exe;Configuration={BUILD_TYPE};std=c++latest;BuildInParallel=true -m"
    quit(0)
  var cxx_compiler = if cxx_args.len != 0: cxx_args[0] else: "g++"

  # if generating project file, then set the cmake_option
  if generate_args.len != 0:
    var generator_options = get_supported_cmake_projects()
    # check if user specified a valid option
    if not generator_options.has_key generate_args[0]:
      write_error("Error: ",&"no generator named '{generate_args[0]}'")
      quit(1)
    cmake_options.add "-G"
    cmake_options.add &"{generator_options[generate_args[0]]}"
  else:
    # otherwise, generate a standard makefile
    cmake_options.add "-G"
    when defined(windows):
      cmake_options.add "MSYS Makefiles"
    when not defined(windows):
      cmake_options.add "Unix Makefiles"

  # set debug/release configuration
  var BUILD_TYPE = if debug_enabled: "Debug" else: "Release"
  cmake_options.add &"-DCMAKE_BUILD_TYPE={BUILD_TYPE}"
  cmake_options.add &"-DCMAKE_CONFIGURATION_TYPES={BUILD_TYPE}"
  write_warning("Warning: ",&"configuring for {BUILD_TYPE} mode build")

  # fail if the compiler doesn't exist
  if not exe_exists cxx_compiler:
    write_error("Error: ",&"compiler '{cxx_compiler}' not found")
    quit(1)

  # add the compiler to the cmake options
  cmake_options.add_cxx_compiler cxx_compiler

  # run cmake configuration (this also generates project files - Makefile by default)
  if generate_enabled or not quick_enabled:
    run_cmake_configure cmake_options
    if generate_enabled:
      write_success("Project Success: ","Project created in build/")

  # if we aren't making a project file
  # then do a full compile
  if generate_args.len == 0:
    run_cmake_build()

# Templates
proc list_templates() =
  echo "Using the 'new' command"
  echo ""
  for module_type in ["archivist","brain","genome","optimizer","world"]:
    echo &"  new {module_type} NEW_NAME"
  echo ""
  echo "Example: new world Water"
  echo ""
  echo "Note: 'world' is not case sensitive, but the name 'Water' is case sensitive."
  echo ""

proc is_valid_module_type(module_type:string):bool =
  if module_type.to_lower_ascii in ["archivist","brain","genome","optimizer","world"]: result = true
  else: result = false

proc is_valid_template_module_type(module_type:string):bool =
  result = module_type.is_valid_module_type()
  if (result == true) and (not file_exists "code" / "Utilities" / "Templates" / "Template"&module_type.to_lower_ascii.capitalize_ascii&".h"):
    write_warning("Missing: ",&"sorry, no template files for {module_type.to_lower_ascii}s exist yet")
    result = false

proc copy_template_to_module(module_type, module_name:string) =
  ## forced overwrites whatever files are there
  let
    source_path = "code" / "Utilities" / "Templates"
    dest_path = "code" / module_type / module_name&module_type
    base_name = module_name & module_type
  var source_paths,dest_paths:seq[string]
  for filename in [base_name&".h", base_name&".cpp", "CMakeLists.txt"]:
    dest_paths.add dest_path / filename
  for filename in ["Template"&module_type&".h", "Template"&module_type&".cpp", "CMakeLists.txt"]:
    source_paths.add source_path / filename
  # copy files and perform template world replacement
  let replacements = @[("{{MODULE_NAME}}",     module_name),
                       ("{{MODULE_NAME_CAPS}}",module_name.to_upper_ascii),
                       ("{{MODULE_TYPE}}",     module_type)]
  create_dir dest_path
  for i,(source,destination) in zip(source_paths, dest_paths):
    if force_enabled or not file_exists destination:
      copy_file(source, destination)
      let contents = read_file destination
      let new_contents = contents.multi_replace(replacements)
      destination.write_file new_contents
    else:
      write_warning("Skipping file: ",&"file exists; use -f to overwrite '{destination}'")
  write_success("Created Module: ",&"{module_type}/{module_name}{module_type} created")

proc list_or_make_templates() =
  if new_args.len == 0 or new_args[0] == "help":
    list_templates()
    quit(0)
  if not new_args[0].is_valid_template_module_type():
    write_error("Error: ",&"'{new_args[0]}' not a valid module type")
    quit(1)
  if new_args.len == 1: # actually need 2 arguments
    write_error("Error: ","you need to provide a new name, in addition to the type of module you are creating")
    quit(1)
  # remove extraneous module names from target names
  for typeName in "Archivist Brain Genome Optimizer World".split:
    for i,newName in new_args.mpairs:
      if i==0: continue
      if newName.endsWith(typeName) and newName.len > typeName.len:
        newName.removeSuffix typeName
        break
  for each_name in new_args[1 .. ^1]: # skip first argument
    copy_template_to_module(new_args[0].to_lower_ascii.capitalize_ascii, each_name)

# installed modules listing for making copies
proc list_installed_modules() =
  echo "Using the 'copy' or 'cp' command"
  var table = initOrderedTable[string,seq[string]]()
  for module_type in MODULE_TYPES:
    table[module_type] = @[]
  let local_files = directory_structure_from_local()
  for entry in local_files:
    let (module_type,module_name) = entry.localpath.split_path
    table[module_type].add module_name
    table[module_type][^1].remove_suffix module_type
  echo ""
  for module_type,module_names in table:
    echo module_type,"s"
    for module_name in module_names:
      echo &"  {module_name}"
    echo ""
  echo "Example: mbuild copy world Test MyTestVariation"
  echo ""
  echo "Note: 'world' is not case sensitive, but the names after are case sensitive."
  echo ""

proc is_valid_module_name(name:string):bool =
  let local_files = directory_structure_from_local()
  var query:FileEntry
  for module_type in MODULE_TYPES:
    query.localpath = module_type&DirSep&name&module_type
    if query in local_files:
      return true
  return false

# recursive copy files with word replacement in name and contents
proc recursive_copy_files_and_replace_names(source_dir,dest_dir,source_name,dest_name:string) =
  let source_name_caps = source_name.to_upper_ascii
  let dest_name_caps = dest_name.to_upper_ascii
  for file_type,file_name in walk_dir(dir=source_dir, relative=true):
    if file_type == pcDir:
      let
        new_name = file_name.replace(source_name,dest_name).replace(source_name_caps,dest_name_caps)
        new_dir = dest_dir / new_name
        old_dir = source_dir / file_name
      create_dir new_dir
      recursive_copy_files_and_replace_names(old_dir,new_dir,source_name,dest_name)
    else: # file_type == pcFile
      let
        new_name = file_name.replace(source_name,dest_name).replace(source_name_caps,dest_name_caps)
        new_file = dest_dir / new_name
        old_file = source_dir / file_name
        new_contents = read_file(old_file).replace(source_name,dest_name).replace(source_name_caps,dest_name_caps)
      new_file.write_file new_contents

# copy module worker
proc copy_module(module_type,module_sname,module_dname:string) =
  let
    module_spath = "code" / module_type / module_sname & module_type
    module_dpath = "code" / module_type / module_dname & module_type
  create_dir module_dpath
  recursive_copy_files_and_replace_names(source_dir  = module_spath,
                               dest_dir    = module_dpath,
                               source_name = module_sname,
                               dest_name   = module_dname)

# copy module bouncer
proc list_or_make_copy() =
  if copy_args.len == 0 or copy_args[0] == "help":
    list_installed_modules()
    quit(0)
  # remove extraneous module names from source module
  for name in "Archivist Brain Genome Optimizer World".split:
    if copy_args[1].endsWith(name) and copy_args[1].len > name.len:
      copy_args[1].removeSuffix name
      break
  # remove extraneous module names from target module
  for name in "Archivist Brain Genome Optimizer World".split:
    if copy_args[2].endsWith(name) and copy_args[2].len > name.len:
      copy_args[2].removeSuffix name
      break
  # ensure valid module type
  if not copy_args[0].is_valid_module_type():
    write_error("Error: ",&"'{copy_args[0]}' not a valid module type")
    quit(1)
  # ensure provided 2 names in addition to module_type
  if copy_args.len != 3:
    write_error("Error: ","you need to provide a name of a module to copy, and a new name for the copy, and only those 2 names.")
    quit(1)
  # ensure the module to copy is valid
  if not copy_args[1].is_valid_module_name():
    write_error("Error: ",&"'{copy_args[1]}' not a valid existing module name")
    quit(1)
  # if we got this far, then perform the copy
  let
    source_name = "code" / copy_args[0].capitalize_ascii / copy_args[1] & copy_args[0].capitalize_ascii
    dest_name = "code" / copy_args[0].capitalize_ascii / copy_args[2] & copy_args[0].capitalize_ascii
  echo &"copying {source_name} to {dest_name}"
  # only as long as the file doesn't already exist
  if (not force_enabled) and (dest_name.dir_exists):
    write_warning("Skipping file: ",&"file exists; use -f to overwrite '{dest_name}'")
  else:
    copy_module(module_type=copy_args[0].capitalize_ascii, module_sname=copy_args[1], module_dname=copy_args[2])
  write_success("Copied Module: ",&"new {copy_args[0]} module at: {dest_name}")

# mabe extras downloading
proc list_extra_modules(manifest_files,local_files:auto) =
  # find length of longest line we will be printing
  var length_longest_line = 0
  for entry in manifest_files:
    if (entry.moduledir) and (entry.remotepath.len > length_longest_line):
      length_longest_line = entry.remotepath.len
  var table = initOrderedTable[string,seq[FileEntry]]()
  for module_type in MODULE_TYPES:
    table[module_type] = @[]
  for entry in manifest_files:
    if entry.moduledir:
      table[entry.remotepath.split('/')[1]].add entry
  var n = 1
  echo "Using the 'download' or 'dl' command"
  echo "Specify either the index or full name to download a module"
  echo ""
  echo "index ","module name".align_left(length_longest_line)," status"
  echo "===== ",'='.repeat(length_longest_line)," ==========="
  for module_type,entries in table:
    echo module_type,"s"
    for entry in entries:
      if entry.remotepath.starts_with 's': # stable
        stdout.styled_write(fgGreen, align($n,5) & " " & entry.remotepath)
      else:
        stdout.styled_write(fgYellow, align($n,5) & " " & entry.remotepath)
      if entry in local_files:
        stdout.write "[installed]".align(length_longest_line+12-entry.remotepath.len)
      stdout.write "\n"
      inc n
    echo ""
  echo &"Example: mbuild dl {table[\"Brain\"][0].remotepath}"
  echo "  or"
  echo &"Example: mbuild dl {table[\"Archivist\"].len+1}"

proc get_module_path(index:int,manifest_files:auto):string =
  # construct table of grouped entries by module_type
  var table = initOrderedTable[string,seq[FileEntry]]()
  for module_type in MODULE_TYPES:
    table[module_type] = @[]
  for entry in manifest_files:
    if entry.moduledir:
      table[entry.remotepath.split('/')[1]].add entry
  # browse grouped table, looking for index'th element we come across
  var n = 1
  for module_type,entries in table:
    for entry in entries:
      if entry.moduledir:
        if n == index:
          return entry.remotepath
        inc n

proc has_cmake_file_in_manifest(entry:FileEntry,manifest_files:auto):bool =
  var query:FileEntry
  query.localpath = entry.localpath&"/CMakeLists.txt"
  result = query in manifest_files

proc download_and_install(remote_module_path:string,manifest_files:auto) =
  var downloaded_all_okay = true
  var local_module_path:string
  for entry in manifest_files:
    if entry.remotepath.starts_with remote_module_path:
      let local_file_path = "code" / entry.localpath
      # store local module path once
      # and check for CMakeFiles existence
      if entry.remotepath == remote_module_path:
        local_module_path = local_file_path
        if (not force_enabled) and (not entry.has_cmake_file_in_manifest manifest_files):
          write_error("Incompatible: ",&"'{remote_module_path}' has no CMake file, so will need the code updated. Use -f to install anyway.")
          quit(1)
      if (not force_enabled) and (local_file_path.file_exists):
        write_warning("Skipping file: ",&"file exists; use -f to overwrite '{local_file_path}'")
        continue
      # make dir if dir, or download file if file
      if entry.kind == pcDir:
        create_dir local_file_path
      else: # entry.kind == pcFile
        stdout.write(&"downloading '{entry.remotepath}'  ")
        try:
          download_file(repo_path&entry.remotepath, local_file_path)
          stdout.styled_write(fgGreen,"Success\n",fgDefault)
        except:
          stdout.styled_write(fgRed,"Failed\n",fgDefault)
          downloaded_all_okay = false
  if downloaded_all_okay:
    write_success("Installed: ",&"{local_module_path}")
  else:
    write_error("Install Failed: ",&"{remote_module_path} could not be installed")
    quit(1)

proc list_or_install_extra_modules() =
  var manifest_files = directory_structure_from_manifest()
  var local_files = directory_structure_from_local()
  if download_args.len == 0 or download_args[0] == "help":
    list_extra_modules(manifest_files,local_files)
    quit(0)
  else: # download_args[0] == path or index
    var
      index:int
      gave_index = false
      remote_module_path:string
    # see if user passed an index instead of a module string
    try:
      index = download_args[0].parse_int
      gave_index = true
    except:
      discard
    # find the module path based on index or direct string
    remote_module_path = ""
    if gave_index:
      remote_module_path = index.get_module_path manifest_files
    else:
      # verify correct path
      for entry in manifest_files:
        if entry.moduledir and (entry.remotepath == download_args[0]):
          remote_module_path = download_args[0]
    if remote_module_path.len == 0:
      write_error("Error: ",&"not a valid mabe_extras module name or index '{download_args[0]}'")
      quit(1)
    # download and install files to correct locations
    remote_module_path.download_and_install(manifest_files)

const exe_name = "mbuild"
const help_text = """ 

  mbuild [command] [options]

  Automates project-level tasks for the MABE repository, including:
  * Building the codebase according to modules.txt and compiler options
  * Creating new modules from templates
  * Downloading extra modules from the MABE_extras repository
  Default behavior with no arguments will build Release with the default compiler
  Note: this tool is only an automation of cmake etc., so is not required to build MABE
        if you are familiar with the standard cmake build process, though it is easier
        with ccmake (or cmake-gui) to see all the variables you must set.
  
  commands:
    <no command>  = Build MABE (default is Release mode)
    init,refresh  = Re-initialize modules.txt from all modules in code/
    new           = Create a new module; Leave blank for help
    generate, gen = Specify a project file to generate; Leave blank for help
    copy, cp      = Create a new module as a copy of an existing one; Leave blank for help
    download, dl  = Download extra modules from the MABE_extras repository; Leave blank for help

  options:
    --force, -f   = Force any associated command (clean rebuild, overwrite files, etc.)
    --cxx, -c     = Specify an alternative c++ compiler ex: g++ clang++ pgc++ etc. (must be on path)
    --quick, -q   = Don't regenerate files when building, only recompiling minimally changed files. Dangerous!
    --debug, -d   = Configure and build in debug mode (default Release)
    --help, -h    = Show this help
    
"""
#TODO add vs to above help

proc main() =

  # parse the command line options
  var p = initOptParser(command_line_params())
  while true:
    p.next()
    case p.kind:
      of cmdEnd: break
      of cmdShortOption, cmdLongOption:
        p.capture_command force
        p.capture_command quick
        p.capture_command debug
        p.capture_command cxx
        p.capture_command help
        write_error("Error: ",&"Unknown command or option '{p.key}'")
        quit(1)
      of cmdArgument:
        p.capture_command new
        p.capture_command copy
        p.capture_command download
        p.capture_command generate
        p.capture_command init
        when defined(windows):
          p.capture_command vs
        write_error("Error: ",&"Unknown command or option '{p.key}'")
        quit(1)

  if help_enabled:
    echo help_text
    quit(0)
  
  error_if_no_code_cmake_cmakelists_modules_or_build()

  # refresh modules.txt from code/ and -- if exists -- also from modules.txt
  if init_enabled:
    discard refresh_and_get_modules()
    quit(0)

  # make new module from template
  if new_enabled:
    list_or_make_templates()
    discard refresh_and_get_modules(new_module_type=new_args[0], new_module_name=new_args[1])
    quit(0)

  # download modules from MABE_extras repo
  if download_enabled:
    list_or_install_extra_modules()
    discard refresh_and_get_modules()
    quit(0)

  # make new module as copy from another
  if copy_enabled:
    list_or_make_copy()
    discard refresh_and_get_modules(new_module_type=copy_args[0], new_module_name=copy_args[1])
    quit(0)

  # if we get here, then we know we should generate
  # a project file using cmake, maybe the default one
  generate_and_build()
  quit(0)

when is_main_module:
  main()
