$pythonPaths = @(
    "C:\Python*",
    "C:\Program Files\Python*",
    "C:\Program Files (x86)\Python*",
    "$env:LOCALAPPDATA\Programs\Python\*",
    "$env:USERPROFILE\AppData\Local\Programs\Python\*"
)
Get-ChildItem -Path $pythonPaths -Filter "python.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
