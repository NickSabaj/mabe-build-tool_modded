# mabe-build-tool
Convenience utility for building MABE

[![Build status](https://ci.appveyor.com/api/projects/status/kohmpvlejn4uorbm?svg=true)](https://ci.appveyor.com/project/JorySchossau/mabe-build-tool)

### Downloads
If you don't want to use the version of this tool that ships with MABE, then download here or clone this repo to build it yourself, then put it in the root directory of MABE, and for consistency rename it to `mbuild`.
* [Linux](https://github.com/JorySchossau/mabe-build-tool/releases/latest/download/lin_build)
* [Mac](https://github.com/JorySchossau/mabe-build-tool/releases/latest/download/osx_build)
* [Windows](https://github.com/JorySchossau/mabe-build-tool/releases/latest/download/win_build.exe)

[Older Releases](https://github.com/JorySchossau/mabe-build-tool/releases)

### Features
* Build MABE with zero configuration effort
* Create module wizard
* Copy module wizard
* Download module wizard (MABE_extras repo)
* Generate IDE project files
* Use arbitrary c++ compilers
* Change to debug build mode

### Documentation
```

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
    init          = Re-initialize modules.txt from all modules in src/
    new           = Create a new module; Leave blank for help
    generate, gen = Specify a project file to generate; Leave blank for help
    copy, cp      = Create a new module as a copy of an existing one; Leave blank for help
    download, dl  = Download extra modules from the MABE_extras repository; Leave blank for help

  options:
    --force, -f   = Force the associated command (clean rebuild, overwrite files, etc.)
    --cxx, -c     = Specify an alternative c++ compiler ex: g++ clang++ pgc++ etc.
    --debug, -g   = Configure and build in debug mode (default Release)
    --help, -h    = Show this help
```

### Build from source
* Requires the excellent [Nim](https://nim-lang.org) compiler.
* Which requires a C compiler.
* Until I make a build package for this, use the below to build yourself:

```sh
# osx or linux
nim c build

# windows (visual studio)
nim c --cc:vcc build
```

For my release builds I go to the extra effort of ensuring cross-version compatibility and small binary size. For linux I use the musl-libc compiler. For mac I target the older 10.13 SDK. For both of those I strip symbols and further compress using the amazing [Ultimate Packer for Executables](https://upx.github.io/).

### To Do
* [ ] Refactor the httpclient_tlse custom nim code that gives SSL/TLS support into a proper stand-alone nim package
