# UPS via NUT to Zabbix (Ansible)

Sets up a USB-connected UPS on a Raspberry Pi with NUT (Network UPS Tools) and makes it
visible in Zabbix through the template **"nut_ups template"** (agent key `upsmon[...]`).

Tested 2026-11-18 on Raspberry Pi with Debian 13 (zabbix-agent 8.0) and Raspberry Pi OS / Debian 12
(Debian's zabbix-agent), with APC Back-UPS and HP T750.
A second run changes nothing (changed=0). The optional status page (`nut_web`) was tested
2026-11-23 on Debian 13, next to an existing Apache on ports 80/443.

## Prerequisites

**Ansible** is a tool that configures other machines over SSH from your own computer. You run
the playbook on your computer, and Ansible logs in to each Pi and makes the changes there.
Nothing needs to be installed on the Pis beforehand (Python 3 is already part of Raspberry Pi OS).

On your computer (Linux, macOS, or WSL on Windows), install Ansible 2.14 or newer
(tested with ansible-core 2.20):

```bash
sudo apt install ansible           # Debian, Ubuntu, Raspberry Pi OS, WSL
brew install ansible               # macOS
pipx install --include-deps ansible  # any system with pipx
```

Check the installation with `ansible --version`.

On each Pi:

- the UPS is connected via USB,
- you can log in with an SSH key, and your user has sudo rights.

In Zabbix, the template **"nut_ups template"** must be imported (see [In Zabbix](#in-zabbix)),
and the Zabbix server must be able to reach the agent on the Pi on port 10050.

## What the playbook does

1. Installs `nut-server`, `nut-client` and `zabbix-agent`.
2. **NUT** (unless `nut_manage` is `false`): **standalone** mode, the UPS in `/etc/nut/ups.conf`
   (driver `usbhid-ups`, UPS name = the Pi's short host name) and NUT's USB rule
   (`udevadm trigger`), so the driver can open a UPS that was plugged in before NUT was installed.
3. **upsmon** (always with `nut_manage`, otherwise if `nut_upsmon=true`): an internal NUT user
   with a random password and a MONITOR line, so the Pi **shuts down cleanly on low battery**.
4. **Zabbix agent**: `/etc/zabbix/scripts/upsmon.sh` and `UserParameter=upsmon[*]` in the
   agent's include directory (found automatically), and `Server=` if `zabbix_server` is set.
5. **Status page** (only if `nut_web=true`): NUT's read-only web page (`nut-cgi`) served by
   `lighttpd` on port 8088, see [Status page](#status-page-optional).
6. Finally checks that NUT responds, that the agent answers the same questions Zabbix asks,
   and (with `nut_web`) that the status page shows the UPS.

## Usage

```bash
eval "$(ssh-agent -s)" && ssh-add          # once per terminal window
cp inventory.example.ini inventory.ini     # first time, fill in your Pis
ansible-playbook -i inventory.ini ups.yml -K -l <host> --check --diff   # dry run
ansible-playbook -i inventory.ini ups.yml -K -l <host>                  # for real
```

`-K` asks for the sudo password on the target Pi. Run one Pi at a time if the passwords differ.
A dry run on a brand-new Pi stops after the install step (the configuration files don't exist
until the packages are installed) and says so.

## Per-host variables (inventory.ini)

| Variable | Meaning |
|---|---|
| `zabbix_server` | The Zabbix server allowed to query the agent (sets `Server=`) |
| `ups_name` | UPS name in NUT and Zabbix (default: the Pi's short host name) |
| `nut_vendorid`, `nut_productid`, `nut_desc` | USB IDs and description (optional, from `lsusb`) |
| `nut_manage=false` | Leave an existing NUT setup alone, only add the Zabbix part. `ups_name` must then match the section in `ups.conf`. |
| `nut_upsmon=true` | With `nut_manage=false`: still add upsmon (clean shutdown) |
| `nut_web=true` | Also serve the read-only status page (default `false`) |
| `nut_web_port` | Port for the status page (default `8088`) |
| `nut_web_allow` | Comma-separated networks allowed to see the page (default `44.0.0.0/9,44.128.0.0/10,10.0.0.0/8`; localhost is always allowed) |

## Status page (optional)

With `nut_web=true` the Pi shows the UPS in a browser at `http://<pi>:8088/`
(battery charge, load, runtime, status). The playbook:

- installs `nut-cgi` and `lighttpd` and sets lighttpd's port to `nut_web_port`,
- serves **only** the status page (`upsstats.cgi` and its graphs). Everything else, including
  the settings page `upsset.cgi`, returns 403,
- allows only localhost and the networks in `nut_web_allow`; other addresses get 403,
- adds the UPS to `/etc/nut/hosts.conf`.

The address restriction is a second layer. Also block the port in your firewall or routers
for anyone who shouldn't see the page.

Setting `nut_web=false` later does not remove anything. To remove the page, run
`sudo apt purge nut-cgi lighttpd` on the Pi.

## In Zabbix

The template **"nut_ups template"** comes from
[delin/Zabbix-NUT-Template](https://github.com/delin/Zabbix-NUT-Template) (Apache-2.0).
For Zabbix 7.0 LTS and later, import `nut_ups_template_zb-6.4_.xml` from that repository.
This playbook installs its own agent script (`files/upsmon.sh`), which answers the same
`upsmon[...]` keys, so the template works unchanged.

Add the host with an **Agent** interface (the Pi's IP, port 10050) and the templates
**"nut_ups template"** and **"Linux by Zabbix agent"** (the passive one, not "active").

| Key | Content |
|---|---|
| `upsmon[ups.discovery]` | list of UPSes (`{#UPSNAME}`) |
| `upsmon[<ups>,ups.status]` | status as a number: 1 on line, 2 on battery, 3 low battery, 13 on line and charging, 14 on battery and discharging … (value map "UPS Battery Status") |
| `upsmon[<ups>,battery.charge]` etc. | the value straight from `upsc` |

Values the UPS model doesn't report show up as "Not supported" in Zabbix. That is normal.

## Troubleshooting

- `upsc <ups>@localhost` says **"Driver not connected"**: check
  `journalctl -u 'nut-driver@*'`. Run the driver by hand with `-DD`
  (`/lib/nut/usbhid-ups -a <ups> -u nut -DD`). The message "insufficient permissions on everything"
  can be misleading: if it says "failed match of VendorID", the `vendorid`/`productid` in
  `ups.conf` don't match the UPS (e.g. after the UPS was replaced).
- `zabbix_agentd` is in `/usr/sbin` and not in an ordinary user's PATH on Debian 12.

## Files

- `ups.yml`: the playbook
- `inventory.example.ini`: example, copy it to `inventory.ini`
- `files/upsmon.sh`: the agent script
- `templates/nut-web.conf.j2`: lighttpd rules for the status page
- `credentials/<host>/upsmon`: the random NUT password per host. Created automatically and
  must not be committed or shared (listed in `.gitignore`, as is `inventory.ini`).

## License

GNU General Public License v3.0, see `LICENSE`.
