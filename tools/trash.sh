#!/bin/bash
# Sends files to the Windows Recycle Bin (never rm). Usage: bash tools/trash.sh <path>...
for f in "$@"; do
  w=$(cygpath -w "$(realpath "$f")")
  powershell -NoProfile -Command "Add-Type -AssemblyName Microsoft.VisualBasic; [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile('$w', 'OnlyErrorDialogs', 'SendToRecycleBin')"
done
