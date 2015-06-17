import times, md5, os
import tables
import streams

type
  BDeps* = object
    files: TableRef[string, BFile]
    commands: seq[BCommand]

  BFile* = ref object
    path: string
    mtime: Time
    md5: MD5Digest
    outputFrom: seq[BCommandId]
    inputTo: seq[BCommandId]

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
    newSeq(result.inputTo, 0)
    newSeq(result.outputFrom, 0)
    deps.files[path] = result

template files*(deps: var BDeps, iter: expr): seq[BFile] =
  var result = newSeq[BFile](0)
  for path in iter: result.add(deps.file(path))
  result

proc setInputs*(cmd: BCommand, files: seq[BFile]) =
  doAssert(cmd.inputs.isNil)
  cmd.inputs = files
  for file in files:
    file.inputTo.add(cmd.id)

proc setOutputs*(cmd: BCommand, files: seq[BFile]) =
  doAssert(cmd.outputs.isNil)
  cmd.outputs = files
  for file in files:
    file.outputFrom.add(cmd.id)

proc commandId*(cmd: BCommand): int32 =
  if not cmd.isNil:
    result = cmd.id.int32

proc md5file*(filename: string): MD5Digest =
  var ctx: MD5Context
  md5init(ctx)

  var file: File

  if not file.open(filename, fmRead):
    doAssert(false)

  var buffer: array[4096, char]
  while true:
    let n = file.readChars(buffer, 0, buffer.len)
    if n == 0: break
    md5update(ctx, buffer.cstring, n)

  md5final(ctx, result)

proc sync*(deps: var BDeps) =
  for file in deps.files.values:
    file.mtime = file.path.getLastModificationTime
    file.md5 = file.path.md5file

## File format

const fileMagic = "BOB!"
const fileVersion = 1.int8

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
    s.write(file.outputFrom.len.int32)
    for cmdId in file.outputFrom:
      s.write(cmdId)

    s.write(file.inputTo.len.int32)
    for cmdId in file.inputTo:
      s.write(cmdId)

proc readFiles*(deps: var BDeps, filename: string) =
  let s = newFileStream(filename, fmRead)
  doAssert(s.readStr(4) == fileMagic)
  doAssert(s.readInt8 == fileVersion)

  let fileCount = s.readInt32

  for i in 0 .. <fileCount:
    let path = s.readStr(s.readInt32)
    let file = deps.file(path)

    for j in 0 .. <s.readInt32:
      file.outputFrom.add(BCommandId(s.readInt32))

    for j in 0 .. <s.readInt32:
      file.inputTo.add(BCommandId(s.readInt32))

