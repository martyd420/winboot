# winboot.sh

Bash script for creating a bootable Windows USB installation drive on Linux.


## Requirements
- Linux (tested on Ubuntu/Debian)
- Root privileges (sudo)
- Packages: `rsync`, `parted`, `wimtools`
- For Legacy mode additionally: `grub-pc-bin`
- The script will attempt to automatically install missing `wimtools` and `grub-pc-bin` via `apt-get`

## Usage
```bash
chmod +x winboot.sh
sudo ./winboot.sh -i <path_to_iso> -o <target_device> -m <uefi|legacy>
```

**Examples:**
```bash
sudo ./winboot.sh -i Win11_x64.iso -o /dev/sdd -m uefi
sudo ./winboot.sh -i Win10.iso -o /dev/sdd -m legacy
```

