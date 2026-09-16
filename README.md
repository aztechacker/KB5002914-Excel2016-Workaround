# KB5002914-Excel2016-Workaround
PowerShell workaround for uninstalling and hiding KB5002914 on Microsoft Excel 2016 x86/x64.

Initial release.

- Detects and removes KB5002914 from Microsoft Excel 2016.
- Supports Office 2016 x86 and x64.
- Uses the registered Office uninstall command instead of hard-coded product GUIDs.
- Hides KB5002914 from Microsoft Update.
- Includes periodic verification to help prevent the update from being reinstalled.

Important:
KB5002914 is a Microsoft security update. This project is intended as a temporary workaround only. Test before production deployment and install a corrected or superseding Microsoft update when available.
