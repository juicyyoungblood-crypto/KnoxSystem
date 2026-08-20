# Deploy and host access — Knox System

How design/code written by Hermes reaches **Project Zomboid** for testing, and what you must set up on the Windows machine.

## Critical fact about this Hermes environment

As of the readiness pass, the agent runs in a **Docker container**:

- Writable project data: `/opt/data` (includes `workspace/pz-system-apocalypse/`)
- **No** `/mnt/c` Windows host mount visible
- **No** direct path to `%UserProfile%\Zomboid\mods`
- Hostname looks like a container id; `ssh` client exists; host filesystem is not attached

So: **the agent cannot drop files straight into your live Zomboid mods folder until you bridge that gap.**

Design + future `mod/` code will be written under:

```text
/opt/data/workspace/pz-system-apocalypse/
```

You (or a mount/sync you enable) must get `mod/Contents/mods/KnoxSystem` into the game’s mods directory.

---

## Where Zomboid expects local mods (Windows)

Typical paths (your username may differ):

```text
C:\Users\<YOU>\Zomboid\mods\
```

B42 workshop-style local layout often looks like:

```text
C:\Users\<YOU>\Zomboid\mods\KnoxSystem\
  42\
    mod.info
    media\...
```

or, matching our repo:

```text
...\mods\KnoxSystem\   ← contents of mod/Contents/mods/KnoxSystem
```

Steam game install (for reference, not where you drop loose mods):

```text
C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid\
```

Confirm in-game: **Mods** screen lists **Knox System** after copy + restart.

---

## Path options (pick one)

### Option 1 — Manual copy (simplest, no SSH)

1. Agent writes to `/opt/data/workspace/pz-system-apocalypse/mod/...`
2. On Windows, copy that folder into `Zomboid\mods\`
3. Restart PZ, enable mod, **new game**

**You need:** File Explorer access to wherever Docker Desktop mounts `/opt/data`.

Docker Desktop (Windows) volume data is often under a WSL distro or Docker’s disk image—not always a friendly path. If you cannot see `/opt/data` from Explorer:

- Use **Option 2** or **Option 3**.

### Option 2 — Bind-mount Windows folder into the Hermes container (best for agent writes)

Goal: same folder visible as:

- Windows: `C:\Users\<YOU>\Zomboid\mods\KnoxSystem` (or a dev folder you copy from)
- Container: e.g. `/opt/data/workspace/pz-system-apocalypse/mod/Contents/mods/KnoxSystem`

**You need to:**

1. Create the Windows mods (or dev) directory.
2. Reconfigure the Hermes/Docker run to **mount** that directory into the container path above.
3. Tell the agent the mount is live (path confirmation).

How to mount depends on how you start Hermes (Docker Compose, Docker Desktop UI, Hermes installer). Exactly one of:

- Docker Desktop → container → **Volumes** add bind mount  
- `docker run -v /mnt/c/Users/<YOU>/Zomboid/mods/KnoxSystem:/opt/data/workspace/pz-system-apocalypse/mod/Contents/mods/KnoxSystem ...`  
- Compose `volumes:` entry  

**WSL2 note:** From a real WSL distro, Windows is `/mnt/c/...`. This container currently did **not** expose `/mnt/c`; the mount must be added to **this** container’s config.

### Option 3 — Sync script on the host

1. Agent writes under `/opt/data/workspace/...`
2. A host-side script (Task Scheduler / manual) copies out of the Docker volume to `Zomboid\mods`

**You need:** A way to read the Docker volume from Windows (Docker Desktop “Files”, `docker cp`, or volume export).

Example host-side idea:

```bat
docker cp <hermes_container>:/opt/data/workspace/pz-system-apocalypse/mod/Contents/mods/KnoxSystem C:\Users\<YOU>\Zomboid\mods\KnoxSystem
```

### Option 4 — SSH into the Windows host / WSL (what you asked about)

Use this if you want the agent to `scp`/`rsync` into a path the game sees.

#### 4a. SSH into WSL2 (often easier than bare Windows)

On Windows (admin PowerShell / Win+R):

1. Install WSL if needed: `wsl --install`
2. Inside WSL: install OpenSSH server  
   `sudo apt update && sudo apt install -y openssh-server`  
   `sudo service ssh start`
3. Allow your user + key auth (`~/.ssh/authorized_keys`)
4. From the Hermes container, test:  
   `ssh <user>@<windows-host-ip>`  
   Host IP from Windows: `ipconfig` (WSL often uses a virtual adapter; Docker Desktop networking may need `host.docker.internal` or the Windows LAN IP)
5. Ensure WSL can write to `/mnt/c/Users/<YOU>/Zomboid/mods`

**Firewall:** Windows Defender Firewall → allow OpenSSH / port 22 on private networks only.

#### 4b. OpenSSH Server on Windows proper

1. Settings → Apps → Optional features → **OpenSSH Server**
2. Services → OpenSSH SSH Server → Automatic + Start
3. Firewall rule for OpenSSH
4. Prefer **key auth**; avoid password over LAN if possible
5. Agent connects to `user@<pc-lan-ip>` and writes under  
   `C:\Users\<YOU>\Zomboid\mods\`  
   (OpenSSH path quoting matters)

#### 4c. What to give the agent (do not paste private keys into chat if avoidable)

Prefer:

- SSH config in the container: host, user, key path mounted as a secret file
- Or Hermes terminal backend pointed at the host

Minimum checklist for the agent:

| Item | Example |
|------|---------|
| Host | `192.168.1.50` or `host.docker.internal` |
| User | `jesse` |
| Auth | key file path inside container |
| Remote mods path | `C:/Users/jesse/Zomboid/mods/KnoxSystem` or `/mnt/c/Users/jesse/Zomboid/mods/KnoxSystem` |
| PZ version | B42.x |

---

## Recommended setup for *this* project

**Preferred:** Option **2** (bind-mount).

**Container on your PC:** `hermes-mech-support`  
**Windows user (known from Mech Support copies):** `jesse`

**Step-by-step bind-mount guide (do this next):**

```text
docs/bind-mount-hermes-mech-support.md
```

**SSH (Option 4)** if mounts are painful.  
**Avoid** relying on `/mnt/c` inside Hermes until a mount exists.

---

## What you should do next (action list)

1. **Locate** your `Zomboid\mods` folder on Windows (create `mods` if missing).
2. **Choose** Option 2, 3, or 4.
3. **Verify** agent can see a write target:
   - Mount/cp test file `KS_DEPLOY_TEST.txt` appears on Windows.
4. Tell the agent:
   - Windows username
   - Chosen option
   - Exact mods path
   - (If SSH) host, user, how to auth
5. Only then start **Phase 0** scaffold into `mod/` and deploy once.

---

## Security notes

- Do not expose port 22 to the public internet.
- Use private network + key auth.
- Revoke keys when done if this is temporary.
- Prefer bind-mount over permanent SSH if you only need file drop for a single-player mod.

---

## Agent checklist before Phase 0 “loads in game”

- [ ] `mod/` tree exists in repo
- [ ] Deploy bridge tested (file appears under `Zomboid\mods`)
- [ ] Game lists Knox System
- [ ] New game with mod enabled launches without Lua error spam
