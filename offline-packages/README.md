Put your offline .deb packages in this directory.

Notes:
- Files must have .deb extension. They will be installed with: sudo dpkg -i <file>.
- The installer will attempt to fix missing dependencies afterward with: sudo apt-get -f install -y.
- Order of installation is lexical (sorted by filename). If a specific order is required, prefix files with numbers like 01-, 02-, etc.
