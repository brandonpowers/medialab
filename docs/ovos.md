# Open Voice OS Setup Guide

Open Voice OS (OVOS) is an open-source voice assistant platform that provides privacy-focused, locally-hosted voice control capabilities. This guide covers the complete setup for OVOS in your homelab.

## Overview

Your homelab now includes a full Open Voice OS stack with the following components:

- **ovos-messagebus** - Central message bus for inter-service communication
- **ovos-core** - Skills service that handles user queries and intent processing
- **ovos-listener** - Captures voice input with wake word detection and STT
- **ovos-audio** - Handles audio playback and TTS output
- **ovos-phal** - Platform Hardware Abstraction Layer for device integration
- **ovos-gui** - Web-based graphical interface

## Prerequisites

### 1. Audio Device Access

For OVOS to access audio devices (microphone and speakers), ensure audio devices are available on your Ubuntu server.

**Verify audio devices:**

```bash
# Check audio devices are available
ls -la /dev/snd/

# You should see output like:
# drwxr-xr-x  4 root audio    280 Nov 21 10:00 .
# crw-rw----+ 1 root audio 116,  0 Nov 21 10:00 controlC0
# crw-rw----+ 1 root audio 116, 16 Nov 21 10:00 pcmC0D0c
# crw-rw----+ 1 root audio 116, 17 Nov 21 10:00 pcmC0D0p
```

### 2. USB Audio Device (Optional)

If you're using a USB microphone or speakers, they should be automatically detected:

```bash
# List USB devices
lsusb

# Example output:
# Bus 001 Device 004: ID 046d:0825 Logitech, Inc. Webcam C270

# List audio devices
arecord -l
aplay -l
```

### 3. Audio System Requirements

The setup script automatically handles these, but for reference:

- **PulseAudio** - Audio server for routing audio between containers and hardware
- **User in audio group** - Required for container user to access audio devices
- **User lingering** - Keeps user services (like PulseAudio) running after logout

## Initial Setup

The automated setup script (`./scripts/setup-homelab.sh`) handles OVOS configuration automatically:

1. Creates OVOS data directories
2. Generates default configuration file
3. Checks for audio device availability
4. Adds user to audio group
5. Installs and starts PulseAudio if needed
6. Enables user lingering

**Run the setup:**

```bash
cd /opt/homelab
./scripts/setup-homelab.sh
```

## Manual Configuration

### OVOS Configuration File

The main configuration file is at `data/ovos/config/mycroft.conf`. This file is automatically created with sensible defaults.

**Key configuration sections:**

```json
{
  "lang": "en-us",
  "listener": {
    "wake_word": "hey_mycroft",
    "recording_timeout": 10.0
  },
  "stt": {
    "module": "ovos-stt-plugin-vosk"
  },
  "tts": {
    "module": "ovos-tts-plugin-mimic3"
  }
}
```

**To customize:**

```bash
nano data/ovos/config/mycroft.conf
# Make your changes
docker compose restart ovos-core ovos-listener ovos-audio
```

### Wake Word Options

You can change the wake word by editing the configuration:

Available wake words:
- `hey_mycroft` (default)
- `hey_jarvis`
- `alexa`
- `computer`

Edit `data/ovos/config/mycroft.conf`:

```json
{
  "listener": {
    "wake_word": "hey_jarvis"
  }
}
```

## Service Access

### OVOS GUI (Web Interface)

Access the OVOS graphical interface via Tailscale:

```
http://homelab-media:8484
```

This provides a web-based UI for interacting with OVOS, viewing skills, and seeing visual feedback.

### OVOS Message Bus (Advanced)

For debugging and development, the message bus is accessible at:

```
ws://homelab-media:8181
```

## Testing OVOS

### 1. Check Service Status

```bash
cd /opt/homelab

# Check all OVOS services are running
docker compose ps | grep ovos

# Should show all services as "Up"
```

### 2. Check Logs

```bash
# View all OVOS logs
docker compose logs -f ovos-listener ovos-core ovos-audio

# Check for errors
docker compose logs ovos-listener | grep -i error
```

### 3. Test Microphone

```bash
# Test microphone recording (5 seconds)
docker compose exec ovos-listener arecord -d 5 -f cd /tmp/test.wav

# If this fails, check audio device passthrough
```

### 4. Test Wake Word Detection

Simply say the wake word ("Hey Mycroft") while the services are running. Check logs:

```bash
docker compose logs -f ovos-listener

# Look for messages like:
# "Wakeword detected"
# "Recording started"
```

### 5. Test a Voice Command

Say: **"Hey Mycroft, what time is it?"**

Watch the logs:

```bash
docker compose logs -f ovos-core ovos-audio

# You should see:
# - Intent recognized
# - Skill executing
# - TTS response
```

## Troubleshooting

### Audio Devices Not Found

**Symptom:** `/dev/snd` doesn't exist

**Solution:**
```bash
# Check if audio devices are connected
lspci | grep -i audio
lsusb | grep -i audio

# Load audio modules if needed
sudo modprobe snd-hda-intel

# Add user to audio group
sudo usermod -aG audio $USER
```

### PulseAudio Socket Not Found

**Symptom:** Services can't connect to PulseAudio

**Solution:**
```bash
# Check PulseAudio is running
systemctl --user status pulseaudio

# Start if needed
pulseaudio --start

# Check socket exists
ls -la /run/user/1000/pulse/native
```

### User Not in Audio Group

**Symptom:** Permission denied errors for audio devices

**Solution:**
```bash
# Add user to audio group
sudo usermod -aG audio $USER

# Logout and login for changes to take effect
# Or restart the container
```

### Wake Word Not Detected

**Symptom:** OVOS doesn't respond to wake word

**Check microphone:**
```bash
# Test microphone is working
arecord -d 5 -f cd /tmp/test.wav
aplay /tmp/test.wav

# Check OVOS listener logs
docker compose logs -f ovos-listener
```

**Check wake word configuration:**
```bash
# Verify wake word setting
cat data/ovos/config/mycroft.conf | grep wake_word

# Try adjusting sensitivity in mycroft.conf:
{
  "listener": {
    "energy_ratio": 1.5,  # Lower = more sensitive
    "multiplier": 1.0     # Adjust threshold
  }
}
```

### No Audio Output (TTS Not Speaking)

**Check speakers:**
```bash
# Test speaker output
paplay /usr/share/sounds/alsa/Front_Center.wav

# Check OVOS audio logs
docker compose logs -f ovos-audio

# Verify PulseAudio configuration
pactl info
```

### Services Keep Restarting

**Check logs for errors:**
```bash
docker compose logs ovos-listener
docker compose logs ovos-core

# Common issues:
# - Missing audio devices
# - Configuration file syntax errors
# - Network connectivity to message bus
```

## Installing Skills

OVOS skills extend functionality. Skills are installed into the shared volume.

**Install a skill:**

```bash
# Enter the core container
docker compose exec ovos-core bash

# Install a skill using pip
pip install ovos-skill-weather

# Restart core to load the skill
docker compose restart ovos-core
```

**Popular skills:**
- `ovos-skill-weather` - Weather information
- `ovos-skill-timer` - Timers and alarms
- `ovos-skill-wiki` - Wikipedia queries
- `ovos-skill-date-time` - Date and time information
- `ovos-skill-news` - News headlines

## Advanced Configuration

### Custom TTS Voice

Edit `data/ovos/config/mycroft.conf`:

```json
{
  "tts": {
    "module": "ovos-tts-plugin-mimic3",
    "ovos-tts-plugin-mimic3": {
      "voice": "en_US/vctk_low#p225"
    }
  }
}
```

Available voices: https://mycroftai.github.io/mimic3-voices/

### Custom STT Engine

By default, OVOS uses Vosk for speech-to-text (offline). You can switch to other engines:

```json
{
  "stt": {
    "module": "ovos-stt-plugin-whisper-streaming"
  }
}
```

### Home Assistant Integration

OVOS can integrate with Home Assistant for smart home control:

1. Install the Home Assistant skill:
```bash
docker compose exec ovos-core pip install ovos-skill-homeassistant
```

2. Configure in `mycroft.conf`:
```json
{
  "skills": {
    "ovos-skill-homeassistant": {
      "host": "http://homeassistant:8123",
      "token": "your_ha_token_here"
    }
  }
}
```

## Architecture

```
┌─────────────────────────────────────────────────┐
│           OVOS Stack Architecture               │
├─────────────────────────────────────────────────┤
│                                                 │
│  ┌──────────┐      ┌──────────┐                │
│  │  Audio   │◄────►│ Message  │                │
│  │  Input   │      │   Bus    │                │
│  │ (Mic)    │      │ :8181    │                │
│  └─────┬────┘      └────┬─────┘                │
│        │                │                       │
│        │                │                       │
│  ┌─────▼────┐     ┌────▼─────┐                 │
│  │ Listener │     │   Core   │                 │
│  │  (STT/   │     │ (Skills  │                 │
│  │  Wake)   │     │  Engine) │                 │
│  └──────────┘     └────┬─────┘                 │
│                        │                        │
│                   ┌────▼─────┐                  │
│  ┌──────────┐    │   PHAL   │    ┌─────────┐  │
│  │  Audio   │◄───┤ (Hardware│◄───┤   GUI   │  │
│  │  Output  │    │  Layer)  │    │  :8484  │  │
│  │(Speakers)│    └──────────┘    └─────────┘  │
│  └──────────┘                                  │
│                                                 │
└─────────────────────────────────────────────────┘
```

## Resources

- **Official Docs:** https://openvoiceos.github.io/ovos-docker/
- **Skills Repository:** https://github.com/OpenVoiceOS/OVOS-skills-store
- **Community:** https://github.com/OpenVoiceOS/OpenVoiceOS/discussions
- **Reddit:** r/OpenVoiceOS

## Service Details

| Service | Container Name | Purpose | Dependencies |
|---------|---------------|---------|--------------|
| Message Bus | ovos-messagebus | Inter-service communication | None |
| Core | ovos-core | Skills and intent processing | messagebus |
| Listener | ovos-listener | Wake word + STT | messagebus, audio devices |
| Audio | ovos-audio | TTS + audio playback | messagebus, audio devices |
| PHAL | ovos-phal | Hardware abstraction | messagebus, audio devices |
| GUI | ovos-gui | Web interface | messagebus |

## Port Reference

| Port | Service | Description |
|------|---------|-------------|
| 8181 | ovos-messagebus | WebSocket message bus |
| 8484 | ovos-gui | Web GUI interface |

## Next Steps

1. **Test basic voice commands** - Try "Hey Mycroft, what time is it?"
2. **Install additional skills** - Add weather, news, timers, etc.
3. **Customize wake word** - Change to your preference
4. **Integrate with Home Assistant** - Control smart home devices
5. **Adjust sensitivity** - Fine-tune wake word detection
6. **Add to Uptime Kuma** - Monitor OVOS services health

---

For more help, check the logs with `docker compose logs -f ovos-listener ovos-core ovos-audio`
