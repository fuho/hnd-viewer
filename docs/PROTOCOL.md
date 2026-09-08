# HND-NE3-D ear camera — stream protocol

Self-contained wire-spec for the factory firmware's live stream. The camera
runs no HTTP server; all traffic is **UDP** on fixed ports. All integers are
big-endian unless stated otherwise.

## Topology

- The camera boots as a Wi-Fi **access point** with SSID `HNDEC_55-<mac>`.
- Its gateway address is **`192.168.1.1`**.
- The viewer joins that AP as a DHCP client (`192.168.1.x`).
- The AP provides **no internet**; the viewer must work fully offline.

## Ports

| Port | Direction | Purpose |
|-----:|-----------|---------|
| 46526 | viewer → camera (broadcast) | discovery / wake |
| 44506 | bidirectional | video control + stream |
| 52219 | bidirectional | gyro / accelerometer |

## Discovery / wake

Send the 4-byte datagram `66 30 01 01` to `192.168.1.255:46526` (twice,
back-to-back). The camera replies with a UTF-8 **JSON** document describing
the unit (fields include `model`, `brand`, `soc`, `macid`, `firmware`, …).

Discovery is optional for streaming: the camera address is the fixed gateway
`192.168.1.1`, so a viewer may skip discovery and go straight to video.

## Video (JPEG stream)

1. Bind a local UDP socket on **44506**.
2. Send `20 36` (ASCII `" 6"`) to `192.168.1.1:44506` to **start** the stream.
3. The camera emits JPEG frames fragmented across UDP datagrams (≤1472 bytes).

Each datagram is:

```
byte 0  fid   frame id (increments per frame)
byte 1  eof   end-of-frame flag (1 on the last fragment of a frame)
byte 2  pkg   1-based fragment index (1..40)
byte 3  0x04  constant
byte 4+ …     JPEG fragment payload
```

Reassembly mirrors the vendor decoder:

- Three rotating frame buffers (40 slots each); active slot = `fid % 3`.
- A new `fid` resets that slot.
- The fragment carrying `eof = 1` announces the total fragment count in
  `pkg`; the frame is complete when the slot holds all `1..total` fragments.
- The JPEG payload is terminated by the EOI marker `FF D9`; trim any bytes
  after it (the camera appends a short footer).

Stream shape: **~12 fps, 480×480 baseline JPEG**.

Commands:

| Bytes | ASCII | Meaning |
|-------|-------|---------|
| `20 36` | `" 6"` | start video |
| `20 37` | `" 7"` | stop (observed: does not reliably stop the stream) |
| `20 35` | `" 5"` | heartbeat, sent ~every 2 s (keeps session alive) |

## Gyro / accelerometer

1. Bind a local UDP socket on **52219**.
2. Send `86 06 01` to `192.168.1.1:52219` to subscribe.
3. The camera streams 24-byte packets:

```
bytes 0..5   X, Y, Z  — three int16, big-endian (accelerometer, raw)
bytes 6..17  mid      — 12 bytes (unused / unknown)
bytes 18..19 tail     — 2 bytes (unused / unknown)
```

### Roll angle

Roll is derived from the accelerometer axes, not a fused quaternion:

```
mag   = hypot(axis_a, axis_b)
angle = degrees(atan2(axis_a, axis_b))     # axis pair default (y, z)
if mag < ~1500 → near-vertical, roll undefined (hold last good value)
```

Apply an EMA smoothing factor plus a small deadband to suppress jitter.

## Notes

- The camera IP/ports are fixed by the factory firmware; a different
  firmware revision may change them. The dev-info JSON (`soc`/`model`) is the
  sanity check before assuming the protocol matches.
- Byte sequences above are factual protocol observations, re-implemented
  independently; no vendor source is used or distributed here.
