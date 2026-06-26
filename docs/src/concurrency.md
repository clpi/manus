# Concurrency

Duo provides cooperative concurrency through async/await and channels, enabling scalable I/O-bound and parallel workloads.

## Async Functions

Define async functions with the `async` keyword:

```duo
async fun fetch(url: str): str
    response = await http_get(url)
    return response.body
end
```

Async functions compile to C structs with a step function. The current path returns results directly while descriptors are emitted for the full scheduler path.

## The sync Module

Use `std.sync` for cooperative scheduling:

```duo
sync = req "std.sync"

-- Spawn creates a coroutine task
sync.spawn(fun()
    print("task 1")
end)

-- Run drives all spawned tasks to completion
sync.run()
```

## Channels

Typed channels enable communication between async tasks:

```duo
sync = req "std.sync"

-- Channel with capacity
ch = sync.channel(10)

-- Send and receive
sync.channel_send(ch, "hello")
msg = sync.channel_recv(ch)
```

## Producer-Consumer Pattern

```duo
sync = req "std.sync"

fun producer(ch): void
    for i = 1, 100
        sync.channel_send(ch, "item-" .. tostring(i))
    end
    sync.channel_close(ch)
end

fun consumer(ch): void
    while true
        msg = sync.channel_recv(ch)
        if msg == nil then break end
        print("Got: " .. msg)
    end
end
```

## Standard-Library Concurrency

In addition to the `async`/`await` language primitives, the standard library provides cooperative and OS-level concurrency in `lib/std/`:

- `std.coroutine` — Lua-style coroutine helpers (`create`, `resume`, `yield`, `status`, `wrap`, `close`).
- `std.sync` — single-threaded cooperative scheduler and typed channels (`spawn`, `run`, `yield`, `channel`, `channel_send`, `channel_recv`, `step`).
- `std.concurrent` — high-level patterns (`go`, `wait`, `all`, `race`, `select`) built on `std.sync`.
- `std.thread` — mutex, rwlock, condvar, semaphore, barrier, and thread spawn/join. Cooperative in single-threaded mode; maps to pthreads under `@concurrent("threaded")`.
- `std.mproc` — multi-process helpers (`spawn`, `wait`, `kill`, `pid`).
- `std.atomic` — atomic primitives and mutexes.

See the [Standard Library](./stdlib.md) chapter for examples.

## Threaded Scheduler

For CPU-bound work, use thread pools:

```duo
@concurrent("threaded")
async fun compute_heavy(n: i64): i64
    -- Runs on thread pool
    return fibonacci(n)
end

-- Or via command line:
-- duo run script.duo --threads
```

Note: Threaded mode not supported on WASM targets.

## Cancellation

Tasks can be cancelled with proper cleanup:

```duo
async fun with_timeout(): i64
    resource = acquire()
    
    defer release(resource)  -- Always runs on cancellation
    
    result = await some_operation()
    return result
end
```

## State Machine Compilation

Async functions compile to C structs with explicit state:

```c
typedef struct {
    int state;              // Current yield point
    PollResult result;        // Return value when done
    // Captured locals
    int64_t i;
    void* ch;
} duo_async_frame_pipeline;
```

Each `await` becomes a yield point, and the scheduler (when complete) resumes execution by calling the step function.