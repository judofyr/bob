import times, md5
import tables
import streams

type
  BDeps* = object
    files: TableRef[string, BFile]
    commands: seq[BCommand]

  BFile* = ref object
    path: string
    outputFrom: BCommandId
    inputFor: seq[BCommandId]

  BCommandId = distinct int32

  BCommand* = ref object
    id: BCommandId
    program*: string
    args*: seq[string]
    pwd*: string
    envs*: seq[string]

    inputs*: seq[BFile]
    outputs*: seq[BFile]

proc newCommand*(deps: var BDeps): BCommand =
  new(result)
  result.id = BCommandId(deps.commands.len)
  deps.commands.add(result)

proc initDeps*(deps: var BDeps) =
  deps.files = newTable[string, BFile]()
  newSeq(deps.commands, 0)

proc file*(deps: var BDeps, path: string): BFile =
  if deps.files.hasKey(path):
    result = deps.files[path]
  else:
    new(result)
    result.path = path
    newSeq(result.inputFor, 0)
    deps.files[path] = result

template files*(deps: var BDeps, iter: expr): seq[BFile] =
  var result = newSeq[BFile](0)
  for path in iter: result.add(deps.file(path))
  result

proc setInputs*(cmd: BCommand, files: seq[BFile]) =
  doAssert(cmd.inputs.isNil)
  cmd.inputs = files
  for file in files:
    file.inputFor.add(cmd.id)

proc setOutputs*(cmd: BCommand, files: seq[BFile]) =
  doAssert(cmd.outputs.isNil)
  cmd.outputs = files
  for file in files:
    # TODO: how to handle conflicts?
    file.outputFrom = cmd.id

proc commandId*(cmd: BCommand): int32 =
  if not cmd.isNil:
    result = cmd.id.int32

## File format

const fileMagic = "BOB!"
const fileVersion = 1.uint8

proc write*(deps: var BDeps, filename: string) =
  let s = newFileStream(filename, fmWrite)
  s.write(fileMagic)
  s.write(fileVersion)

  s.write(deps.files.len.int32)

  for file in deps.files.values:
    # Write length-encoded string
    s.write(file.path.len.int32)
    s.write(file.path)

    # Write outputFrom
    s.write(file.outputFrom)

    # Write inputFor
    s.write(file.inputFor.len.int32)
    for cmdId in file.inputFor:
      s.write(cmdId)

