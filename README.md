# UserProfile Cleanup Script

This script automatically removes user profiles in the same way that Windows would, using the `Win32_UserProfile` WMI instance. This ensures that the next time the user logs on, they will not encounter any errors, as opposed to simply deleting the folder on disk.

## Parameters

### `-SpaceLimit`
Removes user profiles until the desired free space threshold on the disk is reached.

- **Example:** `-SpaceLimit 100` will delete user profiles until you reach 100GB of free space on the disk.

### `-MonthCutoff`
Removes any user profiles that haven't been used since today's date minus the specified number of months.

- **Example:** `-MonthCutoff 6` will remove user profiles that have not been used in the last six months.

### Combined Usage
You can combine `-SpaceLimit` and `-MonthCutoff` to remove user profiles based on both criteria.

- **Example:** `-SpaceLimit 100 -MonthCutoff 6` will remove user profiles that have not been used in the last six months, until you have 100GB of free space on the disk.

### `-WhitelistUser`
Whitelists any matching username from deletion.

- **Example:** `-WhitelistUser USDOEJ` will not delete the `USDOEJ` user regardless of space or month limitations. This is useful for admin profiles, service accounts, or top users.
- **Note:** If you are going to use this for an organization, you can also directly change the `$WhitelistUsers` variable (added 's') so you don't have to check this switch every time.

### `-ProfileLimit`
Limits the number of profiles removed (used for testing).

- **Example:** `-ProfileLimit 5` will only remove the first 5 found profiles, in arbitrary order.

### `-DebugMode`
Enables "safe" mode, which bypasses admin checks and does not actually delete any user profiles.

### `-Verbose`
Enables verbose logging for some commands (WMI related commands).

## Usage Examples

1. **Basic Usage:**
   ```powershell
   .\UserProfileCleanup.ps1 -SpaceLimit 100 -MonthCutoff 6
   ```

2. **Whitelist a User:**
   ```powershell
   .\UserProfileCleanup.ps1 -SpaceLimit 100 -MonthCutoff 6 -WhitelistUser USDOEJ
   ```

3. **Test Run (Debug Mode):**
   ```powershell
   .\UserProfileCleanup.ps1 -SpaceLimit 100 -MonthCutoff 6 -DebugMode
   ```

4. **Verbose Logging:**
   ```powershell
   .\UserProfileCleanup.ps1 -SpaceLimit 100 -MonthCutoff 6 -Verbose
   ```

## Notes
- Ensure you have the necessary permissions to run this script.
- Use `-DebugMode` to test the script without making any changes.
- The `-Verbose` switch can help with troubleshooting by providing detailed logs.
