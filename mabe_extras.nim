import httpclient_tlse
import strutils
import os
import streams

## exported public symbols:
## repo_path:string
##   (contains the static part of the raw github url)
## FileEntry:tuple[remotepath,localpath,url:string,kind:PathComponent,moduledir:bool]
## directory_structure_from_manifest():seq[FileEntry]
##   returns a sequence of file objects
##   from dir structure in code/
## directory_structure_from_local():seq[FileEntry]
##   returns a sequence of file objects
##   from dir structure in remote repository mabe_extras
## `in` operator
##   allows asking if a file object is in a list of file objects
##   based on localpath

type FileEntry* = tuple[remotepath,localpath,url:string,kind:PathComponent,moduledir:bool]

const repo_path* = "https://raw.githubusercontent.com/Hintzelab/MABE_extras/master/"

proc directory_structure_from_manifest*():seq[FileEntry] =
  var
    manifest:StringStream
    line:string
    current_category:string = "none"
    current_branch:string
  try:
    manifest = new_string_stream(get_content repo_path&"manifest.txt")
  except:
    echo "Error: ","couldn't download the manifest from repository. Are you connected to the internet?"
    quit(1)

  const module_types = ["Archivist","Brain","Genome","Optimizer","World"]
  const branch_types = ["experimental","stable"]
  while manifest.read_line line:
    # are we reading entries in a category we've started?
    if line.starts_with current_category:
      # found a directory
      if line.ends_with '/':
        var entry:FileEntry
        entry.remotepath = line
        entry.localpath = line
        entry.localpath.remove_prefix current_branch
        entry.kind = pcDir
        if line.count('/') == 3:
          entry.moduledir = true
          entry.localpath.remove_suffix '/'
          entry.remotepath.remove_suffix '/'
        result.add entry
      # found a file (non-directory)
      else:
        var entry:FileEntry
        entry.remotepath = line
        entry.localpath = line
        entry.localpath.remove_prefix current_branch
        entry.kind = pcFile
        entry.moduledir = false
        result.add entry
    # if the above checks failed and we are not looking
    # at a module belonging to a continued category, then
    # determine if we're looking at a valid category at all
    # and continue read_line loop without modifying variables if not
    # otherwise if we found a new valid category, then set it.
    for branch_type in branch_types:
      for module_type in module_types:
        # if start of module type (world, brain, etc.)
        if line == branch_type&"/"&module_type&"/":
          current_category = line
          current_branch = branch_type&"/"
  for entry in result.mitems:
    entry.localpath = entry.localpath.replace("/",$DirSep)

proc directory_structure_from_local*():seq[FileEntry] =
  ## lists only the directories for modules
  ## so every entry has entry.moduledir = true
  const module_types = ["Archivist","Brain","Genome","Optimizer","World"]
  for module_type in module_types:
    for dirname in walk_dirs("code" / module_type / "*"):
      var entry:FileEntry
      entry.localpath = dirname.replace("code"&DirSep,"")
      entry.moduledir = true
      result.add entry

proc `in`*(query:FileEntry, list:openArray[FileEntry]):bool =
  # return true if a file entry is in a list of file entries
  for entry in list:
    if query.localpath == entry.localpath: return true
  return false

# for testing purposes
when isMainModule:
  var line:string
  var manifest = new_string_stream(get_content repo_path&"manifest.txt")
  while manifest.read_line line:
    echo line
  #var files = directory_structure_from_manifest()
  #echo files.len
