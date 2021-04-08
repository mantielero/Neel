{.passC: "-DWEBVIEW_STATIC -DWEBVIEW_IMPLEMENTATION".}
{.passC: "-I" & currentSourcePath().substr(0, high(currentSourcePath()) - 4).} #disregard error

when defined(linux):
  {.passC: "-DWEBVIEW_GTK=1 " &
          staticExec"pkg-config --cflags gtk+-3.0 webkit2gtk-4.0".}
  {.passL: staticExec"pkg-config --libs gtk+-3.0 webkit2gtk-4.0".}
elif defined(windows):
  {.passC: "-DWEBVIEW_WINAPI=1".}
  {.passL: "-lole32 -lcomctl32 -loleaut32 -luuid -lgdi32".}
elif defined(macosx):
  {.passC: "-DWEBVIEW_COCOA=1 -x objective-c".}
  {.passL: "-framework Cocoa -framework WebKit".}

proc webview(title: cstring; url: cstring; w: cint; h: cint; resizable: cint): cint {.importc: "webview", header: "webview.h".}
proc openWebView*(title="WebView", url="", width=640, height=480, resizable=true) =
    discard webview(title.cstring, url.cstring, width.cint, height.cint, (if resizable: 1 else: 0).cint)
