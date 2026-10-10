Get-Process | Where-Object { $_.ProcessName -match "chrome|msedge|firefox|opera|brave" } | 
    Where-Object { $_.MainWindowTitle } | 
    Select-Object ProcessName, MainWindowTitle
