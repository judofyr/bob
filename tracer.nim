import posix, os, streams
import sets, sequtils

type
  Tracer* = object
    pwd*: string
    cmd*: string
    argv*: seq[string]
    env*: seq[string]
    libpath*: string

  TraceResult* = object
    inputs*: seq[string]
    outputs*: seq[string]
    status*: cint

  TraceData = object
    cmd: string
    argv: cstringArray
    env: cstringArray

  Action = enum
    Ping, Input, Output, Rename

# This is called in the main process. Used to set up the data.
proc prepare(t: var Tracer, data: ptr TraceData, comm: FileHandle)

# This is called in the child process.
proc trace(data: ptr TraceData)

proc readStr(s: Stream): string =
  let len = s.readInt32
  return s.readStr(len)

proc processResults(fd: FileHandle, res: var TraceResult) =
  newSeq(res.inputs, 0)
  newSeq(res.outputs, 0)

  var file: File
  discard file.open(fd)
  var stream = newFileStream(file)

  try:
    while true:
      let cmd = stream.readInt8.Action

      case cmd
      of Ping:
        discard
      of Input:
        let str = stream.readStr
        res.inputs.add(str)
      of Output:
        let str = stream.readStr
        res.outputs.add(str)
      of Rename:
        let oldpath = stream.readStr
        let newpath = stream.readStr

        res.outputs.mapIt(
          if it == oldpath:
            newpath
          else:
            oldpath
        )
  except:
    return

proc start*(t: var Tracer): TraceResult =
  var comm: array[2, FileHandle]
  discard pipe(comm)

  var data: TraceData
  t.prepare(addr(data), comm[1])

  let pid = fork()

  if pid == 0:
    GC_disable()
    # close the reader in the child process
    discard comm[0].close
    # and trace it!
    trace(addr(data))
    exitnow(1)

  # close the writer in the main process
  discard comm[1].close

  processResults(comm[0], result)

  discard waitpid(pid, result.status, 0)

when defined(linux):
  include ./tracer_linux
elif defined(macosx):
  include ./tracer_macosx
else:
  {.error:"platform not supported (only linux and macosx for now)".}

when isMainModule:
  var t: Tracer
  t.cmd = "bash"
  t.argv = @["-c", "env"]
  t.env = @["PATH=" & getEnv("PATH")]
  t.env = @[]
  discard t.start

