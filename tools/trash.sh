#!/bin/bash
# Sends files or directories to the Windows Recycle Bin (never rm). Usage: bash tools/trash.sh <path>...
for f in "$@"; do
  w=$(cygpath -w "$(realpath "$f")")
  if [ -d "$f" ]; then op=DeleteDirectory; else op=DeleteFile; fi
  powershell -NoProfile -Command "Add-Type -AssemblyName Microsoft.VisualBasic; [Microsoft.VisualBasic.FileIO.FileSystem]::$op('$w', 'OnlyErrorDialogs', 'SendToRecycleBin')"
done
