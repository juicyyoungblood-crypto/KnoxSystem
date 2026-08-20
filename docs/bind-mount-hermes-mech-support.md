# Bind-mount recreate — hermes-mech-support (from your inspect)

Inspect results (your PC):

```text
Mount:  volume hermes-data  ->  /opt/data
Image:  nousresearch/hermes-agent
```

Only **one** volume today. We keep it and add the KnoxSystem bind.

---

## Step 0 — Create Windows mod folder (if you have not)

```powershell
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\Zomboid\mods\KnoxSystem"
```

---

## Step 2b — Capture ports / restart (run once before stop)

So we do not lose gateway/dashboard ports:

```powershell
docker inspect hermes-mech-support --format "Restart={{.HostConfig.RestartPolicy.Name}}"
docker inspect hermes-mech-support --format "Ports={{json .HostConfig.PortBindings}}"
docker inspect hermes-mech-support --format "PublishAll={{.HostConfig.PublishAllPorts}}"
docker inspect hermes-mech-support --format "NetworkMode={{.HostConfig.NetworkMode}}"
docker inspect hermes-mech-support --format "Entrypoint={{json .Config.Entrypoint}}"
docker inspect hermes-mech-support --format "Cmd={{json .Config.Cmd}}"
```

If **Ports=** shows something like `{"8642/tcp":[{"HostPort":"8642"}]}`, add matching `-p` flags in Step 4.

If Ports is `{}` or empty, you may be on host networking or a desktop-managed network — use Step 4 as written, then fix ports only if Hermes UI/gateway breaks.

---

## Step 3 — Stop and rename (rollback-safe)

```powershell
docker stop hermes-mech-support
docker rename hermes-mech-support hermes-mech-support-old
```

---

## Step 4 — Recreate with volume + KnoxSystem bind

**Minimal (matches your inspect):**

```powershell
docker run -d `
  --name hermes-mech-support `
  --restart unless-stopped `
  -v hermes-data:/opt/data `
  -v "C:\Users\jesse\Zomboid\mods\KnoxSystem:/opt/data/workspace/pz-system-apocalypse/mod/Contents/mods/KnoxSystem" `
  nousresearch/hermes-agent
```

### If Step 2b showed host ports

Example only — use **your** ports from inspect:

```powershell
docker run -d `
  --name hermes-mech-support `
  --restart unless-stopped `
  -p 8642:8642 `
  -v hermes-data:/opt/data `
  -v "C:\Users\jesse\Zomboid\mods\KnoxSystem:/opt/data/workspace/pz-system-apocalypse/mod/Contents/mods/KnoxSystem" `
  nousresearch/hermes-agent
```

### If the old container used a custom entrypoint/cmd

Append the same Cmd after the image name only if inspect showed a non-default Cmd. Most `nousresearch/hermes-agent` images are fine with no extra command.

### Confirm it is running

```powershell
docker ps --filter name=hermes-mech-support
docker inspect hermes-mech-support --format "{{range .Mounts}}{{.Type}} {{.Source}} -> {{.Destination}}{{println}}{{end}}"
```

You want **two** lines roughly:

```text
volume .../hermes-data/_data -> /opt/data
bind   C:\Users\jesse\Zomboid\mods\KnoxSystem -> /opt/data/workspace/pz-system-apocalypse/mod/Contents/mods/KnoxSystem
```

(Windows may show the Source as `/run/desktop/mnt/host/c/Users/jesse/Zomboid/mods/KnoxSystem` — that is normal in Docker Desktop.)

---

## Step 4-fail — Rollback

```powershell
docker stop hermes-mech-support
docker rm hermes-mech-support
docker rename hermes-mech-support-old hermes-mech-support
docker start hermes-mech-support
```

---

## Step 5 — Verify bridge

### 5a. On PC

```powershell
docker exec hermes-mech-support ls -la /opt/data/workspace/pz-system-apocalypse/mod/Contents/mods/KnoxSystem
docker exec hermes-mech-support sh -c "echo bridge-ok > /opt/data/workspace/pz-system-apocalypse/mod/Contents/mods/KnoxSystem/KS_DEPLOY_TEST.txt"
type $env:USERPROFILE\Zomboid\mods\KnoxSystem\KS_DEPLOY_TEST.txt
```

Expected: `bridge-ok`

### 5b. Reconnect Hermes

Open a **new** Hermes chat/session against `hermes-mech-support` (old session may be dead after recreate).

Tell the agent: **Bridge OK — KS_DEPLOY_TEST.txt visible.**

Then we run Phase 0 scaffold into the mounted path.

---

## Notes

1. **`hermes-data` is unchanged** — all `/opt/data` design docs, Mech Support books, skills stay on the named volume.
2. The bind mount **covers only**  
   `.../mod/Contents/mods/KnoxSystem`  
   so the game folder and agent mod output are the same directory.
3. Until Phase 0 adds `42/mod.info`, PZ may not list a mod — the test file is enough to prove the bridge.
4. If `docker run` errors on the bind path, recreate the folder (Step 0) and ensure Docker Desktop file sharing can access `C:\Users\jesse`.
