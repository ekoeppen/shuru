# Fork of shuru

This is a fork of [shuru](https://shuru.run) with the following modifications:

- Add script to create Debian based rootfs
- Add support for writable mounts
- Allow passing environment variables into the guest
- Configure verbose output via CLI flags

## Usage

```sh
# Show verbose output (includes kernel boot logs)
shuru -vv run -- echo "booted with logs"
```

### Environment variables

Pass environment variables into the VM using the `-e` or `--env` flags. Multiple variables can be set by repeating the flag.

```sh
# Pass a single variable
shuru run -e API_KEY=secret -- env | grep API_KEY

# Pass multiple variables
shuru run -e KEY1=val1 -e KEY2=val2 -- env

# Environment variables are also supported when creating checkpoints
shuru checkpoint create myenv -e APP_ENV=prod -- apk add my-package
```

Environment variables can also be set in `shuru.json` (see [Config file](#config-file)).

### Directory mounts

```sh
# Mount a directory (ephemeral: guest writes to RAM layer, host is untouched)
shuru run --mount ./src:/workspace -- ls /workspace

# Persistent mount (guest writes directly to the host directory)
shuru run --mount ./data:/data:rw -- sh

# Explicit read-only mount (same as default)
shuru run --mount ./docs:/docs:ro -- cat /docs/README.md

# Multiple mounts with mixed modes
shuru run --mount ./src:/src:ro --mount ./out:/out:rw -- make
```


### Config file

Shuru loads `shuru.json` from the current directory (or `--config PATH`). All fields are optional; CLI flags take precedence.

```json
{
  "cpus": 4,
  "memory": 4096,
  "disk_size": 8192,
  "allow_net": true,
  "ports": ["8080:80"],
  "env": {
    "API_KEY": "secret",
    "NODE_ENV": "production"
  },
  "mounts": ["./src:/workspace", "./data:/data"],
  "command": ["python", "script.py"]
}
```
