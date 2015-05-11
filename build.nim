import strutils
import os, osproc

const dir = "pkg"
const name = "bob"
const version = "0.1.0"
const pkgname = [name, version, hostOS, hostCPU].join("-")

when defined(release):
  const flags = @["-d:release", "--verbosity:0", "--threads:on"]
  const pkgdir = dir / pkgname
  const srcdir = pkgdir / "src"
else:
  const flags = @["--parallelBuild:1", "--threads:on"]
  const pkgdir = "."

proc nimc(name: string, output: string, args: varargs[string]) =
  let fullargs =
    @["c"] &
    flags &
    @["-o:" & (pkgdir / output)] &
    @args &
    @["--nimcache:nimcache/" & name] &
    @[name]

  echo "[*] NIM ", fullargs.join(" ")
  let p = startProcess(
    command="nim",
    args=fullargs,
    options={poParentStreams, poUsePath}
  )
  let err = p.waitForExit
  if err != 0:
    quit(err)

when defined(release):
  removeDir("nimcache")
  removeDir("nimcache-preload")
  removeDir(pkgdir)
  createDir(pkgdir)

nimc("bob.nim", "bob")

when defined(macosx):
  nimc("bobpreload.nim", "libbobpreload.dylib",
    "--app:lib",
    "--os:standalone",
    "--gc:none",
    "--stackTrace:off",
    "--lineTrace:off",
  )

when defined(release):
  createDir(srcdir)
  # TODO: copy over nimcache + nimbase.h


