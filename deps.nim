import times, md5
import tables
import streams

type
  BDeps* = object
    files: TableRef[string, BFile]
    commands: seq[BCommand]

  BFile* = ref object
    path: string

  BCommand* = ref object
    program*: string
    args*: seq[string]
    pwd*: string
    envs*: seq[string]

    inputs*: seq[BFile]
    outputs*: seq[BFile]

proc newCommand*: BCommand = new(result)

proc initDeps*(deps: var BDeps) =
  deps.files = newTable[string, BFile]()
  newSeq(deps.commands, 0)

proc file*(deps: var BDeps, path: string): BFile =
  if deps.files.hasKey(path):
    result = deps.files[path]
  else:
    new(result)
    result.path = path
    deps.files[path] = result

proc addCommand*(deps: var BDeps, cmd: BCommand) =
  deps.commands.add(cmd)

## File format

const fileMagic = "BOB!"
const fileVersion = 1.uint8

proc write*(deps: var BDeps, filename: string) =
  let s = newFileStream(filename, fmWrite)
  s.write(fileMagic)
  s.write(fileVersion)

  for path in deps.files.keys:
    let size = path.len.int32
    s.write(size)
    s.write(path)

  let zero = 0.int32
  s.write(zero)

