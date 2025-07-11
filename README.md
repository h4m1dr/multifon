# Multifon - Multi-instance Psiphon Launcher

> 🔐 Run multiple isolated Psiphon tunnels in parallel using Firejail sandboxing, region selection, and smart automation.

---

## 🧩 About

**Multifon** is a Bash script that allows you to install, configure, and run multiple Psiphon instances on Linux.  
It uses sandboxing with **Firejail** to isolate each tunnel, enabling connections to multiple egress regions simultaneously without interference.

---

## 🚀 Installation

Run the script using:

```bash
bash <(curl -Ls https://raw.githubusercontent.com/h4m1dr/multifon/main/multifon.sh)
