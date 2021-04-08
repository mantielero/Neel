from sequtils import keepItIf

proc findChromeMac: string =
    const defaultPath :string = r"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    const name = "Google Chrome.app"

    try:
        if fileExists(absolutePath(defaultPath)):
            result = defaultPath.replace(" ", r"\ ")
        else: # Recursive search as implemented in the eel project
            var alternate_dirs = execProcess("mdfind", args = [name], options = {poUsePath}).split("\n")
            alternate_dirs.keepItIf(it.contains(name))
        
            if alternate_dirs != @[]:
                result = alternate_dirs[0] & "/Contents/MacOS/Google Chrome"
            else:
                raise newException(CustomError, "could not find Chrome")

    except:
        raise newException(CustomError, "could not find Chrome in Applications directory")

proc findChromeWindows: string =
    #const defaultPath = r"SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe" # for registery
    const defaultPath = r"\Program Files (x86)\Google\Chrome\Application\chrome.exe"
    const backupPath = r"\Program Files\Google\Chrome\Application\chrome.exe"
    if fileExists(absolutePath(defaultPath)):
        result = defaultPath
    elif fileExists(absolutePath(backupPath)): #originally an if 4/5/21
        result = backupPath
    else: # include registry search in future versions to account for any location
        raise newException(CustomError, "could not find Chrome in Program Files (x86) directory")

proc findChromeLinux: string =
    const chromeNames = ["google-chrome", "chromium-browser", "chromium"]
    for name in chromeNames:
        if execCmd("which " & name) == 0:
            return name
    raise newException(CustomError, "could not find Chrome in PATH")#(os, "could not find Chrome in PATH")

proc findPath: string =
    when hostOS == "macosx":
        result = findChromeMac()
    elif hostOS == "windows":
        result = findChromeWindows()
    elif hostOS == "linux":
        result = findChromeLinux()
    else:
        raise newException(CustomError, "unkown OS in findPath() for neel.nim")

proc openChrome*(portNo: int) =
    var chromeStuff = " --app=http://localhost:" & portNo.intToStr & "/ --disable-http-cache"
    let command = findPath() & chromeStuff
    if execCmd(command) != 0:
        raise newException(CustomError,"could not open Chrome browser")
