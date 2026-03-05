@{
    # --- Main ---
    URL                 = "https://www.google.com"
    UseSSH              = $false          # $true = SSH Tunnel, $false = direct

    # --- Monitoring ---
    ConnectionTimeout   = 30
    IntervalSeconds     = 120
    MaxLines            = 2880
    SnippetMaxLen       = 100
    LogFolder           = ".\data"

    # --- SSH ---
    SshHost             = "127.0.0.1"
    SshPort             = 22
    SshUser             = "user"
    SshPassword         = "passwort"

    # --- Plink ---
    PlinkExe            = ".\PLINK.EXE"
    
}