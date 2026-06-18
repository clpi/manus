# Concurrency

Duo provides cooperative concurrency through async/await and channels, enabling scalable I/O-bound and parallel workloads.

## Async Functions

Define async functions with the `async` keyword:

```duo
async fun fetch(url: str): str
    response = await http.get(url)
    return response.body
end
```

Async functions return `Poll[T]` - they may complete immediately or need resumption.

## The Scheduler

Duo uses a cooperative event loop:

```duo
-- Spawn creates a task
task1 = spawn fetch("https://api.example.com/users")
task2 = spawn fetch("https://api.example.com/posts")

-- Await collects results
users = await task1
posts = await task2
```

The scheduler polls pending tasks and drives them to completion.

## Channels

Typed channels enable communication between async tasks:

```duo
-- Channel with capacity
ch: Channel[i64] = channel(10)

-- Sender blocks when full
-- Receiver blocks when empty
```

## Producer-Consumer Pattern

```duo
async fun producer(ch: Channel[str]): void
    for i = 1, 100
        await ch.send("item-" .. tostring(i))
    end
    ch.close()
end

async fun consumer(ch: Channel[str]): void
    while true
        msg: Option[str] = await ch.recv()
        if not msg then break end
        print("Got: " .. msg)
    end
end
```

## Standard-Library Concurrency

In addition to the `async`/`await` language primitives, the standard library provides cooperative and OS-level concurrency in `lib/std/`:

- `std.coroutine` — Lua-style coroutine helpers (`create`, `resume`, `yield`, `status`, `wrap`, `close`).
- `std.sync` — single-threaded cooperative scheduler and typed channels (`spawn`, `run`, `channel`, `channel_send`, `channel_recv`).
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

## Task Groups

Wait for multiple tasks concurrently:

```duo
async fun parallel_map<T, U>(items: []T, f: fun(T): U): []U
    results: []U = {}
    tasks: []Task[U] = {}
    
    for item in items
        tasks[#tasks + 1] = spawn f(item)
    end
    
    for i, task in ipairs(tasks)
        results[i] = await task
    end
    
    return results
end
```

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

## Await Points

Every `await` is a yield point where other tasks can run:

```duo
async fun pipeline(): void
    data1 = await stage1()    -- Yield point 1
    data2 = await stage2(data1) -- Yield point 2
    data3 = await stage3(data2) -- Yield point 3
    return data3
end
```

## State Machine Compilation

Async functions compile to C structs with explicit state:

```c
typedef struct {
    int state;
    PollResult result;
    // Captured locals
    int64_t i;
    void* ch;
} duo_async_frame_pipeline;
```

The scheduler resumes by calling the step function at the appropriate state.