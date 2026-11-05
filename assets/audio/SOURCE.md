# Sound effects

- Made for this game, no recordings: rendered offline from physical models by
  `tools/audio/render_sfx.py` (numpy only, fixed random seeds, so the files can be rebuilt).
- Water: impact noise plus Minnaert bubbles with rising pitch (van den Doel, "Physically based
  models for liquid sounds", ACM Transactions on Applied Perception, 2005). Reel and clutch:
  trains of metallic clicks. Gulls: harmonic glides through formant band-passes. Surf: pink noise
  under wave envelopes, cross-faded into a seamless loop. A small Schroeder reverb on top.
- Licence: same as the game's own code. No third-party audio.
- Format: mono, 16-bit PCM WAV, 32 kHz.
