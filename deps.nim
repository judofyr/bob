import times, md5, os
import tables
import streams

type
  BDeps* = object
    files: seq[BFile]
    fileCache: TableRef[string, BFile]
    commands: seq[BCommand]

  BFileId = distinct int32

  BFile* = ref object
    id: BFileId
    path: string
    mtime: Time
    md5: MD5Digest

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
  newSeq(deps.files, 0)
  newSeq(deps.commands, 0)
  deps.fileCache = newTable[string, BFile]()

proc file*(deps: var BDeps, path: string): BFile =
  if deps.fileCache.hasKey(path):
    result = deps.fileCache[path]
  else:
    new(result)
    result.id = BFileId(deps.files.len)
    result.path = path
    deps.fileCache[path] = result
    deps.files.add(result)

template files*(deps: var BDeps, iter: expr): seq[BFile] =
  var result = newSeq[BFile](0)
  for path in iter: result.add(deps.file(path))
  result

proc setInputs*(cmd: BCommand, files: seq[BFile]) =
  doAssert(cmd.inputs.isNil)
  cmd.inputs = files

proc setOutputs*(cmd: BCommand, files: seq[BFile]) =
  doAssert(cmd.outputs.isNil)
  cmd.outputs = files

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
  for file in deps.files:
    file.mtime = file.path.getLastModificationTime
    file.md5 = file.path.md5file

# These sync-procs returns true if the file has *changed*

proc syncMD5(file: BFile): bool =
  let md5 = file.path.md5file
  if file.md5 == md5:
    result = false
  else:
    file.md5 = md5
    result = true

proc syncFull*(file: BFile): bool =
  file.mtime = file.path.getLastModificationTime
  result = file.syncMD5

proc syncQuick*(file: BFile): bool =
  let mtime = file.path.getLastModificationTime
  if file.mtime == mtime:
    result = false
  else:
    file.mtime = mtime
    result = file.syncMD5

## File format

const fileMagic = "BOB!"
const fileVersion = 1.int8

proc write*(deps: var BDeps, filename: string) =
  let s = newFileStream(filename, fmWrite)
  s.write(fileMagic)
  s.write(fileVersion)

  s.write(deps.files.len.int32)

  for file in deps.files:
    # Write length-encoded string
    s.write(file.path.len.int32)
    s.write(file.path)

    s.write(file.mtime)
    s.write(file.md5)

proc readFiles*(deps: var BDeps, filename: string) =
  let s = newFileStream(filename, fmRead)
  if s.isNil: return

  doAssert(s.readStr(4) == fileMagic)
  doAssert(s.readInt8 == fileVersion)

  let fileCount = s.readInt32

  for i in 0 .. <fileCount:
    let path = s.readStr(s.readInt32)
    let file = deps.file(path)

    proc read[T](s: Stream, res: var T) =
      let nread = s.readData(addr(res), sizeof(T))
      doAssert(nread == sizeof(T))

    s.read(file.mtime)
    s.read(file.md5)

