# Async Functions

Async functions are parsed, type-checked, and lowered into stackless state
machine descriptors. They also emit a direct callable body today, so async
functions and simple `await` chains run through the normal compiled path while
the cooperative scheduler is still being completed.

## Declaration

Use the `async` keyword to define an async function:

```duo
async fun fetch_data(url: str): str
    response = await http_get(url)
    return response.body
end
```

The current callable path returns `T` directly. The compiler still emits
`duo_Poll` frame/step descriptors for async functions so the scheduler-backed
`Poll[T]` path can take over as it is completed.

## Await

The `await` keyword marks a yield point for lowering. In the current direct
runtime path it evaluates the awaited expression synchronously:

```duo
async fun process_all(urls: []str): []str
    results: []str = {}
    for url in urls
        body = await fetch_data(url)  -- Yield point
        results[#results + 1] = body
    end
    return results
end
```

## Scheduler

The cooperative single-threaded scheduler is still in progress:

```duo
-- Spawn a task
task = spawn fetch_data("https://example.com")

-- The scheduler runs automatically when you await or poll tasks
result = await task
```

## Channels

Typed channels enable communication between async tasks:

```duo
async fun producer(ch: Channel[i64]): void
    for i = 1, 100
        await ch.send(i)
    end
    ch.close()
end

async fun consumer(ch: Channel[i64]): i64
    total: i64 = 0
    while true
        value = await ch.recv()
        if not value then break end
        total = total + value
    end
    return total
end
```

## Threaded Scheduler

For CPU-bound workloads, use the threaded scheduler:

```duo
-- Via attribute:
@concurrent("threaded")
async fun cpu_intensive(n: i64): i64
    -- Runs on thread pool
    return heavy_computation(n)
end

-- Or via command line:
-- duo run script.duo --threads
```

Note: Threaded mode is not supported on WASM targets.

## Task Cancellation

Tasks can be cancelled with defer cleanup:

```duo
async fun with_cleanup(): i64
    resource = acquire_resource()
    
    defer release_resource(resource)
    
    await some_operation()
    return 42
end
```

If the task is cancelled or an error occurs, the defer blocks execute in LIFO order.

## State Machine Compilation

Under the hood, async functions compile to C structs:

```c
typedef struct {
    int state;              // Current yield point
    PollResult result;      // Return value when done
    int64_t local_counter;  // Captured locals
    void* local_channel;
} duo_async_frame_myFunc;
```

Each `await` becomes a yield point, and the scheduler resumes execution by calling the step function.
