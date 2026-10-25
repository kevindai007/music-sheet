# LiberLive C2 BLE protocol (reverse-engineered 2026-10-24)

Sources: read-only GATT dump from a Mac (`gatt-dump.txt`) and a PacketLogger capture of the official
iOS app (`recored_log.pklg`). Codec: `liberlive.py` (round-trips all 9,303 captured frames).

## GATT
Device name `LiberLiveC2-<last 4 hex of MAC>` (ours: `LiberLiveC2-44BC`, MAC 44:1B:F6:65:44:BE, Espressif OUI).
One service `0x00FF`:

| Char | Props | Use |
|---|---|---|
| A101 | notify | guitar -> app events (`noti_basic` ~10 Hz, `noti_chord`, `noti_event`) |
| A102 | read   | reply to the last command written to A103 |
| A103 | write (with response) | app -> guitar commands |

App flow: enable A101 notifications, then for each request write A103 and read A102.

## Frame
```
0      '$'
1      'M' app->guitar | 'A' guitar->app
2      total length
3      0xC0
4..11  nonce (random per frame)
12..15 uint32 LE timestamp (guitar: ms since boot)
16     CRC-8 poly 0x31 init 0 over bytes 0..15
17..   body, byte k XOR frame[4 + k%12] XOR KEY[k%12]
       KEY = b6 1e 2a b7 69 0d ea 06 7e 6d ea cc
last 2 CRC-16/XMODEM over the scrambled body, little-endian
```

## Body
* Named command: `[len][ascii name][args]`; the reply in A102 echoes the name followed by data.
* Binary command: `01 <opcode> [args]`.

### Named commands seen (official app)
get_style_settings, get_fret_chords, get_fret_notes, get_vers_all, get_uids_all, get_func_support,
get_func_v2_support, get_volume / set_volume, get_config_basic / set_config_pack, get_user_data,
get_sys_encrypted, get_midi_info, get_dmachine / set_dmachine, get_fret_mode, set_guitar_mode,
set_notify_param, set_auto_playing, **set_remind_chord** (95x while practising: 3 arg bytes,
e.g. `05 01 00`, `09 08 00`, `00 00 00`; likely the chord hint shown on the neck).

### Binary commands seen
* `01 07` (584x while playing): timed event list. Contains float32 beat positions (1.0, 2.0, 3.0 ...)
  and durations (0.5, 1.0 ...) plus chord ids with velocity 0x64; the app streams upcoming chords/notes.
* `01 0f` query (reply `06 01 01 02 01 03 01 04 00 05 00 06 00`), `01 06`, `01 08`, `01 0a`, `01 16` setup.

### Notifications
* `noti_chord`: sent each time a pick is played (not when a chord button is pressed or held), with the
  chord button held at the time: `[root][01][root][quality][00][pick]`. root = semitone (C=0 D=2 E=4 F=5 G=7
  A=9 B=11), quality 0=major 1=minor 3=dim, pick = which of the guitar's two picks (0/1; each can carry its
  own pattern, e.g. picking vs strumming). The second byte has always been 01. Verified with the 7 diatonic
  buttons C Dm Em F G Am B°.
* `noti_basic`: status, ~10 Hz. Not decoded yet.
* `noti_event`: misc events (e.g. `04 00`). Not decoded yet.

## Open questions
* Exact meaning of `set_remind_chord` args and the `01 07` record layout (needs a capture with a known song).
* `get_sys_encrypted` reply `01 00 02 01 03 01 04 00` hints at optional encryption modes; the default needs no handshake.
* Nothing has been written to the guitar by our own code yet.
