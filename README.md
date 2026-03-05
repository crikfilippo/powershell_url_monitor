# PowerShell URL Monitor

## Description
This script monitors the status of a URL using either a direct connection or an SSH tunnel. Results are logged in a CSV file.

## Configuration Parameters
Edit the `config.psd1` file to specify the following parameters:

- **`URL`**: The URL to monitor.
- **`UseSSH`**: Set to `true` to use an SSH tunnel, or `false` for a direct connection.
- **`SshHost`**: The hostname or IP address of the SSH server.
- **`SshPort`**: The port number for the SSH connection (default is 22).
- **`SshUser`**: The username for the SSH connection.
- **`SshPassword`**: The password for the SSH connection.
- **`ConnectionTimeout`**: Timeout in seconds for the connection (default is 30).
- **`SnippetMaxLen`**: Maximum length of the content snippet saved in the log (default is 100).
- **`IntervalSeconds`**: Time interval in seconds between checks (default is 120).
- **`MaxLines`**: Maximum number of lines per log file before creating a new one (default is 2880).

## Usage
1. Open PowerShell.
2. Navigate to the folder containing the script.
3. Run the script with the following command:
   ```powershell
   .\monitor_url.ps1
   ```

## CSV Log Format
The results are saved in the `data/` folder in CSV format. Each row contains the following columns:
- **`Timestamp`**: The date and time of the check.
- **`Status`**: `OK` if the check was successful, `KO` otherwise.
- **`HttpCode`**: The HTTP status code returned by the server.
- **`Connection`**: The connection type and details (e.g., `DIRECT` or `SSH`).
- **`ContentSnippet`**: A snippet of the content returned by the server (truncated to `SnippetMaxLen`).

## Notes
- This script includes **Plink** from the PuTTY suite for SSH connections. You can download PuTTY from its official website: [https://www.chiark.greenend.org.uk/~sgtatham/putty/](https://www.chiark.greenend.org.uk/~sgtatham/putty/).
- The script works on Windows. For direct connections, `curl` must be available. For SSH connections, it works on Windows (with `curl`) or Linux hosts.
- SSH host keys are cached in the Windows registry under the following path:
  ```
  HKEY_CURRENT_USER\Software\SimonTatham\PuTTY\SshHostKeys
  ```



