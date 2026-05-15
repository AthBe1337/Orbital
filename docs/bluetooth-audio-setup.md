# Bluetooth Audio on OnePlus 6T

Bluetooth audio (A2DP/HFP) profiles are not advertised by the local adapter
until the following WirePlumber configuration is applied.

## Symptom

Bluetooth devices pair and connect, but no audio profiles (A2DP sink/source,
HFP) are listed. `pactl list cards` shows no Bluetooth audio card.

## Root cause

The OnePlus 6T runs no graphical session bound to `seat0`. systemd-logind
reports the seat as `online` but never `active`.

WirePlumber's bluez monitor (`bluez.lua:547`) checks whether the seat is
`active` before initialising. Since the seat is never `active`, the monitor
silently skips initialisation, and the adapter advertises no audio profiles.

The relevant guard in bluez.lua:

```
if self.seat_monitoring ~= "disabled" and not is_seat_active (...) then
  log:info("not loading, seat not active")
  return
end
```

*Source:* [bluez.lua#L547](https://gitlab.freedesktop.org/pipewire/wireplumber/-/blob/master/src/scripts/monitors/bluez/bluez.lua#L547)

## Fix

Disable seat-monitoring for the bluez monitor so it loads unconditionally:

```bash
sudo mkdir -p /etc/wireplumber/wireplumber.conf.d && \
sudo tee /etc/wireplumber/wireplumber.conf.d/50-bluez-no-seat.conf >/dev/null <<'EOF'
# OnePlus 6T has no graphical session bound to seat0, so logind reports
# the seat as "online" but never "active" — wireplumber's bluez monitor
# (bluez.lua:547) waits for "active" and silently never starts, which
# is why the local adapter advertises no A2DP/HFP profiles. Disable
# the seat-monitoring guard so the bluez monitor loads unconditionally.
wireplumber.profiles = {
main = {
  monitor.bluez.seat-monitoring = disabled
}
}
EOF
```

Then restart WirePlumber:

```bash
systemctl restart wireplumber
```

## Verification

After restart, confirm the Bluetooth audio card appears:

```bash
pactl list cards | grep -i bluez
```
