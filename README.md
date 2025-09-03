# Multifon - Multi-instance Psiphon Manager

> 🔐 Run multiple isolated Psiphon tunnels in parallel with Firejail sandboxing, smart port allocation, and region selection.

---

## 🧩 About

**Multifon** is a Bash-based manager for [Psiphon](https://github.com/SpherionOS/PsiphonLinux).  
It allows you to install Psiphon, manage multiple isolated instances, and run them simultaneously in different regions.  
Each instance is sandboxed with **Firejail**, preventing conflicts and ensuring separation of configs and ports.

---

## ✨ Features

- 📦 **Install & update Psiphon** (automatic, manual, or latest binary)
- 🛡 **Firejail integration** for sandboxed execution
- 🌍 **Multi-region support** with per-country folders (`psiphon-us`, `psiphon-de`, etc.)
- 🔀 **Smart port management** (avoids collisions across runs)
- ⚡ **Bulk operations**: start, stop, restart all tunnels
- 🔁 **Systemd autostart service** (`multifon-psiphon.service`)
- 🧹 **Cleanup tools** for removing Psiphon instances or Firejail

---

## 🚀 Installation

Run the script directly:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/h4m1dr/multifon/main/multifon.sh)
```

Or clone the repository:
```bash
git clone https://github.com/h4m1dr/multifon.git
cd multifon
bash multifon.sh
```

---

📖 Usage
When you run the script, you will see an interactive menu:

```bash
Main Menu:
 1) Psiphon Installation Menu
 2) Install Firejail
 3) Psiphon Folder Management
 4) Cleanup Options
 0) Exit

```

---

Example Workflows
Install Psiphon
Choose option 1 → Automatic Global Installation.

Install Firejail
Choose option 2.

Create Psiphon folders for regions
Choose option 3 → Create Psiphon folders (with Firejail)
Enter region codes like: US,DE,NL

Start all instances
Option 3 → Start all Psiphon locations

Check status
Option 3 → Check Psiphon status (all locations)

Enable autostart
The script automatically sets up a systemd service:
multifon-psiphon.service

---

📂 Folder Structure
Each configured Psiphon instance is stored under:

~/psiphon/psiphon-<cc>
 ├─ config.json
 ├─ psiphon-tunnel-core-x86_64
 ├─ start.sh
 └─ log.txt
Where <cc> is the 2-letter country code (e.g. us, de, nl).

---

🛠 Cleanup
Delete specific or all psiphon-* folders

Remove Firejail

Remove Psiphon binaries and configs

📋 Requirements
Linux (Debian/Ubuntu recommended)

bash, wget, git

firejail (auto-installable from menu)

systemd (for autostart service)

---

📜 License

This project is open-source under the MIT License.
Uses Psiphon binaries from SpherionOS/PsiphonLinux.
