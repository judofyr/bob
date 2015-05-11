import os, osproc
import tables, sets
import md5, hashes
import times
import sequtils, strutils

import tracer

type
  BServer = object
    # Tracing Working Directory
    twd: string
    pwdstack: seq[string]

proc newBServer(): BServer =
  result.twd = getCurrentDir()

  newSeq(result.pwdstack, 0)
  result.pwdstack.add("")

proc pwd(s: BServer): string =
  s.twd / s.pwdstack[^1]


proc handleCommand(s: var BServer, cmd: seq[string]): int =
  let program = cmd[0]
  let args = cmd[1 .. ^1]

  case program
  of "--pushd":
    let newpwd = s.pwdstack[^1] / args[0]
    s.pwdstack.add(newpwd)
    return 0

  of "--popd":
    if s.pwdstack.len == 1:
      return 1

    discard s.pwdstack.pop
    return 0

  of "--depend":
    # TODO: store this somewhere
    return 0

  echo program, " ", args.join(" ")

  var tracer: Tracer
  tracer.twd = s.twd
  tracer.pwd = s.pwd
  tracer.cmd = program
  tracer.argv = args
  tracer.env = @["PATH=" & getEnv("PATH")]
  tracer.libpath = getAppDir()

  let res = tracer.start
  echo "inputs: ", res.inputs
  echo "outputs: ", res.outputs
  echo "status: ", res.status.int
  echo ""
  return res.status.int

## Main module
let argv = commandLineParams()
let cmd = if argv.len == 0: "--help" else: argv[0]

case cmd
of "--start":
  echo """
echo "bob: start"

set -o errexit -o nounset -o pipefail

bob_cleanup() {
  local res=$?
  if [ $res -eq 0 ]; then
    echo bob: done
  else
    echo bob: error $res
  fi

  if [ -n "${BOB_SERVER-}" ]; then
    kill $BOB_SERVER
    wait $BOB_SERVER 2>/dev/null
  fi

  if [ -n "${BOB_TMP-}" ]; then
    rm -rf "$BOB_TMP".{in,out}
  fi

  exit
}

trap bob_cleanup EXIT

BOB_TMP="$(mktemp -u -t bob)"
# Turn it into a FIFO
mkfifo "$BOB_TMP.in"
mkfifo "$BOB_TMP.out"

BOB_DIR=$(dirname "${BASH_SOURCE[0]}")
cd "$BOB_DIR"

# Start the Bach server in the background.
"$BOB_BIN" --server "$BOB_TMP" &
BOB_SERVER=$!

# Override the bob command to pass commands to the server
bob() {
  # send command in a single packet
  (
    for var in "$@"; do
      printf "%s\\xFF" "$var"
    done
  ) >"$BOB_TMP.in"

  # wait for confirmation
  read BOB_RES <"$BOB_TMP.out"
  return $BOB_RES
}

# Move into jail
mkdir "$BOB_TMP.jail"
cd "$BOB_TMP.jail"
rmdir "$BOB_TMP.jail"

# Now unset env
for var in $(env | cut -f 1 -d =); do
  if [ "$var" != "PATH" ]; then
    declare "env$var"="${!var}"
    unset $var
  fi
done

readenv() {
  local name="$1"
  local var="env$name"
  shift

  # declare it locally (and handle spaces properly):
  declare "loc$name"="${!var-"$*"}"
  # and now globally:
  eval $name=\"\$loc$name\"

  bob --depend "$name" "${!name}"
}

""".replace("$BOB_BIN", getAppFilename())

of "--server":
  var inpipe, outpipe: File
  var server = newBServer()

  while true:
    # open pipes
    discard inpipe.open(argv[1] & ".in")
    discard outpipe.open(argv[1] & ".out", fmWrite)

    # read data
    var data = inpipe.readAll().split('\xFF')
    # the last one is empty
    assert(data.pop == "")
    let res = server.handleCommand(data)
    # mark it as complete
    outpipe.write($res & "\n")
    # close pipes
    inpipe.close
    outpipe.close
else:
  discard

