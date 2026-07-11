# Nuvio GMPlayerKit Fork

This directory vendors the engine sources from GMPlayer `main-oss` at commit
`3da8bda9d557c61837fb2e4c97ed662219283043` (MIT).

Nuvio compiles these targets inside MPVKit so both players use MPVKit's single
FFmpeg and libdovi runtime. `scripts/configure-mpvkit-gmplayer.sh` copies the
sources and extends the released MPVKit package manifest used by CI.

Current Dolby Vision behavior:

- MKV is remuxed on demand to fragmented MP4/HLS and played by AVPlayer.
- Profile 7 currently retains GMPlayer's HDR10 base-layer behavior.
- `CFFmpeg/dovi.c` is the packet transformation seam for converting Profile 7
  RPU NAL units to Profile 8.1 and removing enhancement-layer NAL units.
- Do not advertise `dvh1` until that transformer and MP4 `dvcC` signaling are
  implemented and validated on physical Apple TV hardware.
