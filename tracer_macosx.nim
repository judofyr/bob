var environ {.importc.}: cstringArray

proc prepare(t: var Tracer, data: ptr TraceData, comm: FileHandle) =
  data.cmd = t.program
  data.argv = allocCStringArray(@[t.program] & t.args)

  var preloadPath = "libbobpreload.dylib"
  if not t.libpath.isNil:
    preloadPath = t.libpath / preloadPath

  let fullEnv = t.envs & @[
    "BOB_FD=" & $comm.int,
    "BOB_TWD=" & t.twd,
    "DYLD_FORCE_FLAT_NAMESPACE=1",
    "DYLD_INSERT_LIBRARIES=" & preloadPath,
  ]

  data.env = allocCStringArray(fullEnv)

proc trace(data: ptr TraceData) =
  environ = data.env
  if execvp(data.cmd.cstring, data.argv) == -1:
    let err = osLastError()
    echo osErrorMsg(err)
    exitnow(1)

