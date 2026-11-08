#!/usr/bin/env bats

# Tests for the real-time queue: dispatch_utterances (bounded workers),
# wait_for_queue_space (bounded queue), and the drain at exit.

load test_helper

setup() {
  cd "$BATS_TEST_TMPDIR"
  load_whisper_stream

  WORK_DIR="$BATS_TEST_TMPDIR/work"
  QUEUE_DIR="$WORK_DIR/queue"
  ACTIVE_DIR="$WORK_DIR/active"
  mkdir -p "$QUEUE_DIR" "$ACTIVE_DIR"
  STDOUT_MODE=true
  EVENTS="$BATS_TEST_TMPDIR/events.log"
  : > "$EVENTS"

  # Stand-in worker: logs start/end with the seq, holds its slot briefly,
  # and removes its file like the real one.
  convert_audio_to_text() {
    echo "start $2" >> "$EVENTS"
    sleep 0.3
    echo "end $2" >> "$EVENTS"
    rm -f "$1"
  }
}

queue_utterances() {
  local n
  for n in "$@"; do
    printf 'audio' > "$QUEUE_DIR/$(printf 'output_%06d.mp3' "$n")"
  done
}

# Highest number of workers that were running at the same time.
max_concurrency() {
  awk '$1 == "start" { n++; if (n > m) m = n } $1 == "end" { n-- } END { print m + 0 }' "$EVENTS"
}

run_dispatcher_to_completion() {
  : > "$WORK_DIR/stop"
  dispatch_utterances "$1"
}

@test "dispatcher never runs more workers than its limit" {
  queue_utterances 1 2 3 4 5 6
  run_dispatcher_to_completion 2
  [ "$(grep -c '^end' "$EVENTS")" -eq 6 ]
  [ "$(max_concurrency)" -eq 2 ]
}

@test "dispatcher with a limit of one runs workers one at a time, in capture order" {
  queue_utterances 3 1 2
  run_dispatcher_to_completion 1
  [ "$(max_concurrency)" -eq 1 ]
  [ "$(grep '^start' "$EVENTS" | tr '\n' ' ')" = "start 1 start 2 start 3 " ]
}

@test "dispatcher passes the capture sequence number parsed from the file name" {
  queue_utterances 12
  run_dispatcher_to_completion 1
  grep -qx 'start 12' "$EVENTS"
}

@test "a failed worker frees its slot" {
  convert_audio_to_text() {
    echo "start $2" >> "$EVENTS"
    echo "end $2" >> "$EVENTS"
    rm -f "$1"
    return 1
  }
  queue_utterances 1 2 3
  run_dispatcher_to_completion 1
  [ "$(grep -c '^end' "$EVENTS")" -eq 3 ]
}

@test "dispatcher keeps running until asked to stop, then drains the queue" {
  dispatch_utterances 1 &
  local pid=$!
  queue_utterances 1
  sleep 1
  kill -0 "$pid"
  queue_utterances 2 3
  : > "$WORK_DIR/stop"
  wait "$pid"
  [ "$(grep -c '^end' "$EVENTS")" -eq 3 ]
  [ "$(count_utterances "$QUEUE_DIR")" -eq 0 ]
}

@test "wait_for_queue_space returns at once while the queue has room" {
  MAX_QUEUE=3
  DISPATCHER_PID=$$
  queue_utterances 1 2
  run wait_for_queue_space
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "wait_for_queue_space pauses recording while the queue is full" {
  MAX_QUEUE=2
  sleep 30 &
  DISPATCHER_PID=$!
  queue_utterances 1 2
  ( sleep 0.7; rm -f "$QUEUE_DIR/output_000001.mp3" ) &
  run wait_for_queue_space
  kill "$DISPATCHER_PID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"recording paused"* ]]
  [[ "$output" == *"Recording resumed"* ]]
}

@test "wait_for_queue_space fails when the dispatcher is gone" {
  MAX_QUEUE=1
  sleep 0 &
  DISPATCHER_PID=$!
  wait "$DISPATCHER_PID"
  queue_utterances 1
  run wait_for_queue_space
  [ "$status" -ne 0 ]
}

@test "count_utterances counts only queued audio files" {
  [ "$(count_utterances "$QUEUE_DIR")" -eq 0 ]
  queue_utterances 1 2
  touch "$QUEUE_DIR/other.txt"
  [ "$(count_utterances "$QUEUE_DIR")" -eq 2 ]
}

@test "kill_process_tree stops a process and its descendants" {
  bash -c 'sleep 30 & sleep 30 & wait' &
  local parent=$!
  sleep 0.3
  local -a children
  children=($(pgrep -P "$parent"))
  [ ${#children[@]} -eq 2 ]
  kill_process_tree "$parent"
  wait "$parent" 2>/dev/null || true
  sleep 0.2
  ! kill -0 "$parent" 2>/dev/null || false
  ! kill -0 "${children[0]}" 2>/dev/null || false
  ! kill -0 "${children[1]}" 2>/dev/null || false
}

@test "the local backend dispatches to a single worker" {
  run awk '/^if \[ "\$BACKEND" = "local" \]; then$/ { getline; print; exit }' "$SCRIPT_PATH"
  [ "$output" = "  dispatch_utterances 1 &" ]
}

# --- the whole loop -------------------------------------------------------------

install_loop_stubs() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  export REC_COUNT="$BATS_TEST_TMPDIR/rec_count"
  echo 0 > "$REC_COUNT"
  # Three utterances, then rec fails three times and the session ends.
  cat > "$BATS_TEST_TMPDIR/bin/rec" <<'STUB'
#!/usr/bin/env bash
n=$(( $(cat "$REC_COUNT") + 1 )); echo "$n" > "$REC_COUNT"
[ "$n" -le 3 ] || exit 1
printf 'FAKEPCM'
STUB
  cat > "$BATS_TEST_TMPDIR/bin/sox" <<'STUB'
#!/usr/bin/env bash
cat > "${@: -1}"
STUB
  # Each request holds a slot long enough to overlap with the next ones.
  export CURL_EVENTS="$EVENTS"
  cat > "$BATS_TEST_TMPDIR/bin/curl" <<'STUB'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in file=@*) f=$(basename "${a#file=@}") ;; esac
done
echo "start $f" >> "$CURL_EVENTS"
sleep 0.5
echo "end $f" >> "$CURL_EVENTS"
printf '{"text":"%s"}\n200' "$f"
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/rec" "$BATS_TEST_TMPDIR/bin/sox" "$BATS_TEST_TMPDIR/bin/curl"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test "--max-jobs 1 sends one request at a time and still transcribes every utterance" {
  install_loop_stubs
  run env OPENAI_API_KEY=sk-test "$SCRIPT_PATH" --stdout --max-jobs 1
  [ "$(max_concurrency)" -eq 1 ]
  [[ "$output" == *"output_000001.mp3"* ]]
  [[ "$output" == *"output_000002.mp3"* ]]
  [[ "$output" == *"output_000003.mp3"* ]]
}

@test "requests overlap up to the default limit" {
  install_loop_stubs
  run env OPENAI_API_KEY=sk-test "$SCRIPT_PATH" --stdout
  [ "$(grep -c '^end' "$EVENTS")" -eq 3 ]
  [ "$(max_concurrency)" -ge 2 ]
}

@test "--max-jobs rejects values that are not positive integers" {
  run env OPENAI_API_KEY=sk-test "$SCRIPT_PATH" --max-jobs 0
  [ "$status" -ne 0 ]
  [[ "$output" == *"positive integer"* ]]
  run env OPENAI_API_KEY=sk-test "$SCRIPT_PATH" --api-timeout 1.5
  [ "$status" -ne 0 ]
  [[ "$output" == *"positive integer"* ]]
}

@test "an utterance queued just before the stop request is still transcribed" {
  # Queue the last utterance and publish stop right after the dispatcher has
  # found the queue empty, the narrowest window between its checks.
  count_utterances() {
    local -a f=("$1"/output_*.mp3)
    local n=0
    [ -e "${f[0]}" ] && n=${#f[@]}
    if [ "$n" = 0 ] && [ ! -e "$WORK_DIR/stop" ]; then
      printf 'audio' > "$QUEUE_DIR/output_000001.mp3"
      : > "$WORK_DIR/stop"
    fi
    echo "$n"
  }
  # Should the dispatcher not count the queue before seeing stop, publish
  # both at its first idle tick instead, so the test always ends.
  sleep() {
    if [ ! -e "$WORK_DIR/stop" ]; then
      printf 'audio' > "$QUEUE_DIR/output_000001.mp3"
      : > "$WORK_DIR/stop"
    fi
    command sleep "$@"
  }
  dispatch_utterances 1
  grep -qx 'end 1' "$EVENTS"
  [ ! -e "$QUEUE_DIR/output_000001.mp3" ]
}

@test "a queued file that cannot be moved is skipped, not retried forever" {
  queue_utterances 1
  mv() { return 1; }
  run_dispatcher_to_completion 1
  unset -f mv
  [ ! -s "$EVENTS" ]
  [ "$(count_utterances "$QUEUE_DIR")" -eq 0 ]
}

@test "wait_for_queue_space fails at once when the dispatcher is gone, even with room" {
  MAX_QUEUE=100
  sleep 0 &
  DISPATCHER_PID=$!
  wait "$DISPATCHER_PID"
  run wait_for_queue_space
  [ "$status" -ne 0 ]
}

@test "kill_process_tree reaches grandchildren and processes that ignore SIGTERM" {
  bash -c 'bash -c "trap \"\" TERM; sleep 30 & wait" & sleep 30 & wait' &
  local root=$!
  sleep 0.5
  local -a tree=("$root") more
  local i=0
  while [ $i -lt ${#tree[@]} ]; do
    more=($(pgrep -P "${tree[$i]}" || true))
    tree+=("${more[@]}")
    i=$((i + 1))
  done
  [ ${#tree[@]} -ge 4 ]
  kill_process_tree "$root"
  wait "$root" 2>/dev/null || true
  local pid
  for pid in "${tree[@]}"; do
    ! kill -0 "$pid" 2>/dev/null || false
  done
}

# --- handle_exit in real-time mode ----------------------------------------------
#
# handle_exit ends the process, so each scenario runs in its own bash.

run_exit_scenario() {
  cat > "$BATS_TEST_TMPDIR/scenario.sh" <<SCENARIO
WHISPER_STREAM_LIB=1 source "$SCRIPT_PATH"
WORK_DIR="$WORK_DIR"
QUEUE_DIR="$QUEUE_DIR"
ACTIVE_DIR="$ACTIVE_DIR"
STDOUT_MODE=true
convert_audio_to_text() { echo "transcribed \$2" >> "$EVENTS"; rm -f "\$1"; }
soxi() { [ "\$(cat "\$2")" = audio ] && echo 1.0; }
$1
handle_exit
SCENARIO
  run bash "$BATS_TEST_TMPDIR/scenario.sh"
}

@test "handle_exit transcribes the queue and the utterance being recorded" {
  run_exit_scenario '
dispatch_utterances 1 &
DISPATCHER_PID=$!
printf audio > "$QUEUE_DIR/output_000001.mp3"
OUTPUT_FILE="$WORK_DIR/output_000002.mp3"
printf audio > "$OUTPUT_FILE"'
  [ "$status" -eq 0 ]
  grep -qx 'transcribed 1' "$EVENTS"
  grep -qx 'transcribed 2' "$EVENTS"
  [ ! -d "$WORK_DIR" ]
}

@test "handle_exit drops the utterance being recorded when it holds no audio yet" {
  run_exit_scenario '
dispatch_utterances 1 &
DISPATCHER_PID=$!
printf audio > "$QUEUE_DIR/output_000001.mp3"
OUTPUT_FILE="$WORK_DIR/output_000002.mp3"
printf header > "$OUTPUT_FILE"'
  [ "$status" -eq 0 ]
  grep -qx 'transcribed 1' "$EVENTS"
  ! grep -qx 'transcribed 2' "$EVENTS" || false
  [ ! -d "$WORK_DIR" ]
}

@test "handle_exit fails the session when the dispatcher died with utterances queued" {
  run_exit_scenario '
sleep 0 &
DISPATCHER_PID=$!
wait "$DISPATCHER_PID"
printf audio > "$QUEUE_DIR/output_000001.mp3"'
  [ "$status" -eq 1 ]
  [[ "$output" == *"1 recorded utterance(s) were not transcribed"* ]]
}

@test "handle_exit fails the session when the utterance being recorded cannot be queued" {
  run_exit_scenario '
dispatch_utterances 1 &
DISPATCHER_PID=$!
OUTPUT_FILE="$WORK_DIR/output_000001.mp3"
printf audio > "$OUTPUT_FILE"
mv() { [ "$1" = "$OUTPUT_FILE" ] && return 1; command mv "$@"; }'
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not queue the utterance being recorded"* ]]
}

@test "handle_exit fails the session when the dispatcher failed with an empty queue" {
  run_exit_scenario '
(exit 9) &
DISPATCHER_PID=$!'
  [ "$status" -eq 1 ]
  [[ "$output" == *"transcription worker failed (exit status 9)"* ]]
}
