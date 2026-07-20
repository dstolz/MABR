# Acquisition Engine

Reference for `+mabr/+acq/` — the subsystem that actually plays and records. This page is for developers; users do not need it.

## Processes and channels

```
        GUI process                          parpool worker (1 process)
   ┌─────────────────────┐                 ┌──────────────────────────┐
   │  mabr.acq.Engine    │                 │  mabr.acq.worker_loop    │
   │                     │  PollableDataQ  │                          │
   │  send_cmd() ────────┼────────────────►│  poll(cmdQueue,0)        │
   │                     │   Cmd messages  │  every frame             │
   │                     │                 │                          │
   │  on_worker_message()│    DataQueue    │  send(resultQueue,...)   │
   │  ◄──────────────────┼─────────────────┤  handshake/state/error   │
   │      afterEach      │                 │                          │
   │                     │                 │  audioPlayerRecorder     │
   │  RingBuffer (RO) ◄──┼── memmap files ─┼── RingBuffer (RW)        │
   └─────────────────────┘                 └──────────────────────────┘
```

Three files back the ring buffer, all in `.runtime_data/`: `ring_signal.dat`, `ring_timing.dat` (both `single`, `maxInputBufferLength` samples), and `ring_header.dat` (two `uint32`: write head and block sequence).

## Lifecycle

```matlab
eng = mabr.acq.Engine(cfg,testing);   % starts pool, launches worker
eng.waitUntilReady();                 % one-time handshake (bounded)
eng.prep(blockSpec);                  % arm a block
eng.run();                            % start streaming
eng.pause(); eng.resume();
eng.stop();                           % end block early
eng.kill();                           % release device, exit worker
```

`Engine` construction does three things: opens a read-only `RingBuffer` (creating the backing files if absent), ensures a 1-worker pool, and `parfeval`s the worker loop. It also runs `pctRunOnAll` to add the repo root to the worker path before the config argument is deserialized — this defends against a **reused pool that predates the MABR path**, which is otherwise a confusing startup failure.

`waitUntilReady` is the only bounded wait in the system. It polls for the handshake with `pause(0.05)` — necessary, because `afterEach` callbacks only run when MATLAB yields. It fails fast with a clear error if the future has already errored.

## Commands and states

[mabr.acq.Cmd](../+mabr/+acq/Cmd.m) — client to worker:

| Command | Meaning |
|---------|---------|
| `Prep` | Configure for a new block; payload carries the play matrix and parameters |
| `Run` | Begin streaming the prepared block from the start |
| `Pause` | Suspend in place, keeping the device open |
| `Resume` | Continue a paused block — **ignored unless a block is paused**, so it can never re-run a completed one |
| `Stop` | End the current block early, return to Ready |
| `Kill` | Release the device and terminate the worker loop |

[mabr.acq.State](../+mabr/+acq/State.m) — worker to client: `Idle`, `Ready`, `Acquire`, `Paused`, `Completed`, `Error`.

Both are enumerations sent as messages. They are never written into shared memory.

## Events

`Engine` translates worker messages into MATLAB events in `on_worker_message`:

| Event | Fires when | Payload |
|-------|-----------|---------|
| `StateChanged` | Any worker state transition | [StateEventData](../+mabr/+acq/StateEventData.m) with `.State` |
| `BlockCompleted` | State becomes `Completed` (edge-triggered) | — |
| `WorkerError` | Worker reports an error | `.Identifier`, `.Message` |

`BlockCompleted` is edge-triggered against the previous state, so a repeated `Completed` cannot double-fire and advance the schedule twice.

## The Prep payload

`prep()` takes the struct that [BlockQueue.renderSpec](../+mabr/+stim/BlockQueue.m) produces:

| Field | Type | Meaning |
|-------|------|---------|
| `PlayMatrix` | `[N x 2] single` | Column 1 stimulus, column 2 timing pulses |
| `SampleRate` | scalar | Must equal `Config.DACSampleRate` |
| `PlayerChannels` | `[1x2]` | Device output channels (default `[1 2]`) |
| `RecorderChannels` | `[1x2]` | Device input channels (default `[1 2]`) |
| `Device` | char | Optional ASIO device name |
| `ExpectedOnsets` | `[k x 1]` | Nominal onsets, for reference |
| `TestingFrameDelay` | scalar | Loopback pacing, tests only |

`BlockQueue.buildSpec` pads the matrix to a whole number of frames and brackets it with silence for device settling. It **errors** if the block's sample rate differs from `Config.DACSampleRate` rather than resampling — the ring buffer is clocked at the DAC rate and downstream windowing assumes it, so silently mis-windowing is worse than failing.

## The streaming loop

`stream_block` in [worker_loop.m](../+mabr/+acq/worker_loop.m) is the hot path:

```matlab
while i <= N
    [msg,ok] = poll(cmdQueue,0);          % non-blocking, EVERY frame
    if ok, handle Stop/Kill/Pause end
    frame    = X(i:hi,:);
    audioADC = apr(frame);                % full-duplex play+record
    rb.writeFrame(audioADC(:,1),audioADC(:,2));
    i = hi + 1;
end
```

Two properties matter. The **zero-timeout poll every frame** means Pause/Stop/Kill take effect within one frame (~5 ms at 192 kHz with a 1024-sample frame). And **play and record are one call** — `audioPlayerRecorder` is full-duplex, so the recorded frame is inherently aligned with the played frame. That is what makes the timing channel trustworthy.

Underruns and overruns are logged but do not abort the block.

Pause blocks in `wait_while_paused`, which polls with a 50 ms timeout and returns either on `Resume` or with a terminal reason for `Stop`/`Kill`.

## Testing mode

`Engine(cfg,true)` runs everything with no audio device: the outgoing frame is fed back as the recorded frame plus a trace of noise, and no `audioPlayerRecorder` is constructed. Every other code path — queues, ring buffer, state machine, sweep extraction, advance criteria, file writing — is identical. This is what makes the whole engine testable in CI without hardware; see [Testing](Testing.md).

## RingBuffer

[mabr.acq.RingBuffer](../+mabr/+acq/RingBuffer.m) is a **true circular buffer** over three memory-mapped files.

**The addressing rule:** `WriteHead` is the **monotonic count of samples written since the last `reset()`**, not a physical index. Physical position is `WriteHead mod MaxLength`, and writes straddling the end are split. Readers address samples by absolute monotonic index and the buffer maps back to storage. A block longer than one lap is therefore still read in chronological order — only the oldest `MaxLength` samples survive.

```matlab
rb = mabr.acq.RingBuffer(cfg,true);    % worker: writable
rb = mabr.acq.RingBuffer(cfg,false);   % client: read-only

rb.reset();                            % new block: zero head, bump BlockSeq
rb.writeFrame(sig,tim);                % append
y = rb.readSignal(lo,hi);              % monotonic range
[sig,tim] = rb.readBlock();            % whole retained block, chronological
y = rb.readSignalAt(idxMatrix);        % arbitrary indices, shape preserved
```

Performance detail: the writer **caches the header** and performs exactly one header write per frame, never reading it back. Readers always read the header through the map. `assert_writable` guards every mutating call, so a read-only client cannot corrupt the buffer.

`ensure_file` recreates a backing file whose size on disk does not match expectations. A stale file — left by a different `maxInputBufferLength`, or truncated by a crash or full disk — would otherwise be mapped as-is and produce out-of-range writes on the acquisition hot path.

`BlockSeq` increments on every `reset()`. Consumers use it to detect a block boundary and discard stale cursors; that is exactly what `extract_sweeps` does.

## Sweep extraction

Two functions, both in [+metrics](../+mabr/+metrics/):

[find_timing_onsets(timing,shadowSamples,threshold)](../+mabr/+metrics/find_timing_onsets.m) is pure. It detects the **first sample to reach threshold on a rising edge**, which works for both the clean synthesized impulses of loopback mode and the smeared pulses that come back from real hardware. Only the positive part of the signal is used. Onsets closer than `shadowSamples` are merged, keeping the earliest. A vector already above threshold at sample 1 yields an onset there — necessary because a pulse can straddle two incremental slices; the resulting duplicate is removed by the caller's shadow de-duplication.

[extract_sweeps(rb,params,state)](../+mabr/+metrics/extract_sweeps.m) is incremental. Each call detects onsets only in the freshly arrived region, windows only newly completed sweeps, caches them in `state`, and returns the accumulated pre-onset and post-onset matrices rebuilt from that cache — not re-read from the memmap every tick. **The cursor is explicit**, passed in and out by the caller, which is what allows the live view to run at 20 Hz over a long block without re-reading megabytes each time.

```matlab
params = struct('SampleRate',cfg.DACSampleRate,'window',[0 0.01], ...
                'decimation',cfg.decimationFactor,'threshold',0.1,'shadow',0.002);
[pre,post,onsets,state] = mabr.metrics.extract_sweeps(rb,params,state);
```

Pass `[]` or `struct()` as `state` to reset. The pre-onset window is the baseline used by [partition_corr](../+mabr/+metrics/partition_corr.m) for the online advance metric.

## Failure modes worth knowing

| Symptom | Cause |
|---------|-------|
| `handshakeTimeout` | Pool could not start, or the worker cannot resolve `+mabr` |
| `workerFailed` at startup | Worker errored during launch; the message carries the original error |
| `notPrepared` | `Run` arrived before `Prep` |
| `sampleRate` error from BlockQueue | Source block rate ≠ `Config.DACSampleRate` |
| `readOnly` from RingBuffer | Something tried to write through the client's view |
| No onsets found at finalization | Timing channel not recorded — check input channel mapping |

Worker errors are logged in red via `mabr.log.vprintf(0,1,...)` and surface as `WorkerError` events.
