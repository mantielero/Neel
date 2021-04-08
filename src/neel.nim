import macros, jester, os, strutils, ws, ws/jester_extra, osproc, json, threadpool, asyncdispatch
export jester, os, strutils, ws, osproc, json, threadpool, asyncdispatch

when defined(webview):
    include "neel/webview"

{.warning[InheritFromException]: off.} #for annoying CustomError warning
type
    CustomError* = object of Exception


when defined(chrome):
    include "neel/chrome"


const PARAMTYPES* = ["string","int","float","bool","OrderedTable[string, JsonNode]", "seq[JsonNode]"]


var wsVar* {.threadvar.} :WebSocket


macro callJs*(funcName: string, params: varargs[untyped]) =
    quote do:
        asynccheck wsVar.send($(%*{"funcName":`funcName`,"params":[`params`]}))


proc validation*(procs: NimNode) =

    for procedure in procs.children:

        procedure.expectKind(nnkProcDef) #each has to be a proc definition
        procedure[3][0].expectKind(nnkEmpty) #there should be no return type
        procedure[4].expectKind(nnkEmpty) #there should be no pragma

        for param in procedure.params: #block below checks type of each param, should match w/ string in PARAMTYPES

            if param.kind != nnkEmpty:
                for i in 0 .. param.len-1:
                    if param[i].kind == nnkEmpty:
                        if param[i-1].repr in PARAMTYPES:
                            continue
                        else:
                            error "param type: " & param[i-1].repr & """ invalid. accepted types:
                                 string, int, float, bool, OrderedTable[string, JsonNode], seq[JsonNode]"""


proc ofStatements*(procedure: NimNode): NimNode =

    if procedure[3].len == 1:#handles procedure w/ empty params (formalParams has one child of kind nnkEmpty)
        result = nnkOfBranch.newTree(
                newLit(procedure[0].repr), #name of proc
                nnkStmtList.newTree(
                        nnkCall.newTree(
                            newIdentNode(procedure[0].repr) #name of proc
                    )))
    else:
        result = nnkOfBranch.newTree()
        result.add newLit(procedure[0].repr) #name of proc
        var
            statementList = nnkStmtList.newTree()
            procCall = nnkCall.newTree()
            paramsData :seq[tuple[paramType:string,typeQuantity:int]]

        procCall.add newIdentNode(procedure[0].repr) #name of proc

        for param in procedure.params:

            var typeQuantity :int
            for child in param.children:

                if child.kind != nnkEmpty:
                    if child.repr notin PARAMTYPES:
                        inc typeQuantity
                    else:
                        paramsData.add (paramType:child.repr, typeQuantity:typeQuantity)

        var paramIndex :int
        for i in 0 .. paramsData.high:
            for count in 1 .. paramsData[i].typeQuantity:
                var paramId :string
                case paramsData[i].paramType
                of "string":
                    paramId.add "getStr"
                of "int":
                    paramId.add "getInt"
                of "bool":
                    paramId.add "getBool"
                of "float":
                    paramId.add "getFloat"
                of "seq[JsonNode]":
                    paramId.add "getElems"
                of "OrderedTable[string, JsonNode]":
                    paramId.add "getFields"

                procCall.add nnkDotExpr.newTree(
                    nnkBracketExpr.newTree(
                    newIdentNode("params"),
                    newLit(paramIndex)),
                    newIdentNode(paramId))

                inc paramIndex

        statementList.add procCall
        result.add statementList

proc caseStatement*(procs: NimNode): NimNode =

    result = nnkCaseStmt.newTree()
    result.add newIdentNode("procName")

    for procedure in procs:
        result.add ofStatements(procedure) #converts proc param types for parsing json data & returns "of" statements

    #add an else statement for invalid/unkown proc calls in future iteration

macro exposeProcs*(procs: untyped) = #macro has to be untyped, otherwise callJs() expands & causes a type error
    procs.validation() #validates procs passed into the macro

    result = nnkProcDef.newTree(
            newIdentNode("callProc"),
            newEmptyNode(),
            newEmptyNode(),
            nnkFormalParams.newTree(
            newEmptyNode(),
            nnkIdentDefs.newTree(
                newIdentNode("jsData"),
                newIdentNode("JsonNode"),
                newEmptyNode()
            )),
            newEmptyNode(),
            newEmptyNode(),
            nnkStmtList.newTree(
            nnkVarSection.newTree(
                nnkIdentDefs.newTree(
                newIdentNode("procName"),
                newEmptyNode(),
                nnkDotExpr.newTree(
                    nnkBracketExpr.newTree(
                    newIdentNode("jsData"),
                    newLit("procName")
                    ),
                    newIdentNode("getStr")
                )),
                nnkIdentDefs.newTree(
                newIdentNode("params"),
                newEmptyNode(),
                nnkDotExpr.newTree(
                    nnkBracketExpr.newTree(
                    newIdentNode("jsData"),
                    newLit("params")
                    ),
                    newIdentNode("getElems")
                ))),
            procs,
            caseStatement(procs) #converts types into proper json parsing & returns case statement logic
            ))
    
    #echo result.repr #for testing macro expansion

macro startApp*(startURL, assetsDir: string, portNo: int = 5000,
                    position: array[2, int] = [500,150], size: array[2, int] = [600,600]) =

    quote do:

        const NOCACHE_HEADER = @[("Cache-Control","no-store")]
        var openSockets: bool

        proc handleFrontEndData*(frontEndData :string) {.async, gcsafe.} =
            callProc(frontEndData.parseJson)

        proc detectShutdown =
            sleep(1200) #time requirement may vary?
            if not openSockets:
                quit()

        when defined(chrome):
            spawn openChrome(portNo=`portNo`)

        router theRouter:
            get "/":
                resp(Http200,NOCACHE_HEADER,readFile(currentSourcePath.parentDir() / `assetsDir` / `startURL`))#is this most efficient?
            get "/neel.js":
                resp(Http200, NOCACHE_HEADER,"window.moveTo(" & $`position`[0] & "," & $`position`[1] & ")\n" &
                        "window.resizeTo(" & $`size`[0] & "," & $`size`[1] & ")\n" &
                        "var ws = new WebSocket(\"ws://localhost:" & $`portNo` & "/ws\")\n" &
                        """var connected = false
                        ws.onmessage = (data) => {
                            try {
                                let x = JSON.parse(data.data)
                                let v = Object.values(x)
                                neel.callJs(v[0], v[1])
                            } catch (err) {
                                let x = JSON.parse(data)
                                let v = Object.values(x)
                                neel.callJs(v[0], v[1])
                            }
                        }
                        var neel = {
                            callJs: function (func, arr) {
                                window[func].apply(null, arr);
                            },
                            callProc: function (func, ...args) {
                                if (!connected) {
                                    function check(func, ...args) { if (ws.readyState == 1) { connected = true; neel.callProc(func, ...args); clearInterval(myInterval); } }
                                    var myInterval = setInterval(check,15,func,...args)
                                } else {
                                    let paramArray = []
                                    for (var i = 0; i < args.length; i++) {
                                        paramArray.push(args[i])
                                    }
                                    let data = JSON.stringify({ "procName": func, "params": paramArray })
                                    ws.send(data)
                                }
                            }
                        }""")

            get "/ws":
                try:
                    var ws = await newWebSocket(request)
                    wsVar = ws #test
                    while ws.readyState == Open:
                        openSockets = true
                        let frontEndData = await ws.receiveStrPacket
                        spawn asyncCheck handleFrontEndData(frontEndData)
                except WebSocketError:
                    openSockets = false
                    spawn detectShutdown()

            get "/@path":
                try: # currentSourcePath.parentDir() over currentDir()
                    resp(Http200,NOCACHE_HEADER,readFile(currentSourcePath.parentDir() / `assetsDir` / path(request)))
                except:
                    raise newException(CustomError, "path: " & path(request) & " doesn't exist") #is this proper?

            # below are exact copies of route above, supporting static files up to 5 directories deep
            # ***review later for better implementation & reduce code duplication***
            get "/@path/@path2":
                try:
                    resp(Http200,NOCACHE_HEADER,readFile(currentSourcePath.parentDir() / `assetsDir` / path(request)))
                except:
                    raise newException(CustomError, path(request) & " doesn't exist")
            get "/@path/@path2/@path3":
                try:
                    resp(Http200,NOCACHE_HEADER,readFile(currentSourcePath.parentDir() / `assetsDir` / path(request)))
                except:
                    raise newException(CustomError, path(request) & " doesn't exist")
            get "/@path/@path2/@path3/@path4":
                try:
                    resp(Http200,NOCACHE_HEADER,readFile(currentSourcePath.parentDir() / `assetsDir` / path(request)))
                except:
                    raise newException(CustomError, path(request) & " doesn't exist")
            get "/@path/@path2/@path3/@path4/@path5":
                try:
                    resp(Http200,NOCACHE_HEADER,readFile(currentSourcePath.parentDir() / `assetsDir` / path(request)))
                except:
                    raise newException(CustomError, path(request) & " doesn't exist")
            get "/@path/@path2/@path3/@path4/@path5/@path6":
                try:
                    resp(Http200,NOCACHE_HEADER,readFile(currentSourcePath.parentDir() / `assetsDir` / path(request)))
                except:
                    raise newException(CustomError, path(request) & " doesn't exist")

        proc main =
            let settings = newSettings(`portNo`.Port)
            var jester = initJester(theRouter, settings=settings)
            jester.serve

        when defined(webview):
            spawn main()
            sleep 500 #temporary placeholder until better implementation for potential time delay issue
            openWebView(url="http://localhost:" & $`portNo` & "/")
        else:
            main()
