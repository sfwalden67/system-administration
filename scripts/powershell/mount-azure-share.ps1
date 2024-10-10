$connectTestResult = Test-NetConnection -ComputerName <AZURE_FILE> -Port 445
if ($connectTestResult.TcpTestSucceeded) {
    # Save the password so the drive will persist on reboot
    cmd.exe /C "cmdkey /add:`"<AZURE_SERVER>`" /user:`"localhost\<AZURE_SHARENAME>`" /pass:`"<PASSWORD_SHARE>`""
    # Mount the drive
    New-PSDrive -Name Z -PSProvider FileSystem -Root "\\<AZURE_SERVERNAME>\<AZURE_SHARENAME>" -Persist
} else {
    Write-Error -Message "Unable to reach the Azure storage account via port 445. Check to make sure your organization or ISP is not blocking port 445, or use Azure P2S VPN, Azure S2S VPN, or Express Route to tunnel SMB traffic over a different port."
}