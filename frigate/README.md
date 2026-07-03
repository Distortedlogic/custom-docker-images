# Frigate

Single-camera NVR for the Reolink E1 Outdoor SE PoE (camera id `driveway`, `192.168.100.130`).

## Layout

| Path | Purpose |
|---|---|
| `docker-compose.yml` | Container definition (TensorRT image, NVIDIA runtime, port mappings) |
| `.env` | Holds `FRIGATE_RTSP_PASSWORD` — **URL-encoded** camera password |
| `config/config.yml` | Frigate camera + detector + zones + go2rtc config |
| `config/model_cache/yolov9-t-320.onnx` | YOLOv9-tiny ONNX model used by the detector (8 MB) |
| `config/` | Frigate's persistent state (sqlite db, CLIP embedding cache) |
| `media/` | Recordings + snapshots |

## Run

```sh
just up-frigate           # from ~/repos/custom-docker-images
just logs-frigate
just restart-frigate
just down-frigate
```

Web UI: <https://localhost:8971> (self-signed cert, click through). Auth is enabled; first start prints the auto-generated admin password to the logs. Recover it any time with:

```sh
docker logs frigate 2>&1 | grep -A1 "User: admin" | head -3
```

The current password is `4db11199806a380ed232bfe59646ebe1`.

## Stack

| Component | Choice | Why |
|---|---|---|
| Image | `ghcr.io/blakeblackshear/frigate:stable-tensorrt` | Required for NVIDIA GPU detection in Frigate 0.17 (the regular `stable` image lacks the TensorRT execution provider for onnxruntime). |
| Decode | `preset-nvidia` → NVDEC on RTX 3090 | Handles the 4K H.265 main stream without touching CPU. |
| Detector | `onnx` + YOLOv9-tiny @ 320×320 | The `tensorrt` detector type was deprecated in 0.17 on amd64. ONNX detector auto-uses the TensorRT execution provider on NVIDIA — same speed, supported path. |
| Live view | `go2rtc` WebRTC | Restreams the camera once, browser plays via WebRTC (~200 ms latency). |
| Recording | Motion mode, 7-day base / 30-day alerts / 7-day detections | Only records when motion is present. |
| Semantic search | enabled, `jinaai/jina-clip-v1` (small) | Lets you search past clips by text ("white SUV", "person carrying box"). Embeddings cached in `config/`. |
| Auth | enabled | Required for web push notifications. |
| Notifications | enabled (web push, VAPID auto-generated) | Open the web UI on your phone, log in, accept the browser push permission; alerts in the `parking` or `approach` zones ping you. |

## Camera streams

- **Main (record)**: `rtsp://.../h265Preview_01_main` — 3840×2160 @ 25 fps, H.265, ~6 Mbps
- **Sub (detect)**: `rtsp://.../h264Preview_01_sub` — 640×360 @ 10 fps, H.264

Both republished by go2rtc on `:8554`.

## Zones (in 640×360 detect-frame coordinates)

| Zone | Purpose | Routing |
|---|---|---|
| `parking` | The gravel pad in the bottom-left where the car parks | Alert zone — fires push, 30-day retain |
| `approach` | The entrance strip where the driveway meets the road | Alert zone |
| `street` | The visible paved road across the middle/right | Detection only — 7-day retain, no push |

A motion mask covers the top 47 % of the frame (tree canopy) to suppress wind-sway false positives.

## Tracked objects

`person`, `car`, `motorcycle`, `bicycle`. Dropped `dog` / `cat` (overhead-angle false-positive factory). Per-object size and confidence filters are set in `config/config.yml` under `objects.filters` and should be tuned from the Debug view once you see real events.

## Storage budget

Motion-mode recording on a 6 Mbps stream lands around 20–30 GB/day. With base 7-day retention that's ~150–200 GB in `./media`. Alerts retain 30 days, detections 7. Move `./media` to a dedicated disk when that matters.

## Password

Camera password contains `@#$%` which break a raw RTSP URL. The `.env` stores the **URL-encoded** form (`JJM111jjm%40%23%24%25`). Frigate substitutes `{FRIGATE_RTSP_PASSWORD}` into URLs verbatim, so always store the encoded value here.

## Rebuilding the detection model

The YOLOv9-tiny ONNX is built locally via the official Frigate recipe and committed to `config/model_cache/`. To rebuild (e.g. swap size `t→s` or resolution `320→640`):

```sh
docker buildx build /tmp --build-arg MODEL_SIZE=t --build-arg IMG_SIZE=320 --output /tmp -f- <<'EOF'
FROM python:3.11 AS build
RUN apt-get update && apt-get install --no-install-recommends -y cmake libgl1 && rm -rf /var/lib/apt/lists/*
COPY --from=ghcr.io/astral-sh/uv:0.10.4 /uv /bin/
WORKDIR /yolov9
ADD https://github.com/WongKinYiu/yolov9.git .
RUN uv pip install --system -r requirements.txt
RUN uv pip install --system onnx==1.18.0 onnxruntime onnx-simplifier==0.4.* onnxscript
ARG MODEL_SIZE
ARG IMG_SIZE
ADD https://github.com/WongKinYiu/yolov9/releases/download/v0.1/yolov9-${MODEL_SIZE}-converted.pt yolov9-${MODEL_SIZE}.pt
RUN sed -i "s/ckpt = torch.load(attempt_download(w), map_location='cpu')/ckpt = torch.load(attempt_download(w), map_location='cpu', weights_only=False)/g" models/experimental.py
RUN python3 export.py --weights ./yolov9-${MODEL_SIZE}.pt --imgsz ${IMG_SIZE} --simplify --include onnx
FROM scratch
ARG MODEL_SIZE
ARG IMG_SIZE
COPY --from=build /yolov9/yolov9-${MODEL_SIZE}.onnx /yolov9-${MODEL_SIZE}-${IMG_SIZE}.onnx
EOF

docker run --rm -v /tmp/yolov9-t-320.onnx:/src:ro -v "$PWD/config/model_cache:/dst" alpine cp /src /dst/yolov9-t-320.onnx
just restart-frigate
```
