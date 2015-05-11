when appType != "lib":
  {.error:"bobpreload: must be compiled with --app:lib".}

const PATH_MAX = 1024
type FileHandle = cint

type
  IOVec = object
    buf: pointer
    len: int

proc write(fd: FileHandle, data: pointer, len: int): int {.importc.}
proc writev(fd: FileHandle, vecs: ptr IOVec, vecLen: cint): cint {.importc,header:"<sys/uio.h>".}
proc getcwd(buf: cstring, size: int): cint {.importc,header:"<sys/uio.h>".}

proc dlsym(handler: pointer, symbol: cstring): pointer {.importc,header:"<dlfcn.h>".}
var RTLD_NEXT {.importc,header:"<dlfcn.h>"}: pointer

type
  Action = enum
    Ping, Input, Output, Rename

proc tell(action: Action, data: varargs[cstring]): bool

type PathBuf = array[PATH_MAX, char]

var environ {.importc.}: cstringArray
var bobFd {.threadvar.}: FileHandle
var bobPwd {.threadvar.}: PathBuf
var bobPwdLen {.threadvar.}: int
var inResolve {.threadvar.}: bool

const fdKey = "BOB_FD="
const pwdKey = "BOB_PWD="

proc initBob() =
  if bobFd.cint == 0:
    var num: cint

    for i in 0 .. high(int):
      let str = environ[i]
      if str.isNil:
        break

      if equalMem(str, fdKey.cstring, fdKey.len):
        for j in fdKey.len .. high(int):
          if str[j] == '\0': break
          let digit = str[j].int8 - '0'.int8
          if digit notin (0..9):
            num = 0
            break
          num = num*10 + digit

      if equalMem(str, pwdKey.cstring, pwdKey.len):
        for j in 0 .. high(int):
          bobPwd[j] = str[j + pwdKey.len]
          if bobPwd[j] == '\0':
            bobPwd[j] = '/'
            bobPwd[j+1] = '\0'
            bobPwdLen = j+1
            break

    bobFd = FileHandle(num)

    if num == 0 or not tell(Ping):
      echo "bob: could not find master"
      quit(1)

proc tell(action: Action, data: varargs[cstring]): bool =
  var cmd: int8 = action.int8
  var lens: array[10, int32]
  var vecs: array[10, IOVec]
  var vecLen = 0

  vecs[vecLen] = IOVec(buf: addr(cmd), len: sizeof(cmd))
  vecLen.inc

  for idx, d in data:
    let len = d.len.int32
    lens[idx] = len
    vecs[vecLen] = IOVec(buf: addr(lens[idx]), len: sizeof(int32))
    vecLen.inc
    vecs[vecLen] = IOVec(buf: d, len: len)
    vecLen.inc

  if bobFd.writev(cast[ptr IOVec](addr(vecs)), vecLen.cint) == -1:
    return false

  return true

template initNext(varName: stmt, name: string) =
  if varName.isNil:
    varName = cast[type(varName)](dlsym(RTLD_NEXT, name))

# We need to handle varargs
type va_list {.importc,header:"<stdarg.h>".} = object

# We need a custom type of const char*
type constcstring {.importc:"const char*".} = object
template tocstring(s: constcstring): cstring = cast[cstring](s)

proc resolve(path: cstring, buf: var PathBuf): cstring =
  if inResolve: return nil

  const SepChar = {'/', '\0'}

  inResolve = true

  # Find the current directory
  discard getcwd(buf, buf.len)

  # Start at the last byte
  let pathLen = path.len
  var pos = buf.cstring.len

  var i = 0

  if path[0] == '/':
    # absolute path
    pos = 0

  while i < pathLen:
    if path[i] == '\0':
      break

    # ignore any extra slashes
    if path[i] == '/':
      i += 1
      continue

    # ignore single dots
    if path[i] == '.' and path[i+1] in SepChar:
      i += 2
      continue

    # handle parent dir
    if path[i] == '.' and path[i+1] == '.' and path[i+2] in SepChar:
      # walk one directory up
      while pos > 0:
        pos -= 1
        if buf[pos] in SepChar:
          break

      i += 3
      continue

    # add a slash
    buf[pos] = '/'
    pos += 1

    # then copy over everything until the next component:
    while i < pathLen and path[i] notin SepChar:
      buf[pos] = path[i]
      pos += 1
      i += 1

  # make it 0-terminated
  buf[pos] = '\0'

  if equalMem(buf.cstring, bobPwd.cstring, bobPwdLen):
    result = cast[cstring](
      cast[int](buf) + bobPwdLen
    )

  inResolve = false

# Aaand let's start:
type
  mode_t {.importc,header:"<sys/types.h>".} = object
  FILE {.importc,header:"<stdio.h>".} = object

var
  O_CREAT {.importc,header:"<fcntl.h>".}: cint 

var openNext: proc(name: cstring, oflag: cint): cint {.cdecl,varargs.}
proc open(name: constcstring, oflag: cint): cint {.exportc,varargs.} =
  initBob()
  openNext.initNext("open")

  var name = name.tocstring
  var action = Input

  if (oflag and O_CREAT) != 0:
    var vl: va_list
    var mode: mode_t

    {.emit:"""
      va_start(`vl`, `oflag`);
      `mode` = va_arg(`vl`, mode_t);
      va_end(`vl`);
    """.}

    action = Output
    result = openNext(name, oflag, mode)
  else:
    result = openNext(name, oflag)

  var buf: PathBuf
  let resolved = resolve(name, buf)
  if not resolved.isNil:
    discard tell(action, resolved)

var open_nocancelNext: proc(name: cstring, oflag: cint, mode: mode_t): cint {.cdecl,varargs.}
proc open_nocancel(name: cstring, oflag: cint, mode: mode_t): cint {.exportc:"open$$NOCANCEL",varargs.} =
  initBob()
  open_nocancelNext.initNext("open$NOCANCEL")

  var action = Input
  if (oflag and O_CREAT) != 0:
    action = Output

  result = open_nocancelNext(name, oflag, mode)

  var buf: PathBuf
  let resolved = resolve(name, buf)
  if not resolved.isNil:
    discard tell(action, resolved)

var creatNext: proc(name: cstring, mode: mode_t): cint {.cdecl.}
proc creat(name: constcstring, mode: mode_t): cint {.exportc.} =
  initBob()
  creatNext.initNext("creat")

  var name = name.tocstring

  result = creatNext(name, mode)

var renameNext: proc(oldpath, newpath: cstring): cint {.cdecl.}
proc rename(oldpath, newpath: constcstring): cint {.exportc.} =
  initBob()
  renameNext.initNext("rename")

  var
    oldpath = oldpath.tocstring
    newpath = newpath.tocstring

  result = renameNext(oldpath, newpath)

  var oldbuf, newbuf: PathBuf

  let oldres = resolve(oldpath, oldbuf)
  let newres = resolve(newpath, newbuf)

  if not oldres.isNil and not newres.isNil:
    discard tell(Rename, oldres, newres)

var mkdirNext: proc(path: cstring, mode: mode_t): cint {.cdecl.}
proc mkdir(path: constcstring, mode: mode_t): cint {.exportc.} =
  initBob()
  mkdirNext.initNext("mkdir")

  var path = path.tocstring

  result = mkdirNext(path, mode)

  var buf: PathBuf
  let resolved = resolve(path, buf)
  if not resolved.isNil:
    discard tell(Output, resolved)

