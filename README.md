# Windows Temp & Cache Cleanup Script (`tempDel.ps1`)

PowerShell script to reclaim disk space by deleting **old, low-value files** like temp files, caches, logs, and crash dumps — without touching your documents, photos, or other important data.

By default it:

- Scans for *candidate* files first (dry-run)
- Shows what it found and how much space you could free
- Asks for confirmation before deleting anything  

You can also run it in **silent/auto mode** for scheduled cleanups.

---

## What this script cleans

All deletions are:

- **Files only** – it never removes entire folders.
- **Age-limited** – nothing younger than **2 days** is touched.
- **Scoped to typical temp/cache/log locations** – no user documents.

### Age thresholds

These are defined near the top of the script:

```powershell
$TempDays    = 2    # user / app temp
$CacheDays   = 2    # caches (browsers/Electron/Firefox forks/AppData caches)
$LogDays     = 2    # logs in typical log dirs
$SystemDays  = 7    # system-level stuff (update cache, minidumps, WER, etc.)
````

You can tweak these values if you want to be more or less aggressive.

### Targets

The script looks at:

1. **Windows & user temp folders** (≥ 2 days old)

   * `%TEMP%`, `%TMP%`
   * `C:\Windows\Temp`

2. **System update & diagnostic junk** (≥ 7 days old)

   * `C:\Windows\SoftwareDistribution\Download` (Windows Update cache)
   * `C:\Windows\Minidump` (BSOD/minidump files)
   * `C:\CrashDumps` (user-mode crash dumps, if present)
   * Windows Error Reporting (WER) folders under `C:\ProgramData\Microsoft\Windows\WER`
     (e.g. `ReportArchive`, `ReportQueue`)

3. **Legacy Edge/IE cache** (≥ 2 days old)

   * `%LOCALAPPDATA%\Microsoft\Windows\INetCache`

4. **Generic caches under AppData** (≥ 2 days old)
   For each of:

   * `%LOCALAPPDATA%`
   * `%APPDATA%`

   It looks for subfolders that *look like* caches, e.g.:

   * `*\*\Cache*`
   * `*\*\Code Cache*`
   * `*\*\GPUCache*`

   (This catches many Chromium/Electron-based apps and other software that follows the same structure.)

5. **Generic temp/log folders under AppData** (≥ 2 days old)

   Under `%LOCALAPPDATA%` and `%APPDATA%`, it scans directories such as:

   * `*\Temp`
   * `*\tmp`
   * `*\Logs`

6. **Gecko/Firefox & Firefox forks caches** (≥ 2 days old)

   It scans profile directories under patterns such as:

   * `%LOCALAPPDATA%\Mozilla\*\Profiles\*`
   * `%APPDATA%\Mozilla\*\Profiles\*`
   * `%LOCALAPPDATA%\*\Profiles\*`
   * `%APPDATA%\*\Profiles\*`

   And in each profile it targets:

   * `cache2\entries`
   * `cache2`
   * `cache`

---

## Safety characteristics

* Only deletes **files**, never nukes whole directories.
* Enforces a **minimum age of 2 days**.
* Skips paths it cannot access (permissions, locks, etc.).
* Prints what it finds per location:

  * either `X files, Y MB`
  * or `"nothing to clean."`

If nothing qualifies, it prints:

> `No old temp/cache/log files found to clean.`

and exits without changes.

---

## Requirements

* **OS:** Windows
* **Shell:** PowerShell (Windows PowerShell or PowerShell 7+)
* To clean system-level areas (Windows Update cache, minidumps, WER, etc.),
  you’ll typically want to run it from an **elevated (Run as Administrator)** PowerShell prompt.

---

## Usage

In examples below we assume the script is named `tempDel.ps1` and is in your current directory.
If you rename/move it, adjust the paths accordingly.

### 1. Interactive dry-run + prompt (recommended first run)

From PowerShell:

```powershell
cd path\to\script
.\tempDel.ps1
```

What happens:

1. The script scans all configured locations.

2. For each area, it prints something like:

   * `Windows/user temp files in 'C:\Users\You\AppData\Local\Temp': 123 files, 456.78 MB`
   * or `...: nothing to clean.`

3. It summarizes:

   ```text
   Scan complete.
     Files identified: 1234
     Potential space to free: 1.23 GB
   ```

4. It then asks:

   ```text
   Dry-run only so far: no files deleted yet.
   Delete these files now? (Y/N)
   ```

* **Type `Y` and press Enter** to actually delete the files.
* Any other answer will abort:

  ```text
  Cleanup aborted by user. No files were deleted.
  ```

### 2. Silent / unattended cleanup

To skip the confirmation prompt and delete immediately, use the `-del` switch:

```powershell
.\tempDel.ps1 -del
```

In this mode the script:

* Still scans and summarizes,
* **Does not** ask for confirmation,
* Prints:

  ```text
  Silent delete mode (-del) enabled. Deleting files without confirmation...
  ```

Use this for:

* Scheduled cleanups (e.g. Windows Task Scheduler)
* Automated maintenance scripts

### Behaviour summary

| Command              | Behaviour                                    |
| -------------------- | -------------------------------------------- |
| `.\tempDel.ps1`      | Dry-run + shows summary, then prompts Y/N    |
| `.\tempDel.ps1 -del` | Deletes immediately, no prompt (silent mode) |

---

## Output example

Typical end-of-run output:

```text
Scan complete.
  Files identified: 842
  Potential space to free: 2.37 GB

Proceeding to delete files...
Deleted 842 files, freeing 2.37 GB.
Cleanup complete at 2025-01-01 12:34:56.
```

If you ran without `-del` and chose `N`, or if there’s nothing old to remove,
it will clearly say **no files were deleted**.

---

## Customization

If you want to tune what gets cleaned:

* **Change age thresholds**
  Edit the values of `$TempDays`, `$CacheDays`, `$LogDays`, `$SystemDays`.

* **Add/remove locations**

  * Add extra paths to:

    * `$windowsTempRoots`
    * `$systemRoots`
  * Add new wildcard patterns to:

    * `$genericCachePatterns`
    * `$genericTempPatterns`
  * Or adjust / remove gecko profile patterns if you don’t use Firefox-style browsers.

Whenever you change the script, it’s a good idea to run it **without `-del` first** to verify what it will target.

---

## What this script does *not* do

* Does **not** touch:

  * Documents, Desktop, Pictures, Music, Videos, Downloads, etc.
  * Browser bookmarks, history, passwords, profiles (only caches).
* Does **not** clean:

  * Recycle Bin
  * System restore points
  * Registry entries

It’s narrowly focused on **old temp/cache/log/crash files**.

---

## Running via Task Scheduler (optional)

If you want periodic automatic cleanup:

1. Open **Task Scheduler** → *Create Task…*
2. Set **Run with highest privileges** (for system areas).
3. Trigger: e.g. *Weekly*.
4. Action:

   * Program/script: `powershell.exe`
   * Arguments:

     ```text
     -NoProfile -ExecutionPolicy Bypass -File "C:\Path\To\tempDel.ps1" -del
     ```
5. Save.

This will run the script silently, using the same `-del` behavior as manual runs.

---

## Notes

* The header comment in the script mentions `Clean-TempAndCache.ps1`;
  you can name the file whatever you like (e.g. `tempDel.ps1`) – just adjust commands accordingly.
* If your PowerShell execution policy is restrictive, you may need:

  ```powershell
  Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
  ```

  (Run from an elevated prompt and only if this makes sense for your environment.)
